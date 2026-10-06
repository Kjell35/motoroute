"""Environment-Konfiguration (fail fast, siehe docs/10-dev-process.md §2)."""

from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Alle Werte kommen aus der Environment – keine Secrets im Code."""

    # Lokale Projekt-.env für `uvicorn` aus jedem Arbeitsverzeichnis;
    # im Container überschreibt Compose diese Werte explizit.
    model_config = SettingsConfigDict(
        env_prefix="MOTOROUTE_",
        env_file=Path(__file__).resolve().parents[4] / ".env",
        extra="ignore",
    )

    app_name: str = "MotoRoute Backend"
    valhalla_url: str = "http://localhost:8002"
    photon_url: str = "https://photon.komoot.io"
    overpass_url: str = "https://overpass-api.de/api/interpreter"
    tomtom_api_key: str | None = None
    tomtom_traffic_url: str = "https://api.tomtom.com/traffic/services/5/incidentDetails"
    client_token: str | None = None
    rate_limit_per_minute: int = 60


@lru_cache
def get_settings() -> Settings:
    """Singleton-Settings; invalidiert bei Tests via get_settings.cache_clear()."""
    return Settings()
