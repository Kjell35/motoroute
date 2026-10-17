"""OSM-Ortskerne für die Ortsdurchfahrten-Meidung.

Holt die Umriss-Polygone von Siedlungen (place=village/town/suburb) aus
OpenStreetMap/Overpass und wandelt sie in Valhalla-`avoid_polygons`-Ringe um.
Der Radius-Puffer erweitert jeden Ortskern leicht nach außen, damit auch die
Zufahrtsstraßen am Ortsrand vermieden werden, nicht nur die Ortsmitte.

Ehrliche Grenze (kein Fake-Daten-Prinzip): Overpass liefert Orts-Umrisse nur,
wo OSM-Mapper die Fläche als Relation/Weg gepflegt haben. Fehlt der Umriss,
fällt der Aufruf auf kreisförmige Fallback-Polygone um den Wegpunkt zurück
(Radius 1500 m – wie bisher).
"""

from __future__ import annotations

import asyncio
import math
import time
from typing import Any

import httpx2
from shapely.geometry import Polygon

from ..core.config import get_settings

_PLACES = ("village", "town", "suburb")
_MAX_POLYGONS = 40
_MAX_RING_POINTS = 64

# Valhalla-Service-Limits für avoid_polygons (live verifiziert 2026-10-11,
# docs/14 §5.4): max. **Gesamtumfang** aller Ringe 10 000 m, max. 100 Vertizes.
# Enforcer-Budget mit 2-km Sicherheitsabstand oberhalb des Hardlimits.
_MAX_TOTAL_CIRCUMFERENCE_M = 8000.0
_MAX_TOTAL_VERTICES = 96

# Cache: Overpass-Polygone pro BBox-Zelle, um Rate-Limits zu vermeiden.
# Zero-Budget: In-Memory-Dict reicht für die Container-Laufzeit (kein Redis).
_CACHE_TTL_SECONDS = 24 * 3600.0
_CACHE_LOCK = asyncio.Lock()
_polygon_cache: dict[str, tuple[float, list[list[dict[str, float]]]]] = {}


def _avoid_polygon_ring(
    center: tuple[float, float],
    radius_m: float,
    steps: int = 16,
) -> list[dict[str, float]]:
    """Kreisförmiger Fallback-Ring (identisches Format zu routing.py)."""
    lat0, lon0 = center
    lat_per_m = 1.0 / 111_320.0
    lon_per_m = 1.0 / (111_320.0 * max(math.cos(math.radians(lat0)), 1e-6))
    ring: list[dict[str, float]] = []
    for step in range(steps):
        angle = 2.0 * math.pi * step / steps
        ring.append(
            {
                "lat": lat0 + lat_per_m * radius_m * math.sin(angle),
                "lon": lon0 + lon_per_m * radius_m * math.cos(angle),
            }
        )
    ring.append(dict(ring[0]))
    return ring


async def _overpass(query: str) -> dict[str, Any]:
    settings = get_settings()
    async with httpx2.AsyncClient(timeout=15.0) as client:
        response = await client.post(settings.overpass_url, data={"data": query})
        response.raise_for_status()
        payload: dict[str, Any] = response.json()
        return payload


def _bbox_around(
    lat: float,
    lon: float,
    radius_m: float = 4000.0,
) -> tuple[float, float, float, float]:
    """Kleine BBox um einen Wegpunkt, genügt für Orts-Areale der Umgebung."""
    lat_d = radius_m / 111_320.0
    lon_d = radius_m / (111_320.0 * max(math.cos(math.radians(lat)), 1e-6))
    return (lon - lon_d, lat - lat_d, lon + lon_d, lat + lat_d)


