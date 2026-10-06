"""API-Schutz: App-Attestation light (docs/04-api.md §4).

MVP: statischer Client-Token aus der Environment. Kein User-Login im MVP
(Zero-Budget/Kein-Account-Prinzip, docs/07-privacy-security.md).
Später: Token-Rotation, echte App-Attestation (Play Integrity).
"""

from fastapi import Header, HTTPException, status

from .config import get_settings


async def require_client_token(
    x_client_token: str | None = Header(default=None),
) -> None:
    """Prüft den Client-Token; in der Entwicklung optional (ohne Header erlaubt)."""
    settings = get_settings()
    expected = getattr(settings, "client_token", None)
    if expected is None:
        return  # Dev-Modus: kein Token konfiguriert -> offen (nur lokal nutzen!)
    if x_client_token != expected:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "INVALID_CLIENT_TOKEN", "message": "Missing or invalid client token"},
        )
