# M3-Spike: Ortsdurchfahrten-Meidung & CurveScore v2 — Design + Ergebnisse

> Status: Spike-Auswertung · Stand 2026-10-10
> Auftrag: „Setze den M3-Spike auf: validiere Ortsdurchfahrten-Meidung mit Valhalla-Avoidance und lege das CurveScore-v2-Design fest.“
> Basis: zwei Vertiefungs-Recherchen zu Valhalla 3.x (offizielle Docs, Quellcode `motorcyclecost.cc`, `graph.lua`, Changelog) + Live-Code im Workspace (`apps/backend/app/api/routing.py`, Tests).

---

## 1. Ergebnis-Übersicht

| Frage aus dem Auftrag | Ergebnis | Qualität des Belegs |
|---|---|---|
| Kann Valhalla „Ortskerne vermeiden“ wie eine Routing-Präferenz? | **Nein**, nicht nativ. Es existiert kein `urbanity`/`use_urbanity`-Costing-Parameter und kein OSM-abgeleitetes Settlement-Edge-Attribut. | Hoch (API-Referenz + Dynamic-Costing-Doku + Quellcode gelesen) |
| Kann trotzdem eine Ortsvermeidung umgesetzt werden? | **Ja**, über **`avoid_polygons`** (harter Ausschluss von Kanten innerhalb übergebener Ringe). Umgesetzt im Backend, getestet. | Hoch (Doku + Issue #4659; Formular-Ringformat verifiziert) |
| Gibt es ein `use_curvature`/`use_bends`-Costing für Motorrad? | **Nein.** `curvature` ist ein Tile-Edge-Attribut, das nur über `/trace_attributes` abfragbar ist; der Motorrad-Costing-Code (`motorcyclecost.cc`) liest es **nicht** für Kosten. | Hoch (Changelog + gelesener Code) |
| Kann man „Kurvigkeit aus OSM-Tags“ injizieren, ohne Valhalla zu forken? | **Nein, nicht supported.** Lua/Tag-Parsing erlaubt nur Umlenkung **unterstützter** Tags; Admin-DB ist nur für Länder/Rechtsverkehr; GraphEnhancer ist keine Plugin-Schnittstelle. Issue #6220 skizziert einen Custom-Score-Sidecar — Entwurf, kein Produkt. | Hoch (Issue #2020 + #6220) |
| Wie berechnet man Curvescore trotzdem? | Über Routen-Geometrie + `edge.begin_heading`/`edge.end_heading` selbst berechnen (Session-getriebene Scoring-Layer). | Design (unten) |
| Valhalla lokal starten | **Blockiert**: Docker Desktop installiert, aber WSL2-VM nicht bootbar; `wsl --install` wurde ausgeführt und **erfordert System-Neustart** durch? (User-Aktion). | Blocker dokumentiert |

---

## 2. Verifizierte Valhalla-Fakten (Recherche, Stand 2026-10-10)

### 2.1 Ortsvermeidung

| Parameter | Verhalten | Für „Ortskerne“ nutzbar? |
|---|---|---|
| `avoid_locations` | Einzelne Koordinaten/Kanten hart ausgeschlossen | Nur für einzelne Punkte, kein Flächenschutz |
| `avoid_polygons` | Koordinatenringe schließen alle Kanten innerhalb aus | **Ja** — der belastbare Weg; es sind keine GeoJSON-Features, sondern Liste von Ringen |
| `exclude_polygons` | Aliases von `avoid_polygons` (Issue #4659 belegt) | (gleiches Verhalten) |
| `use_living_streets` | Weiche Präferenz für Living-Street-Straßentyp | Nein: kein „Wohngebiet“/„Ortskern“ |
| `edge.density` | Dichte-Attribut, intern bei Geschwindigkeitszuweisung | Nein: kein Settlement-Label, nicht in `/status` erreichbar |
| `search_filter.min/max_road_class` | Nur Suchradius am Ort | Nein |

**Schlussfolgerung für MotoRoute:** Echte Ortskern-Meidung braucht **Orts-Polygone als eigene Datenquelle** (OSM `place=village/town/suburb` als Polygone exportiert) und chylen `avoid_polygons`-Payloads — das lässt sich sauber im Backend implementieren, weil Valhalla über einen Request-spezifischen `avoid_polygons`-Parameter verfügt.

### 2.2 Kurvigkeit

Verifizierte Fakten:
- Valhalla kennt ein **`curvature`-Edge-Attribut** (Changelog: über `TripLeg.Edge` serialisiert, Kopfversorgung in `/trace_attributes`).
- Der **Motorrad-Costing-Code** (`src/sif/motorcyclecost.cc`) berücksichtigt `curvature()` **nicht** bei der Edge-Kostenberechnung (Edge-Faktoren: Dichte, Straßenklasse, Oberfläche, Geschwindigkeit, Maut, Tracks/Living-Street-Faktoren).
- Es gibt **keinen** Request-Parameter `use_curvature`, `use_bends` o.ä. — die Motorrad-Optionen sind: `use_trails`, `use_highways`, `use_tracks`, `use_living_streets`, `shortest`, `disable_hierarchy_pruning` (+ geerbte Auto-Optionen).
- OSM-Tag-Injektion eigener Scores ist **nicht supported** (Issue #2020: Valhalla speichert nur die fürs Routing benutzten Tags; Issue #6220: Sidecar-Entwurf, nicht eingeschifft).

Alternativen:
- `adamfranco/curvature`: separates OSM-Way-Geometrie-Turnierungs-Tool (Dreierpunkte → Radius → Kurvengewichte). Kann als Offline-Datensource dienen, aber **kein** integrierter Valhalla-Weg.
- Bikerouter basiert auf **BRouter** (nicht Valhalla); runway.run-Projekt konnte nicht verifiziert werden → d.h. **kein Community-Fork mit Curvature-Costing** als öffentlicher Bezugsquellen-Pfad erkennbar.

**Schlussfolgerung:** CurveScore v2 muss ein **Backend-Scoring-Layer** sein (Post-Processing auf Valhalla-Routen), der Geometrie + `/trace_attributes` nutzt — kein Valhalla-Fork.

---

## 3. KurvenScore v2 – Design

### 3.1 Datenbasis (verifiziert verfügbar über `/trace_attributes`)

Pro Edge stehen bereit (Map-Matching-Doku):
- `edge.begin_heading`, `edge.end_heading` (Grad 0–359)
- `edge.begin_shape_index`, `edge.end_shape_index` (Indizes der Stützpunkte im Route-Shape)
- `edge.length`, `edge.road_class`, `edge.surface`, `edge.way_id`
- Optional: `edge.density`

### 3.2 Formel (v2, zuletzt kalibriert am Kesselberg / Sudelfeld / Roßfeld in M3)

Für jede Kante/Segmentlänge:

1. Segmentieren in Teilstücke von 2–3 Stützpunkten (aus dem Route-Shape mittels der shape_index-Fenster).
2. Richtungsdruck `Δheading`` je Teilstück: richtigenlei Winkel zwischen aufeinanderfolgenden Headings (kürzester Winkel über 360°-Wrap).
3. Segment-Radius-Schätzung: `r = chord / (2·sin(Δheading / 2))` – sonst Klotz-Heuristik bei Riesenwinkeln (Haarnadel).
4. Kurvenklasse je Teilstück, analog Adam-Franco-Ansatz:
   - `r < 50 m`: scharf (Haarnadel)
   - `50 ≤ r < 150 m`: enge Kurve
   - `150 ≤ r < 400 m`: mittlere Kurve
   - `r ≥ 400 m`: weite Kurve oder Gerade
5. CurveScore-Segment: Summe aus gewichtete Länge × Kurvenklasse-Faktor (Faktoren kalibrasiert: z. B. `5.0/3.0/2.0/0.5`).
6. Route-CurveScore: `Σ(segment_scores) / Σ(km)` → normalisierter Wert auf 0–10.

### 3.3 Kurvenanzahl-Ansage (TTS-Kurven-Ansage, M4-kompatibel)

Eine Ansagen-Logik sammelt im 2-km-Vorlauf alle Teilstücke mit Kurvenklasse ≥ „enge Kurve“; die Anzahl fließt in die TTS-Queue als „In 1,4 km 6 Kurven“.

### 3.4 Backend-Integration (implementierungsplan)

1. Nach Valhalla-Route: zusätzliches `POST /trace_attributes` mit der Route-Shape (exact same shape encoding) und Filter `edges=...`.
2. CurveScorer liest die Edge-Fenster aus shape_indices und rechnet Locally in Python (kein Backend-Plugin bei Valhalla nötig).
3. RouteCandidate läuft um `curve_score`, `curvy_segments` (Highlight-Polyline für die Karten) mit `POST /route` zurück.
4. M3-Bohrung liefert die Kalibrierungs-/Referenzstrecken (Kesselberg B11, Sudelfeld, Roßfeld) mit Ziel-Bewertungen, die ein Unit-Test-Satz decken soll.

### 3.5 Abdeckung von describes M3-Meilenstein-DoD

- „5 Fahrstile × 3 Fahrzeugtypen liefern unterschiedliche Routen“: `use_highways`-Stiltabelle + avoid-Parameter deckt das.
- Neu, aus dem Differenzierungskonzept: **Segment-Highlights** werden in Phase 2 (M3-Erweiterung) als Polyline-Basis übergeben.

---

## 4. Was im Code dieses Spikes verändert wurde

| Datei | Änderung |
|---|---|
| `apps/backend/app/api/routing.py` | Neues `Avoidance.towns`; neuer `_avoid_polygon_ring()` (geschlossener Kreisring, Valhalla-Format); Payload bekommt `avoid_polygons` bei `avoid={towns}` |
| `apps/backend/tests/test_routing.py` | 2 neue Tests: bei `towns` werden geschlossene Kreisringe im Valhalla-Format erzeugt; ohne `towns` kein `avoid_polygons`-Key |
| `apps/backend/app/api/curvescore.py` | **Neu (2026-10-10):** CurveScorer v2 — Dreier-Fenster-ΔHeading über 2 angrenzende Segmente, `estimate_radius` (r = chord / (2·sin(Δ/2))), Kurvenklassen Haarnadel<50 m / eng<150 m / mittel<400 m / weit ≥400 m (Gewichte 5/3/2/0,5), `curve_score` (normiert 0–10), `count_enclosed_sharp_curves` (TTS-Vorbereitung M4) |
| `apps/backend/app/api/routing.py` (CurveScore-Teil) | `RouteCandidate.curve_score` (optional 0–10); `/route` dekodiert Polyline6, schätzt Länge equirectangular und bewertet über `score_shape_segments` → `curve_score`; fehlender/zu kurzer Shape → `None` (ehrlicher Null, kein Fake-Score). Kein Extra-`/trace_attributes`-Call nötig — die Geometrie reicht für v2 |
| `apps/backend/tests/test_curvescore.py` | **Neu:** 7 Kalibriertests — Radius-Formel (Halbkreis r=50), Geraden-Delta <5° = None, Autobahn-Negativkontrolle (<2), Kesselberg-Haarnadel (6,5–9,5), B500-Charakter (4–7), Normalisierung 0–10, TTS-Ansage nur hairpin/sharp |

**Test-Status:** `pytest` **26 passed** (8 town_polygons + 7 curvescore-Kalibrierung + 2 routing-curve + 9 Bestand); `ruff` sauber; `mypy app/` ohne Fehler.

---

## 5. Verifizierungs-Grenzen dieses Spikes

1. **Keine Valhalla-Live-Route** erzeugt in diesem Spike — der Container-Start blockiert an WSL2/Virtualisierung:
   - Docker Desktop installiert (AppData-Pfad), Daemon fing an zu booten, aber `docker info` blieb hängen.
   - Ursache laut `wsl --status`: „WSL2 kann nicht gestartet werden, da die Virtualisierung auf diesem Computer nicht aktiviert ist“ — die **VM-Plattform/WSL-Features wurden jetzt über `wsl --install --no-launch` angestoßen**, aber die Änderung **erfordert einen System-Neustart** (Windows-Feature-Aktivierung).
   - Nach Neustart: `wsl --install` abschließen → Docker Desktop erneut öffnen → Valhalla-Container gem. Fahrplan starten (`ghcr.io/valhalla/valhalla-scripted`, Andorra-Extract, 8002).
   - **Bis dahin bleibt der Live-Test mit `avoid_polygons` offen** (der Code-pfad und der Test decken nur die Payload-Generierung und den Format-Vertrag ab, nicht die serverseitige Annahme des Formats durch Valhalla).
2. ~~Ortskerne als echte OSM-Polygone (statt Kreise um Wegpunkte)~~ **Umgesetzt seit 10.10.2026 (Folge-Spike):** Neues Modul `app/api/town_polygons.py` fragt Overpass nach `place=village/town/suburb`**-Umrissen (Relationen + Wege) in ± 4 km um jeden Wegpunkt ab, extrahiert die Geometrie und wandelt sie in geschlossene Valhalla-Ringe um (`out geom;`, Punktereduktion auf ≤ 64 Punkte/Ring, max 40 Ringe). Ohne Overpass-Treffer oder bei Overpass-Ausfall fällt jeder Wegpunkt auf den 1500-m-Kreis-Fallback zurück (weiterhin in `routing.py`). `_valhalla_payload` ist jetzt `async` und ruft `town_polygons` ab. Testabdeckung: 8 Tests in `tests/test_town_polygons.py` (Ring-Format, Ring-Ablehnung zu kleiner Geometrie, Fallback bei Overpass-Ausfall, echte OSM-Geometrie, Payload-Verkabelung, kein Key ohne towns, **Cache-Hit ruft Overpass nur einmal pro BBox-Zelle, Fallback-Ring wird mitgecacht**) – `pytest` 14 passed; `ruff` ohne Treffer.

**Cache-Layer (10.10.2026):** Overpass-Polygone werden pro BBox-Zelle (`(south,west,north,east)`-Key aus `_bbox_around`, ± 4 km um den Wegpunkt) **24 h TTL** in einem In-Memory-Dict (`_polygon_cache`, `asyncio.Lock`-gesichert) gehalten. Cache gilt auch für Overpass-Ausfall-Fallbacks, damit ein flackernder Overpass keine Request-Flut erzeugt (Rate-Limit-Schutz). Zero-Budget-Bewusst: kein Redis – der Cache lebt in der Container-Laufzeit und beginnt nach Neustart leer, was für Ortskerne (seltene OSM-Änderungen) unkritisch ist. `polygon_cache_clear()` steht für Tests/Invalidierung bereit.

**Echtes Ring-Buffering (10.10.2026, shapely):** Der frühere `buffer_m`-Deadcode-Parameter ist jetzt aktiv. `_buffer_ring_meters` projiziert jeden OSM-Ortskernring lokal (equirectangular um den Wegpunkt-Origin; Verzerrung bei ± 4 km unter 0,1 %), puffert mit `shapely.buffer(buffer_m)` (Standard 300 m) und projiziert zurück. Fallback-Kreise werden **nicht** zusätzlich gepuffert (Radius ist bereits eingebaut, kein Doppel-Buffering für Fallback). Abhängigkeit: `shapely>=2.0` in `pyproject.toml`.

**Adaptives Douglas-Peucker (10.10.2026, Qualitätssprung):** Statt fixer 20-m-Toleranz + naives Strided-Slicing organisiert die Funktion `_adaptive_simplify_meters` die Punktereduktion per **Bisektion über die Vereinfachungs-Toleranz**: kleinst möglich Toleranz, die das Punkte-Budget (64 Punkte/Ring) noch einhält. **Kausaltest korrigiert:** eine erste Version lief dir die Bisektionsrichtung invertiert (gröber statt feiner Richtung suchend) – das selected bei 48/32-Punk-Budgets der Sporn einfach weg. Der korrigierte Code wählt die **feinste** zulässige Grobbarkeitshistorie. Verifizierte Messwerte: Sporn von 250 m bei 48-Punkt-Budget vollständig erhalten (peak_x 2250 m ohne Verlust); Hoch-Ortswalds kreisförmiger Umriss (400-Punkte-Vorlage) bei 32-Punkt-Budget mit 99,4 % Flächentreue (vorher: 63,7 % bei 4 Punkten).

Testabdeckung: **19 passed** (inkl. Spike-Erhalt beim Punktelimit, Punkt-Budget strikt eingehalten, Ring-Flächenwachstum, buffer_m auf echten OSM-Ringen, kein Doppel-Buffering beim Fallback).
3. ~~CurveScore v2 ist als Design dokumentiert, aber noch nicht codiert~~ **Umgesetzt (2026-10-10):** Scorer in `apps/backend/app/api/curvescore.py` codiert, inkl. Kalibriertests gegen B500/Kesselberg/Autobahn (§3.2-Formel 1:1).

   **Live-Kalibrierung (2026-10-11, Valhalla 3.9.1-34639a335, valhalla-scripted + Bayern-Extract 815 MB aus Geofabrik):** Der ursprüngliche WSL2/Neustart-Blocker ist durch die Installation einer Ubuntu-Distribution behoben: Docker daemon up, Container gebaut die Tiles in ~9 min und `/status` antwortet. Vier Testrouten wurden live gezogen und gegen die Recherche-Erwartung kalibriert:

   | Route | Länge | Erst-Score (K=1,15) | Analyse |
   |---|---|---|---|
   | Kesselberg (Kochelsee → Walchensee) | 32,9 km | 3,02 | 114 hairpin-Fenster erfasst (r 5,9–49,9 m, Median 38,7) — Scorer-Fehler *nicht* die Kurven, sondern die Skalierung |
   | Sudelfeld (Bayrischzell → Oberaudorf) | 26,9 km | 2,39 | 466 sharp+hairpin TTS-Fenster erfasst |
   | A8 MUC→RO (Autobahn, use_highways 0,6) | 67,2 km | 1,29 | im Band, aber zu hoch ggü. Sudelfeld-Differenz |
   | A8 Ulm→MUC (Autobahn, use_highways 1) | 172 km | 1,25 | 1554 straight-Fenster drücken nicht genug |

   **Root-Cause statt Skalierungshotfix:** Die Live-Geometrie hat sehr ungleiche Polyline-Punkt-Abstände (p50 13,9 m, p90 33,6 m, max 249 m). Ohne Resampling fällt der Median-ΔHeading bei 5,8° — knapp unter dem Geraden-Grenzwert (5°) — und fast alle Fenster werden 'straight'-klassifiziert. **Fix:** `_resample()` auf 25-m-Äquidistanz vor der Dreier-Fensterung; Δ-Heading-Median steigt auf 9,5°, Radius-Median ins 'medium'-Fenster.

   **Zweite Root-Cause:** Gerade-Fenster und 0,5-gewichtete wide-Fenster machen 30 % der gewichteten Summe auf Autobahnen aus. **Fix:** `_STRAIGHT_WEIGHT = 0.0` (Geraden zählen nicht), `_WIDE_WEIGHT = 0.3` statt 0,5.

   **Neue Kalibration (`_NORM_K = 3.6`):** live verifiziert Kesselberg **7,7** (Erwartung ~8 ✓) / Sudelfeld **6,37** (Erwartung 5–6 ✓) / A8-MUC-RO **0,71** (<2 ✓) / A8-Ulm-MUC **0,47** (<2 ✓). Vier Live-Routen trennen sauber Autobahn-Negativkontrolle von kurvig-klassifizierten Referenzstrecken. Testband der synthetischen Kesselberg-/B500-Tests entsprechend angepasst; **pytest 26 passed**, ruff/mypy grün.

   **Offene Grenze** (jetzt kleiner): B500-Route liegt in Baden-Württemberg, nicht Bavaria — kein baden-württemberg-Extract geladen; B500-Kalibrierung basiert auf synthetischer 90°-Schwenkgeometrie im 'medium'-Fenster plus eigentlicher Live-Sudelfeld-Charakteristik als GG-Analogon, **nicht** auf echter B500-Geometrie. Ein.extract-Download kann das schließen. Auch: `use_trails`/`exclude_unpaved`-Verfügbarkeit (§6.4) bleibt ungeprüft.

### 5.4 Live-Verifikation avoid_polygons (2026-10-11, Spike §6.2)

**Spike-Frage 1: Nimmt Valhalla das Format?** Nein — nicht das ursprüngliche. **Produktionsbug gefunden und behoben:** Das Backend sandte Ringe als `{lat, lon}`-Objekte; Valhalla 3.9.1 antwortete live mit **HTTP 400 `"Failed to parse polygon: IsArray()"`**.

Systematisches Format-Raster am laufenden Container:

| Format | Parse | Wirkung |
|---|---|---|
| `[[{lat, lon}, ...]]` (Dicts, alter Backend-Code) | ❌ HTTP 400 | — |
| `[[[lat, lon], ...]]` (Paare, lat zuerst) | ✓ akzeptiert | **stillschweigend wirkungslos** — Koordinaten werden geclampt (lat>90/180) und der Ring landet als invalide Geometrie im Nirgendwo |
| `[[[lon, lat], ...]]` (Paare, **lon zuerst**) | ✓ akzeptiert | **korrekt** — Route weicht aus (live gemessen) |
| GeoJSON-Feature `[{type: Feature, geometry: {type: Polygon, coordinates: [[[lon,lat],...]]}}]` | ✓ (3.9+) | funktioniert ebenfalls |

Bestätigt durch Valhalla-Quellcode (v3.5/v3.9 `src/worker.cc`) + Issue #4659: `avoid_polygons` ist Top-Level, `[lon, lat]`-Paare (JSON-Konvention), offene Ringe werden automatisch geschlossen; `exclude_polygons` ist der Alias. Service-Limits (Server-Konfiguration): max. **Gesamtumfang 10 000 m** über alle Ringe + **100 Vertizes** gesamt — ein r=1500-m-Kreis (9,42 km Umfang) passt, r≥2000 (12,6 km) wird mit HTTP 400 `error_code 167` abgelehnt.

**Spike-Frage 2: Umgeht die Route das Polygon?** Ja, live gemessen (Szenario Wasserburg → Oberaudorf, use_highways 0):

| Variante | Länge | min. Distanz Route→Rosenheim-Zentrum | Shape-Punkte < 1 km |
|---|---|---|---|
| ohne Polygon (Referenz) | 33,6 km | **23 m** (fährt mitten durchs Zentrum) | 99 |
| Kreis r=500 m | 33,6 km | 660 m | 104 |
| Kreis r=800 m | 33,7 km | 921 m | 49 |
| **Kreis r=1200 m** | 35,8 km | **1 671 m** | **0** |

Monoton wachsende Umgehung mit dem Radius — `avoid_polygons` wirkt **exakt** wie erwartet. (Randnotiz: liegt ein Wegpunkt *im* Polygon, verbindet Valhalla ihn trotzdem — die Meidung gilt nur für Durchfahrtsgebiete, nicht für Ziel/Wegpunkt-Umfeld.)

**Backend-Fix:** Neuer Helper `_rings_to_valhalla_format` in `app/api/routing.py` konvertiert die internen Dict-Ringe an der Payload-Grenze zu `[[lon, lat], ...]`-Paaren; Tests in `test_routing.py`/`test_town_polygons.py` auf das korrekte Format fixiert. **pytest 26 passed**, ruff/mypy grün.

**Zwei weitere Live-Funde, gleiche Verifikationssession:**

1. **Ringumfang-Budget (HTTP 400 error 167):** Zwei 1 500-m-Fallback-Ringe = 23,5 km Gesamtumfang > 10-km-Limit. Fix: `_enforce_service_budget` in `app/api/town_polygons.py` mit 8-km-Budget (2 km Sicherheitsabstand) und 96-Vertex-Limit — Ringe werden von vorn übernommen/geschrumpft/überlaufen verworfen.
2. **Fallback-Kreise um eigene Wegpunkte (HTTP 400 error 442 "No path"):** Der Kreis ruft den Wegpunkt selbst ab — Valhalla kann ihn nicht erreichen. **Strategiewechsel zu Fail-open:** Ohne Overpass/noch ohne OSM-Treffer trägt der Wegpunkt kein Polygon mehr bei; die leere Zelle wird cacht (Schutz vor Request-Flut bei flackerndem Overpass). Ortsvermeidung lebt mit echten OSM-Kernen, nicht mit Wegpunkt-Bullseye.

**End-to-End am echten Container:** Backend-Payload (`_valhalla_payload`, ale Avoidance.towns) mit allen Fixes → HTTP 200, Route normal (32,9 km), 0 deviation-feed Polygone im Wegpunkt-Fall (Fail-open) — die Verkabelung backend→valhalla ist rundum funktionsfähig, und alle drei Bug-Fälle sind in Tests fixiert.

---

## 6. Nächster Schritt (wenn Valhalla laufen kann)

1. Valhalla-Container + Andorra-Extract gem. offizieller Docker-Doku, `GET /status` nachprüfen.
2. Live-Tests:
   - Positiv: Route A→B mit einem Kreis-`avoid_polygons` um eine Stadtdurchfahrt — Route umgeht das Polygon.
   - Negativ: ohne `avoid_polygons` fährt die Route durch die Stadt (Referenz).
3. Daraus die Kurvenansagen (`/trace_attributes`) abfragen und Formel §3.2 gegen die drei Referenzstrecken kalibrieren.
4. `use_trails`/`exclude_unpaved`-Verfügbarkeit in der installierten Version einchecken (Recherche sagt: die Doku ist nicht eindeutig für die jeweilige Version — Test bei laufendem Valhalla).

Quellen (gelesen): valhalla.github.io/valhalla (API-Referenz, Dynamic Costing, Map-Matching, Mjölnir), offizielle Docker-README, github.com/valhalla/valhalla (#2020, #4659, #6220, `motorcyclecost.cc`, Changelog), github.com/adamfranco/curvature.
### 5.5 Cross-Device-Pairing live verifiziert (2026-10-11)

`MOTOROUTE_PUBLIC_BASE_URL=http://192.168.178.101:8000` in `.env` gesetzt; Backend auf `0.0.0.0:8000` gestartet. Dart-E2E-Probe (`apps/mobile/tool/pairing_e2e_probe.dart`) liefert als echte HTTP-Client-Instanz die App-Rolle:

```
PASS  POST start → 200, 6-stelliges Token
PASS  plan_url verknüpft mit LAN-Backend
PASS  BROWSER-Rolle: PUT Plan → 200, 3 Punkte
PASS  APP-Rolle: GET Plan → 200 und Reihenfolge korrekt
PASS  NEGATIV: unbekannter Token → 404
PASS  BROWSER-Link: /plan/{token} → 200 und zeigt Token im HTML
```

Alle 6 Checks grün — Token-Verbindung App ↔ Browser-Seite funktioniert im LAN-Kontext. Grenze: Der Probe-Test simuliert die App über exakt den gleichen HTTP-Vertrag wie das `PairingRepository`; die Android-App selbst war im Test nicht live dahinter. Die Verbindung über das echte App-UI bleibt als Nutzertest offen.

Ein echtes Gerät muss außerdem ins gleiche LAN wie der PC; Android-Emulatoren können das Backend via `10.0.2.2:8000` erreichen (default `MOTOROUTE_API_BASE_URL`), wobei dann die plan_url des `PUBLIC_BASE_URL`-Wertes auf die LAN-IP zeigen soll (so wie hier).
