"""Tests für die „Route am Computer planen“-Pairing (docs/04-api.md, M3)."""

from fastapi.testclient import TestClient

from app.api.pairing import reset_store
from app.main import app


def _client() -> TestClient:
    return TestClient(app)


def setup_function() -> None:
    reset_store()


def test_start_pairing_returns_token_and_url() -> None:
    with _client() as client:
        response = client.post("/api/v1/pairing/start")
        assert response.status_code == 200
        body = response.json()
        assert len(body["token"]) == 32
        assert all(char in "0123456789ABCDEF" for char in body["token"])
        assert body["token"] == body["token"].upper()
        assert body["plan_url"].endswith(f"/plan/{body['token']}")
        assert body["expires_in_seconds"] > 0


def test_start_pairing_returns_multiple_candidate_urls() -> None:
    """App-zu-App-Pairing (LAN/Hotspot): Der QR-Code deckt ALLE Kandidaten ab."""
    with _client() as client:
        body = client.post("/api/v1/pairing/start").json()
        urls = body["plan_urls"]
        assert isinstance(urls, list) and len(urls) >= 1
        assert urls[0] == body["plan_url"]
        for url in urls:
            # Jede Kandidaten-URL muss auf denselben Token zeigen.
            assert url.endswith(f"/plan/{body['token']}")
            assert url.startswith("http://")
        # Loopback/Link-Local (WSL-vEthernet) dürfen nicht als primäre Adressen zeigen.
        assert not any("127.0.0.1" in url or "localhost" in url for url in urls[1:])


def test_plan_roundtrip_via_update_and_read() -> None:
    with _client() as client:
        token = client.post("/api/v1/pairing/start").json()["token"]

        # Vor dem Schreiben: leerer Plan, aber gültiger Status.
        empty = client.get(f"/api/v1/pairing/{token}")
        assert empty.status_code == 200
        assert empty.json()["points"] == []

        put = client.put(
            f"/api/v1/pairing/{token}",
            json={"points": [
                {"label": "München", "lat": 48.137, "lon": 11.575},
                {"label": "Oberaudorf", "lat": 47.647, "lon": 12.214},
            ]},
        )
        assert put.status_code == 200
        assert [point["label"] for point in put.json()["points"]] == ["München", "Oberaudorf"]

        # Kleinschreibung im Token-Eingabepfad ist bewusst erlaubt.
        got = client.get(f"/api/v1/pairing/{token.lower()}")
        assert got.status_code == 200
        assert got.json()["points"][0]["label"] == "München"


def test_unknown_token_returns_404_not_sniffable() -> None:
    with _client() as client:
        assert client.get("/api/v1/pairing/00000000000000000000000000000000").status_code == 404
        assert client.put(
            "/api/v1/pairing/00000000000000000000000000000000",
            json={"points": [{"label": "X", "lat": 0.0, "lon": 0.0}]},
        ).status_code == 404


def test_plan_page_is_served_for_browser() -> None:
    with _client() as client:
        token = client.post("/api/v1/pairing/start").json()["token"]
        response = client.get(f"/plan/{token}")
        assert response.status_code == 200
        assert "text/html" in response.headers["content-type"]
        assert token in response.text
        assert response.headers["cache-control"] == "no-store"

        assert client.get("/plan/ABC123").status_code == 404


def test_pairing_plan_is_scoped_to_bearer_token_and_search_is_public(monkeypatch) -> None:
    async def fake_fetch(path: str, params: dict[str, object]) -> dict[str, object]:
        assert path == "/api"
        assert params["q"] == "Mu"
        return {"features": []}

    monkeypatch.setattr("app.api.pairing.photon_client.fetch", fake_fetch)
    with _client() as client:
        token = client.post("/api/v1/pairing/start").json()["token"]
        assert client.put(
            f"/api/v1/pairing/{token}",
            json={"points": [{"label": "Start", "lat": 48.0, "lon": 11.0}]},
        ).status_code == 200
        assert client.get(f"/api/v1/pairing/{token}").json()["points"][0]["label"] == "Start"

        # Browser-Planung benutzt das isolierte Pairing-Geocoding statt des
        # geschützten allgemeinen Geocode-Endpunkts.
        search = client.get(f"/api/v1/pairing/geocode?token={token}&q=Mu&limit=6")
        assert search.status_code == 200
        assert search.json() == []
        invalid_search = client.get(
            "/api/v1/pairing/geocode?token=00000000000000000000000000000000&q=Mu"
        )
        assert invalid_search.status_code == 404


def test_plan_validation_rejects_bad_points() -> None:
    with _client() as client:
        token = client.post("/api/v1/pairing/start").json()["token"]
        assert client.put(
            f"/api/v1/pairing/{token}",
            json={"points": [{"label": "üble Koordinate", "lat": 190.0, "lon": 0.0}]},
        ).status_code == 422
        # Zu viele Punkte (Limit 12 = App-Vertrag max_length der Waypoints)
        too_many = [{"label": f"P{i}", "lat": 48.0 + i / 100, "lon": 11.0} for i in range(13)]
        assert client.put(
            f"/api/v1/pairing/{token}", json={"points": too_many}
        ).status_code == 422
