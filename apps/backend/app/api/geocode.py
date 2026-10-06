"""Geocoding-Endpoints (docs/04-api.md §2).

Dünne, normalisierende Proxy-Schicht vor Photon – die App kennt Photon nicht.
Photon-URL kommt aus der Environment (docs/10-dev-process.md §2).
"""

from typing import Any

import httpx
from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel

from ..core.config import get_settings
from ..core.security import require_client_token


class PlaceOut(BaseModel):
    """Normalisiertes Suchergebnis (Vertrag, docs/04-api.md)."""

    id: str
    label: str
    detail: str | None = None
    lat: float
    lon: float


class PhotonClient:
    """Minimaler Async-Client für Photon (Austauschbarkeit: eigener Adapter)."""

    def __init__(self, base_url: str) -> None:
        self._base_url = base_url.rstrip("/")
        self._client = httpx.AsyncClient(timeout=5.0)

    async def fetch(self, path: str, params: dict[str, Any]) -> dict[str, Any]:
        response = await self._client.get(f"{self._base_url}{path}", params=params)
        response.raise_for_status()
        return response.json()


photon_client = PhotonClient(get_settings().photon_url)

router = APIRouter(
    prefix="/api/v1",
    tags=["search"],
    dependencies=[Depends(require_client_token)],
)


@router.get("/geocode", response_model=list[PlaceOut])
async def geocode(
    q: str = Query(min_length=2, max_length=120),
    lat: float | None = Query(default=None, ge=-90, le=90),
    lon: float | None = Query(default=None, ge=-180, le=180),
    limit: int = Query(default=10, ge=1, le=20),
) -> list[PlaceOut]:
    """Forward-Geocoding: Ort, PLZ, Straße, POI (Bias auf aktuelle Position)."""
    params: dict[str, Any] = {"q": q, "lang": "de", "limit": limit}
    if lat is not None and lon is not None:
        params["lat"] = lat
        params["lon"] = lon
    data = await photon_client.fetch("/api", params)
    return _normalize(data)


@router.get("/reverse", response_model=list[PlaceOut])
async def reverse(
    lat: float = Query(ge=-90, le=90),
    lon: float = Query(ge=-180, le=180),
    limit: int = Query(default=1, ge=1, le=5),
) -> list[PlaceOut]:
    """Reverse-Geocoding für Waypoint-Labels (docs/09-mvp-plan.md, M2)."""
    data = await photon_client.fetch(
        "/reverse", {"lat": lat, "lon": lon, "lang": "de", "limit": limit}
    )
    return _normalize(data)


def _normalize(payload: dict[str, Any]) -> list[PlaceOut]:
    """Mappt Photon-FeatureCollection auf den schmalen PlaceOut-Vertrag."""
    places: list[PlaceOut] = []
    for feature in payload.get("features", []):
        props: dict[str, Any] = feature.get("properties", {})
        geometry = feature.get("geometry", {})
        coords = geometry.get("coordinates", [None, None])
        if len(coords) != 2 or coords[0] is None or coords[1] is None:
            continue

        osm_type = props.get("osm_type")
        osm_id = props.get("osm_id")
        place_id = f"{osm_type}:{osm_id}" if osm_type and osm_id else f"anon:{len(places)}"

        label = props.get("name") or _street_label(props) or "Unbenannter Ort"
        detail = _detail(props)

        places.append(
            PlaceOut(
                id=place_id,
                label=label,
                detail=detail,
                lat=float(coords[1]),
                lon=float(coords[0]),
            )
        )
    return places


def _street_label(props: dict[str, Any]) -> str | None:
    street = props.get("street")
    housenumber = props.get("housenumber")
    if street and housenumber:
        return f"{street} {housenumber}"
    return street


def _detail(props: dict[str, Any]) -> str | None:
    """Detail-Zeile: [Hausnummer+Straße, PLZ+Ort, Region, Land]."""
    parts: list[str] = []
    street = _street_label(props)
    if street and props.get("name"):
        parts.append(street)

    city = props.get("city") or props.get("town") or props.get("village")
    postcode = props.get("postcode")
    locality = " ".join(x for x in [postcode, city] if x)
    if locality:
        parts.append(locality)

    for key in ("state", "country"):
        if props.get(key):
            parts.append(props[key])

    return ", ".join(parts) if parts else None
