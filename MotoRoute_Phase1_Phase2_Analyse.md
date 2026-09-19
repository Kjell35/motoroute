# MotoRoute – Phase 1 & Phase 2: Analyse & Architektur

*Stand: 15. September 2026 – Grundlage für Freigabe vor Implementierungsbeginn*

---

## Teil A – PHASE 1: ANALYSE

### A.1 Produktverständnis in einem Satz

MotoRoute ist keine "Navigations-App mit Motorrad-Icon", sondern eine **Routing-Engine-App**, bei der die Kernkompetenz die *qualitative Bewertung von Straßen* ist (Kurvigkeit, Belag, Charakter) statt nur Distanz/Zeit. Das ist die eigentliche technische Herausforderung des Projekts – alles andere (Karte, GPS, UI) ist lösbares Standardhandwerk.

### A.2 Die größten technischen Herausforderungen

**1. "Kurvig" / "Extra kurvig" ist kein Standard-Routing-Feature**

Kommerzielle Routing-APIs (Google, HERE, TomTom, Mapbox Directions) bieten **kein** Kurvigkeits-Kriterium an. Das ist der zentrale Grund, warum eine reine "wir nehmen eine fertige API"-Strategie hier scheitert. Es gibt zwei praxiserprobte Lösungswege:

- **Eigene Kurven-Bewertung auf Basis von OpenStreetMap-Geometrie**: Aus der Liniengeometrie eines Straßensegments lässt sich ein Krümmungswert (Richtungsänderung pro Streckenlänge) berechnen und als zusätzliches Routing-Gewicht einspeisen.
- **Precedent-Projekt (wichtig für Architektur-Vertrauen):** Genau dieses Problem hat die bekannte Motorrad-Routenapp *Kurviger* bereits gelöst – sie basiert auf dem Open-Source-Routing-Server **BRouter**, der Straßenkurven aus OSM-Geometrie bewertet und Profile für "kurvig"/"sehr kurvig" anbietet. Das bestätigt: Der Ansatz "Open-Source-Routing-Engine + eigenes Kurven-Gewichtsmodell" ist marktbewährt und nicht experimentell.
- Alternative: **GraphHopper** mit seinem *Custom Model* / Flex-Routing-API, bei dem eigene Gewichtungsformeln (inkl. selbst berechneter Kurvigkeits-Werte pro Kante) definiert werden können.

→ Fazit: Wir brauchen eine **selbst gehostete, quelloffene Routing-Engine**, keine Black-Box-API. Das ist die wichtigste Architekturentscheidung des ganzen Projekts.

**2. Datenqualität für Motorrad-relevante POIs**

Tankstellen sind in OSM/kommerziellen Datensätzen gut erfasst. "Motorradhotels" und "Biker-Treffs" sind es **nicht** – das ist keine Standardkategorie. Diese Daten müssen zu großen Teilen selbst kuratiert bzw. community-gepflegt werden (→ eigene POI-Tabelle statt reiner OSM-Abfrage).

**3. Echtzeitverkehr + Motorrad-Präferenzen gleichzeitig respektieren**

Verkehrs-APIs liefern Ereignisse (Stau, Sperrung), aber die *Neuberechnung* muss durch unsere eigene Routing-Schicht laufen, nicht durch die Verkehrs-API selbst – sonst geht die Kurvig-/Vermeiden-Präferenz bei der Alternativroute verloren. Das bedeutet: Verkehrsdaten sind nur ein *Input* in unser eigenes Routing, kein Ersatz dafür.

**4. Rundtouren-Generierung ("gib Distanz + Stil vor, ich baue eine Schleife")**

Das ist algorithmisch der anspruchsvollste MVP-nahe Punkt (Ähnlichkeit zu "Traveling Salesman"-artigen Constraint-Problemen: Rückkehr zum Start, Ziel-Distanz einhalten, Stil maximieren). Technisch lösbar über iterative Wegpunkt-Generierung + Scoring, aber bewusst **nicht** Teil des MVP – nur die Architektur muss es zulassen (siehe A.4).

**5. Motorrad-Fahrbedingungen im UI (Handschuhe, Sonne, Vibration)**