def _ring_from_geometry(coords: list[Any]) -> list[dict[str, float]] | None:
    """Wandelt GeoJSON-ähnliche Koordinatenlisten in einen geschlossenen Ring."""
    ring: list[dict[str, float]] = []
    for coord in coords:
        if not isinstance(coord, (list, tuple)) or len(coord) < 2:
            continue
        lon, lat = float(coord[0]), float(coord[1])
        if not (-180 <= lon <= 180 and -90 <= lat <= 90):
            continue
        ring.append({"lat": lat, "lon": lon})
    if len(ring) < 4:
        return None
    # Naives Strided-Slicing entfernt: adaptives Douglas-Peucker übernimmt die
    # detaillierte Reduktion im Meter-Projektions-Pfad (_adaptive_simplify_meters).
    # Nur ein Notfall-Budget gegen absurde Overpass-GeVometrien bleibt hier.
    if len(ring) > _MAX_RING_POINTS * 4:
        keep = max(1, len(ring) // _MAX_RING_POINTS)
        ring = ring[::keep]
    ring.append(dict(ring[0]))
    return ring


def _adaptive_simplify_meters(
    polygon: Any,
    max_points: int,
    start_tolerance_m: float = 1.0,
    end_tolerance_m: float = 500.0,
) -> Any:
    """Adaptives Douglas-Peucker per Bisektion über die Toleranz.

    Ziel: Das Detailmaximum innerhalb des Punkt-Budgets, statt naives
    Äquidistant-Slicing, das prägnante Erhebungen (Kurvenecken, Sporne)
    ratenlos abschneidet.
    """
    # Bisektionsziel: die kleinste Toleranz finden, die noch im Punkte-Budget
    # bleibt (maximale Detailtreue). Kleine Toleranz = viele Punkte (detailerhaltend),
    # große Toleranz = wenig Punkte (grob). Wir starten mit hi = gröberer sichere
    # Richtung und nähern uns der feinsten zulässigen Grenze von oben.
    lo, hi = start_tolerance_m, end_tolerance_m
    best = polygon.simplify(tolerance=hi, preserve_topology=True)
    for _ in range(8):  # 8 Bisektionsschritte reichen praxisnah
        mid = (lo + hi) / 2
        candidate = polygon.simplify(tolerance=mid, preserve_topology=True)
        vertex_count = len(candidate.exterior.coords) - 1  # ohne Schließung
        if vertex_count <= max_points:
            # Detailreicher als aktuell erlaubt – merken und weiter Richtung fein.
            best = candidate
            hi = mid
        else:
            # Zu detailreich (zu viele Punkte): gröbere Toleranz nötig.
            lo = mid
    return best


def _buffer_ring_meters(
    ring: list[dict[str, float]],
    buffer_m: float,
    origin: tuple[float, float],
) -> list[dict[str, float]]:
    """Puffert einen Ortskernring lokal in Meter-Näherung (equirectangular).

    Projektion um den Wegpunkt-Origin; kleine Regionen (± 4 km) machen den
    Verzerrungsfehler unter 0,1 % – pyproj/UTM lohnt hier nicht. Danach
    adaptives Douglas-Peucker (max. Detail im Punkte-Budget) und Rück-Projektion.
    """
    lat0, lon0 = origin
    cos_lat = max(math.cos(math.radians(lat0)), 1e-6)
    meters_per_deg_lat = 111_320.0
    meters_per_deg_lon = 111_320.0 * cos_lat

    # Valhalla-Ring (lat/lon) -> Meter-Koordinaten relativ zum Origin.
    meter_coords: list[tuple[float, float]] = [
        (
            (point["lat"] - lat0) * meters_per_deg_lat,
            (point["lon"] - lon0) * meters_per_deg_lon,
        )
        for point in ring[:-1]  # Schließungspunkt entfernen, Polygon schließt selbst
    ]
    if len(meter_coords) < 3:
        return ring

    polygon = Polygon(meter_coords)
    if not polygon.is_valid:
        polygon = polygon.buffer(0)  # Self-Intersection-Reparatur
    buffered = polygon.buffer(buffer_m)
    if buffered.is_empty:
        return ring

    # Adaptives Douglas-Peucker: maximale Umriss-Genauigkeit innerhalb des
    # Punkt-Budgets (statt fixer 20-m-Toleranz, die Detail entweder schrottet
    # oder das Budget verfehlt).
    simplified = _adaptive_simplify_meters(buffered, _MAX_RING_POINTS)
    lon1, lat1 = simplified.exterior.coords.xy
    result: list[dict[str, float]] = [
        {
            "lat": lat0 + y / meters_per_deg_lat,
            "lon": lon0 + x / meters_per_deg_lon,
        }
        for x, y in zip(lon1, lat1, strict=True)
    ]
    if result[0] != result[-1]:
        result.append(dict(result[0]))
    return result


async def town_polygons(
    waypoints: list[tuple[float, float]],
    fallback_radius_m: float = 1500.0,
    buffer_m: float = 300.0,
) -> list[list[dict[str, float]]]:
    """Ringe der Ortskerne in Valhalla-`avoid_polygons`-Form.

    Pro Wegpunkt: echte OSM-Umrisse in ± 4 km Umkreis (place=village/town/suburb,
    als Relation/Weg gemappt). Fail-open (live verifiziert 2026-10-11,
    docs/14 §5.4): ohne Overpass oder ohne OSM-Treffer trägt der Wegpunkt
    NICHTS bei — der frühere Fallback-Kreis um den Wegpunkt selbst isolierte
    ihn (Route unmöglich, HTTP 400). Die leere Zelle wird mitgecacht, damit
    ein flackernder Overpass keine Request-Flut erzeugt.
    """
    polygons: list[list[dict[str, float]]] = []
    stamp = time.monotonic()
    for lat, lon in waypoints:
        west, south, east, north = _bbox_around(lat, lon)
        cell_key = f"({south:.6f},{west:.6f},{north:.6f},{east:.6f})"

        # Cache-Hit: Gültige Ringe für diese BBox-Zelle sind bereits vorhanden.
        async with _CACHE_LOCK:
            entry = _polygon_cache.get(cell_key)
            if entry is not None and stamp - entry[0] <= _CACHE_TTL_SECONDS:
                polygons.extend(entry[1])
                continue

        bounds = f"({south:.6f},{west:.6f},{north:.6f},{east:.6f})"
        clauses = "".join(
            f'rel["place"="{p}"]{bounds};way["place"="{p}"]{bounds};' for p in _PLACES
        )
        try:
            data = await _overpass(f"[out:json][timeout:12];({clauses});out geom;")
        except (httpx2.HTTPError, ValueError):
            # Overpass aus: NICHTS beitragen statt Fallback-Kreis um den
            # eigenen Wegpunkt (live-Fund, docs/14 §5.4: Ring um den Wegpunkt
            # isoliert ihn -> HTTP 400 "No path"). Fail-open; die leere
            # Zelle wird gecacht (Rate-Limit-Schutz bei flackerndem Overpass).
            async with _CACHE_LOCK:
                _polygon_cache[cell_key] = (stamp, [])
            continue

        rings: list[list[dict[str, float]]] = []
        for element in data.get("elements", []):
            geometry = element.get("geometry") or []
            if element.get("type") == "relation":
                for member in geometry:
                    ring = _ring_from_geometry(member or [])
                    if ring:
                        rings.append(ring)
            else:
                ring = _ring_from_geometry(geometry)
                if ring:
                    rings.append(ring)
        cell_result: list[list[dict[str, float]]]
        if rings:
            # Echtes Ring-Buffering: jeder OSM-Ortskern wird um buffer_m Meter
            # nach außen vergrößert (300 m Standard), damit auch Zufahrtsstraßen
            # am Ortsrand vermieden werden.
            buffered_rings = [
                _buffer_ring_meters(ring, buffer_m, (lat, lon)) for ring in rings
            ]
            cell_result = list(buffered_rings[:_MAX_POLYGONS])
        else:
            # Overpass liefert nichts in ± 4 km: periphere Gegend, kein Ortskern
            # zu meiden. Kein Fallback-Kreis um den Wegpunkt (live-Fund,
            # docs/14 §5.4 — Ring um den Wegpunkt selbst = No-path-HTTP-400).
            cell_result = []

        # Zell-Ergebnis cachen; der Key ist die exakte BBox der Zelle.
        async with _CACHE_LOCK:
            _polygon_cache[cell_key] = (stamp, cell_result)
        polygons.extend(cell_result)

    return _enforce_service_budget(polygons)


def _ring_circumference_m(ring: list[dict[str, float]]) -> float:
    """Ringumfang in Meter (equirectangular um den Ring-Schwerpunkt)."""
    if len(ring) < 3:
        return 0.0
    lat_mid = sum(p["lat"] for p in ring[:-1]) / (len(ring) - 1)
    mlat = 111_320.0
    mlon = mlat * max(math.cos(math.radians(lat_mid)), 1e-6)
    total = 0.0
    for (a, b) in zip(ring[:-1], ring[1:], strict=False):
        total += math.hypot(
            (b["lat"] - a["lat"]) * mlat, (b["lon"] - a["lon"]) * mlon
        )
    return total


def _enforce_service_budget(
    polygons: list[list[dict[str, float]]],
) -> list[list[dict[str, float]]]:
    """Kappt/Schrumpft Ringe bis Valhallas Service-Limits eingehalten sind.

    Mehrere Fallback-Kreise à ~9,4 km sprengen sonst das 10-km-Gesamtlimit
    (live reproduziert: 2 Ringe à 1 500 m = 23,5 km -> HTTP 400 error_code
    167; **ein einzelner** 1 500-m-Fallback ist mit 9,4 km selbst schon über
    dem Enforcer-Budget von 8 km). Strategie:
    1. Ringe der Reihe nach übernehmen, bis Budget ohne sie passt.
    2. Ein **einziger** überdimensionierter Ring wird auf das Budget
       geschrumpft (Radius-Skala), nicht verworfen — ein Fallback-Kreis um
       den Wegpunkt ist besser als gar kein Ortschutz.
    """
    kept: list[list[dict[str, float]]] = []
    circumference = 0.0
    vertices = 0
    for ring in polygons:
        ring_len = len(ring)
        ring_circ = _ring_circumference_m(ring)
        if (
            circumference + ring_circ <= _MAX_TOTAL_CIRCUMFERENCE_M
            and vertices + ring_len <= _MAX_TOTAL_VERTICES
        ):
            kept.append(ring)
            circumference += ring_circ
            vertices += ring_len
            continue
        # Einziger Ring (der erste) über dem Budget:IW schrumpfen statt wegwerfen.
        if not kept and _ring_circumference_m(ring) > _MAX_TOTAL_CIRCUMFERENCE_M:
            center_lat = sum(p["lat"] for p in ring[:-1]) / (len(ring) - 1)
            center_lon = sum(p["lon"] for p in ring[:-1]) / (len(ring) - 1)
            scale = _MAX_TOTAL_CIRCUMFERENCE_M / ring_circ
            shrunk = _avoid_polygon_ring(
                (center_lat, center_lon),
                # effektiver Radius = Original-Kreisradius × Budget-Skala
                1500.0 * scale,
            )
            kept.append(shrunk)
            circumference += _ring_circumference_m(shrunk)
            vertices += len(shrunk)
            continue
        break  # Budget voll: weitere Ringe flogen sowieso raus
    return kept


def polygon_cache_clear() -> None:
    """Leert den Polygon-Cache (für Tests und Invalidierung)."""
    _polygon_cache.clear()
