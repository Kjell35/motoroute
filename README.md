# MotoRoute

Mobile Navigations-App für Motorradfahrer mit fahrspaß-orientiertem
Routing. Siehe die Phase-Dokumente für den vollständigen Kontext:

- `MotoRoute_Phase1_Phase2_Analyse.md` – Analyse, Tech-Stack,
  Architektur, Datenmodelle, Kosten, Rechtliches
- `MotoRoute_Phase3_UIUX.md` – Design-System, alle 11 Screens

## Teilprojekte

| Ordner | Inhalt | Status |
|---|---|---|
| `graphhopper-curvature-ext/` | Java-Erweiterung: Kurvigkeits-Bewertung pro Straßenkante | Geschrieben, nicht gegen echte GraphHopper-Version kompiliert – siehe `motoroute_api/docs/GRAPHHOPPER_SETUP.md` |
| `motoroute_poi_service/` | **NEU**: Eigenständiger Biker-POI-Dienst (TomTom Search API): täglicher Welt-Scan über ~195 Länder × 8 Biker-Kategorien, Biker-Score 0–100, PostGIS-Deduplizierung (75 m), REST-Delta-Sync + Socket.IO-Push | Vollständig funktionsfähig – benötigt eigene Postgres/PostGIS-Instanz + eigenen TomTom-Key (siehe `motoroute_poi_service/README.md`) |
| `motoroute_api/` | Backend (NestJS) inkl. GraphHopper-Konfiguration | Kompiliert, Unit-Tests grün: Routing/POI/Search/Traffic/Weather/User/Chat/GroupRoutes/GroupRides/Hazards + echte Supabase-JWT-Guards. Roundtrip weiterhin bewusst 501 (Post-MVP) |
| `motoroute_app/` | Mobile App (Flutter) | Kompiliert ohne Analyzer-Errors/Warnings, 48 Tests grün: alle Screens + Chat-/Community-System + kollaborativer Gruppen-Routenplaner + Live-Gruppenfahrt (opt-in) – inkl. aktiver Navigation mit GPS-Stream, Off-Route-Erkennung (60 m) und automatischem Rerouting mit Präferenz-Erhalt |

## Chat-System (neu)

Die App enthält ein vollständiges Chat-/Community-System:

- **💬 Chat-Bereich** mit drei Tabs: 🌍 Öffentlicher Chat, 🔒 Private
  Chats, 👥 Gruppen
- **Öffentlicher Chat** für alle angemeldeten Nutzer (Singleton-
  Konversation mit fester UUID)
- **Private 1:1-Chats** über Benutzersuche, mit Unread-Zählern,
  Lesen-Markieren, Soft-Delete („Nachricht gelöscht“)
- **Gruppen** mit Owner-Rolle (👑), Einladungscodes (`MOTO-XXXXXXXX`,
  kryptografisch zufällig, deaktivierbar, Ablaufdatum optional),
  Mitglieder-Verwaltung, Ownership-Transfer beim Verlassen
- **Sicherheit**: RLS auf allen 8 Tabellen (private Nachrichten für
  Nicht-Teilnehmer physikalisch unlesbar), Blockierung serverseitig in
  Policies durchgesetzt, WS-Gateway prüft Raum-Mitgliedschaft
  serverseitig, Spam-Rate-Limits, Meldungen (6 Gründe) im Backend
- **Echtzeit**: WebSocket (`/v1/chat/ws`) mit JWT-Auth, Reconnect mit
  Backoff, Typing-Indikator; ohne Verbindung Fallback auf REST-Polling
- **Attachments vorbereitet**: Route teilen (Name, km, Dauer,
  Kurven-Score), Standort teilen, GPX – Serializer liegen im
  `ChatAttachment`-Builder, Backend speichert JSONB

Aktivierung: `motoroute_api/supabase/schema.sql` **und**
`supabase/schema_group_routes.sql` in einem Supabase-Projekt ausführen,
Keys in `motoroute_api/.env` eintragen. Ohne Supabase läuft die
Navigation vollständig weiter; der Chat zeigt dann einen sauberen
„Dienst nicht verfügbar“-Zustand statt zu crashen.

## Biker-POI-Dienst (NEU – TomTom-Kuratierung, weltweit)

Der Ordner `motoroute_poi_service/` enthält ein eigenständiges
Backend, das täglich weltweit bikerfreundliche POIs findet und
kuratiert:

- **8 Biker-Kategorien** (Imbiss, Bikertreff, Kneipe, Pension,
  Restaurant, Hotel, Zeltplatz, Gartenlokal) mit **Biker-Score 0–100**
  und Amenities (Motorradparkplatz, Treffpunkt, Schrauberecke)
- **Weltabdeckung**: länderweise TomTom-Category-Search (~195 Länder),
  Kategorien werden **live gegen den TomTom-Katalog aufgelöst** (keine
  hartcodierten IDs), Freitext-Fallbacks für Bikertreff/Gartenlokal
- **Deduplizierung** per PostGIS `ST_DWithin` (75 m) – kein Duplikat-
  Chaos trotz täglicher Läufe; Soft-Delete für saubere Delta-Syncs
- **Integration in die App-Infrastruktur** (so ist es eingebunden):
  - Der Dienst läuft **autark** (eigene Postgres/PostGIS, eigener
    TomTom-Key für den Scan – getrennt vom Traffic-Key des BFF)
  - Das NestJS-BFF proxyt ihn authentifiziert unter
    **`GET /v1/biker-pois/sync`** (60-s-TTL-Cache, Kategorie-Mapping
    auf App-Kategorien, `biker-`-ID-Präfix zur Namensraum-Trennung von
    OSM-POIs, 503 bei Nicht-Konfiguration statt Crash)
  - Die App führt einen **Delta-Sync mit persistentem Cursor**
    (SharedPreferences): beim Start Cache laden, dann synchronisieren,
    danach alle 10 min nachziehen – offline bleiben gecachte POIs
    sichtbar
  - **Realtime-Push (sofort auf der Karte)**: Der Socket.IO-Strom des
    Dienstes (`poi:upsert`/`poi:delete`, gespeist vom Postgres-
    LISTEN/NOTIFY-Trigger) wird vom BFF über eine server-interne
    Socket.IO-Verbindung empfangen, **5-s-Koaleszierung** (nach dem
    nächtlichen Scan-Burst kommt EIN Batch statt hunderter Einzel-
    events) und als `bikerpoi.batch`-Frame über die authentifizierte
    App-WebSocket (`/v1/chat/ws`) verteilt. Die App zieht die
    betroffenen IDs sofort per Delta-Sync nach und zeichnet den
    Karten-Layer **ohne HTTP und ohne Kamerabewegung** neu – der
    10-Minuten-Timer bleibt als Fallback, falls die WS tot ist.
  - Die Karte **mergt** beide Quellen: OSM-POIs (live, viewport)
    + kuratierte Biker-POIs (gelb markiert) – gesteuert über dieselben
    Kategorien-Toggles, inkl. neuer Kategorien Restaurants, Kneipen &
    Bars, Imbisse
  - Das POI-Popup zeigt bei kuratierten POIs den **Biker-Score** und
    Amenities-Chips (Motorradparkplatz / Treffpunkt) plus
    „Als Stopp in die Route“
- Setup: `motoroute_poi_service/README.md` (schema.sql in die eigene
  PostGIS-DB, `.env` befüllen, `npm start`), dann im BFF
  `BIKER_POI_SERVICE_URL` setzen. Ohne den Dienst läuft alles andere
  unverändert (OSM-POIs decken die Karte ab).
- **Live-Radar (Biker Meetup)** über denselben Socket.IO-Server:
  `update_location` mit Ghost-Mode (true = NICHTS wird gespeichert),
  ST_DWithin-15-km-Umkreis, Push an nahe Biker. Datenschutz:
  eine Zeile pro Biker (keine Historie), Bereinigungs-Job löscht
  Positionen älter als 30 Minuten physisch, Disconnect entfernt
  sofort, keine REST-Route leitet Positionen aus. Details:
  `motoroute_poi_service/README.md` (Abschnitt Live-Radar),
  Migration `schema_radar.sql`.

## Gemeinsame Routenplanung (neu)

Kollaborativer Gruppen-Routenplaner, vollständig ins Gruppensystem
integriert:

- **🏍️ Route planen** in der Gruppeninfo → Owner erstellt „Neue
  Gruppenroute“ (Start/Ziel über Ortssuche inkl. PLZ, Fahrzeug,
  Routenstil, Vermeidungen) und entscheidet **„Wer darf diese Route
  bearbeiten?“** (🔓 Alle Mitglieder / 🔒 Nur Owner) – jederzeit
  änderbar.