Kein Backend-Problem, aber ein hartes UX-Constraint: große Touch-Ziele, hoher Kontrast, minimale Interaktion während der Fahrt. Das beeinflusst Screens/Design-System (Phase 3), nicht die Architektur direkt.

**6. Kosten-Risiko bei falscher API-Wahl**

Kartendienste rechnen typischerweise pro Kartenaufruf/aktivem Nutzer ab (z. B. Mapbox: Web-Kartenaufrufe ab ca. 5 $/1.000 über dem Freikontingent, mobile Pläne ab ca. 100 $/Monat für kleine Kontingente; Stand Mitte 2026). Bei einer Navigations-App mit *aktiver* Dauernutzung (nicht nur gelegentlichen Kartenaufrufen) skaliert das schnell schlecht. Das spricht stark für einen **selbst gehosteten Karten-/Routing-Stack** statt nutzungsbasierter Fremd-APIs.

### A.3 Abhängigkeiten (Kategorien)

| Kategorie | Wird benötigt für |
|---|---|
| Kartendaten (Vektor-Tiles) | Darstellung |
| Routing-Engine | Kernfunktion (Fahrstile) |
| POI-Daten | Tankstellen, Motorradhotels etc. |
| Verkehr/Ereignisse | Echtzeit-Neuberechnung |
| Geokodierung/Suche | Zielsuche |
| Backend/Auth/DB | Benutzerkonten, gespeicherte Routen (später) |
| Push/Hintergrunddienste | Navigation im Hintergrund, Rerouting |

### A.4 Risiken, die ich früh markiere (damit sie architektonisch nicht überraschen)

- **OSM-Lizenz (ODbL):** Nutzung ist für eine kommerzielle App uneingeschränkt zulässig, aber es gibt Auflagen (Attribution Pflicht; bei Weitergabe *abgeleiteter Datenbanken* Share-Alike – reines Kartenrendering/Routing-Ergebnis ist unkritisch). Muss rechtlich sauber dokumentiert werden, ist aber kein Show-Stopper.
- **Verkehrsdaten-Lizenzverträge** (TomTom/HERE) verbieten meist das dauerhafte Speichern/Cachen roher Ereignisdaten über die erlaubte TTL hinaus – relevant für unsere Backend-Architektur (nur transientes Caching, kein Data Warehouse mit Rohdaten).
- **Kartenanbieter-Vendor-Lock-in:** Bei Wahl eines proprietären SDKs (Mapbox GL, Google Maps SDK) ist ein späterer Wechsel teuer. Empfehlung unten vermeidet das bewusst.
- **Rundtouren-Feature** ist rechenintensiv – falls naiv umgesetzt, kann es Server-Kosten treiben. Deshalb: MVP ohne dieses Feature, aber mit vorbereiteter Schnittstelle.
- **Genauigkeit der Kurven-Bewertung** ist ein Produktrisiko, kein technisches Risiko: Die erste Version des Kurven-Algorithmus wird nicht perfekt sein und braucht Nutzerfeedback/Iteration. Erwartungsmanagement gegenüber dir: Das ist ein "nie fertiges" Qualitätsmerkmal, kein einmalig lösbares Ticket.

---

## Teil B – TECH-STACK-EMPFEHLUNG

Prinzip bei jeder Entscheidung: **Kein proprietärer Lock-in, wenn eine quelloffene, selbst hostbare Alternative die Kernanforderung (Kurvig-Routing) überhaupt erst ermöglicht.**

### B.1 Mobile Framework: **Flutter**

| | Flutter | React Native |
|---|---|---|
| Eigene Render-Engine (Skia/Impeller) | Ja – wichtig für flüssige, batteriesparende Kartenoverlays bei Navigation | Nein, Bridge zu nativen Views – bei komplexen Karten-Overlays potenziell mehr Ruckeln |
| Kartenanbindung (MapLibre) | Offizielles `maplibre_gl`-Plugin, aktiv gepflegt | Ebenfalls vorhanden, aber Community-Anbindung uneinheitlicher |
| Energiesparmodus-Kontrolle | Direkterer Zugriff auf Rendering-Frequenz | Schwieriger, da über Bridge |
| Team-Verfügbarkeit (falls später Entwickler dazukommen) | Etwas kleinerer Markt als RN | Größerer JS/TS-Talentpool |

