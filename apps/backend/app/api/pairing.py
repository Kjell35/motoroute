"""Route am Computer planen (M3-Komfort-Feature).

Pairing-Modell:
1. Die App fragt ein zufälliges, 128-Bit starkes Pairing-Token an (POST /api/v1/pairing/start).
2. Der Token wird angezeigt (groß lesbar) und im Link kodiert:
   {public_base_url}/plan/{token}
3. Am Computer öffnet der Nutzer den Link, plant dort Start/Ziel/Stopps.
4. Die App ruft periodisch GET /api/v1/pairing/{token} ab und übernimmt
   die Waypoints in den lokalen Entwurf.

Speicher: In-Memory, TTL 30 Min., Zero-Budget (kein Redis). Ein nicht
aufgelöster Token erzeugt 404 — kein Token-Sniffing über Antwortdauer.
"""

import re
import secrets
import time
from typing import Annotated, Any

from fastapi import APIRouter, HTTPException, Query, status
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field

from ..core.config import get_settings
from .geocode import PlaceOut, _normalize, photon_client

router = APIRouter(prefix="/api/v1/pairing", tags=["pairing"])

# Eigener Router für die Browser-Seite, weil die /plan/{token}-URL bewusst
# OHNE /api/v1-Prefix im Root liegt ( Nutzer-typische, kurze URL ).
web_router = APIRouter(tags=["pairing"])

_TTL_SECONDS = 30 * 60
_STORE: dict[str, tuple[float, list[dict[str, Any]]]] = {}
_TOKEN_PATTERN = re.compile(r"^[A-F0-9]{32}$")


class PairingStartOut(BaseModel):
    # 128 Bit Zufall: Der Plan-Link ist ein kurzlebiges Bearer-Capability.
    token: str = Field(min_length=32, max_length=32)
    plan_url: str
    plan_urls: list[str] = Field(min_length=1)
    expires_in_seconds: int


class PlanPoint(BaseModel):
    """Ein von der Web-Planung übernommener Punkt (wie die App ihn kennt)."""

    label: str = Field(min_length=1, max_length=160)
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    detail: str | None = Field(default=None, max_length=200)


class PlanOut(BaseModel):
    token: str = Field(min_length=32, max_length=32)
    points: list[PlanPoint]
    expires_in_seconds: int


def _cleanup() -> None:
    now = time.monotonic()
    stale = [key for key, (stamp, _) in _STORE.items() if now - stamp > _TTL_SECONDS]
    for key in stale:
        _STORE.pop(key, None)


@router.post("/start", response_model=PairingStartOut)
async def start_pairing() -> PairingStartOut:
    """Erzeugt einen frischen Pairing-Token und alle erreichbaren Plan-Links.

    Der QR-Code in der App kodiert ALLE Kandidaten (ein Code pro URL-Zeile):
    die lesende App/der Scan probiert sie der Reihe nach durch. Damit klappt
    App-zu-App-Pairing über LAN **und** Hotspot, ohne dass der Nutzer etwas
    umkonfiguriert (docs/14 §5.5).
    """
    settings = get_settings()
    _cleanup()
    token = secrets.token_hex(16).upper()  # 128 Bit; URL-safe hex
    _STORE[token] = (time.monotonic(), [])
    bases = _candidate_bases(settings)
    urls = [f"{base}/plan/{token}" for base in bases]
    return PairingStartOut(
        token=token,
        plan_url=urls[0],
        plan_urls=urls,
        expires_in_seconds=_TTL_SECONDS,
    )


def _candidate_bases(settings: Any) -> list[str]:
    """Alle plausiblen Backend-Basen: konfigurierte URL + automatisch ermittelte LAN-IPs.

    Reihenfolge: explizit konfigurierte URL zuerst, dann automatisch entdeckte
    Nicht-Loopback-/Nicht-Link-Local-IPv4-Adressen derInterfaces (deckt
    Ethernet, WLAN und Android-Hotspot-Interface ab).
    """
    candidates: list[str] = []
    configured = (settings.public_base_url or "").rstrip("/")
    if configured:
        candidates.append(configured)
    for ip in _local_ipv4s():
        base = f"http://{ip}:8000"
        if base not in candidates:
            candidates.append(base)
    if not candidates:
        candidates.append("http://localhost:8000")
    return candidates


def _local_ipv4s() -> list[str]:
    """Nicht-proxyfähige IPv4-Adressen dieses Rechners (Windows/macOS/Linux)."""
    import ipaddress
    import socket

    found: list[str] = []
    try:
        hostname = socket.gethostname()
        for info in socket.getaddrinfo(hostname, None, family=socket.AF_INET):
            ip = info[4][0]
            if isinstance(ip, str) and _usable(ip, ipaddress):
                found.append(ip)
    except OSError:
        pass
    # Primäre Route (UDP ohne Paket gibt die Quell-IP der Standard-Route zurück).
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.settimeout(0.5)
            probe.connect(("192.0.2.254", 9))  # TEST-NET, kein Paket gaat raus
            ip = probe.getsockname()[0]
            if _usable(ip, ipaddress) and ip not in found:
                found.insert(0, ip)
    except OSError:
        pass
    return found


