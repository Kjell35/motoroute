# MotoRoute – API-Struktur

> Status: Empfehlung zur Freigabe · Version 1.0 · Stand 2026-09-15
> Alle Endpoints unter `/api/v1`. JSON, UTF-8, ISO-8601, GeoJSON-Konventionen.

## 1. Prinzipien

1. **Stateless Präferenzen:** Fahrstil, Vermeidungen, Fahrzeugtyp sind Pflichtfelder jedes Route-Calls – der Server speichert sie nie.
2. **Versioniert ab Tag 1** (`/v1`); Breaking Changes → `/v2`, `/v1` läuft mit Deprecation-Header weiter.
3. **Einheitliches Fehlerformat** (RFC 7807-inspiriert):
```json
{
  "error": {
    "code": "ROUTE_NOT_FOUND",
    "message": "No route found for given preferences",
    "details": { "waypoint_index": 2 },
    "trace_id": "b0c9…"
  }
}
```
4. **Kein PII in Logs**, `trace_id` korreliert App-Crash-Reports ↔ Server-Logs ohne Personenbezug.

## 2. Endpoints MVP

### POST /api/v1/route
Berechnet 1–3 Routen-Kandidaten inkl. Manöverliste + CurveScore.

```json
// Request
{
  "waypoints": [ {"lon": 11.57, "lat": 48.13}, {"lon": 11.07, "lat": 49.45} ],
  "preferences": {
    "vehicle": "motorcycle",
    "ride_style": "fast_and_curvy",
    "avoid": ["toll", "ferry"]
  },
  "alternatives": 3,
  "language": "de-DE"
}
// Response (verkürzt)
{
  "plan_id": "…",
  "candidates": [ {
    "provider_route_id": "…",
    "geometry_polyline6": "…",
    "distance_m": 241000,
    "duration_s": 11200,
    "curve_score": { "value": 78.4, "curve_density_per_km": 5.1 },
    "legs": [ { "maneuvers": [ /* … */ ] } ]
  } ],
  "exhausted": false
}
```

### POST /api/v1/reroute
Gleicher Vertrag wie `/route`, aber: `waypoints[0]` ist die aktuelle Position, Restzustand `origin_plan_id` referenziert die Ursprungs-Route. Server **erzwingt** identische `preferences` gegenüber dem Ursprungsplan (sonst 409 `PREFERENCES_MISMATCH`) – das ist die technische Absicherung der Produktregel „Fahrstil bleibt stabil“.

### GET /api/v1/geocode?q=…&lat=…&lon=…
Forward-Geocoding (Ort, PLZ, Straße, POI-Name), Bias auf aktuelle Karte. Antwort: normalisierte `Place`-Liste.

### GET /api/v1/reverse?lat=…&lon=…
Reverse-Geocoding für „Route hierher“-Flows und Waypoint-Labels.

### GET /api/v1/pois?bbox=…&categories=fuel,biker_meet
POIs für den Kartenausschnitt. `categories` filtert; Antwort ist GeoJSON-FeatureCollection mit `poi_id`, `name`, `source`.

### GET /api/v1/traffic/incidents?bbox=…
Verkehrs-Störungen als GeoJSON (Typ: jam, roadwork, accident, closure). Quelle austauschbar (TomTom / OSM-Stub).

### POST /api/v1/tour *(Phase 2, Architektur vorgesehen)*
Rundtour-Generator: Start, Ziel-Distanz, Fahrstil, Vermeidungen → Tour-Plan (Loop zurück zum Start), intern mehrere Routing-Aufrufe + PostGIS-Auswahl kurvenreicher Korridore.

### POST /api/v1/chat/media/images *(Community-Phase, offen)*
Nimmt **ein** Bild auf und liefert die URL, die danach in `POST /v1/chat/groups`
bzw. `PUT /v1/chat/groups/{groupId}` als `imageUrl` gesetzt wird. Der Upload ist
bewusst vom Gruppen-Call getrennt: ein fehlgeschlagener Upload darf das Erstellen
der Gruppe nicht verhindern, und derselbe Endpunkt bedient später Profilbilder.

```json
// Request: multipart/form-data
//   file  = Binärdaten (Pflicht)
//   scope = "group" | "avatar" (optional, Default "group" - nur für Quota/Aufbewahrung)

// Response 201
{
  "url": "https://media.motoroute.app/i/7f3c….webp",
  "width": 1024,
  "height": 768,
  "bytes": 210331,
  "content_type": "image/webp"
}
```

