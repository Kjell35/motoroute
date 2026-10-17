# motoroute_app

Flutter-Client für MotoRoute.

## Stand dieses Codes

**Echt implementiert (0 Analyzer-Errors/Warnings, 36 Tests grün via `flutter test`):**

- Design-System aus Phase 3 als Code (`core/theme/`) – Farben,
  Typografie (inkl. tabellarischer Ziffern für Navigationswerte),
  Abstände.
- State-Layer (`core/state/`, `features/*/`): globale Riverpod-Provider
  für Fahrzeugtyp, Einheiten, POI-Kategorien, Wegpunkte, aktive Route.
- Alle 11 Screens aus Phase 3 gebaut und funktional verdrahtet:
  Splash → Onboarding (Fahrzeugwahl schreibt in den globalen Provider) →
  Karte (Suche/POI/Settings öffnen, Fahrzeug-Segment-Control, GPS-
  Zentrieren) → Zielsuche (echtes Backend, Lade-/Fehler-/Leerzustände) →
  Fahrstil-Auswahl (echte Berechnung, Avoid-Chips mit State) →
  Routenübersicht (echte Distanz/Zeit/ETA + Segmentliste) → aktive
  Navigation (GPS-Stream, Routen-Overlay, Off-Route-Erkennung,
  automatisches Rerouting) → Wegpunktverwaltung (Reorder/Löschen) →
  POI-Auswahl (Toggle steuert Karten-Layer-State) → Einstellungen.
- `features/navigation_session/navigation_providers.dart` – der
  sicherheitskritische Kern: Fortschritt entlang der Route, Off-Route-
  Erkennung (60-m-Schwelle), Rerouting über das Backend mit ERHALT der
  ursprünglichen Präferenz (Fahrstil/Vermeiden gehen nie verloren),
  GPS-Stream-Stop beim Verlassen des Screens (Akkueffizienz).
- `core/utils/geo.dart` + `formatters.dart` – unit-getestete Geo-Mathe
  (Haversine, Punkt-zu-Segment, kumulierte Distanzen) und Formatierung
  (km/mi). Der Segment-Distanz-Bug aus der ersten Fassung (verfälschte
  Projektion) ist durch Tests abgedeckt.
- Routing-Repository mit `Either<Failure, T>` und Dio-Mock-Tests.
- **Chat-/Community-System (`features/chat/`)** – vollständig funktional:
  - `data/chat_repository.dart` – REST-Client für alle `/v1/chat`-
    Endpunkte (Profil, Usersuche, Konversationen, Nachrichten mit
    Pagination, Gruppen, Einladungscodes, Blöcke, Meldungen) plus
    `ChatAttachment`-Builder für Route-/Standort-/GPX-Sharing
    (Architektur vorbereitet, Abschnitt 38 der Chat-Vorgabe).
  - `data/chat_realtime.dart` – WebSocket-Client (`/v1/chat/ws`) mit
    JWT-Auth-Frame, Reconnect mit exponentiellem Backoff, Heartbeat,
    Verbindungszustands-Stream (Offline-Banner in der UI).
  - `chat_providers.dart` – zentraler Controller: Konversationslisten
    mit Unread-Zählern, Realtime-Verdrahtung, Polling-Fallback (15 s)
    wenn WS down, Lesen-Markieren.
  - Screens: **Chat-Hub** (3 Tabs: Öffentlich/Privat/Gruppen),
    **Konversation** (Bubble-UI, Pagination, Reply, Soft-Delete,
    Melden, Typing-Indikator, Profil-Tap), **Neuer Chat** (Usersuche
    mit Debounce), **Gruppe erstellen**, **Gruppe beitreten** (Code-
    Vorschau mit Name/Mitgliederzahl), **Gruppeninfo** (Mitglieder
    mit Rollen, Owner-Verwaltung: Code erstellen/deaktivieren,
    entfernen, Ownership transferieren, bearbeiten, löschen).
  - Integration: Chat-Button mit Unread-Badge auf der Karte,
    `/chat`-Route, Einstellungen für Chat-Session + Online-Status-
    Datenschutz.
  - Unit-getestet: Formatter (relative Zeiten), Model-Parsing
    (snake_case ↔ Dart), Attachment-Builder.

**Bewusst offen/als TODO markiert:**

- Kartengrafik: ohne `MAP_STYLE_URL` wird ein eingebetteter Dark-Style
  erwartet (`assets/styles/moto-route-dark.json` – noch nicht erstellt,
  wartet auf die Tile-Anbieter-Entscheidung Phase 1/2 Teil H); ohne
  Asset startet die Karte mit leerem Stil statt zu crashen.
- Sprachansagen (TTS) und Energiesparmodus: Provider/Architektur
  vorbereitet, Umsetzung folgt (Sprint 8/11 des MVP-Plans).
- Native `android/`, `ios/`-Ordner werden durch das Flutter-Tooling
  erzeugt, nicht von Hand gepflegt. Siehe Setup unten.

## Setup

```bash
flutter create . --project-name motoroute_app --org com.motoroute --platforms=android,ios
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

`flutter create .` erzeugt die native Android/iOS-Projektstruktur in
diesem bereits vorhandenen `lib/`-Baum, ohne bestehende Dart-Dateien zu
überschreiben.

## Tests

```bash
flutter test          # 36 Unit-Tests
flutter analyze       # Statik-Analyse
```

## Nächste konkrete Schritte

1. `flutter create .` ausführen und auf Emulator/Gerät gegen das lokal
   laufende Backend (`motoroute_api`) testen.
2. Turn-by-Turn-Erkennung verfeinern: aktuelles Segment-Index-Matching
   durch echtes Map-Matching ersetzen (aktuell: nächstliegender
   Geometrie-Punkt – ausreichend für MVP, siehe Kommentar im
   NavigationController).
3. Sprachansagen über `flutter_tts` an die Instruktionen des
   NavigationControllers koppeln.
4. `assets/styles/moto-route-dark.json` erstellen bzw. Tile-Anbieter
   festlegen und `MAP_STYLE_URL` setzen (Phase 1/2 Teil H).
