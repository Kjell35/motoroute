# MotoRoute 🏍️

**Professionelle Navigations-App für Motorradfahrer – Routen nach Fahrspaß, nicht nur nach Geschwindigkeit.**

> Status: **M0/M1 abgeschlossen · M2 (Suche & Wegpunkte) implementiert.** APK-Build automatisch auf GitHub – siehe [GITHUB_SETUP.md](GITHUB_SETUP.md).

## Projekt-Dokumentation

| # | Dokument | Inhalt |
|---|---|---|
| 00 | [Produktvision](docs/00-product-vision.md) | Positionierung, Zielgruppen, Produktprinzipien, Erfolgskriterien |
| 01 | [Tech-Stack](docs/01-tech-stack.md) | Anbietervergleich (Karten/Routing/Backend), begründete Wahl, Alternativen |
| 02 | [Architektur](docs/02-architecture.md) | Systemaufbau, Schichten, Projektstruktur, State-Management, Navigation/Rerouting |
| 03 | [Datenmodelle](docs/03-data-models.md) | Domain-Entities + PostgreSQL/PostGIS-Schema |
| 04 | [API](docs/04-api.md) | Endpunkte v1, Fehlerformat, Auth, Vertragssicherung |
| 05 | [Design-System](docs/05-design-system.md) | „Midnight Asphalt": Farben, Typo, Komponenten, Kartenstil |
| 06 | [UX & Fahrsicherheit](docs/06-ux-safety.md) | Screen-Verträge, Navigation-Layout, Handschuh-Bedienung |
| 07 | [Datenschutz & Security](docs/07-privacy-security.md) | Datenflüsse, DSGVO, Berechtigungen, Backend-Security |
| 08 | [Energiesparmodus](docs/08-energy-saving.md) | Konkrete Maßnahmen, Sicherheits-Guards |
| 09 | [MVP-Plan](docs/09-mvp-plan.md) | Meilensteine M0–M6, Risiken, Backlog |
| 10 | [Entwicklungsprozess](docs/10-dev-process.md) | Monorepo, Environments, DoD, CI, Testing |
| 11 | [Kosten & API-Keys](docs/11-costs.md) | Benötigte Keys, monatliche Szenarien, Skalierungs-Trigger |
| 12 | [Recht & Lizenzen](docs/12-legal.md) | ODbL, Blitzer-Problematik, DSGVO, Launch-Checkliste |

## Tech-Stack (Kurzfassung)

**Zielplattform MVP: Android.** (Flutter hält die iOS-Option offen – ein Port ist eine spätere, separate Entscheidung.)

**Flutter** · **MapLibre** + OpenFreeMap-Tiles · **Valhalla** (self-hosted, echtes Motorcycle-Costing) · **FastAPI** · **PostgreSQL + PostGIS** · **Photon** (Geocoding) · Traffic im MVP via **OSM-Sperrungen** (ehrlich gekennzeichnet; TomTom später optional).

**Zero-Budget-Prinzip:** Der komplette MVP läuft ohne bezahlte Dienste und ohne API-Keys – die App ist kostenlos, ohne Abos oder Plans. Details: [Kosten-Doku](docs/11-costs.md).

Kern-Eigenschaft: Karten- und Routing-Anbieter sind **Austauschbar** (Ports & Adapters) – „kurvig" ist eine eigene, getestete Scoring-Logik auf dem Server, kein Marketing-Label.

## Wichtigste Produktregeln

1. Fahrstil/Vermeidungen bleiben über jede Neuberechnung stabil (serverseitig erzwungen).
2. Fahrzeugtyp beeinflusst echtes Routing, nicht nur Icons.
3. Navigationsansicht: maximal 2 Info-Zonen, keine Ablenkung.
4. Keine Persistenz von Standortverläufen – Datenschutz by design.
5. Kein API-Key im Code/APK – Environment-Konfiguration überall.

## Repository-Struktur

```
apps/mobile/     Flutter-App (Android-MVP, Design-System „Midnight Asphalt“)
apps/backend/    FastAPI-Backend (dünne API-Grenze vor Valhalla/Photon)
infra/           docker-compose (Backend, Postgres+PostGIS; Valhalla/Photon ab M2/M3)
docs/            Produkt- & Architektur-Dokumentation
.github/         CI: Tests + automatischer APK-Build
```

## Nächster Schritt

M3 – Routing-Kern: Valhalla-Client, Fahrstil-Profile, CurveScore und Routen-Preview
([MVP-Plan](docs/09-mvp-plan.md)).