- **Kollaborative Bearbeitung**: berechtigte Mitglieder fügen Stopps
  hinzu (Suche oder direkt auf der Karte), verschieben sie per
  Drag & Drop, löschen sie – die Route wird **automatisch neu
  berechnet** (gleiche Engine + gespeicherte Stil-/Vermeidungs-
  Einstellungen).
- **Echtzeit**: Änderungen erscheinen sofort auf allen Geräten
  (WS-Events + Nachladen des server-autoritativen Zustands,
  Versionsfeld für Konflikt-Erkennung, optimistische Updates mit
  Rollback).
- **Änderungsverlauf**: „Lisa hat ‚Tankstelle Shell‘ hinzugefügt“,
  Statuswechsel, Berechtigungsänderungen – alles auditiert.
- **Status**: 📝 Planung → ✅ Fertig → 🏍️ Unterwegs → ✔️ Abgeschlossen,
  plus 🔒 Sperre. Owner-Steuerung im Planer.
- **Serverseitige Berechtigungen** (Abschnitt 25/32): `can_edit_route`
  greift in RLS-Policies und jeder RPC-Prüfung – „Nur Owner“ ist auf
  der Datenbank durchgesetzt, nicht nur in der UI.
- **Route starten**: übergibt Start → Stopps → Ziel mit gespeicherter
  Präferenz an die normale MotoRoute-Navigation (übersichts- und
  Rerouting-fähig, Markierung „Unterwegs“).
- **Route-Card im Gruppenchat**: 🏍️ Name · km · Dauer · Kurven-Score
  mit „ROUTE ÖFFNEN“-Button direkt in den kollaborativen Planer.
- **Live-Gruppenfahrt** (👥): Fahrer teilen ihre Position **strikt
  opt-in** während der gemeinsamen Tour - Mitglieder sehen in Echtzeit
  wer unterwegs ist, wer noch nicht gestartet und wer am Ziel ist.
  GPS-Stream läuft nur bei aktiver Freigabe (15-s-Heartbeat,
  Low-Accuracy, Akku schonend); Abschalten löscht die Position
  **physisch** auf dem Server. Keine Historie, kein Tracking.
- **Ride-Radar (Live-Gruppenfahrt × Radar)**: Mitglieder derselben
  Route sehen einander **unabhängig vom Umkreis** (auch auf Anreise
  über Kontinente hinweg). Jeder RLS-verifizierte Heartbeat wird vom
  BFF per Shared Secret in das Ride-Relais des POI-Dienstes
  eingespeist; die zurückkommende verifizierte Mitgliederliste geht
  als `groupride.radar` ausschließlich an App-Sockets im Ride-Raum
  (`subscribe_ride`, serverseitig gegen `is_group_member_for_route`
  geprüft). Strukturell getrennt vom öffentlichen Radar: eigene
  Tabelle (`active_ride_bikers`), eigene Events, eigene Secret-Auth;
  30-Minuten-Prune auch hier. Positionslose globale Events bleiben
  bewusst positionsfrei.
- **Vorbereitet**: Stopp-Kommentare (Schema + API fertig, UI folgt),
  Offline-Sync-Marker im Modell.

## Community-Gefahrenradar (neu)

Biker melden von unterwegs Gefahrenstellen – mit 2 Klicks aus dem
Karten-Screen:

- **Melden** (⚠️-Button an der Karte): Typ antippen (🚧 Rollsplitt,
  ⛔ Sperrung, 🚜 Baustelle, 🛢️ Ölspur) → MELDEN. Position kommt vom
  GPS, kein Freitext nötig (Fahren kostet Aufmerksamkeit).
- **Konsolidierung**: mehrere Meldungen derselben Gefahr innerhalb
  100 m verschmelzen zu EINEM Report – die erste Fahrt durch die
  Baustelle erstellt ihn, jede weitere bestätigt ihn (+1 Upvote,
  Gültigkeit refreshed).
- **Gültigkeit**: standardmäßig 24 h. Ein Upvote („Gefahr ist noch
  da“) verlängert um 6 h, max. 72 h ab Erstellung – bestätigte
  Gefahren bleiben sichtbar, ungeprüfte verschwinden.
- **Karte**: rote/orange Kreise, Radius wächst mit der Zahl der
  Bestätigungen; Tap öffnet Detail mit Alter, Restlaufzeit und
  Upvote-Button. Abgelaufene Meldungen nehmen keine Upvotes mehr an
  (410) und werden serverseitig deaktiviert.
