from app.api.routing import (
    Avoidance,
    Coordinate,
    Preferences,
    RideStyle,
    RouteRequest,
    Vehicle,
    _valhalla_payload,
)


def test_route_preferences_are_translated_to_valhalla_costing() -> None:
    request = RouteRequest(
        waypoints=[Coordinate(lat=48.1, lon=11.5), Coordinate(lat=49.4, lon=11.1)],
        preferences=Preferences(
            vehicle=Vehicle.motorcycle,
            ride_style=RideStyle.extra_curvy,
            avoid={Avoidance.toll, Avoidance.ferry},
        ),
    )

    payload = _valhalla_payload(request)

    assert payload["costing"] == "motorcycle"
    options = payload["costing_options"]["motorcycle"]
    assert options["use_highways"] == 0.0
    assert options["use_tolls"] == 0.0
    assert options["use_ferry"] == 0.0
