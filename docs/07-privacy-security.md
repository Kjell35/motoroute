# MotoRoute – Datenschutz & Sicherheit

> Status: Empfehlung zur Freigabe · Version 1.0 · Stand 2026-09-15
> Grundsatz: Datenminimierung vor Komfort. Die App funktioniert ohne Benutzerkonto.

## 1. Verarbeitete Daten (vollständige Liste, MVP)

| Daten | Zweck | Speicherort | Dauer |
|---|---|---|---|
| GPS-Position (live) | Navigation, Kartenzentrierung | nur RAM (Stream) | nicht persistiert |
| Ziele & Waypoints | Routing, Favoriten (opt-in) | lokal (Isar) | bis Löschen |
| Gespeicherte Routen | Wiederaufruf, später Offline | lokal, optional Sync | bis Löschen |
| Anonyme Metriken | Latenz, Cache-Treffer, Fehlerquoten | Server | 30 Tage, rollierend |
| Crash-Reports (opt-in) | Stabilität | Sentry, self-hosted | 90 Tage |

**Bewusste Nicht-Speicherung:** Positionsverlauf, Suchanfragen (serverseitig), User-Profile im MVP. Eine `trips`-Tabelle existiert bewusst nicht (siehe `03-data-models.md`).

## 2. Datenfluss Position

```
GPS (on device) → Domain-Services (Guidance, OffRouteDetector) → Rendering
                       │
                       └─ nur bei Route-/POI-/Traffic-Call: aktuelle Position(en)
                          transient im HTTPS-Body → Backend → Valhalla/Photon/TomTom
                          (Weitergabe = Verarbeitung im Auftrag, keine Persistenz)
```

## 3. Berechtigungen (least-privilege, lazy)

| Berechtigung | Wann angefragt | Begründung im UI |
|---|---|---|
| Standort „beim Benutzen" | erst beim ersten „Navigation starten" | „MotoRoute braucht den Standort für Turn-by-Turn-Guidance." |
| Benachrichtigungen (Android 13+) | beim ersten Start der Navigation | Foreground-Service-Pflicht |
| Speicher (nur Export) | beim ersten GPX-Export (Phase 2) | Datei-Ziel wählen statt Vollzugriff |

Zielplattform ist **Android** (Beschluss 2026-09-15). Android-Pendant: `ACCESS_FINE_LOCATION` („While-In-Use") im MVP; Hintergrund-Location erst mit Phase 2 (Foreground-Service-Konzept, siehe `09-mvp-plan.md`). iOS-Entscheidungen sind bewusst zurückgestellt, bis ein iOS-Port beschlossen wird.

## 4. Backend-Security

- TLS 1.3, HSTS, Security-Header (CSP, X-Frame-Options), Caddy als Edge.
- Client-Token (app-signatur-gebunden, kein User-Login im MVP), Rate-Limits, Request-Size-Limits.
- Valhalla/Photon/Postgres nie exponiert – nur internes Docker-Netzwerk.
- Secrets ausschließlich via Environment/`docker secrets` – **kein Key im Code oder APK** (siehe `10-dev-process.md`).
- Dependency-Scanning in CI (pip-audit, osv-scanner, `dart pub outdated --json`).

## 5. DSGVO-Grundsätze im Design

| Grundsatz | Umsetzung |
|---|---|
| Datenminimierung | keine Konto-Pflicht, keine Positions-Persistenz, Metriken ohne Personenbezug |
| Zweckbindung | Standort nur für laufende Navigation/Routing/POI-Suche |
| Speicherbegrenzung | Metriken 30 Tage, Crash-Reports 90 Tage, danach automatische Löschung |
| Auskunft & Löschung | Self-Service „Daten löschen" in Settings: lokal sofort, Server-Restposten via Job |
| Auftragsverarbeitung | AVV (Art. 28) mit Hoster (EU) und Sentry-Instanz vor Go-live abschließen; TomTom erst bei späterer Aktivierung |
| TOM-Dokumentation | dieses Dokument + Ops-Runbook (`10-dev-process.md`) |

## 6. Traffic-Quelle: OSM-Stub (Zero-Budget-Beschluss)

Im MVP laufen Verkehrsdaten ausschließlich über den OSM-Stub – minimale Datenweitergabe, kein Bezahl-Anbieter, keine zusätzliche AVV. Ein Echtzeit-Traffic via TomTom wird erst bei Budget-Freigabe geprüft (dann nur mit DPA/AVV, siehe `11-costs.md`).

## 7. Offene Punkte für Phase 2

- Android-Hintergrund-Location + Foreground-Service (Play-Richtlinien-konformes UX-Konzept).
- Client-Token-Rotation ohne hartes Cert-Pinning (konfigurierbare Pin-Liste).
- Sentry self-hosted als Default; Alternativbetrieb (EU-Cloud) nur mit AVV.
