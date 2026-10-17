"""Tests für die OSM-Ortskerne-Ortsvermeidung (ohne Live-Overpass-Zugriff)."""

import asyncio

import httpx2
import pytest
from shapely.geometry import Polygon

from app.api.routing import (
    Avoidance,
    Coordinate,
    Preferences,
    RideStyle,
    RouteRequest,
    Vehicle,
    _valhalla_payload,
)
from app.api.town_polygons import (
    _adaptive_simplify_meters,
    _buffer_ring_meters,
    _ring_from_geometry,
    polygon_cache_clear,
    town_polygons,
)


def _waypoint_request() -> RouteRequest:
    return RouteRequest(
        waypoints=[Coordinate(lat=48.1, lon=11.5), Coordinate(lat=49.4, lon=11.1)],
        preferences=Preferences(
            vehicle=Vehicle.motorcycle,
            ride_style=RideStyle.curvy,
            avoid={Avoidance.towns},
        ),
    )


def test_ring_from_geometry_closes_ring_and_dedupes_points() -> None:
    ring = _ring_from_geometry([[11.5, 48.1], [11.6, 48.2], [11.55, 48.15], [11.5, 48.05]])
    assert ring is not None
    assert ring[0] == ring[-1]  # geschlossener Ring
    assert len(ring) >= 4


def test_ring_from_geometry_rejects_too_small_geometry() -> None:
    assert _ring_from_geometry([[11.5, 48.1], [11.6, 48.2]]) is None
    assert _ring_from_geometry([]) is None


@pytest.mark.asyncio
async def test_town_polygons_fails_open_without_overpass(monkeypatch) -> None:
    """Overpass down: kein Fallback-Kreis um den Wegpunkt (live-Fund, docs/14 §5.4).

    Ein Ring um den Wegpunkt selbst isoliert ihn -> Valhalla HTTP 400
    
    "No path could be found". Fail-open: ohne Overpass-Leben keine Polygone.
    """
    async def _fail(query: str):
        raise httpx2.ConnectError("Overpass down")

    monkeypatch.setattr("app.api.town_polygons._overpass", _fail)
    rings = await town_polygons([(48.1, 11.5)])
    assert rings == []  # Fail-open, kein Ein-Ring-Um-Wegpunkt


@pytest.mark.asyncio
async def test_town_polygons_uses_osm_geometry_when_available(monkeypatch) -> None:
    async def _mock_overpass(query: str):
        return {
            "elements": [
                {
                    "type": "way",
                    "id": 1,
                    "geometry": [[11.5, 48.1], [11.6, 48.2], [11.55, 48.15], [11.5, 48.05]],
                }
            ]
        }

    monkeypatch.setattr("app.api.town_polygons._overpass", _mock_overpass)
    rings = await town_polygons([(48.1, 11.5)], buffer_m=300.0)
    assert len(rings) == 1
    assert rings[0][0] == rings[0][-1]
    # Echter OSM-Ring, bufferfach rundet: der Ring wird an Simplify-Auflösung
    # angepasst (nicht mehr exakt 4-Punkte-Ausgang) – valider Bereich des Tests.
    assert len(rings[0]) >= 5


@pytest.mark.asyncio
async def test_payload_with_towns_requests_osm_polygons(monkeypatch) -> None:
    async def _fixed_polygons(waypoints, fallback_radius_m=1500.0, buffer_m=300.0):
        return [[{"lat": 1.0, "lon": 2.0}, {"lat": 3.0, "lon": 4.0}, {"lat": 1.0, "lon": 2.0}]]

    monkeypatch.setattr("app.api.routing.town_polygons", _fixed_polygons)
    payload = await _valhalla_payload(_waypoint_request())
    # Die Payload-Grenze konvertiert Dict-Ringe in Valhallas Parse-Format:
    # Paare aus [lon, lat] (live verifiziert 2026-10-11; Valhalla 3.9.1).
    assert payload["avoid_polygons"] == [[[2.0, 1.0], [4.0, 3.0], [2.0, 1.0]]]


