# Vergleich der beiden MotoRoute-Linien

> Stand: 6. Oktober 2026 · Faktenbasis: Git-Inspektion von `origin/main` (Commit
> `2e32dea`, letzter Push 05.10.2026) und lokalem `main` (Commit `287764b`).
> Beide Linien sind dasselbe Produkt („Navigations-App für Motorradfahrer mit
> fahrspaß-orientiertem Routing“), aber zwei getrennte Historien ohne gemeinsamen
> Vorfahren.
>
> **Revision 2 (nach Tiefenanalyse des Routing-Codes):** Die frühere Einschätzung
> „toter GraphHopper-Pfad“ war zu hart – der echte Stand steht unten im Abschnitt
> Routing-Kern; der verbindliche Plan ist `docs/ROUTING_FAHRPLAN.md` (im Klon
> `motoroute-v1`).

## TL;DR

**Linie A (GitHub `main`, v1.0.2)** ist breit, vertriebsfertig und aktiv – ihr
Routing läuft heute real, aber degradiert (OSRM-Fallback mit Kurven-Scorer);
die eigene Kurven-Engine ist zu ~90 % vorbereitet, jedoch ungeprüft – und sie hat
sich vom Zero-Budget-Prinzip entfernt. **Linie B (Branch `monorepo`, lokal)** hat den
disziplinierten Kern (getestete Valhalla-Routing-Logik, saubere Architektur,
strenge Privacy-Regeln), aber fast keine Features und nie einen Build gesehen.

Empfehlung: **Linie A als Produktionslinie weiterführen und den Kern über das
Sprint-0-Entscheidungstor schließen** (CI baut die GraphHopper-Extension und
startet die Engine gegen echten Datenausschnitt): Grün → GraphHopper, da zu ~90 %
vorbereitet; Rot → Valhalla-Swap, dessen Referenz-Übersetzung bereits getestet in
Linie B liegt. Die Monorepo-Linie bleibt als Archiv/Referenz-Branch erhalten.
Details: `docs/ROUTING_FAHRPLAN.md`.

## Die beiden Linien im Überblick

| | **Linie A – `main` (v1.0.2+38)** | **Linie B – Branch `monorepo`** |
|---|---|---|
| Struktur | `motoroute_app/` + `motoroute_api/` (NestJS) + `motoroute_poi_service/` + `garage/` + `graphhopper-curvature-ext/` + `render.yaml` | Monorepo: `apps/mobile/` (Flutter) + `apps/backend/` (FastAPI) + `infra/` (Compose) + `docs/00–12` |
| Dateien | 412 | 86 |
| Letzter Commit | 05.10.2026 (gestern) | heute (erster Commit, nie gepusht außer als Archiv-Branch) |
| Releases | v0.1.0 … v1.0.2, **signierte APKs** über GitHub-Secrets | keiner, APK debug-signiert, CI nie gelaufen |
| Karten-Engine | MapLibre 0.22 | MapLibre 0.19 |
| State/Deps | Riverpod, dio, dartz, freezed, WebSockets, battery_plus | Riverpod, go_router, http |

## Routing-Kern (das Herzstück des Produkts)

| | Linie A | Linie B |
|---|---|---|
| Ansatz | Eigene Java-Extension `graphhopper-curvature-ext` (Curvature-Score pro Kante) | Valhalla `motorcycle`-Costing; Fahrstile → Costing-Parameter übersetzt |
| Heute live | ✅ **Routing läuft real über den OSRM-Fallback** (echte Routen, deutsche TBT-Texte, Auswahl der kurvigsten von 2 Alternativen via `curvinessPerKm`; per-Kante-Kurvenpräferenz und Autobahn-Avoid fehlen dort bewusst) | ✅ Backend-Endpoint mit getesteter Costing-Übersetzung; App zeigt Distanz/Dauer, Route wird noch nicht gezeichnet |
| Vorbereitung | ✅ **~90 % fertig:** engine-isolierter Client, Profil-Mapping (5 Motorrad-Fahrstile), Avoid-Overrides, `config.yml` + `custom_models/*.json`, Spec-Tests – die `config.yml` verweigert ohne Extension-EV bewusst den Start (fail-fast) | – |
| Offen | ⚠️ Versions-Pin + Extension-Build, EV-Namen-Abgleich (`curvature`, `road_access`, `motorcycle_access`), Daten-Import, Kalibrierung (`SCORE_CEILING = 3.2` ist Schätzwert) – genau das prüft Sprint 0 | Hosting/RAM-Budget; Kurvenpräferenz gröber (Costing-Optionen statt Kanten-Score) |
| App-seitige Navigation | ✅ Aktive Navigation mit GPS-Stream, Off-Route-Erkennung (60 m), Rerouting mit Präferenz-Erhalt implementiert | ❌ noch nicht (M4) |
| Rundtouren | ❌ bewusst 501 (`roundtrip.module.ts:41`, NOT_IMPLEMENTED) | nicht begonnen |

