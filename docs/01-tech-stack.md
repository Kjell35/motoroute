# MotoRoute – Technologie-Stack & Anbieterbewertung

> Status: Empfehlung zur Freigabe · Version 1.0 · Stand 2026-09-15
> Jede externe Abhängigkeit ist bewusst gewählt, begründet und hinter einer Adapter-Grenze kapselbar.

## 1. Entscheidungs-Matrix (Kurzfassung)

| Ebene | Wahl | Begründung in einem Satz |
|---|---|---|
| Mobile Framework | **Flutter 3.x (Dart)** | beste Kontrolle über Pixel/Animationen für ein eigenständiges Premium-Design, eine Codebasis für Android (MVP-Zielplattform) mit offener iOS-Option, exzellente Karten-/Kamera-Performance |
| Karten-Renderer | **MapLibre Native** via `flutter-maplibre-gl` | Open Source (BSD-2), vendor-neutral, Vektortiles, Offline-Regionen, eigenes Styling – kein Lock-in |
| Karten-Daten (Tiles) | **OpenFreeMap (public instance)** MVP, später **self-hosted** | kostenlos & kommerziell nutzbar, Vektortiles auf OpenMapTiles-Schema; selbsteinsetzbar sobald Traffic es rechtfertigt |
| Routing | **Valhalla (self-hosted, Docker)** | einzige Engine mit echtem „Motorcycle"-Costing inkl. „use_trails" (unbefestigt), flexibles Costing pro Request, Turn-by-Turn-Manöver inklusive, Offline-fähig durch Tile-Architektur |
| Geocoding/POI-Suche | **Photon (self-hosted)** + OSM Overpass-Extraktion für Fach-POIs | Kompass/Photon ist frei, DACH-stark; Biker-POIs kommen aus eigenen OSM-Extrakten |
| Traffic | **OSM-Sperrungen (Stub-Adapter)** im MVP; TomTom später optional | Zero-Budget-Beschluss: keine bezahlten APIs im MVP; der Port bleibt austauschbar – siehe Abschnitt 6 |
| Backend | **FastAPI (Python) auf eigener Infrastruktur** | dünne API-Grenze vor Valhalla/Photon (Key-Schutz, Rate-Limits, Datenschutz), einfach zu betreiben |
| DB | **PostgreSQL 16 + PostGIS** | geografische Queries (POI-Boxen, Rundtour-Daten) sind Kern-Requirement |
| Auth (später) | **Selbst gehostetes Auth über FastAPI (Passkeys/OAuth) – oder Keycloak** | MVCC-freundlich, DSGVO-freundlich (EU-Hosting), kein Vendor-Lock-in |
| CI/CD | GitHub Actions + Fastlane | Standard, Free Tier ausreichend |

## 2. Mobile Framework: Flutter vs. React Native

