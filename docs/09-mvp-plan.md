# MotoRoute – MVP-Entwicklungsplan

> Status: Empfehlung zur Freigabe · Version 1.1 (Zero-Budget-Pfad) · Stand 2026-09-15
> Annahme: 1 Entwickler + AI-Assistenz, Vollzeit. Puffer enthalten; Kalenderwochen bewusst offen gelassen (Start nach Freigabe).

## 1. Meilensteine

### M0 – Fundament (Woche 1)
- Repo-Setup: Monorepo (`apps/mobile`, `apps/backend`, `docs/`), CI (GitHub Actions): Flutter analyze/test, Python lint/pytest, Docker-Builds.
- Design-Tokens in Code (Farben/Typo/Spacing als Dart-Klassen), `MrButton/MrCard/MrChip/MrSheet` v1.
- Backend-Skeleton (FastAPI, Health-Endpoint, Config via Env), docker-compose mit Postgres+PostGIS.
- **DoD:** CI grün, App zeigt Splash + leere Dark-Karte (OpenFreeMap + eigenem Style-JSON-Grundgerüst).

### M1 – Karte & GPS (Woche 2–3)
- MapLibre-Integration (flutter-maplibre-gl), „Midnight Asphalt"-Kartenstil v1.
- LocationService: GPS-Stream, Heading-Filter, Speed; Positionspfeil auf Karte; Zentrieren-FAB + manual-mode-Erkennung.
- Berechtigungs-Flow (Onboarding-Pre-Prompt).
- **DoD:** echte Fahrt (Fahrrad-Test) zeigt Position flüssig, Kamera folgt, manueller Modus switcht korrekt.

### M2 – Suche & Waypoints (Woche 4–5)
- Backend: Photon-Integration (`/geocode`, `/reverse`), App: Such-Screen mit Debounce, Verlauf (lokal).
- Waypoint-Modell + Map-Long-Press + „Route hierher"; Waypoint-Verwaltung (Reihenfolge, löschen).
- **DoD:** A→B mit 2 Zwischenstopps planbar; Suche findet Ort/Adresse/POI.

### M3 – Routing-Kern ⭐ (Woche 6–8, kritischer Pfad)
- Backend: Valhalla-Client, Profile-Builder (Fahrzeugtyp × Fahrstil × Vermeidungen → Valhalla-Costing-Params), `/route`.
- CurveScorer v1 + Unit-Tests gegen Referenz-Routen (B500, Alpenpässe, A8 als Negativfall).
- App: Routen-Preview-Screen (Kandidaten-Cards mit CurveScore-Badge), Routenübersicht, „Navigation starten".
- **DoD:** 5 Fahrstile × 3 Fahrzeugtypen liefern sichtbar unterschiedliche, plausible Routen; „kurvig" schlägt messbar kurvenreichere Routen vor (Testdaten).

### M4 – Turn-by-Turn-Navigation (Woche 9–11)
- Maneuver-Engine (Domain): Snap-to-route, Manöver-Trigger, Restwerte, ETA.
- Nav-Screen nach Layout-Vertrag (Turn-Banner, eine Info-Zeile, 2 FABs), Kamera-Follow-Modus.
- TTS-Sprachansagen (de/en), Prioritäts-Queue; Off-Route-Detector + `/reroute` (Präferenzen-Stabilität serverseitig erzwungen).
- Foreground-Service (Android, Zielplattform) mit Benachrichtigungs-Kanal (Android 13+: Notification-Permission).
- **DoD:** GPX-Replay-Integrationstest: 60-min-Tour inkl. 3 erzwungener Off-Route-Events → Reroutes behalten Fahrstil (automatisierter Assert).

### M5 – POIs, Traffic-Stub, Sparmodus (Woche 12–13)
- POI-Pipeline: Overpass-Extraktion (DACH) → PostGIS → `/pois`; Kategorien-Toggles, Cluster-Rendering.
- Traffic: OSM-basierte Sperrungen als `/traffic`-Adapter (ehrlich gekennzeichnet); TomTom-Adapter bleibt **deaktiviert** (Feature-Flag, Zero-Budget-Beschluss).
- Sparmodus laut `08-energy-saving.md`.
- **DoD:** alle MVP-POI-Kategorien sichtbar/abschaltbar; Sparmodus messbar weniger Renderlast (Profiling-Protokoll im Repo).

### M6 – Release-Readiness (Woche 14)
- Onboarding final, Einstellungen vollständig, Fehler-/Offline-States, Crash-Reporting (opt-in).
- Play-Store-Assets (Android-first, Zero-Budget: kein iOS im MVP), Privacy-Policy-Entwurf (mit DSB-Vorlage), Closed Testing via Play Internal Testing / direkter APK-Verteilung.
- **DoD:** Beta im Closed-Test auf eigenen Geräten + 3–5 externen Testern.

## 2. Explizit NICHT im MVP (Backlog, produktionsnah vorbereitet)

Rundtouren-Generator, GPX-Import/Export, Offline-Karten/-Routing, Höhenprofil, Wetter, Kurven-Score-Ausbau (Segment-Highlights), Community/Favoriten-Sync, Accounts, Blitzer, Hintergrund-Navigation über „Immer"-Location hinaus, iOS-Port.

## 3. Kritischer Pfad & Risiken

| Risiko | Wahrsch. | Impact | Gegenmaßnahme |
|---|---|---|---|
| Valhalla-Kurvenqualität unzureichend | mittel | hoch | CurveScorer früh testen (M3, Woche 6); GraphHopper-Adapter als Fallback geplant |
| flutter-maplibre-gl Lücken (z. B. Kamera-APIs) | mittel | mittel | frühe Spike in M1; notfalls MethodChannel-Ergänzungen (Plugin ist PR-freundlich) |
| Android-Hintergrund-Location von Play-Review abgelehnt | mittel | mittel | MVP nur While-In-Use + sichtbare Foreground-Service-Notification; „Immer" als Phase-2 mit sauberem UX-Case |
| Overpass-Extraktionsqualität (Biker-POIs) | hoch | niedrig | UI-Hinweis „Datenlücke", Kuratierung ab Phase 2 |
| Ein-Personen-Bottleneck | – | – | KI-Pairing, harte M-DoDs, README-Runbooks |

## 4. Nach dem MVP (grobe Sequenz)

1. **Phase 2a:** Rundtouren (PostGIS-Korridore + Loop-Routing), GPX-Import/-Export, gespeicherte Routen.
2. **Phase 2b:** Offline-Karten (PMTiles-Regionen), danach Offline-Routing-Evaluation (Valhalla on-device).
3. **Phase 3:** Accounts (Passkeys), Favoriten-Sync, Community (Bewertungen, POI-Vorschläge mit Moderation).
4. **Phase 4:** Kurven-Score 2.0 (eigenes Highlighting), Wetter, Blitzer (juristisch pro Land).