**Kernaussage (korrigiert):** Linie A hat die Navigation *herum* gebaut und
routet heute real – aber im Degradationsmodus (OSRM); die eigene Kurven-Engine
ist vollständig vorbereitet und ungeprüft, nicht tot. Linie B hat die
Engine-Logik getestet, aber keine Navigation *herum*.

## Features

**Linie A (weit über MVP hinaus):** Chat/Community (öffentlich, privat, Gruppen
mit Einladungscodes, RLS auf 8 Tabellen), Marktplatz mit KI-Prüfung (Gemini),
Garage (Fahrzeuge/Wartung/Kosten, eigener Prisma-Dienst), Badges/„Pass-Knacker“,
Gruppen-Routenplaner kollaborativ, Live-Gruppenfahrt (opt-in), Gefahrenradar
(Community-Meldungen mit Konsolidierung), Wetter-Radar mit Sturm-Frühwarnung
(OpenWeatherMap), Tour-Tagebuch + GPX, TTS-Sprachansagen, Biker-POI-Dienst
(TomTom, weltweit, Biker-Score – **noch nicht deployt**, braucht eigene PostGIS
+ TomTom-Key).

**Linie B (MVP-Kern):** Karte mit Follow-Kamera/Pan-Policy, Suche, Wegpunkte
(Reorder), Routenplaner (Fahrzeug/Fahrstil/Vermeidungen), Routenberechnung
(Backend), POI-/Traffic-Layer (OSM, ehrlich als „nicht live“ gekennzeichnet),
Sparmodus, 5 Flutter-Tests + 3 pytest-Dateien.

## Infrastruktur, Kosten, Keys

| | Linie A | Linie B |
|---|---|---|
| Backend-Hosting | Render Free (NestJS-BFF, garage-api); **schläft ein** (Kaltstart 30–60 s), 3 Keep-Alive-Workflows pingen dagegen | geplant: self-hosted Valhalla + FastAPI (Compose), Deployment offen |
| Datenbank | Supabase (Auth + Postgres + RLS; Migrationen **manuell** im Dashboard durchzuführen) | PostgreSQL+PostGIS self-hosted geplant |
| Keys nötig | TomTom (POI-Scan + Traffic), OpenWeatherMap (optional), Gemini (Marktplatz-KI), Supabase-Keys, GARAGE_TICKET_SECRET | **keine** (Zero-Budget: nur OSM/Photon/Overpass; TomTom bewusst nur als deaktiviertes Flag) |
| Kostenrisiko | Free-Tiers mehrerer Anbieter; Skalierung → mehrere Rechnungen; Keep-Alive verbraucht GitHub-Minuten | nominal 0 € (Hosting-Quote für Valhalla ist die offene Frage) |

Linie A ist damit realistisch „Fast-Zero-Budget“: kostenlos *anfangs*, aber mit
fünf Anbieter-Abhängigkeiten, Keys im Env und Betriebsoverhead (Migrationen per
Hand, Keep-Alive-Pings, Kaltstarts).

## Datenschutz

**Linie B:** streng – keine Standort-Persistenz, keine Keys im APK, Positions-Bias
nur flüchtig, Datenquellen ehrlich gekennzeichnet.

**Linie A:** durchdacht bei den riskanten Features (Live-Radar: Ghost-Mode,
30-Minuten-Prune, keine Historie; Gruppenfahrt strikt opt-in mit physischem
Löschen; anonyme Telemetrie) – aber strukturell mehr DSGVO-Fläche: Nutzerkonten
(Supabase-Auth), Chat-Inhalte, Marktplatz-Inserate, Fehler-Reports. Mehr
Daten = mehr Dokumentations- und Antwortpflichten.

