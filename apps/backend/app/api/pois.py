"""POI- und Sperrungsdaten aus OpenStreetMap/Overpass.

Die Daten sind quelloffen, aber nicht garantiert vollständig oder in Echtzeit.
Die Antwort benennt die Quelle deshalb explizit.
"""

from enum import Enum
from typing import Any

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel

from ..core.config import get_settings
from ..core.security import require_client_token


class PoiCategory(str, Enum):
    fuel = "fuel"
    moto_hotel = "moto_hotel"
    biker_meet = "biker_meet"
    campsite = "campsite"
    ice_cream = "ice_cream"
    speed_camera = "speed_camera"


class PoiOut(BaseModel):
    id: str
    category: PoiCategory
    name: str
    lat: float
    lon: float


class TrafficOut(BaseModel):
    source: str
    real_time: bool
    incidents: list[dict[str, Any]]


_TAGS: dict[PoiCategory, str] = {
    PoiCategory.fuel: '["amenity"="fuel"]',
    PoiCategory.moto_hotel: '["tourism"="hotel"]["motorcycle"]',
    PoiCategory.biker_meet: '["amenity"="motorcycle"]',
    PoiCategory.campsite: '["tourism"="camp_site"]',
    PoiCategory.ice_cream: '["amenity"="ice_cream"]',
    PoiCategory.speed_camera: '["highway"="speed_camera"]',
}

router = APIRouter(prefix="/api/v1", tags=["map"], dependencies=[Depends(require_client_token)])


def _bbox(value: str) -> tuple[float, float, float, float]:
    try:
        west, south, east, north = (float(part) for part in value.split(","))
    except ValueError as error:
        raise HTTPException(status_code=422, detail="bbox muss west,süd,ost,nord sein") from error
    if not (-180 <= west <= east <= 180 and -90 <= south <= north <= 90):
        raise HTTPException(status_code=422, detail="bbox außerhalb des gültigen Bereichs")
    return west, south, east, north


async def _overpass(query: str) -> dict[str, Any]:
    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.post(get_settings().overpass_url, data={"data": query})
            response.raise_for_status()
            return response.json()
    except httpx.HTTPError as error:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "code": "MAP_DATA_UNAVAILABLE",
                "message": "Kartendaten sind gerade nicht verfügbar.",
            },
        ) from error


@router.get("/pois", response_model=list[PoiOut])
async def pois(
    bbox: str = Query(description="west,south,east,north"),
    categories: list[PoiCategory] = Query(default=list(PoiCategory)),
) -> list[PoiOut]:
    west, south, east, north = _bbox(bbox)
    bounds = f"({south},{west},{north},{east})"
    clauses = "".join(f"nwr{_TAGS[category]}{bounds};" for category in categories)
    data = await _overpass(f"[out:json][timeout:12];({clauses});out center tags;")
    result: list[PoiOut] = []
    for element in data.get("elements", []):
        tags = element.get("tags", {})
        lat = element.get("lat") or element.get("center", {}).get("lat")
        lon = element.get("lon") or element.get("center", {}).get("lon")
        if lat is None or lon is None:
            continue
        category = next(
            (item for item, selector in _TAGS.items() if _matches(tags, selector)), None
        )
        if category in categories:
            result.append(PoiOut(
                id=f"osm:{element['type']}:{element['id']}", category=category,
                name=tags.get("name", _fallback_name(category)), lat=float(lat), lon=float(lon),
            ))
    return result


@router.get("/traffic/incidents", response_model=TrafficOut)
async def traffic_incidents(bbox: str = Query(description="west,south,east,north")) -> TrafficOut:
    west, south, east, north = _bbox(bbox)
    if get_settings().tomtom_api_key:
        return await _tomtom_traffic(west, south, east, north)
    bounds = f"({south},{west},{north},{east})"
    data = await _overpass(
        f"[out:json][timeout:12];(nwr[\"highway\"=\"construction\"]{bounds};"
        f"nwr[\"construction\"]{bounds};);out center tags;"
    )
    incidents: list[dict[str, Any]] = []
    for element in data.get("elements", []):
        center = element.get("center", element)
        if center.get("lat") is None or center.get("lon") is None:
            continue
        incidents.append({
            "id": f"osm:{element['type']}:{element['id']}", "type": "closure",
            "name": element.get("tags", {}).get("name", "Sperrung oder Baustelle"),
            "lat": center["lat"], "lon": center["lon"],
        })
    return TrafficOut(source="OpenStreetMap/Overpass", real_time=False, incidents=incidents)


async def _tomtom_traffic(west: float, south: float, east: float, north: float) -> TrafficOut:
    """Liest TomTom ausschließlich serverseitig; der API-Key bleibt aus der APK heraus."""
    settings = get_settings()
    assert settings.tomtom_api_key is not None
    fields = (
        "{incidents{type,geometry{type,coordinates},"
        "properties{id,iconCategory,magnitudeOfDelay,events{description}}}}"
    )
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(
                settings.tomtom_traffic_url,
                params={
                    "key": settings.tomtom_api_key,
                    "bbox": f"{west},{south},{east},{north}",
                    "fields": fields,
                    "language": "de-DE",
                    "t": "-1",
                },
            )
            response.raise_for_status()
        payload: dict[str, Any] = response.json()
    except httpx.HTTPError as error:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "code": "TRAFFIC_UNAVAILABLE",
                "message": "Live-Verkehr ist gerade nicht verfügbar.",
            },
        ) from error
    incidents: list[dict[str, Any]] = []
    for incident in payload.get("incidents", []):
        geometry = incident.get("geometry", {})
        coordinates = geometry.get("coordinates", [])
        properties = incident.get("properties", {})
        if not coordinates:
            continue
        point = coordinates[0] if isinstance(coordinates[0], list) else coordinates
        if len(point) < 2:
            continue
        event = next(iter(properties.get("events", [])), {})
        incidents.append({
            "id": str(properties.get("id", len(incidents))),
            "type": properties.get("iconCategory", incident.get("type", "incident")),
            "name": event.get("description", "Verkehrsmeldung"),
            "delay_seconds": properties.get("magnitudeOfDelay", 0),
            "lon": point[0],
            "lat": point[1],
        })
    return TrafficOut(source="TomTom Traffic", real_time=True, incidents=incidents)


def _matches(tags: dict[str, str], selector: str) -> bool:
    if '"fuel"' in selector:
        return tags.get("amenity") == "fuel"
    if '"camp_site"' in selector:
        return tags.get("tourism") == "camp_site"
    if '"ice_cream"' in selector:
        return tags.get("amenity") == "ice_cream"
    if '"speed_camera"' in selector:
        return tags.get("highway") == "speed_camera"
    if '"hotel"' in selector:
        return tags.get("tourism") == "hotel" and "motorcycle" in tags
    return tags.get("amenity") == "motorcycle"


def _fallback_name(category: PoiCategory) -> str:
    return category.value.replace("_", " ").title()