**Entscheidung: Flutter.** Ausschlaggebend: die Navigationsansicht ist eine Dauer-Animation (Kartendrehung, Positions-Updates, Restdistanz/-zeit) über Stunden bei einer Motorradfahrt – Rendering-Kontrolle und Akkueffizienz wiegen schwerer als der größere RN-Talentpool.

### B.2 Karten: **MapLibre GL (Vektor-Tiles) statt Mapbox GL / Google Maps SDK**

- MapLibre ist der quelloffene Fork von Mapbox GL JS/Native (BSD-Lizenz, kein Nutzungsentgelt für die Bibliothek selbst).
- Tile-Daten: Start mit **OpenStreetMap-basierten Vektor-Tiles**, bezogen entweder von einem günstigen Drittanbieter (z. B. MapTiler Cloud, Stadia Maps – nutzungsbasiert, aber deutlich günstiger als Mapbox/Google) oder mittelfristig **selbst gehostet** (`tileserver-gl` + eigene `.mbtiles`, ein einmaliger Build-Prozess + Server, kein Pay-per-MAU).
- Vorteil: Kein Vendor-Lock-in, volle Kontrolle über den Kartenstil (für das eigenständige "Premium/Dark"-Design aus Abschnitt 10 deiner Anforderungen zwingend nötig – bei Google Maps SDK ist Custom-Styling stark eingeschränkt).

### B.3 Routing: **GraphHopper (selbst gehostet) als primäre Engine, BRouter-Ansatz als Referenzmodell für Kurvigkeit**

- **GraphHopper** (Apache-2.0-Lizenz, Java, selbst hostbar) wird die zentrale Routing-Engine, weil sein **Custom-Model-Mechanismus** erlaubt, eigene Gewichtungsregeln pro Straßensegment zu definieren – exakt das, was für "Schnell / Kurvig / Extra kurvig / Schnell & kurvig" gebraucht wird – die Custom-Model-Konfiguration ist eine simple JSON-Definition, kein Fork des Routing-Codes nötig.
- Wir berechnen **offline** (bei der Kartendaten-Aktualisierung) einen Kurvigkeits-Score pro Straßenkante aus der OSM-Geometrie und speichern ihn als zusätzliches Edge-Attribut. Die Custom-Model-API von GraphHopper erlaubt dann z. B. `"Kurvig" = niedrige Geschwindigkeits-Priorität + hohe Kurvigkeits-Priorität`, `"Schnell" = klassische kürzeste Zeit`.
- Fahrzeugprofile (Motorrad/Auto/Fahrrad) werden als **eigene GraphHopper-Profile** mit unterschiedlichen Zugriffsregeln (z. B. Fahrrad nutzt keine Autobahn) hinterlegt – das erfüllt die Anforderung "Fahrzeugauswahl beeinflusst Routinglogik, nicht nur das Icon" strukturell korrekt.
- **Warum nicht Valhalla?** Auch quelloffen und leistungsfähig, hat aber kein so direktes Custom-Weighting-Modell für "generische" Zusatzkriterien wie Kurvigkeit – die Anpassung wäre ein Fork des C++-Codes statt einer Konfiguration. Für unser Kernfeature ist GraphHopper pragmatischer.
- **Warum nicht Mapbox Directions/HERE/TomTom Routing?** Keine dieser APIs bietet ein Kurvigkeits-Kriterium oder erlaubt eigene Gewichtungsmodelle in dieser Tiefe – sie wären für "Schnell" nutzbar, aber nicht für das eigentliche Alleinstellungsmerkmal der App.

### B.4 Backend: **Eigenes schlankes Backend (Node.js/NestJS oder Go) + Supabase als Managed-Postgres/Auth-Basis**

