# motoroute_api

Backend-for-Frontend für MotoRoute. Kapselt GraphHopper, POI-Daten und
(später) Verkehrsdaten hinter einer einzigen authentifizierten API –
die mobile App kennt ausschließlich diesen Dienst, nie GraphHopper oder
Supabase direkt (siehe Systemarchitektur, Phase 1/2 Teil C).

## Stand dieses Codes

**Echt implementiert und getestet (26 Unit-Tests, `npm test`):**

- `modules/routing/` – vollständiger Weg von Fahrstil-Präferenz →
  GraphHopper-Profil → Custom-Model-Overrides für Vermeiden-Optionen →
  Route-Domänenobjekt. Inkl. Unit-Tests für Profil-Mapping und
  Avoid-Overrides.
- `guards.ts` – echte Supabase-JWT-Validierung (`SupabaseAuthService`)
  mit `OptionalAuthProvider` (anonym erlaubt, Produkt-Requirement) und
  `AuthProvider` (401 mit maschinenlesbarem Code). Unit-getestet ohne
  echte Supabase-Verbindung.
- `modules/users/` – `GET/PUT /v1/users/me` final implementiert:
  User-ID kommt ausschließlich aus dem validierten JWT (nie aus dem
  Body), Profil-Fallback wenn der Webhook-Upsert noch nicht lief,
  PGRST116-Handling. Unit-getestet.
- `modules/search/` – Photon-Integration mit Standort-Bias (`near=lat,lng`),
  15-Result-Limit, saubere 503-Fehler wenn Geocoding nicht konfiguriert
  oder nicht erreichbar ist. In Dateien gesplittet (controller/service/dto).
- `modules/poi/` – Overpass-Abfrage für ALLE 6 POI-Kategorien
  (Tankstellen, Camping, Eisdielen, Blitzer, Motorradhotels,
  Biker-Treffs) in einer kombinierten Query + PostGIS-BBox-Abfrage
  für kuratierte Ergänzungen, parallel ausgeführt.
- `modules/traffic/` – **echte TomTom-Traffic-v5-Integration**
  (incidentDetails): neutraler Mapping-Layer (`tomtom.mapper.ts`, die
  eine Datei mit TomTom-Feldwissen), 60-s-TTL-Cache (Lizenzauflage:
  nur transientes Caching), Degradierung bei Provider-Ausfall.
  Ohne `TRAFFIC_API_KEY` liefert der Endpunkt `[]` (feature disabled).
  Unit-getestet inkl. Cache-TTL und bbox-Formattausch (TomTom will
  lat zuerst).