## Qualität & Hygiene

| | Linie A | Linie B |
|---|---|---|
| Tests | 35 Test-Dateien App, 29 Spec-Dateien Backend, 4 Garage (README nennt ~130+174 Tests – von mir nicht ausgeführt) | 5 Flutter- + 3 pytest-Dateien (klein, aber echt) |
| Doku | Phase-Docs + 9 Spezial-Docs (INSTALL, SECRETS_SETUP, CURVATURE_VALIDATION, ONECLICK_SQL, GARAGE_DEPLOY …) | docs/00–12 einheitlich, konsistent mit Code |
| Auffällig | `.freebuff/` committet; Release-Bumps fast pro Commit (38 Versionen); Keep-Alive als Workaround | CI nie gelaufen → alle „grün“-Annahmen unbewiesen |

## Entscheidungsoptionen

**Option 1 – Linie A weiterführen, Kern über das Sprint-0-Tor schließen (Empfehlung).**
Die v1.0.2-App ist der schnellste Weg zu einer nutzbaren App mit Releases.
Sprint 0 (1–2 Tage, komplett in GitHub Actions) baut die GraphHopper-Extension
gegen eine gepinnte Version und startet die Engine gegen einen kleinen
OSM-Ausschnitt. Tor A grün → GraphHopper fertigstellen (Versions-Pin, EV-Abgleich,
Kalibrierung an Referenzstrecken, Betrieb). Tor B rot → Valhalla-Swap, isoliert
im Engine-Client; die getestete Costing-Übersetzung aus Linie B dient als
Referenz. Beide Wege haben dieselbe offene Betriebsfrage: RAM – Render Free
(512 MB) ist für beide Engines knapp, Kandidat ist Oracle Cloud „Always Free“
(ARM). Der verbindliche Ablauf steht in `docs/ROUTING_FAHRPLAN.md`.

**Option 2 – Linie B zum Produkt machen, Features portieren.** Sauberste
Architektur und strengste Privacy, aber: Chat, Marktplatz, Garage, Gruppen,
Badges etc. müssten neu gebaut werden – Wochen bis Monate, und Linie B hat noch
nie einen erfolgreichen Build gesehen. Nur sinnvoll, wenn dir die
Anbieter-Abhängigkeiten von A ein K.O.-Kriterium sind.

**Option 3 – Beide einfrieren, Neubau.** Verwirft am meisten Wert; nur bei
fundamentalem Neustart-Wunsch.

## Unabhängig von der Wahl zu erledigen

1. **Aus Linie B retten, was A fehlt:** Valhalla-Übersetzung + deren Tests
   (dienen Pfad V als Referenz), Backend-/Privacy-Doku (docs/07) als Vorlage für
   A's Datenschutz-Seite.
2. **Aus Linie A übernehmen:** Release-Signierung per GitHub-Secrets,
   INSTALL-Doku, falls Linie B jemals wieder aufleben soll.
3. **Aufräumen:** `.freebuff/` aus der Git-Historie-Perspektive prüfen
   (derzeit eingecheckt), Home-Verzeichnis-Repo und Klartext-Keystore-Notiz
   auf `C:/Users/treis/` sichern bzw. löschen (Passwort in den Tresor!).

## Verifikations-Grenzen dieses Berichts

Alle Remote-Angaben stammen aus Datei-Inspektion von `origin/main` (README,
Workflows, Quellcode, pubspec) – für Revision 2 zusätzlich die vollständige
Inspektion der Routing-Kette (Engine-Client, `config.yml`, Custom Models,
Profil-Mapping, Setup-Doku) im lokalen Klon `motoroute-v1` (HEAD = `v1.0.2`).
Was ich **nicht** ausgeführt habe: Tests, Builds, Extension-Kompilierung,
OSM-Import oder Deployments beider Linien (lokal kein Flutter/Node/Java) – genau
deshalb ist Sprint 0 als Entscheidungstor konstruiert. README-Behauptungen
(„174 Tests grün“, „kompiliert ohne Analyzer-Errors“) sind plausible
Eigenaussagen, bis der erste eigene CI-Run sie bestätigt.