- **Supabase** liefert: Postgres inkl. **PostGIS** (räumliche Abfragen für POIs/Routen), Auth (E-Mail, OAuth), Storage, Realtime – reduziert MVP-Aufwand erheblich, ist selbst hostbar (kein endgültiger Lock-in) und hat einen fairen Kostenrahmen für den Start.
- **Zusätzlich ein eigener schlanker API-Layer** (Backend-for-Frontend) vor GraphHopper und den POI-/Verkehrsdiensten: Die App spricht **nie direkt** mit Drittanbieter-APIs (kein API-Key im Client, zentrale Rate-Limit-/Kostenkontrolle, zentrale Stelle für "Präferenzen bei Rerouting respektieren").
- Warum nicht Firebase? Kein PostGIS-Äquivalent für saubere Geo-Abfragen, stärkerer Google-Lock-in, schwächer bei relationalen/räumlichen Datenmodellen als Postgres+PostGIS.

### B.5 Verkehr/Ereignisse: **Anbieter noch offen – bewusste MVP-Entscheidung**

Echtzeitverkehr ist die einzige Kategorie, in der es **keine** gute Open-Source-Alternative gibt. Empfehlung: MVP startet **ohne** Live-Verkehr (POI/Rerouting-Architektur ist aber vorbereitet), Evaluierung von TomTom Traffic API oder HERE Traffic API **nach** MVP, wenn Nutzerzahlen die Kosten rechtfertigen. Das ist eine "große Auswirkung"-Entscheidung im Sinne deiner Vorgabe (Abschnitt 20) – ich schlage vor, sie **nach dem MVP** mit echten Nutzungszahlen zu treffen statt jetzt auf Verdacht Geld zu binden.

### B.6 Zusammenfassung Tech-Stack

| Bereich | Wahl | Lock-in-Risiko |
|---|---|---|
| Mobile Framework | Flutter (Dart) | niedrig |
| Karten-Rendering | MapLibre GL Native | keins (BSD) |
| Tile-Daten | MapTiler/Stadia (Start) → self-hosted tileserver-gl (später) | niedrig, austauschbar |
| Routing-Engine | GraphHopper, selbst gehostet | keins (Apache-2.0) |
| Geokodierung/Suche | Photon (OSM-basiert, gehört zum GraphHopper-Ökosystem) oder Nominatim self-hosted | keins |
| Backend/DB/Auth | Supabase (Postgres+PostGIS) | niedrig (self-hostbar) |
| Eigenes BFF-API | Node.js/NestJS (TypeScript, einheitlich mit Frontend-Tooling) | – |
| Verkehr | offen, Evaluierung nach MVP | – |

---

## Teil C – SYSTEMARCHITEKTUR

```
┌─────────────────────────────────────────────────────────────┐
│                      Flutter Mobile App                       │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────────┐ │
│  │ Presentation│ │  State    │ │  Domain    │ │  Data Layer   │ │
│  │ (Screens/  │ │ (Riverpod)│ │ (Use Cases│ │ (Repositories)│ │
│  │  Widgets)  │ │           │ │  Entities)│ │               │ │
│  └───────────┘ └───────────┘ └───────────┘ └───────┬───────┘ │
└──────────────────────────────────────────────────────┼────────┘
                                                         │ HTTPS (eigenes API)
                                                         ▼
                         ┌───────────────────────────────────────┐
                         │        MotoRoute Backend (BFF)          │
                         │  Node.js/NestJS – Auth-Gateway,         │
                         │  Rate-Limiting, Präferenz-Logik         │
                         └──┬──────────┬──────────┬──────────┬────┘
                            │          │          │          │
                 ┌──────────▼──┐ ┌────▼─────┐ ┌───▼────┐ ┌───▼─────────┐
                 │ GraphHopper │ │ Supabase │ │  POI-  │ │ Verkehrs-   │
                 │ (self-host) │ │ Postgres │ │ Service│ │ Dienst      │
                 │ Routing     │ │ +PostGIS │ │(eigene │ │ (später,    │
                 │ + Custom    │ │ Auth     │ │ Tabelle│ │ TomTom/HERE)│
                 │ Models      │ │ Storage  │ │+OSM)   │ │             │
                 └─────────────┘ └──────────┘ └────────┘ └─────────────┘
                            │
                 ┌──────────▼──────────┐
                 │  Tile-Server         │
                 │  (MapTiler → später  │
                 │  self-hosted)        │
                 └──────────────────────┘
```

