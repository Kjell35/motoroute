"""MotoRoute Backend – dünne API-Grenze vor Valhalla/Photon (docs/02-architecture.md)."""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .core.config import get_settings
from .api.geocode import router as geocode_router
from .api.routing import router as routing_router
from .api.pois import router as pois_router

settings = get_settings()

app = FastAPI(
    title=settings.app_name,
    version="0.1.0",
    description=(
        "Routing, Suche, POIs und Traffic für MotoRoute. "
        "Präferenzen sind stateless pro Request (docs/04-api.md)."
    ),
)

# Dev-CORS: Android-Emulator/lokal. Prod: restriktiv (docs/07-privacy-security.md).
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

# Die App spricht ausschließlich mit dieser API-Grenze, nie direkt mit Photon.
app.include_router(geocode_router)
app.include_router(routing_router)
app.include_router(pois_router)


@app.get("/health")
def health() -> dict[str, str]:
    """Liveness/Readiness für Compose-Healthchecks und CI-Smoke."""
    return {"status": "ok", "service": "motoroute-backend"}
