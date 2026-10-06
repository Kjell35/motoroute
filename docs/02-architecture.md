# MotoRoute – Systemarchitektur

> Status: Empfehlung zur Freigabe · Version 1.0 · Stand 2026-09-15
> Grundsatz: Schichtenarchitektur mit Ports & Adapters. Domain-Logik hängt nie an konkreten Anbietern.

## 1. Systemüberblick

```
┌────────────────────────────────────────────────────────────────────┐
│                        Flutter App (Android-MVP)                    │
│  ┌──────────┐ ┌──────────────┐ ┌─────────────────────────────────┐ │
│  │    UI    │ │ Application/ │ │ Domain                          │ │
│  │ Screens, │ │ State        │ │ Route, Trip, Waypoint, POI,     │ │
│  │ Widgets, │ │ (Riverpod)   │ │ Vehicle, Preferences (pure Dart)│ │
│  │ Design   │ │              │ │                                 │ │
│  │ System   │ │              │ │                                 │ │
│  └──────────┘ └──────────────┘ └─────────────────────────────────┘ │
│        │              │                    │                        │
│  ┌─────▼──────────────▼────────────────────▼─────────────────────┐ │
│  │                    Infrastructure / Ports                     │ │
│  │  LocationService(GPS)  MapRenderer(MapLibre)  ApiClient(REST) │ │
│  │  SpeechService(TTS)    SettingsStore  RouteCache  Dir-DB      │ │
│  └───────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────┬──────────────────────────────────┘
                                  │ HTTPS/JSON
┌─────────────────────────────────▼──────────────────────────────────┐
│                     MotoRoute Backend (FastAPI)                    │
│  ┌───────────┐ ┌────────────┐ ┌──────────┐ ┌────────────────────┐ │
│  │ RouteSvc  │ │ PoiSvc     │ │ SearchSvc│ │ TrafficSvc         │ │
│  │ + Curve-  │ │ (PostGIS/  │ │ (Photon) │ │ (TomTom / OSM stub)│ │
│  │  Scoring  │ │  Overpass) │ │          │ │                    │ │
│  └─────┬─────┘ └─────┬──────┘ └────┬─────┘ └─────────┬──────────┘ │
│        ▼             ▼             ▼                 ▼            │
│   Valhalla      PostgreSQL    Photon           TomTom (outbound)  │
│   (Docker)      + PostGIS     (Docker)                            │
└────────────────────────────────────────────────────────────────────┘
```

**Warum Server-Side-Routing statt Routing direkt aus der App?**
1. API-Keys bleiben geheim (Valhalla ist offen, aber wir wollen Rate-Limit + Missbrauchsschutz).
2. Kurven-Score-Logik ist proprietäres Know-how → gehört auf den Server, nicht in die APK.
3. Datenschutz: Wir loggen nur anonyme Request-Metadaten, keine Standort-Historie (siehe `07-privacy-security.md`).
4. Später: Rundtour-Optimierung braucht mehrere Routing-Aufrufe + PostGIS – zu teuer/schwach auf dem Telefon.

## 2. Schichten & Abhängigkeitsregeln (App)

```
presentation  ──►  application  ──►  domain  ◄──  infrastructure
```

- `domain` kennt niemanden. Pure Dart: Entities, Value Objects, Repositories als abstrakte Interfaces (Ports).
- `application` kennt `domain`. Use-Cases/Controller (Riverpod Notifiers), orchestriert Ports.
- `infrastructure` implementiert Ports: MapLibre-Adapter, GPS-Adapter, ApiClient, TTS, Settings.
- `presentation` kennt `application` + `domain`, baut Screens aus Widgets.
- Verbot: `presentation` importiert nie `infrastructure` direkt; alles via Riverpod-Provider injiziert.

## 3. Projektstruktur (Flutter-App)

