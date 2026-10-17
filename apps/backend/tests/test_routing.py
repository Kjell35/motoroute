import asyncio

from app.api.routing import (
    Avoidance,
    Coordinate,
    Preferences,
    RideStyle,
    RouteRequest,
    Vehicle,
    _valhalla_payload,
)


def _payload(request: RouteRequest):
    return asyncio.run(_valhalla_payload(request))


def test_route_preferences_are_translated_to_valhalla_costing() -> None:
    request = RouteRequest(
        waypoints=[Coordinate(lat=48.1, lon=11.5), Coordinate(lat=49.4, lon=11.1)],
        preferences=Preferences(
            vehicle=Vehicle.motorcycle,
            ride_style=RideStyle.extra_curvy,
            avoid={Avoidance.toll, Avoidance.ferry},
        ),
    )

    payload = _payload(request)

    assert payload["costing"] == "motorcycle"
    options = payload["costing_options"]["motorcycle"]
    assert options["use_highways"] == 0.0
    assert options["use_tolls"] == 0.0
    assert options["use_ferry"] == 0.0


def test_avoid_towns_without_overpass_fails_open(monkeypatch) -> None:
    """Ortskern-Meidung ohne Overpass: avoid_polygons bleibt ABWESEND.

    Live-Fund (docs/14 §5.4): der frühere Fallback-Kreis um den Wegpunkt
    selbst isolierte diesen komplett -> Valhalla HTTP 400 "No path could
    be found". Fail-open: kein Key statt kaputter Route.
    """

    async def _fail(_waypoints, fallback_radius_m=1500.0, buffer_m=300.0):
        return []

    monkeypatch.setattr("app.api.routing.town_polygons", _fail)
    request = RouteRequest(
        waypoints=[Coordinate(lat=48.1, lon=11.5), Coordinate(lat=49.4, lon=11.1)],
        preferences=Preferences(
            vehicle=Vehicle.motorcycle,
            ride_style=RideStyle.curvy,
            avoid={Avoidance.towns},
        ),
    )

    payload = asyncio.run(_valhalla_payload(request))
    assert payload.get("avoid_polygons", []) == []


def test_without_towns_avoidance_no_polygons_in_payload() -> None:
    request = RouteRequest(
        waypoints=[Coordinate(lat=48.1, lon=11.5), Coordinate(lat=49.4, lon=11.1)],
        preferences=Preferences(vehicle=Vehicle.motorcycle, ride_style=RideStyle.curvy),
    )

    payload = _payload(request)
    assert "avoid_polygons" not in payload
