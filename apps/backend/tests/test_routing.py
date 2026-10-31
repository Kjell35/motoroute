import asyncio

from app.api.routing import (
    Avoidance,
    Coordinate,
    Preferences,
    RideStyle,
    RoundtripRequest,
    RouteRequest,
    Vehicle,
    _roundtrip_request,
    _segments_from_trip,
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


def test_unpaved_style_prefers_trails_and_disables_highways() -> None:
    request = RouteRequest(
        waypoints=[Coordinate(lat=48.1, lon=11.5), Coordinate(lat=49.4, lon=11.1)],
        preferences=Preferences(vehicle=Vehicle.motorcycle, ride_style=RideStyle.unpaved),
    )
    options = _payload(request)["costing_options"]["motorcycle"]
    assert options["use_highways"] == 0.0
    assert options["use_trails"] == 1.0


def test_each_ride_style_produces_distinct_costing() -> None:
    options_by_style = {}
    for style in RideStyle:
        request = RouteRequest(
            waypoints=[Coordinate(lat=48.1, lon=11.5), Coordinate(lat=49.4, lon=11.1)],
            preferences=Preferences(vehicle=Vehicle.motorcycle, ride_style=style),
        )
        options_by_style[style] = _payload(request)["costing_options"]["motorcycle"]
    assert len(options_by_style) == 5
    assert len({tuple(sorted(o.items())) for o in options_by_style.values()}) == 5


def test_roundtrip_request_is_closed_loop_starting_and_ending_at_start() -> None:
    start = Coordinate(lat=48.1, lon=11.5)
    request = RoundtripRequest(
        start=start,
        target_distance_km=120,
        direction="NORTH",
        preferences=Preferences(vehicle=Vehicle.motorcycle, ride_style=RideStyle.curvy),
    )
    route = _roundtrip_request(request)
    assert route.waypoints[0] == start
    assert route.waypoints[-1] == start
    # Start, zwei Ringpunkte, Start: ein geschlossenes Dreieck.
    assert len(route.waypoints) == 4


def test_trip_maneuvers_become_turn_segments_in_meters_and_seconds() -> None:
    trip = {
        "legs": [
            {
                "maneuvers": [
                    {"instruction": "Turn left onto B12.", "length": 1.25, "time": 90.4},
                    {"length": 0.5, "time": 20},
                ]
            },
            {
                "maneuvers": [
                    {"instruction": "You have arrived at your destination.", "length": 0.0, "time": 0},
                ]
            },
        ]
    }
    segments = _segments_from_trip(trip)
    assert [s.instruction for s in segments] == [
        "Turn left onto B12.",
        "You have arrived at your destination.",
    ]
    assert segments[0].distance_m == 1250
    assert segments[0].duration_s == 90


def test_without_towns_avoidance_no_polygons_in_payload() -> None:
    request = RouteRequest(
        waypoints=[Coordinate(lat=48.1, lon=11.5), Coordinate(lat=49.4, lon=11.1)],
        preferences=Preferences(vehicle=Vehicle.motorcycle, ride_style=RideStyle.curvy),
    )

    payload = _payload(request)
    assert "avoid_polygons" not in payload