**Kommunikationsprinzip:** Die App kennt **ausschließlich** die Adresse des eigenen Backends. Kein Drittanbieter-Key liegt im App-Bundle. Das erfüllt zugleich deine Vorgaben aus Abschnitt 15 (Datenschutz) und 16 (keine hartcodierten Keys) strukturell, nicht nur per Konvention.

---

## Teil D – PROJEKTSTRUKTUR

### D.1 Flutter-App (Clean-Architecture, Feature-first)

```
motoroute_app/
├── lib/
│   ├── core/
│   │   ├── constants/          (Design-Tokens, Enums: RouteStyle, VehicleType)
│   │   ├── error/               (Failure-Typen, Exception-Mapping)
│   │   ├── network/              (Dio-Client, Interceptors, kein API-Key hier)
│   │   └── theme/                (Farben, Typografie – Design-System)
│   ├── features/
│   │   ├── onboarding/
│   │   ├── map/
│   │   │   ├── presentation/     (Screens, Widgets, Riverpod-Controller)
│   │   │   ├── domain/           (Entities: MapPosition, Heading)
│   │   │   └── data/             (LocationRepository → GPS)
│   │   ├── search/
│   │   ├── routing/
│   │   │   ├── presentation/
│   │   │   ├── domain/           (Entities: Route, RoutePreference, Waypoint)
│   │   │   └── data/              (RoutingRepository → BFF-API)
│   │   ├── navigation_session/    (Turn-by-Turn, Sprachansagen, Rerouting-Logik)
│   │   ├── poi/
│   │   ├── waypoints/
│   │   ├── settings/
│   │   └── auth/                  (später)
│   └── main.dart
├── test/                          (unit + widget tests, gespiegelte Struktur)
└── pubspec.yaml
```

### D.2 Backend (NestJS, modular)

```
motoroute_api/
├── src/
│   ├── modules/
│   │   ├── routing/         (Proxy zu GraphHopper + Präferenz-Mapping)
│   │   ├── poi/              (eigene POI-Tabelle + OSM-Abgleich)
│   │   ├── search/           (Geokodierung, Proxy zu Photon/Nominatim)
│   │   ├── traffic/          (Platzhalter-Modul, sauber gekapselt für später)
│   │   ├── users/            (Supabase-Auth-Anbindung)
│   │   └── roundtrip/        (Interface + Stub, Logik folgt nach MVP)
│   ├── common/                (Guards, Interceptors, DTOs)
│   └── config/                 (Environment-Variablen-Validierung)
├── graphhopper/
│   ├── config.yml              (Profile: motorcycle_fast, motorcycle_curvy, ...)
│   └── custom_models/           (JSON Custom-Model-Definitionen pro Fahrstil)
└── .env.example                 (nie echte Keys committen)
```

---

## Teil E – DATENMODELLE (Kern-Entitäten)

```
User
 ├─ id, email, createdAt
 └─ (Standort/Verlauf werden NICHT dauerhaft serverseitig gespeichert, s. Datenschutz)

Vehicle
 ├─ type: MOTORCYCLE | CAR | BICYCLE
 └─ gehört zu User oder ist Sitzungs-Einstellung (Gäste ohne Konto möglich)

RoutePreference
 ├─ style: FAST | CURVY | EXTRA_CURVY | FAST_AND_CURVY | UNPAVED
 ├─ avoid: [HIGHWAY, FERRY, TOLL]  (Set)
 └─ vehicleType: VehicleType

Waypoint
 ├─ id, order (Position in der Route)
 ├─ lat, lng
 ├─ label (Adresse/POI-Name, optional)
 └─ sourceType: MAP_TAP | SEARCH | POI

Route
 ├─ id
 ├─ waypoints: Waypoint[]
 ├─ preference: RoutePreference
 ├─ geometry: LineString (Polyline)
 ├─ distanceMeters, durationSeconds
 ├─ segments: RouteSegment[]  (für Turn-by-Turn-Instruktionen)
 └─ createdAt

RouteSegment
 ├─ instruction, distanceMeters, durationSeconds
 └─ maneuverType

POI
 ├─ id, category: FUEL | MOTO_HOTEL | BIKER_MEETUP | CAMPSITE | ICE_CREAM | SPEED_CAMERA
 ├─ lat, lng, name
 ├─ source: OSM | COMMUNITY | CURATED
 └─ metadata (JSON, kategoriespezifisch)

RoundTripRequest   (Architektur-Platzhalter, MVP nicht implementiert)
 ├─ startPoint, targetDistanceKm, preference
 └─ generatedRoute: Route (nullable, async berechnet)
```