| Kriterium | Flutter | React Native | Gewinner |
|---|---|---|---|
| Karten-Performance (60fps, viele Layer, Rotation) | sehr gut (own Render Pipeline) | gut, aber Bridge/New-Architecture-Risiken bei komplexen Map-Interaktionen | Flutter |
| Pixelgenaue Eigenidentität (Design-System „Midnight Asphalt") | alles selbst zeichenbar | schwieriger, native Widgets locken in Standard-Look | Flutter |
| Background Location / Vordergrund-Service | gute Plugins, Foreground-Service dokumentiert | viable, aber mehr Platform-Code | Flutter |
| Rekrutierung/Ökosystem | groß | groß | Gleichstand |
| Risiko obsoleszenter Third-Party-Plugins | mittel (ein paar Schlüsselplugins) | ähnlich | Gleichstand |

**Entscheidung:** Flutter. Begründung: Das Produkt lebt von einem eigenständigen Look und einer butterweichen Karte mit Rotation/3D-Tilt während der Fahrt. Flutter gibt uns volle Kontrolle. Falls das Team später RN-Lastig ist, sind Domain-Logik und API-Verträge in dieser Architektur transportabel (Protobuf/JSON-Schemas), nur UI/State wäre neu zu schreiben – das Risiko dokumentieren wir bewusst.

## 3. Karten-Anbieter-Vergleich

| Anbieter | Kosten (realistisch) | Lizenz/Lock-in | Offline | Bewertung für MotoRoute |
|---|---|---|---|---|
| **MapLibre + OpenFreeMap** | 0 € (public instance), self-host später ~20–50 €/Mon | BSD-2 / ODbL-Daten, keine Vendor-Bindung | Vektortiles offline via MBTiles/PMTiles | **Best Choice MVP** – volle Design-Kontrolle, keine Kosten, DSGVO-freundlich, wächst mit uns |
| Mapbox | ab ~150–500 $/Monat bei realer Nutzung (Map Loads + Directions) | proprietär, starkes Lock-in | gut | die Premium-Option – aber 3–6× teurer, Lock-in hoch |
| Google Maps Platform | Free Tier 10k Map-Loads, danach teuer | proprietär | Offline nur in eigener App-API begrenzt | Look ist genau das, was wir NICHT wollen; teuer bei Skalierung |
| MapTiler | ab 0 € (dev), Pro ~80 €/Mon | OSM-basiert, APIs proprietär | gut | solide Alternative zu OpenFreeMap, falls wir später kommerzielle Tile-QoS brauchen |
| Stadia Maps | Free 200k Credits, ab ~20 $/Mon | OSM-basiert, gut dokumentiert | gut | starker Kandidat, insbesondere für Valhalla-Hosting-Variante (siehe Abschnitt 4) |
| HERE / TomTom Maps | ab ~100–500 €/Mon | proprietär | gut | Kartenqualität top, aber Budgetkiller für MVP |

**Entscheidung:** MapLibre Native + OpenFreeMap-Tiles + eigenes Style-JSON („Midnight Asphalt" Karte). Damit ist der Look 100 % ours und die Kosten bei 0 €. Wenn wir später bessere Abdeckung/QoS brauchen, tauschen wir nur die Tile-URL + ggf. Style aus – der Renderer bleibt.

## 4. Routing-Anbieter-Vergleich (Kern-Entscheidung!)

Das Herzstück: **„kurvig" und „extra kurvig" müssen echtes Routing sein, kein Marketing-Label.**

| Anbieter | Motorrad-Costing | Kurvig umsetzbar? | Unbefestigt? | Kosten | Offline möglich? | Urteil |
|---|---|---|---|---|---|---|
| **Valhalla (self-hosted)** | eigenes `motorcycle`-Costing | **Ja** – `use_highways`, `use_tolls`, `use_ferry`, `exclude_polygons`, flexible `penalties`/`factors` pro Road-Class; Kurven-Metrik via „scenic"/curvature-Heuristik selbst baubar auf Basis von Geometry + PostGIS | **Ja** – `use_trails`, `use_living_streets`, OSM `surface` wird gelesen | 0 € (Server ~20–40 €/Mon) | **Ja** – Valhalla funktioniert lokal auf Tiles (kostet Speicher, ~50–60 GB EU) | **Best Choice** – volle Kontrolle, echtes Motorcycle-Costing, Offline-Pfad, keine Request-Limits |
| GraphHopper (Cloud) | `motorcycle`-Profil mit `curvature`-Encoded-Value (sehr stark!) | **Ja** – „curvature" ist eine eigene Encoder-Dimension; Custom Models können sie gewichten | teilweise (surface-Encoded-Value) | Free nur nicht-kommerziell (500 req/Tag); Commercial ab ~119 €/Mon | ja mit eigener Engine | **Technisch beste Kurven-Heuristik**, aber Cloud-Lizenz teuer für kommerzielle App; selbst hosten möglich (Java, RAM-hungrig) |
| GraphHopper (self-hosted) | wie oben | Ja | teilweise | 0 € + Server | ja | brauchbare Alternative zu Valhalla; Java-Tuning nötig; Apache-2.0-Lizenz |
| Mapbox Directions | proprietär | nein (nur „driving"/„motorcycle" ohne echte Kurven-Gewichtung) | nein | ab ~2 $/1000 requests | nein (Mapbox eigenes Offline-SDK) | scheidet aus: Kurven nicht abbildbar |
| HERE Routing | proprietär | „scenic"-Route-Attribut, aber nicht steuerbar | nein | ab ~100 €/Mon | eingeschränkt | scheidet als Kern-Routing aus |
| TomTom Routing | proprietär | nein | nein | ab ~100 €/Mon | eingeschränkt | scheidet als Kern-Routing aus |
| openrouteservice (self-hosted) | `motorcycle`-Profil seit v7 | teilweise (Custom Models) | Ja (surface) | 0 € + Server | ja | solider Zweitkandidat, schwächere Manöver-Datenqualität als Valhalla |

**Entscheidung: Valhalla, self-hosted.** Begründung:

1. `motorcycle`-Costing ist offiziell –wir können es per Request parametrisieren.
2. **Kurvig-Heuristik** bauen wir selbst, deterministisch und testbar (siehe Abschnitt 5).
3. Unbefestigte Straßen sind first-class (`use_trails`, `surface`).
4. Turn-by-Turn-Manöver inklusive – kein zweiter Anbieter für Guidance.
5. Später Offline-Navigation möglich, ohne die Engine zu wechseln (Valhalla kann lokal laufen; wir planen die App-Schnittstelle entsprechend).
6. Keine pro-Request-Kosten = wir können interne Features wie Rundtour-Optimierung (viele Requests) ohne Kostenangst bauen.

**Risiko & Gegenmaßnahme:** Valhallas „kurvig" ist nicht out-of-the-box perfekt für jede Region. Wir bauen die Kurven-Heuristik als eigene Komponente mit Unit-Tests auf echten DACH-Beispielen (z. B. Schwarzwald B500, Alpen passes) und tunen dort. GraphHopper self-hosted ist als Ersatz-Adapter vorgesehen (gleiche Port-Schnittstelle), falls Valhalla zu unbefriedigend bleibt.

## 5. Konkretes Routing-Konzept: Wie „kurvig" technisch funktioniert

Fahrstile werden als **Valhalla-Costing-Parameter** + **eigene Kurven-Score-Logik** umgesetzt:

| Fahrstil | Valhalla-Parameter (motorcycle costing) | Ergänzende Logik |
|---|---|---|
| `fast` | `use_highways=1.0`, `use_tolls=0.5`, Standard-Geschwindigkeiten | – |
| `curvy` | `use_highways=0.2`, Landesstraßen bevorzugen | Nach-Filter: Alternativroute mit höherem `curveScore` wählen, wenn ≤ 15 % länger |
| `extra_curvy` | `use_highways=0.05`, `use_ferry=0.1` | wie oben, Threshold ≤ 30 % länger; Kurven-Heuristik bewertet Länder-/Kreisstraßen hoch |
| `fast_and_curvy` | `use_highways=0.4` | Hybrid-Heuristik: Autobahnen nur als „Verbindungsstück" zulässig, Kurvenanteil maximieren |
| `unpaved` | `use_trails=0.6`, `surface`-Präferenz gravel/dirt | Warnhinweis in UI (Reifen/Fahrkompetenz) |

**Kurven-Heuristik (eigener Code, Teil des Backend-Routing-Moduls):**

- Input: Route-Geometry (GeoJSON, Valhalla `shape`).
- Berechnung: segments in 20–50 m Fenster, Bearing-Änderungen summieren, gewichtet mit `Δbearing²/Δdist` (Kurvenintensität pro km). Glättung gegen Rauschen.
- Output: `curveScore` (0–100) pro Route, plus `curveDensity` pro Segment (für spätere Höhenprofil/Kurven-Highlight-Features).
- Fahrstile wählen aus bis zu N Valhalla-Alternativen die mit dem besten Score/Länge-Verhältnis.

Damit ist „kurvig" **testbar** (Unit-Tests mit Referenz-Routen) und **tunable** (Konfig, keine Hardcode-Magie).

## 6. Traffic-Anbieter: bewusster Kompromiss

| Anbieter | Incidents/Flow | Kosten | DSGVO | Urteil |
|---|---|---|---|---|
| **TomTom Traffic** | sehr gut (DACH) | ab ~100 €/Mon (echtes Budget) | gut (EU) | **aufgeschoben** (Zero-Budget-Beschluss); Aktivierung erst bei Budget-Freigabe |
| HERE Traffic | sehr gut | ähnlich | gut | Alternative |
| OSM/Other (OpenData) | mäßig, keine Echtzeit | 0 € | gut | nur Baustellen/Sperrungen statisch |
| **Self-built MVP stub** | Sperrungen via OSM + manuelle Meldungen | 0 € | gut | **Fallback für MVP ohne Budget** |

**Architektonische Konsequenz (Zero-Budget-Beschluss, 2026-09-15):** Traffic ist ein Port (`TrafficProvider`). MVP startet mit OSM-Sperrungen und einem klar gekennzeichneten Stub; TomTom wird erst bei Budget-Freigabe aktiviert (Feature-Flag, siehe `11-costs.md`). Der Fahrstil-Rerouting-Mechanismus ist identisch, egal welcher Provider dahinter hängt.

## 7. Backend & Infrastruktur

**MVP-Setup (einfach, günstig, skalierbar):**

```
[Flutter App]
     │ HTTPS (TLS 1.3, cert pinning optional)
     ▼
[Caddy/Nginx Reverse Proxy]  ← Let's Encrypt, HTTP→HTTPS Redirect
     │
     ├─ /api/route, /api/reroute ──► [FastAPI Backend] ──► [Valhalla (Docker)]
     ├─ /api/geocode, /api/pois  ──►                  ├─► [Photon (Docker)]
     ├─ /api/traffic/incidents ───►                  ├─► [TomTom API (outbound)]
     └─ /api/tour (Rundtour) ────►                  └─► [PostgreSQL + PostGIS]
```

**Warum kein Supabase/Firebase als Kern?** Beide sind exzellent für CRUD-Apps, aber MotoRoute ist primär eine **compute-lastige Geodaten-App** (Routing, Kurven-Score, Rundtour). Wir brauchen eigene Docker-Prozesse für Valhalla/Photon; Supabase wäre eine zweite Plattform daneben, nicht ein Ersatz. Auth/DB von Supabase könnten wir später trotzdem nutzen – die Backend-Grenze (FastAPI) bleibt.

**Hosting-Optionen (Zero-Budget-Pfad):**
- **Entwicklung:** docker-compose lokal auf dem Dev-Rechner (0 €)
- **Closed Beta:** Free-Tier-VM (z. B. Oracle Cloud „Always Free", ARM, bis 24 GB RAM – ausreichend für Valhalla-DACH + Photon + Postgres) (0 €, kein SLA)
- **Öffentlicher Betrieb:** erster gemieteter EU-Server (**Hetzner**, DSGVO-freundlich, ~25–40 €/Mon) – die erste echte Ausgabe, bewusst aufgeschoben

## 8. POI-Strategie (Biker-Treffs, Motorradhotels etc.)

1. **Basis:** OSM-Tags (amenity=fuel, tourism=hotel, tourism=camp_site, amenity=ice_cream) via Photon/Overpass.
2. **Fach-POIs:** Biker-Treffs und Motorradhotels gibt es in OSM teilweise (`amenity=motorcycle`, `tourism=hotel` + `motorcycle=*`), aber lückenhaft. Deshalb:
   - MVP: OSM-Abfrage mit klarem „Datenqualität variiert"-Hinweis in der UI.
   - Phase 2: eigene kuratierte Datenbank + Community-Beiträge (Moderation nötig → Auth-Feature).
3. **Blitzer/Verkehrswarnungen:** Rechtlich sensibel (in manchen Ländern verboten, z. B. Frankreich). MVP: **nicht implementieren**, Architektur-Port vorbereitet, Doku des Risikos in `12-legal.md`.

## 9. Zusammengefasste Monthly-Kosten (Zero-Budget-Pfad, Details in docs/11-costs.md)

| Phase | Setup | Kosten |
|---|---|---|
| Entwicklung (M0–M4) | docker-compose lokal | **0 €** |
| Closed Beta (M5–M6) | Free-Tier-VM + OpenFreeMap + OSM-Traffic-Stub | **0 €** |
| Öffentlicher Betrieb | erster EU-Server (Hetzner) | ~30–50 €/Monat |
| Skalierung (> 5k aktive Nutzer) | Routing-Cluster, ggf. TomTom | 180–1.200 €/Monat |

## 10. Nicht gewählte Alternativen – dokumentiert für spätere Revision

- **Supabase Auth** (statt eigener Auth): wird wieder geprüft, wenn Community-Features starten – Auth-Port ist abstrakt.
- **GraphHopper statt Valhalla**: falls Kurven-Heuristik unbefriedigend bleibt, GraphHopper-Adapter einsetzen (Port existiert).
- **MapTiler/Stadia Tiles statt OpenFreeMap**: falls Tile-QoS/SLA zum Problem wird – nur URL/Style-Tausch.
- **Rust statt Python fürs Backend**: später bei Bedarf (Routing-Module in Rust via PyO3), jetzt zu frühe Optimierung.