- **Serverseitig durchgesetzt**: 1 Upvote pro Nutzer
  (`hazard_report_votes`), Radius-Klemme [100 m, 100 km], RLS +
  SECURITY DEFINER-RPCs (`supabase/schema_hazards.sql`), Endpunkte
  strikt authentifiziert (`/v1/hazards`).

## Wichtigster nächster Schritt

Die Kurvigkeits-Validierung aus `motoroute_api/docs/GRAPHHOPPER_SETUP.md`,
Abschnitt 3 – das ist das größte noch offene technische Risiko des
Projekts und sollte vor jedem weiteren Feature-Sprint stehen.

Zweitgrößter Block: GraphHopper-Instanz tatsächlich starten und die
End-to-End-Kette Flutter-App → Backend → GraphHopper gegen eine kleine
Testregion (z. B. Bayern-Ausschnitt) fahren.

## Wetter-Radar mit Sturm-Frühwarnung (neu)

Während der Navigation zeigt die App ein dezentes Wetter-Widget (Temp +
Kurztext am Ziel). Läuft der Fahrer in Unwetter entlang seiner Route,
wird daraus ein roter Alarm-Streifen:

- **Backend** (`POST /v1/weather/route`): samplet die Routen-Polyline
  alle ~25 km, ordnet jedem Sample seine **ETA** zu (Startzeit +
  Fahrzeit-Anteil) und fragt pro Sample die passende Stunde aus der
  **OpenWeatherMap One Call API 3.0** ab (Key nur im BFF, 10-min-
  transienter Cache, Degradierung ohne Key/Netz wie beim Traffic-Modul).
- **Warn-Algorithmus**: Starkregen (≥ 7,6 mm/h), Gewitter (jeder OWM-
  2xx-Code), Sturmböen (≥ 17,2 m/s; Advisory ab 10,8 m/s), Schneefall.
  Die Meldung nennt den **Streckenabschnitt im Fahrtrichtungs-Stil**:
  „In 20 km zieht ein Gewitter auf: Gewitter + Starkregen".
- **Schutz-POIs**: bei Alarm liefert das Backend die drei nächsten
  Schutzpunkte (Motorradhotels, Bikertreffs, Campingplätze aus der
  bestehenden POI-Infrastruktur) im 15-km-Umkreis des kritischen
  Abschnitts. Tap auf den Alarm-Streifen öffnet das Schutz-Sheet.
- **App**: Widget unterhalb der Navigations-Leiste, 15-min-Refresh
  (Timer stoppt mit dem Screen), Fehler wischen die letzte Warnung
  nicht weg.

Aktivierung: `OPENWEATHER_API_KEY` in `motoroute_api/.env` setzen –
ohne Key blendet die App das Widget komplett aus.

## Android: APK ohne Play Store (GitHub → Handy)

Die App lässt sich komplett ohne Play-Store-Konto installieren und nutzen:

- **Jeder Push auf `main`**: GitHub Actions baut eine Debug-APK (`.github/workflows/android-build.yml`) → Artefakt im Actions-Run.
- **Tag `v0.1.0` pushen**: GitHub Actions baut eine signierte Release-APK (`.github/workflows/android-release.yml`) und hängt sie automatisch an ein GitHub Release an.
- Signierung über GitHub Secrets (`MOTOROUTE_KEYSTORE_B64`, `MOTOROUTE_KEYSTORE_PASSWORD`, `MOTOROUTE_KEY_ALIAS`, `MOTOROUTE_KEY_PASSWORD`); ohne Secrets greift ein Debug-Signatur-Fallback.
- Keystore-Dateien sind via `.gitignore` geblockt (`*.jks`, `*.keystore`, `key.properties`) und gehören niemals ins Repo.

Die App benötigt **keine Google Play Services und kein Firebase** (MapLibre/OpenStreetMap statt Google Maps, Supabase statt Firebase, Android-LocationManager für GPS) — sie läuft deshalb auf jedem Android-Gerät. Installations- und Update-Anleitung inkl. Keystore-Erstellung: **[docs/INSTALL.md](docs/INSTALL.md)**.

## Über den Stand dieses Codes

Alles hier ist echter, strukturierter Code – kein Fake-Gerüst. Wo etwas
bewusst noch nicht implementiert ist (Verkehr, Rundtouren, POI-Daten),
ist das im Code selbst als TODO/Platzhalter mit Begründung markiert,
nicht stillschweigend gemockt. Jede größere Architekturentscheidung ist
in den Phase-1/2-Dokumenten begründet und dort nachlesbar.