def test_payload_without_towns_has_no_polygons() -> None:
    request = RouteRequest(
        waypoints=[Coordinate(lat=48.1, lon=11.5), Coordinate(lat=49.4, lon=11.1)],
        preferences=Preferences(vehicle=Vehicle.motorcycle, ride_style=RideStyle.curvy),
    )
    payload = asyncio.run(_valhalla_payload(request))
    assert "avoid_polygons" not in payload


@pytest.fixture(autouse=True)
def _clean_polygon_cache():
    polygon_cache_clear()
    yield
    polygon_cache_clear()


async def _mock_overpass_counting(calls: list[str]):
    async def _mock_overpass(query: str):
        calls.append(query)
        return {
            "elements": [
                {
                    "type": "way",
                    "id": 1,
                    "geometry": [[11.5, 48.1], [11.6, 48.2], [11.55, 48.15], [11.5, 48.05]],
                }
            ]
        }

    return _mock_overpass


def _shoelace_area_m2(ring: list[dict[str, float]]) -> float:
    """Grober Flächenvergleich in Meter-Näherung (Shoelace auf lat/lon)."""
    meters_lat = 111_320.0
    meters_lon = 111_320.0 * 0.66
    pts = [(p["lon"] * meters_lon, p["lat"] * meters_lat) for p in ring[:-1]]
    return abs(
        sum(
            pts[i][0] * pts[(i + 1) % len(pts)][1]
            - pts[(i + 1) % len(pts)][0] * pts[i][1]
            for i in range(len(pts))
        )
    ) / 2


def _peak_x_m(ring: list[dict[str, float]], origin: tuple[float, float]) -> float:
    """Entfernung des östlichsten Ringpunkts vom Origin in Meter (lon-Anteil)."""
    cos_lat = 0.66
    return max((p["lon"] - origin[1]) * 111_320.0 * cos_lat for p in ring)


def test_adaptive_simplify_preserves_spike_within_budget() -> None:
    """Qualitätssprung-Kern: Ein spike-打架 (Kurvenecke/Sporn, 250 m) überlebt
    adaptives Douglas-Peucker, den naives Strided-Slicing sicher verzerren würde."""
    # Rechteck mit einem scharfen 250-m-Spike an Ostseite.
    meter_shape = [
        (0.0, 0.0),
        (2000.0, 0.0),
        (2250.0, 800.0),   # Spike-Spitze – naives [::2]-Slicing fällt hier
        (2000.0, 1600.0),
        (0.0, 1600.0),
    ]
    polygon = Polygon(meter_shape)

    simplified = _adaptive_simplify_meters(polygon, max_points=48)
    peak_x = max(x for x, _y in simplified.exterior.coords[:-1])

    # Simplify-Kurve über den Sporn toleriert bis ~250 m ohne Abbruch (ein
    # Shapely-verifiziertes Verhalten); wir setzen den Grenzwert konservativ.
    assert peak_x >= 2250.0 - 10.0
    # Budget strikt eingehalten.
    vertex_count = len(simplified.exterior.coords) - 1
    assert vertex_count <= 48


def test_adaptive_simplify_hits_point_budget_tightly() -> None:
    """Bei kleinem Max-Budget liefert die Bisektion ein wahrhaft zulässiges Objekt."""
    # Komplexes, abgerundetes Vieleck (gekrümmte Umrisse wie bei echten Ortskernen).
    import math as _m
    n = 400
    meter_shape = [
        (2000 + 1500 * _m.cos(2 * _m.pi * i / n), 1500 + 1500 * _m.sin(2 * _m.pi * i / n))
        for i in range(n)
    ]
    polygon = Polygon(meter_shape)

    simplified = _adaptive_simplify_meters(polygon, max_points=32)
    vertex_count = len(simplified.exterior.coords) - 1
    assert vertex_count <= 32
    # Flächenverlust klein (gute Detailtreue trotz Budget).
    assert simplified.area > 0.85 * polygon.area


