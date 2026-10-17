"""Routing-Vertrag vor Valhalla.

Die App sendet Präferenzen bei jedem Request; sie werden weder gespeichert
noch für ein Bewegungsprofil verwendet.
"""

from enum import StrEnum
from typing import Any

import httpx2
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from ..core.config import get_settings
from ..core.security import require_client_token
from .curvescore import curve_score, score_shape_segments
from .town_polygons import town_polygons


class Vehicle(StrEnum):
    car = "car"
    motorcycle = "motorcycle"
    bicycle = "bicycle"


class RideStyle(StrEnum):
    fast = "fast"
    curvy = "curvy"
    extra_curvy = "extra_curvy"
    fast_and_curvy = "fast_and_curvy"


class Avoidance(StrEnum):
    highway = "highway"
    ferry = "ferry"
    toll = "toll"
    unpaved = "unpaved"
    cycleway = "cycleway"
    towns = "towns"


class Coordinate(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)


class Preferences(BaseModel):
    vehicle: Vehicle = Vehicle.motorcycle
    ride_style: RideStyle = RideStyle.fast_and_curvy
    avoid: set[Avoidance] = Field(default_factory=set)


class RouteRequest(BaseModel):
    waypoints: list[Coordinate] = Field(min_length=2, max_length=12)
    preferences: Preferences


class RouteCandidate(BaseModel):
    distance_m: int
    duration_s: int
    geometry_polyline6: str | None = None
    curve_score: float | None = None  # CurveScorer v2: 0–10 (docs/14 §3.2)


class RouteResponse(BaseModel):
    candidates: list[RouteCandidate]


def _avoid_polygon_ring(
    center: tuple[float, float],
    radius_m: float,
    steps: int = 16,
) -> list[dict[str, float]]:
    """Erzeugt einen kreisrunden Polygone-Ring (Valhalla-Format: Koordinatenliste).

    Valhalla `avoid_polygons` erwartet Ringe aus Koordinatenpaaren;
    GeoJSON-Feature-Objekte sind das nicht.
    """
    import math

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
    # Valhalla erwartet geschlossenen Ring: erster Punkt = letzter Punkt.
    ring.append(dict(ring[0]))
    return ring


def _rings_to_valhalla_format(
    rings: list[list[dict[str, float]]],
) -> list[list[list[float]]]:
    """Konvertiert interne lat/lon-Dict-Ringe in Valhallas avoid_polygons-Syntax.

    Live-verifiziert (2026-10-11, Valhalla 3.9.1): Ringe müssen Paare aus
    **lon zuerst, lat danach** sein – `[[lon, lat], ...]`. `{lat, lon}`-
    Objekte erzeugen HTTP 400 ("Failed to parse polygon: IsArray()"), und
    die verkehrte Paar-Reihenfolge `[lat, lon]` wird stillschweigend als
    invalide Koordinate (lat > 90/180-Clamp) verworfen – ohne Effekt.
    Service-Limits: max. Gesamtausdehnung 10 000 m + 100 Vertizes.
    """
    converted: list[list[list[float]]] = []
    for ring in rings:
        converted.append(
            [[float(point['lon']), float(point['lat'])] for point in ring]
        )
    return converted


async def _valhalla_payload(request: RouteRequest) -> dict[str, Any]:
    """Übersetzt die Produktpräferenzen in transparente Routing-Parameter."""
    avoid = request.preferences.avoid
    style = request.preferences.ride_style
    # Je kurviger, desto stärker werden Autobahn-Abschnitte abgewertet.
    highway_use = {
        RideStyle.fast: 1.0,
        RideStyle.fast_and_curvy: 0.4,
        RideStyle.curvy: 0.15,
        RideStyle.extra_curvy: 0.0,
    }[style]
    if Avoidance.highway in avoid:
        highway_use = 0.0
    options: dict[str, Any] = {
        "use_highways": highway_use,
        "use_tolls": 0.0 if Avoidance.toll in avoid else 0.5,
        "use_ferry": 0.0 if Avoidance.ferry in avoid else 0.5,
    }
    if Avoidance.unpaved in avoid:
        options["use_trails"] = 0.0
    if Avoidance.cycleway in avoid:
        options["use_tracks"] = 0.0
    payload: dict[str, Any] = {
        "locations": [point.model_dump() for point in request.waypoints],
        "costing": request.preferences.vehicle.value,
        "costing_options": {request.preferences.vehicle.value: options},
        "units": "kilometers",
        "language": "de-DE",
    }
    if Avoidance.towns in avoid:
        # Ortskern-Meidung: echte OSM-Ortskerne (place=village/town/suburb) über
        # das town_polygons-Modul (Overpass); ohne Treffer oder bei Overpass-
        # Ausfall fällt jeder Wegpunkt auf den Kreis-Fallback (1500 m) zurück.
        # Ringe werden an der Payload-Grenze in Valhallas Parse-Format
        # konvertiert: [[lon, lat], ...]-Paare (live verifiziert 2026-10-11).
        payload['avoid_polygons'] = _rings_to_valhalla_format(
            await town_polygons(
                [(point.lat, point.lon) for point in request.waypoints]
            )
        )
    return payload