def _usable(ip: str, ipaddress: Any) -> bool:
    """Keine Loopback-, Link-Local- oder Test-Net-Adressen (z. B. 127.*, 169.254.*)."""
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return False
    return not (addr.is_loopback or addr.is_link_local or addr.is_multicast)


@router.get("/geocode", response_model=list[PlaceOut])
async def pairing_geocode(
    token: str = Query(min_length=32, max_length=32),
    q: str = Query(min_length=2, max_length=120),
    limit: int = Query(default=6, ge=1, le=10),
) -> list[PlaceOut]:
    """Öffentliche Ortssuche für den per Einmal-Link geöffneten Browser-Planer.

    Der Web-Planer darf kein statisches App-Client-Token im Browser benötigen
    oder offenlegen. Die Suche liefert nur öffentliche Photon-Ortsdaten.
    """
    _cleanup()
    if token.upper() not in _STORE or not _TOKEN_PATTERN.fullmatch(token.upper()):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Plan nicht gefunden")
    payload = await photon_client.fetch("/api", {"q": q, "lang": "de", "limit": limit})
    return _normalize(payload)


@router.get("/{token}", response_model=PlanOut)
async def read_plan(token: str) -> PlanOut:
    """App fragt den Plan ab; 404 bei ungültigem/abgelaufenem Token."""
    _cleanup()
    key = token.upper()
    if not _TOKEN_PATTERN.fullmatch(key):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Plan nicht gefunden")
    entry = _STORE.get(key)
    if entry is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "PAIRING_TOKEN_UNKNOWN",
                    "message": "Pairing-Token ungültig oder abgelaufen."},
        )
    stamp, raw_points = entry
    return PlanOut(
        token=key,
        points=[PlanPoint(**point) for point in raw_points],
        expires_in_seconds=max(0, _TTL_SECONDS - int(time.monotonic() - stamp)),
    )


class PlanUpdate(BaseModel):
    """Body der PUT-Anfrage: {"points": [...]} (max. 12 = App-Vertrag)."""

    points: Annotated[list[PlanPoint], Field(min_length=0, max_length=12)]


@router.put("/{token}", response_model=PlanOut)
async def update_plan(token: str, payload: PlanUpdate) -> PlanOut:
    """Web-Planner schreibt den Plan. Ersetzt den Entwurf komplett."""
    _cleanup()
    key = token.upper()
    if not _TOKEN_PATTERN.fullmatch(key):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Plan nicht gefunden")
    entry = _STORE.get(key)
    if entry is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "PAIRING_TOKEN_UNKNOWN",
                    "message": "Pairing-Token ungültig oder abgelaufen."},
        )
    _STORE[key] = (entry[0], [point.model_dump() for point in payload.points])
    stamp, raw_points = _STORE[key]
    return PlanOut(
        token=key,
        points=[PlanPoint(**point) for point in raw_points],
        expires_in_seconds=max(0, _TTL_SECONDS - int(time.monotonic() - stamp)),
    )


@web_router.get("/plan/{token}", response_class=HTMLResponse, include_in_schema=False)
async def plan_page(token: str) -> HTMLResponse:
    """Web-Planner-Seite (Browser am Computer) — Leaflet + Suche + PUT /pairing/{token}."""
    _cleanup()
    key = token.upper()
    if not _TOKEN_PATTERN.fullmatch(key) or key not in _STORE:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Plan nicht gefunden")
    return HTMLResponse(
        _PAGE_HTML.replace("{{TOKEN}}", key),
        headers={"Cache-Control": "no-store", "Referrer-Policy": "no-referrer"},
    )


def reset_store() -> None:
    """Test-Reset (nur in Tests benutzt)."""
    _STORE.clear()