**PostGIS-Nutzung:** `Waypoint.geom`, `POI.geom`, `Route.geometry` werden als `geography(Point/LineString, 4326)` gespeichert – ermöglicht effiziente "POIs im Umkreis X km entlang der Route"-Abfragen, die für die Kartenanzeige zentral sind.

---

## Teil F – API-STRUKTUR (eigenes BFF, Auszug)

```
POST /v1/routes                    → Route berechnen
  Body: { waypoints[], preference: {style, avoid[], vehicleType} }
  Response: Route (inkl. Segmente)

POST /v1/routes/{id}/reroute       → Neuberechnung bei Sperrung/Stau
  Body: { currentPosition, reason }
  Response: Route (respektiert ursprüngliche preference)

GET  /v1/search?q=...&near=lat,lng → Zielsuche (Ort/Adresse/POI)

GET  /v1/pois?bbox=...&categories=FUEL,MOTO_HOTEL
                                    → POIs im Kartenausschnitt

POST /v1/roundtrips                → (Platzhalter, Phase-2-Vorbereitung)
  Body: { start, targetDistanceKm, preference }

GET  /v1/traffic?bbox=...          → (Platzhalter, Modul existiert, MVP leer)

Auth: Bearer-Token (Supabase JWT), optional für anonyme Nutzung ohne Konto
```

Alle Endpunkte laufen **ausschließlich** über das eigene Backend; GraphHopper/PostGIS/Traffic-Anbieter sind nach außen nicht erreichbar (internes Netz/VPC).

---

## Teil G – MVP-ENTWICKLUNGSPLAN (realistische Phasen)

| Sprint | Inhalt |
|---|---|
| 1–2 | Infrastruktur: GraphHopper self-hosted + OSM-Import (Testregion, z. B. Bayern), Backend-Grundgerüst, Flutter-Grundgerüst mit MapLibre |
| 3–4 | Kurvigkeits-Gewichtungsmodell entwickeln & gegen bekannte Motorradstrecken validieren (z. B. bekannte Alpenpässe müssen bei "Extra kurvig" priorisiert werden) |
| 5 | Routing-Endpunkt + Fahrstil-/Vermeiden-Parameter Ende-zu-Ende |
| 6 | Zielsuche (Photon/Nominatim-Anbindung), Kartenseite, GPS-Standort |
| 7 | Wegpunktverwaltung (Hinzufügen/Verschieben/Löschen), Routenübersicht |
| 8 | Aktive Navigation: Turn-by-Turn, Sprachansagen, Heading, Zentrieren |
| 9 | Automatische Neuberechnung bei Abweichung von der Route |
| 10 | POI-Layer (Tankstellen zuerst über OSM, Motorradhotels/Biker-Treffs als eigene kuratierte Tabelle) |
| 11 | Dark Mode + Design-System final, Energiesparmodus (Basisversion) |
| 12 | Interne Testphase, Bugfixing, Store-Vorbereitung |

Verkehr/Sperrungen bewusst **nicht** in diesem Plan enthalten (siehe B.5) – wird nach Anbieter-Entscheidung als eigener Block nachgezogen.

---

## Teil H – BENÖTIGTE API-KEYS/ZUGÄNGE

| Dienst | Wofür | Wann nötig |
|---|---|---|
| MapTiler oder Stadia Maps Account | Vektor-Tiles (Start, bevor eigenes Tile-Hosting steht) | Sprint 1 |
| Supabase-Projekt | Auth, DB, Storage | Sprint 1 |
| Apple Developer Account | iOS-Build/Store | vor MVP-Release |
| Google Play Console Account | Android-Store | vor MVP-Release |
| (Server-Hosting, z. B. Hetzner/Fly.io/Railway) | GraphHopper + Backend | Sprint 1 |
| TomTom/HERE Account | Verkehr | erst nach MVP-Entscheidung (B.5) |