```
apps/mobile/
├── lib/
│   ├── main.dart
│   ├── app.dart                       # Root, Router, Theme
│   ├── core/                          # Framework-unabhängige Helfer
│   │   ├── config/env.dart            # Environment-Config (kein Key im Code!)
│   │   ├── error/failures.dart
│   │   ├── logging/logger.dart
│   │   ├── result/                    # Result/Either-Monade
│   │   └── extensions/
│   ├── design/                        # Design-System „Midnight Asphalt"
│   │   ├── tokens/                    # Farben, Typo, Spacing, Radii, Elevation
│   │   ├── components/                # MrButton, MrCard, MrSheet, MrChip …
│   │   └── icons/                     # eigene Icon-Assets
│   ├── domain/
│   │   ├── entities/                  # Route, Trip, Waypoint, Poi, Vehicle …
│   │   ├── value_objects/             # GeoPoint, RideStyle, AvoidFlags, CurveScore
│   │   ├── repositories/              # abstrakte Ports (Interfaces)
│   │   └── services/                  # z. B. OffRouteDetector (pure Logik)
│   ├── application/
│   │   ├── routing/                   # RoutePlannerController, RerouteController
│   │   ├── navigation/                # NavigationSessionController (Guidance-State)
│   │   ├── map/                       # MapViewController, CameraMode
│   │   ├── search/                    # SearchController
│   │   ├── pois/                      # PoiToggleController
│   │   ├── settings/                  # SettingsController (persistiert)
│   │   └── vehicle/                   # VehicleController
│   ├── infrastructure/
│   │   ├── api/                       # ApiClient, DTOs, Mapper (DTO↔Domain)
│   │   ├── location/                  # Geolocator-Adapter, Heading-Filter
│   │   ├── map/                       # MapLibre-Adapter (Style, Layer, Marker)
│   │   ├── speech/                    # TTS-Adapter
│   │   ├── storage/                   # Settings (shared prefs/Isar), RouteCache
│   │   └── di/                        # Riverpod-Provider-Registry
│   └── presentation/
│       ├── screens/                   # 1 Screen = 1 Ordner (view + widgets)
│       │   ├── splash/  onboarding/  home/  map/  search/
│       │   ├── route_preview/  navigation/  waypoints/  pois/
│       │   └── settings/
│       └── routes/                    # go_router-Konfiguration
├── assets/  (fonts, map-style/, icons/)
├── test/                              # Unit (domain/application) + Widget-Tests
└── integration_test/
```

**Backend-Struktur (Kurzform, Details in `04-api.md`):**

```
apps/backend/
├── app/
│   ├── api/v1/            # Endpoints (route, search, pois, traffic, tour)
│   ├── core/              # Config, Security, Logging
│   ├── domain/            # Models, Value Objects
│   ├── services/          # RoutingService (Valhalla-Client), CurveScorer, PoiService
│   └── infra/             # Valhalla-, Photon-, TomTom-Clients, PostGIS-Repo
├── tests/
├── docker-compose.yml     # api, valhalla, photon, postgres+postgis
└── pyproject.toml
```

## 4. State-Management-Konzept

**Wahl: Riverpod 2.x** (compile-safe, testbar, keine BuildContext-Hacks, gut für async Streams).

| Provider (aktiv) | Typ | Aufgabe |
|---|---|---|
| `vehicleProvider` | StateNotifier (persistiert) | Motorrad/Auto/Fahrrad |
| `rideStyleProvider` | StateNotifier (persistiert) | fast / curvy / extra_curvy / fast_and_curvy / unpaved |
| `avoidancesProvider` | StateNotifier (persistiert) | Autobahn / Fähre / Maut (später: Tunnel etc.) |
| `waypointsProvider` | StateNotifier | geordnete Liste Start → Ziele → Ende |
| `routePlanProvider` | AsyncNotifier | Ergebnis des Route-Plannings (Alternativen, CurveScore) |
| `navSessionProvider` | StateNotifier + Streams | aktive Navigation: Manöver, Restdistanz, Restzeit, ETA |
| `locationProvider` | StreamProvider | GPS-Fixes (position, heading, speed), gefiltert |
| `mapCameraModeProvider` | StateNotifier | follow / manual (gesteuert durch User-Gesten) |
| `poiFilterProvider` | StateNotifier (persistiert) | aktive POI-Kategorien |
| `saverModeProvider` | StateNotifier (persistiert) | Energiesparmodus (reduziert FPS/Refresh/Animationen) |

**Regeln:**
- Navigation-Guidance ist ein **einziger State-Machine-Stream** (`NavigationSessionController`): Zustände `idle → preview → guiding → arrived → rerouting`. UI rendert rein reaktiv.
- **GPS entkoppelt von Widgets:** `locationProvider` feedet Domain-Services (OffRouteDetector), nicht direkt Widgets; Widgets subscriben auf abgeleitete Provider.
- Persistenz nur für Settings/Präferenzen – **nie** für Positionsverlauf (Datenschutz).