_PAGE_HTML = """<!DOCTYPE html>
<html lang="de"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MotoRoute · Route am Computer planen</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<style>
  body { margin:0; font-family:system-ui,sans-serif; background:#0E1116; color:#E7ECF3; }
  #app { display:grid; grid-template-columns: 340px 1fr; height:100vh; }
  #panel { padding:16px; background:#12161D; overflow-y:auto; }
  #map { height:100vh; }
  input, button { font-size:14px; padding:8px; border-radius:8px; border:1px solid #2A3038;
    background:#0E1116; color:#E7ECF3; }
  button { background:#F97316; color:#12151A; border:0; cursor:pointer; }
  #points { list-style:none; padding:0; margin:12px 0; }
  #points li { padding:6px 8px; border-bottom:1px solid #2A3038; display:flex;
              justify-content:space-between; }
  #points li button { background:#2A3038; color:#E7ECF3; padding:2px 8px; }
  h1 { font-size:18px; margin:0 0 8px; } .muted { color:#8B96A8; font-size:12px; }
</style></head><body>
<div id="app">
  <div id="panel">
    <h1>Route am Computer planen</h1>
    <div class="muted">Temporärer Plan-Link · Punkte erscheinen auf deinem Handy sobald
      du „Auf Handy senden“ tippst.</div>
    <div style="margin-top:12px">
      <input id="q" placeholder="Ort suchen (Enter)" style="width:220px"/>
      <button id="searchBtn">Suchen</button>
    </div>
    <div id="results"></div>
    <ol id="points"></ol>
    <button id="sendBtn">Auf Handy senden</button>
    <div id="msg" class="muted"></div>
  </div>
  <div id="map"></div>
</div>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script>
const TOKEN = "{{TOKEN}}";
if (!/^[A-F0-9]{32}$/.test(TOKEN)) throw new Error("Ungültiger Plan-Link");
const map = L.map("map").setView([48.1375, 11.5755], 10);
L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
  maxZoom: 19, attribution: "© OpenStreetMap"
}).addTo(map);
let points = [];
let markers = [];

function render() {
  const ol = document.getElementById("points");
  ol.innerHTML = "";
  points.forEach((p, i) => {
    const li = document.createElement("li");
    const span = document.createElement("span");
    span.textContent = `${i + 1}. ${p.label}`;
    const btn = document.createElement("button");
    btn.textContent = "×";
    btn.onclick = () => { points.splice(i, 1); refresh(); };
    li.append(span, btn);
    ol.append(li);
  });
}

function refresh() {
  markers.forEach(m => map.removeLayer(m));
  markers = points.map(p => L.circleMarker([p.lat, p.lon], {radius: 7}).addTo(map));
  if (points.length >= 2) map.fitBounds(
    L.latLngBounds(points.map(p => [p.lat, p.lon])), {padding: [40, 40]});
  render();
}

function addPoint(point) {
  if (points.length >= 12) {
    setMsg("Maximal 12 Wegpunkte pro Route. Entferne zuerst einen Stopp.");
    return false;
  }
  points.push(point);
  refresh();
  setMsg("");
  return true;
}

async function search(q) {
  const params = new URLSearchParams({token: TOKEN, q: q, limit: "6"});
  try {
    const res = await fetch(`/api/v1/pairing/geocode?${params}`);
    if (!res.ok) { setMsg("Suche nicht erreichbar"); return; }
    const places = await res.json();
    const box = document.getElementById("results");
    box.innerHTML = "";
    places.forEach(p => {
      const b = document.createElement("button");
      b.textContent = p.label + (p.detail ? " · " + p.detail : "");
      b.style.display = "block"; b.style.marginTop = "4px";
      b.onclick = () => {
        if (addPoint({label: p.label, lat: p.lat, lon: p.lon, detail: p.detail})) {
          box.innerHTML = "";
          document.getElementById("q").value = "";
        }
      };
      box.append(b);
    });
    if (places.length === 0) setMsg("Keine Orte gefunden.");
  } catch (_) {
    setMsg("Suche fehlgeschlagen. Prüfe die Verbindung und versuche es erneut.");
  }
}

function setMsg(t) { document.getElementById("msg").textContent = t; }

document.getElementById("searchBtn").onclick = () => {
  const q = document.getElementById("q").value.trim();
  if (q.length >= 2) search(q);
};
document.getElementById("q").addEventListener("keydown", (e) => {
  if (e.key === "Enter") document.getElementById("searchBtn").click();
});

document.getElementById("sendBtn").onclick = async () => {
  if (points.length === 0) { setMsg("Füge zuerst mindestens einen Wegpunkt hinzu."); return; }
  try {
    const res = await fetch(`/api/v1/pairing/${TOKEN}`, {
      method: "PUT",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({points: points})
    });
    setMsg(res.ok ? "Gesendet! Im Handy auf „Plan abrufen“ tippen."
                  : "Senden fehlgeschlagen (" + res.status + ")");
  } catch (_) {
    setMsg("Senden fehlgeschlagen. Prüfe die Verbindung und versuche es erneut.");
  }
};

// Karte anklicken fügt einen Punkt hinzu
map.on("click", (e) => {
  addPoint({label: `Karten-Pin (${e.latlng.lat.toFixed(4)}, ${e.latlng.lng.toFixed(4)})`,
            lat: e.latlng.lat, lon: e.latlng.lng, detail: null});
});
</script></body></html>"""