Regeln:

- **Formate:** JPEG, PNG, WebP. Prüfung über Magic Bytes, nicht über den
  `Content-Type`-Header des Clients.
- **Größe:** max. 5 MB Request, max. 12 MP Ausgangsbild.
- **Serverseitige Normalisierung:** EXIF (inkl. GPS!) entfernen, längste Kante
  auf 1024 px, Re-Encode nach WebP (Fallback JPEG). Das Original wird nicht
  gespeichert - sonst wandern Standortdaten in den Storage.
- **Objektnamen:** zufällig (UUIDv4), kein Nutzerbezug im Pfad.
- **Antwort-URL:** absolut, https, ausschließlich der eigene Media-Host. Fremde
  Hosts werden beim Setzen von `imageUrl` abgelehnt (`INVALID_IMAGE_URL`), damit
  die App keine beliebigen externen Bilder in Gruppen zieht.
- **Berechtigung:** jeder angemeldete Nutzer darf hochladen; wer das Bild an eine
  Gruppe hängt, muss Owner/Moderator sein (bestehende Regel von
  `PUT /v1/chat/groups/{id}`).
- **Aufräumen:** nicht referenzierte Uploads werden nach 24 h gelöscht; beim
  Löschen einer Gruppe verschwindet ihr Bild mit.
- **Missbrauch:** Rate-Limit pro Nutzer (z. B. 20 Uploads/Stunde).

Fehler im Format aus Abschnitt 1:

| Status | code | Ursache |
|---|---|---|
| 400 | `INVALID_IMAGE` | Datei fehlt, leer oder nicht dekodierbar |
| 400 | `INVALID_IMAGE_URL` | `imageUrl` zeigt nicht auf den Media-Host |
| 413 | `IMAGE_TOO_LARGE` | Request > 5 MB |
| 415 | `UNSUPPORTED_MEDIA_TYPE` | Format nicht JPEG/PNG/WebP |
| 429 | `RATE_LIMITED` | Upload-Limit erreicht |
| 503 | `UPLOAD_UNAVAILABLE` | Storage/CDN nicht erreichbar |

Client-Flow (Flutter, heute noch nicht implementiert):

1. Bild mit `image_picker` wählen (`imageQuality: 80`, `maxWidth: 1600`) -
   Vorab-Verkleinerung spart Mobilfunk-Traffic.
2. Vorschau zeigen; die Auswahl lässt sich vor dem Absenden wieder entfernen.
3. Upload beim Absenden; bei Fehler **nicht** die ganze Gruppe verwerfen,
   sondern das Bild weglassen und einen Hinweis zeigen.
4. Erfolgreiche `url` als `imageUrl` an `POST /v1/chat/groups` übergeben.

> Solange dieser Endpunkt fehlt, zeigt das Gruppen-Formular bewusst kein
> Bild-Feld: ein Multipart-Body an einen JSON-Endpunkt würde das Erstellen der
> Gruppe scheitern lassen.

## 3. Nicht-Endpoints (bewusst)

- **Kein** „Positions-Reporting“-Endpoint. Die App sendet Standort nie persistierend; Reroute-Requests enthalten die Position nur transient zur Verarbeitung.
- **Keine** User-Endpoints im MVP (Accounts starten mit Community-Phase).

## 4. Auth & Schutz

- MVP: **App-Attestation light** – ein per App-Signatur gebundener Client-Token (kein User-Login), damit Dritte die API nicht frei nutzen; echte User-Auth (Passkeys/OAuth via eigener FastAPI-Auth oder Keycloak) ab Community-Phase.
- Rate-Limits pro Token (z. B. 60 route-Requests/min), Caddy-level + App-level.
- TLS 1.3 überall; optionales Cert-Pinning in der App (konfigurierbar, um Rotation nicht zu blockieren).

## 5. Vertragssicherung

- OpenAPI-Schema wird aus FastAPI generiert und als Artefakt gepinnt; Flutter-DTOs werden daraus abgeleitet (Codegen) → Compiler-verifizierter Vertrag.
- Contract-Tests in CI: Beispiel-Requests/-Responses werden gegen beide Implementierungen (Pydantic & Dart-Parser) geprüft.
