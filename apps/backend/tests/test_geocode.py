from app.api.geocode import _normalize


def test_normalize_maps_photon_feature_to_public_contract() -> None:
    payload = {
        "features": [
            {
                "properties": {
                    "osm_type": "N",
                    "osm_id": 123,
                    "name": "Marienplatz",
                    "city": "München",
                    "postcode": "80331",
                },
                "geometry": {"coordinates": [11.5755, 48.1375]},
            }
        ]
    }

    places = _normalize(payload)

    assert len(places) == 1
    assert places[0].id == "N:123"
    assert places[0].label == "Marienplatz"
    assert places[0].detail == "80331 München"
    assert places[0].lat == 48.1375
    assert places[0].lon == 11.5755


def test_normalize_ignores_features_without_coordinates() -> None:
    assert _normalize({"features": [{"properties": {}, "geometry": {}}]}) == []