## 5. Navigation-Konzept (Turn-by-Turn, Rerouting)

1. **Route starten:** Backend liefert Geometrie + Manöverliste (Valhalla `legs[].maneuvers`).
2. **Manöver-Engine (Domain, pure Dart):** Projektion der GPS-Position auf Route (`snap to route`), Bestimmung des aktiven Segments, Restdistanz/-zeit via kumulierte Segmentwerte.
3. **Off-Route-Erkennung:** Distanz Position↔Route > 40 m über 2 Fixes → `rerouting`.
4. **Rerouting:** Backend-Call mit aktueller Position, Ziel, **denselben** Präferenzen (Fahrstil/Vermeidungen sind Teil des Requests, nie serverseitig gemerkt) → neue Route → Guidance-Switch mit Sprachansage „Neue Route berechnet".
5. **Sprachansagen:** TTS nativ über die Android-TTS-Engine (hinter `SpeechService`-Port; ein iOS-Adapter folgt erst mit dem iOS-Port) mit Prioritäts-Queue (Manöver > Verkehrshinweis > Hinweis).
6. **Kamera-Modi:** `follow` (Karte rotiert/traselt mit Heading) vs. `manual` (User panned → folgt nicht mehr) + Zentrieren-Button. Kamera-Modus ist State, kein Wildwuchs.

## 6. Kartenschicht

- MapLibre mit eigenem Style-JSON (Dark „Midnight Asphalt"-Karte, hilfreich: niedriger Kontrast der Basiskarte, hoher Kontrast der Route).
- Layer-Aufbau: Basiskarte → Route-Layer (Casing + Linie) → Verkehrs-Overlay → POI-Cluster → Marker (Start/Ziel/Wegpunkte) → Positionspfeil.
- POI-Anzeige: Kategorien als Source-Filter; POIs kommen als GeoJSON vom Backend (PostGIS-Box-Query), nicht clientseitiges Overpass-Gefrickel.
- Energiesparmodus: reduzierte FPS-Metadaten, keine Antialiasing-Extras, statischer Heading-Pfeil, kleinere POI-Refresh-Zyklen (Details `08-energy-saving.md`).

## 7. Offline-/Caching-Strategie (Vorbereitung, nicht MVP)

- Tiles: MVP- online; ab M5 PMTiles/MBTiles-Regionen pro Tour (MapLibre-Offline-Regionen).
- Routing: MVP- online; Valhalla-Tiles-Download (EU ~50–60 GB) ist Phase-2-Thema für On-Device-Routing (App-Interface bleibt gleich dank Port).
- Gespeicherte Routen: lokal (Isar) + später Sync (Supabase/Backend) – Datenmodell von Anfang an sync-tauglich (`synced_at`, `deleted_at`).

## 8. Erweiterbarkeit: vorgesehene Ports (Implementierung erst wenn gebraucht)

| Zukünftige Funktion | Port/Interface (vorgesehen) |
|---|---|
| GPX Import/Export | `GpxCodec` (Domain-Service) |
| Rundtour | `TourPlannerService` (Backend) – nutzt RouteSvc + PostGIS |
| Wetter entlang Route | `WeatherProvider` |
| Kurven-Score-Anzeige | `CurveScoreService` (existiert ab MVP im Backend, Ausbau später) |
| Community/Bewertungen | `CommunityApi` (Auth + Moderation) |
| Offline-Navigation | `OfflineRouteEngine` (implementiert `RouteEngine`-Port) |
| Gefahrenmeldungen/Blitzer | `HazardReportProvider` (rechtlich geprüft pro Land, siehe `12-legal.md`) |

## 9. Test-Strategie

- **Domain:** Unit-Tests (OffRouteDetector, CurveScore-Berechnung, Manöver-Engine) – pure Dart, 100 % testbar ohne Emulator.
- **Application:** Controller-Tests mit Fake-Ports.
- **Backend:** pytest, vor allem CurveScorer (Referenz-Routen: Schwarzwald B500, Alpenpässe, A8-Verlauf als Negativ-Test) und Valhalla-Request-Builder (Snapshot-Tests der JSON-Payloads).
- **Widget-Tests:** kritische Screens (Navigation, Route-Preview) mit Golden-Tests gegen Design-Tokens.
- **Integration:** Android (Emulator + echtes Gerät) mit Mock-Location (GPX-Replay auf echter Route).