- `modules/weather/` – **Wetter-Radar mit Sturm-Frühwarnung**
  (`POST /v1/weather/route`): samplet die Routen-Polyline alle ~25 km
  (max. 12 Samples), ordnet jedem Sample seine **ETA** zu
  (Startzeit + Fahrzeit-Anteil) und fragt je Sample die passende Stunde
  aus der **OpenWeatherMap One Call API 3.0** ab. Koordinaten-Cache
  auf 2 Dezimalen (~1 km) gerundet, 10-min-TTL in-memory. Warn-
  Algorithmus isoliert in `storm-detector.ts` (Starkregen ≥ 7,6 mm/h,
  jedes Gewitter-2xx, Sturmböen ≥ 17,2 m/s, Schneefall) mit
  Fahrtrichtungs-Meldungen („In 20 km zieht ein Gewitter auf").
  Bei Alarm: Schutz-POI-Suche (MOTO_HOTEL/BIKER_MEETUP/CAMPSITE) im
  15-km-Umkreis über den PoiService - deren Ausfall kippt die Warnung
  nicht. Ohne `OPENWEATHER_API_KEY`: `isEnabled:false`, kein Netzcall
  (feature disabled). Unit-getestet (21 Tests: Schwellen, Prioritäten,
  Sampling/ETA, Cache, Degradierung, Shelter-Fehlertoleranz).
- Environment-Validierung (fail-fast), globales Rate-Limiting,
  Input-Validierung mit `whitelist`/`forbidNonWhitelisted`.
- `modules/chat/` – **vollständiges Chat-Backend** (`/v1/chat`):
  öffentlicher Chat (Singleton-Konversation), private 1:1-Chats
  (idempotenter RPC), Gruppen mit Owner-Rolle und Einladungscodes
  (kryptografisch zufällig, `MOTO-XXXXXXXX`, deaktivierbar, Ablaufdatum
  optional), Blockierungen/Meldungen (serverseitig in RLS-Policies
  durchgesetzt), Unread-Zähler (last_read_at), Presence (datenschutz-
  konform via `show_online`), Typing, Spam-Rate-Limits (5 Msg/10 s,
  3 neue Chats/10 s). **WebSocket-Gateway** unter `/v1/chat/ws`:
  JWT-Auth per auth-Frame, serverseitige Raum-Autorisierung via
  `is_conversation_member`, Broadcast von Nachrichten/Löschungen/
  Typing/Presence. **Supabase-Schema** in `supabase/schema.sql`:
  RLS auf allen 8 Tabellen (private Nachrichten für Nicht-Teilnehmer
  physikalisch unlesbar), SECURITY DEFINER-RPCs. Unit-getestet.

- `modules/group-routes/` – **kollaborativer Gruppen-Routenplaner**
  (`/v1/group-routes`): gruppeneigene Routen mit Status
  (planning/final/riding/completed/locked), Bearbeitungsrechten
  (all_members/owner_only), Stopps (hinzufügen/löschen/umordnen mit
  Konsistenzprüfung), Kommentaren pro Stopp, Änderungsverlauf,
  Duplizieren. **Automatische Neuberechnung** über den normalen
  RoutingService (gespeicherte Stil-/Vermeidungs-Einstellungen bleiben
  verbindlich). **Serverseitige Autorisierung**: `can_edit_route` in
  RLS + allen RPCs – ein manipulierter Client kann keine Rechte
  erlangen. `supabase/schema_group_routes.sql` (Migration).

- `modules/biker-pois/` – **BFF-Proxy zum eigenständigen Biker-POI-
  Dienst** (`GET /v1/biker-pois/sync`): authentifizierter Delta-Sync
  für die kuratierten TomTom-POIs (Biker-Score, Amenities). 60-s-TTL-
  Cache, Kategorie-Mapping auf App-Kategorien, `biker-`-ID-Präfix,
  503 bei Nicht-Konfiguration (App läuft mit OSM-POIs weiter). **WS-
  Push**: `BikerPoisRealtimeBridge` hält eine server-interne Socket.IO-
  Verbindung zum Dienst, koalesziert dessen `poi:upsert`/`poi:delete`-
  Strom (5-s-Fenster, 30-s-Hartlimit) und broadcastet `bikerpoi.batch`
  über `/v1/chat/ws` nur an authentifizierte Sockets – die App kennt
  den Dienst nie direkt. Siehe `motoroute_poi_service/README.md`.
- `modules/hazards/` – **Community-Gefahrenradar** (`/v1/hazards`):
  Biker melden Rollsplitt, Sperrungen, Baustellen, Ölspuren. POSTGIS
  `geography(POINT)` + GiST-Index für Umkreis-Abfragen, **24-h-Ablauf**
  (Upvote verlängert um 6 h, max. 72 h), **100-m-Konsolidierung**
  (mehrere Meldungen derselben Gefahr = ein Report mit mehr Upvotes),
  **1 Upvote pro Nutzer** in SQL erzwungen (`hazard_report_votes`).
  Autorisierung komplett serverseitig: RLS + SECURITY DEFINER-RPCs in
  `supabase/schema_hazards.sql`, der Service ist nur ein thin client
  mit User-JWT.
- `modules/group-rides/` – **Live-Gruppenfahrt** (`/v1/group-rides`,
  **+ Ride-Radar**):
  Fahrer teilen ihre Position **strikt opt-in** (kein Server-Code-Pfad
  legt je eine Position ohne ausdrückliche Freigabe an), 15-s-
  Heartbeats nur bei aktiver Freigabe, Abschalten löscht die Zeile
  PHYSISCH (kein toter Datensatz, keine Historie, kein Tracking).
  Live-Zustand (wer unterwegs/gestartet/fertig) nur für Gruppen-
  mitglieder lesbar (RLS + RPC-Prüfung). WS-Events für Echtzeit-
  Updates. Migration: `supabase/schema_group_rides.sql`.
  **Ride-Radar**: Nach jedem RLS-verifizierten Heartbeat
  (`assertRideMember` via `is_group_member_for_route`) speist das
  BFF den Beat per `RIDE_RELAY_SECRET` in das Ride-Relais des POI-
  Dienstes; dessen verifizierte Mitgliederliste geht als
  `groupride.radar` NUR an App-Sockets im Ride-Raum (`subscribe_ride`
  am WS-Gateway, ebenfalls RLS-geprüft) - Mitglieder derselben Route
  sehen einander unabhängig vom Umkreis. `stopSharing` räumt auch
  das Relais (best-effort).

**Bewusst als Platzhalter markiert (kein Fake-Feature):**

- `modules/roundtrip/` – Endpunkt/DTO real, `RoundTripService` wirft
  `501 Not Implemented` (Feature ist explizit MVP-Scope-Ausschluss).

## Setup

```bash
cp .env.example .env   # dann echte Werte eintragen
npm install
npm run start:dev
```

### Chat aktivieren (Supabase)

1. Supabase-Projekt anlegen.
2. `supabase/schema.sql` im SQL-Editor ausführen (idempotent –
   legt Tabellen, RLS-Policies, RPCs und den öffentlichen Chat an).
3. `SUPABASE_URL`, `SUPABASE_ANON_KEY` und `SUPABASE_SERVICE_ROLE_KEY`
   in `.env` setzen – der Server startet auch ohne sie (degradiert),
   aber Chat/Funktionsumfang benötigen echte Werte.
4. Realtime in Supabase für `messages` aktivieren (Fullcast / all
   changes), damit der Change-Strom für fremde Instanzen läuft.

Der Chat-WS-Port läuft mit unter dem normalen HTTP-Server
(`/v1/chat/ws`) – kein zusätzlicher Port nötig.

GraphHopper muss separat laufen (siehe `graphhopper/config.yml` und
`docs/GRAPHHOPPER_SETUP.md` – dort auch die noch offenen
Validierungsschritte für die Kurvigkeits-Gewichtung).

## Tests

```bash
npm test          # 40 Unit-Tests
npm run build     # Produktions-Build
```

## Nächste konkrete Schritte (siehe Phase 1/2 Teil G)

1. GraphHopper-Testinstanz mit `graphhopper-curvature-ext` bauen und
   gegen eine kleine Testregion importieren.
2. `docs/GRAPHHOPPER_SETUP.md` Abschnitt 3 (Validierungsprozess)
   durchführen, bevor `style_curvy.json`/`style_extra_curvy.json` als
   verlässlich gelten.
3. Supabase-Projekt anlegen, `SUPABASE_*`-Variablen setzen, Webhook
   auf `POST /v1/users` konfigurieren.
4. Geocoding-Anbieter final entscheiden (Photon self-hosted empfohlen –
   der SearchService ist bereits gegen die Photon-API geschrieben) und
   `GEOCODING_URL` setzen.