router = APIRouter(prefix="/api/v1", tags=["routing"], dependencies=[Depends(require_client_token)])


@router.post("/route", response_model=RouteResponse)
async def route(request: RouteRequest) -> RouteResponse:
    settings = get_settings()
    try:
        async with httpx2.AsyncClient(timeout=12.0) as client:
            response = await client.post(
                f"{settings.valhalla_url.rstrip('/')}/route",
                json=await _valhalla_payload(request),
            )
            response.raise_for_status()
        trip: dict[str, Any] = response.json()["trip"]
    except (httpx2.HTTPError, KeyError, TypeError, ValueError) as error:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "code": "ROUTING_UNAVAILABLE",
                "message": "Routing ist gerade nicht verfügbar.",
            },
        ) from error
    summary: dict[str, Any] = trip["summary"]
    shape = next((leg.get("shape") for leg in trip.get("legs", []) if leg.get("shape")), None)
    curve = _curve_score_for_shape(shape)
    return RouteResponse(
        candidates=[
            RouteCandidate(
                distance_m=round(float(summary["length"]) * 1000),
                duration_s=round(float(summary["time"])),
                geometry_polyline6=shape,
                curve_score=curve,
            )
        ]
    )


def _curve_score_for_shape(shape: str | None) -> float | None:
    """CurveScorer v2 auf der Valhalla-Route (Shape, Polyline6).

    Kein Extra-/trace_attributes-Call nötig (die Geometrie reicht für v2);
    bei fehlendem/ungültigem Shape wird None geliefert (ehrlicher Null).
    """
    if not shape:
        return None
    try:
        coords = _decode_polyline6(shape)
    except (ValueError, TypeError):
        return None
    if len(coords) < 3:
        return None
    segments = score_shape_segments(coords)
    distance_m = round(float(summary_length_estimation(coords)))
    if distance_m <= 0:
        return None
    return curve_score(segments, length_m_total=distance_m)


def summary_length_estimation(coords: list[tuple[float, float]]) -> float:
    """Länge der Routen-Geometrie in Metern (equirectangular)."""
    import math

    lat0 = coords[0][0]
    m_lat = 111_320.0
    m_lon = 111_320.0 * max(math.cos(math.radians(lat0)), 1e-6)
    total = 0.0
    for (a_lat, a_lon), (b_lat, b_lon) in zip(coords[:-1], coords[1:], strict=True):
        total += math.hypot((b_lat - a_lat) * m_lat, (b_lon - a_lon) * m_lon)
    return total


def _decode_polyline6(polyline: str) -> list[tuple[float, float]]:
    """Valhalla-Polyline6-Decoder (Standard-Algorithmus, Faktor 1e6)."""
    coords: list[tuple[float, float]] = []
    index = lat = lon = 0
    factor = 10.0**6
    while index < len(polyline):
        for axis in range(2):
            shift = result = 0
            while True:
                byte = ord(polyline[index]) - 63
                index += 1
                result |= (byte & 0x1F) << shift
                shift += 5
                if byte < 0x20:
                    break
            if axis == 0:
                lat += ~(result >> 1) if result & 1 else (result >> 1)
            else:
                lon += ~(result >> 1) if result & 1 else (result >> 1)
        coords.append((lat / factor, lon / factor))
    return coords