@pytest.mark.asyncio
async def test_buffer_ring_expands_ring_outward() -> None:
    """Echtes Ring-Buffering: Ring erweitert sich um ~buffer_m Meter nach außen."""
    origin = (48.1, 11.5)
    ring = _ring_from_geometry(
        [[11.5, 48.1], [11.52, 48.1], [11.52, 48.12], [11.5, 48.12]]
    )
    assert ring is not None
    buffered = _buffer_ring_meters(ring, buffer_m=300.0, origin=origin)
    assert buffered[0] == buffered[-1]  # geschlossen

    def _area(ring: list[dict[str, float]]) -> float:
        # Shoelace in Meter-Näherung (grober Flächenvergleich).
        meters_lat = 111_320.0
        meters_lon = 111_320.0 * 0.66
        pts = [(p["lon"] * meters_lon, p["lat"] * meters_lat) for p in ring[:-1]]
        return abs(
            sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
                for i in range(len(pts)))
        ) / 2

    area_before = _area(ring)
    area_after = _area(buffered)
    # 300 m Außenschale um ~2.1 × 2.2 km Rechteck: Area wächst deutlich.
    assert area_after > area_before * 1.10


@pytest.mark.asyncio
async def test_town_polygons_applies_buffer_to_osm_geometry(monkeypatch) -> None:
    """buffer_m fließt in echte OSM-Ringe ein (nicht nur Kreis-Fallback)."""
    async def _mock_overpass(_query: str):
        return {
            "elements": [
                {
                    "type": "way",
                    "id": 1,
                    "geometry": [[11.5, 48.1], [11.52, 48.12], [11.51, 48.13], [11.5, 48.11]],
                }
            ]
        }

    monkeypatch.setattr("app.api.town_polygons._overpass", _mock_overpass)
    rings = await town_polygons([(48.1, 11.5)], buffer_m=500.0)
    assert len(rings) == 1
    assert rings[0][0] == rings[0][-1]
    # Der gepufferte Ring hat mehr Punkte als der 4-Punkte-Ausgang (simplify
    # bewahrt Rundung des Puffers).
    assert len(rings[0]) >= 5


@pytest.mark.asyncio
async def test_fallback_ring_does_not_need_extra_buffer(monkeypatch) -> None:
    """Fail-open (live-Fund): Overpass down → keine Polygone, kein Fallback-Ring.

    Der frühere Fallback-Kreis um den Wegpunkt selbst hat die Route
    unmöglich gemacht (Valhalla HTTP 400 "No path")."""
    async def _fail(_query: str):
        raise httpx2.ConnectError("Overpass down")

    monkeypatch.setattr("app.api.town_polygons._overpass", _fail)
    rings = await town_polygons([(48.1, 11.5)], fallback_radius_m=1500.0, buffer_m=300.0)
    assert rings == []


@pytest.mark.asyncio
async def test_cache_hit_skips_second_overpass_call(monkeypatch) -> None:
    """Rate-Limit-Schutz: derselbe Wegpunkt ruft Overpass nur einmal."""
    calls: list[str] = []

    async def _mock_overpass(_query: str):
        calls.append(_query)
        return {
            "elements": [
                {
                    "type": "way",
                    "id": 1,
                    "geometry": [[11.5, 48.1], [11.52, 48.12], [11.51, 48.13], [11.5, 48.11]],
                }
            ]
        }

    monkeypatch.setattr("app.api.town_polygons._overpass", _mock_overpass)

    rings_first = await town_polygons([(48.1, 11.5)])
    rings_second = await town_polygons([(48.1, 11.5)])
    assert len(calls) == 1
    assert rings_first == rings_second


@pytest.mark.asyncio
async def test_cache_avoids_repeated_overpass_calls_on_failure(monkeypatch) -> None:
    """Overpass-Ausfall: Fail-open-Ergebnis (leere Zelle) wird gecacht —
    keine Wiederhol-Requests pro User-Routing-Call."""
    calls: list[str] = []

    async def _fail(_query: str):
        calls.append(_query)
        raise httpx2.ConnectError("Overpass down")

    monkeypatch.setattr("app.api.town_polygons._overpass", _fail)
    rings_first = await town_polygons([(48.1, 11.5)])
    rings_second = await town_polygons([(48.1, 11.5)], fallback_radius_m=1500.0)

    assert len(calls) == 1  # erster Aufruf schlägt fehl, zweiter liest vom Cache
    assert rings_first == rings_second == []  # Fail-open = keine Ringe
