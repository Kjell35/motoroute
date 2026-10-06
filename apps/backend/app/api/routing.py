"""Routing-Vertrag vor Valhalla.

Die App sendet Präferenzen bei jedem Request; sie werden weder gespeichert
noch für ein Bewegungsprofil verwendet.
"""

from enum import Enum
from typing import Any

import httpx
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from ..core.config import get_settings
from ..core.security import require_client_token


class Vehicle(str, Enum):
    car = "car"
    motorcycle = "motorcycle"
    bicycle = "bicycle"


class RideStyle(str, Enum):
    fast = "fast"
    curvy = "curvy"
    extra_curvy = "extra_curvy"
    fast_and_curvy = "fast_and_curvy"


class Avoidance(str, Enum):
    highway = "highway"
    ferry = "ferry"
    toll = "toll"
    unpaved = "unpaved"
    cycleway = "cycleway"


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


class RouteResponse(BaseModel):
    candidates: list[RouteCandidate]


def _valhalla_payload(request: RouteRequest) -> dict[str, Any]:
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
    return {
        "locations": [point.model_dump() for point in request.waypoints],
        "costing": request.preferences.vehicle.value,
        "costing_options": {request.preferences.vehicle.value: options},
        "units": "kilometers",
        "language": "de-DE",
    }


router = APIRouter(prefix="/api/v1", tags=["routing"], dependencies=[Depends(require_client_token)])


@router.post("/route", response_model=RouteResponse)
async def route(request: RouteRequest) -> RouteResponse:
    settings = get_settings()
    try:
        async with httpx.AsyncClient(timeout=12.0) as client:
            response = await client.post(
                f"{settings.valhalla_url.rstrip('/')}/route",
                json=_valhalla_payload(request),
            )
            response.raise_for_status()
        trip: dict[str, Any] = response.json()["trip"]
    except (httpx.HTTPError, KeyError, TypeError, ValueError) as error:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "code": "ROUTING_UNAVAILABLE",
                "message": "Routing ist gerade nicht verfügbar.",
            },
        ) from error
    summary: dict[str, Any] = trip["summary"]
    shape = next((leg.get("shape") for leg in trip.get("legs", []) if leg.get("shape")), None)
    return RouteResponse(
        candidates=[
            RouteCandidate(
                distance_m=round(float(summary["length"]) * 1000),
                duration_s=round(float(summary["time"])),
                geometry_polyline6=shape,
            )
        ]
    )