Kein Mapbox-, Google-Maps- oder HERE-Maps-Key im MVP nötig – bewusste Kostenvermeidung.

---

## Teil I – GESCHÄTZTE MONATLICHE KOSTEN (MVP-Phase, kleine Nutzerzahl)

*Grobe Richtwerte, vor Vertragsschluss jeweils aktuell zu prüfen:*

| Posten | Größenordnung/Monat |
|---|---|
| Server für GraphHopper (VPS, z. B. 4–8 GB RAM für regionale OSM-Daten) | ca. 20–50 € |
| Server für Backend (klein, gleiche Instanz möglich zu Beginn) | inkl. oben oder ca. 10–20 € |
| Supabase | 0 € (Free-Tier) bis ca. 25 $ (Pro-Tier) |
| Tile-Anbieter (MapTiler/Stadia, kleines Kontingent) | 0–~50 € (nutzungsabhängig) |
| Apple Developer Program | 99 $/Jahr (≈ 8 €/Monat) |
| Google Play Console | einmalig 25 $ |
| **Summe MVP-Start** | **grob 60–150 €/Monat**, ohne Verkehr |

Bei Wahl von Mapbox/Google statt des empfohlenen Stacks lägen allein die Kartenkosten je nach aktiven Nutzern schnell im dreistelligen Bereich – Google-Maps-Einstiegspläne liegen bei ca. 100 $/Monat für vergleichsweise kleine Kontingente. Das bestätigt die Stack-Wahl aus Teil B wirtschaftlich.

Bei Einführung von Live-Verkehr (nach MVP) ist mit einem zusätzlichen, nutzungsabhängigen Posten zu rechnen, der erst nach konkreter Anbieterwahl seriös bezifferbar ist.

---

## Teil J – RECHTLICHE / LIZENZRECHTLICHE HINWEISE (keine Rechtsberatung)

- **OpenStreetMap (ODbL):** kommerzielle Nutzung erlaubt, Attributionspflicht ("© OpenStreetMap-Mitwirkende" sichtbar in App/Impressum), bei Weitergabe roher, abgeleiteter Datenbanken Share-Alike-Pflicht – für unser Rendering-/Routing-Ergebnis unkritisch, sollte aber im Impressum sauber dokumentiert werden.
- **GraphHopper (Apache-2.0):** freie kommerzielle Nutzung des selbst gehosteten Servers, keine Lizenzgebühr.
- **MapLibre (BSD-3):** frei nutzbar, kein Lock-in.
- **DSGVO:** Standortdaten sind besonders schützenswerte Daten; Empfehlung, GPS-Tracks **nicht** dauerhaft mit Personenbezug serverseitig zu speichern (nur für gespeicherte Routen, die der Nutzer aktiv sichert), Löschkonzept für Benutzerkonten von Anfang an mitdenken, App-Berechtigungen ("Standort nur während Nutzung") granular abfragen.
- **Zukünftiger Verkehrsanbieter-Vertrag:** i. d. R. Klauseln zu Cache-TTL und Weitergabeverbot – bei Anbieterwahl vertraglich prüfen, bevor Architektur darauf aufbaut.

---

## Teil K – WEITERES VORGEHEN (nach deiner Freigabe)

1. Freigabe des Tech-Stacks (Teil B) – insbesondere die Grundsatzentscheidung "eigene GraphHopper-Instanz statt Drittanbieter-Routing" ist die folgenreichste und sollte bewusst bestätigt werden.
2. Bei Freigabe: Start mit **Phase 3 (UI/UX)** – Design-System (Farben/Typografie/Komponenten) und die 11 genannten Screens als Wireframes/Spezifikation, bevor der erste MVP-Code entsteht.
3. Parallel dazu (Infrastruktur-Vorlauf): GraphHopper-Testinstanz mit einer kleinen Testregion aufsetzen, um das Kurven-Gewichtungsmodell früh gegen echte Strecken zu validieren – das ist das größte technische Risiko und sollte nicht bis zum Schluss warten.

---

*Dieses Dokument deckt Phase 1 und Phase 2 ab. Es wird noch kein vollständiger Anwendungscode geschrieben – wie in Abschnitt 17/21 deiner Vorgaben gefordert.*
