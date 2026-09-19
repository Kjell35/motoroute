# MotoRoute – Phase 3: UI/UX-Design-System & Screen-Spezifikation

*Stand: 15. September 2026 – Fortsetzung nach Freigabe von Phase 1/2*

---

## Teil A – DESIGN-PHILOSOPHIE

Leitidee: **"Cockpit, kein Stadtplan."** Die App soll sich anfühlen wie ein hochwertiges Motorrad-Instrument – reduziert, kontraststark, mit klarer Informationshierarchie – nicht wie eine eingefärbte Google-Maps-Kopie. Referenzpunkte aus der Motorrad-Welt statt aus der Consumer-Map-Welt: Tacho-Displays, TFT-Cockpits moderner Motorräder, Renn-Timing-Screens. Zwei Zustände dominieren das Produkt und werden bewusst unterschiedlich gestaltet:

- **Planungsmodus** (Suche, Routenauswahl, Einstellungen): ruhiger, informationsreicher, normale Bedienung mit Fingern.
- **Fahrmodus** (aktive Navigation): reduziert auf das Nötigste, extreme Lesbarkeit aus 50–80 cm Entfernung, Handschuh-taugliche Ziele, kaum Interaktion nötig.

---

## Teil B – DESIGN-SYSTEM

### B.1 Farben

Basis ist **Dark-first** (nicht nur Dark Mode als Option, sondern Standard-Erlebnis – passend zu "möglichst wenig Ablenkung" und Sonneneinstrahlung auf dem Display). Ein Light Mode wird als zweites Farbschema mitgeliefert, aber die visuelle Identität wird am Dark-Schema entwickelt.

| Token | Hex (Dark) | Hex (Light) | Verwendung |
|---|---|---|---|
| `bg/base` | `#0B0E11` | `#F5F6F4` | App-Hintergrund |
| `bg/surface` | `#151A1F` | `#FFFFFF` | Karten, Bottom Sheets |
| `bg/surface-raised` | `#1E252C` | `#F0F1EE` | Erhöhte Elemente (Cards über Cards) |
| `accent/primary` | `#FF5A1F` | `#E64E17` | Primärfarbe: aktive Route, primäre Buttons, Fahrstil-Auswahl |
| `accent/secondary` | `#2EC4B6` | `#1E9A8F` | Sekundär: POI-Hervorhebungen, Erfolgsstatus |
| `text/primary` | `#F5F6F4` | `#12151A` | Haupttext |
| `text/secondary` | `#9AA3AD` | `#5B6470` | Sekundärtext, Beschriftungen |
| `text/muted` | `#5B6470` | `#9AA3AD` | Deaktiviert, Platzhalter |
| `status/warning` | `#F5A623` | `#C97F0E` | Sperrungen, Stau |
| `status/danger` | `#E5484D` | `#C7333A` | Kritische Warnung, Blitzer |
| `status/success` | `#2EC4B6` | `#1E9A8F` | Ziel erreicht, Route bestätigt |
| `border/hairline` | `rgba(255,255,255,0.08)` | `rgba(0,0,0,0.08)` | Trennlinien |

**Begründung der Leitfarbe:** Ein warmes Orange/Rot (`#FF5A1F`) statt des naheliegenden "Verkehrsgrün" oder "Google-Blau" – es zitiert Rückleuchten/Blinker/Warnwesten-Ästhetik der Motorradwelt, hat hohen Kontrast auf dunklem Grund und ist bei Sonneneinstrahlung gut erkennbar. Kein Verwechslungsrisiko mit Status-Grün/Rot, da bewusst als reine Markenfarbe (nicht als Status) eingesetzt.

### B.2 Typografie

- **Schriftart:** Eine geometrische, hochkontrastreiche Sans-Serif mit klar unterscheidbaren Ziffern (z. B. *Inter* oder *Space Grotesk* als Startpunkt – finale Wahl in Phase 4 mit echten Schriftmustern auf dem Gerät prüfen, insbesondere Ziffern-Lesbarkeit bei Vibration/Bewegung).
- **Ziffern in der Navigationsansicht** (Geschwindigkeit, Restdistanz, ETA) nutzen **tabellarische Ziffern** (feste Breite), damit sich Werte beim Update nicht seitlich verschieben – sicherheitsrelevant, kein Stilmittel.

| Rolle | Größe / Gewicht | Verwendung |
|---|---|---|
| `display` | 48px / 600 | Restdistanz/ETA in aktiver Navigation |
| `title` | 24px / 600 | Screen-Titel, Routen-Zusammenfassung |
| `body` | 16px / 400 | Standardtext |
| `body-strong` | 16px / 600 | Hervorgehobene Werte in Listen |
| `caption` | 13px / 400 | Sekundärinfos, Zeitstempel |
| `nav-instruction` | 28px / 600 | Nächste Abbiege-Anweisung während Fahrt |

### B.3 Abstände & Layout

8-px-Grid: `4, 8, 12, 16, 24, 32, 48` als einzige erlaubte Abstandswerte. Mindest-Touch-Ziel **48×48 dp** im Planungsmodus, **64×64 dp** für alle interaktiven Elemente im Fahrmodus (Handschuh-Toleranz).

### B.4 Buttons

- **Primär:** gefüllt, `accent/primary`, `text/primary` (auf Orange: dunkler Text `#12151A` für Kontrast), Radius 12px.
- **Sekundär:** Outline, 1px `border/hairline`, transparenter Hintergrund.
- **Icon-Only (Fahrmodus):** kreisförmig, min. 64dp, `bg/surface-raised` mit 70% Opazität über der Karte, damit die Karte durchscheint, aber der Button klar erkennbar bleibt.

### B.5 Icons

Reduzierter, eigener Icon-Satz (Outline-Stil, 2px Strichstärke, konsistent zur Typografie-Geometrie) statt generischer Symbolbibliothek für alle fahrstil- und fahrzeugbezogenen Icons (Kurvig-Symbol, Motorrad/Auto/Fahrrad, Unbefestigt-Symbol) – das ist Teil der eigenständigen visuellen Identität. Für Standard-UI-Icons (Zurück, Schließen, Einstellungen) reicht eine neutrale Outline-Icon-Bibliothek.

### B.6 Kartenstil

Eigener MapLibre-Stylesheet (kein Standard-OSM-Bright-Stil):

- Straßen nach Kategorie eingefärbt mit gedämpften, nicht bunten Tönen im Dark Mode (Autobahnen dezent hervorgehoben, kleine Straßen zurückhaltend) – die **aktive Route** ist die einzige kräftig farbige Linie auf der Karte (`accent/primary`, 6dp Breite, leicht erhöhter Schatten für Tiefenwirkung).
- Kurvige Streckenabschnitte können optional mit einer dünnen Sekundärlinie in `accent/secondary` vorab visuell markiert werden ("Kurven-Heatmap"-Idee für später, MVP: nur die gewählte Route farbig).
- Gebäude/Landnutzung sehr zurückhaltend, fast monochrom – die Route und POIs sollen die einzigen "lauten" Elemente sein.

### B.7 Cards

`bg/surface`, Radius 16px, kein harter Schatten (stattdessen dezenter 1px `border/hairline` + minimaler Weichzeichner-Schatten `rgba(0,0,0,0.3)` im Dark Mode), Innenabstand 16px.

### B.8 Bottom Sheets

Zentrales Bedienmuster für Zielsuche, Routenauswahl, Wegpunkt-Verwaltung – bleibt die Karte im Hintergrund sichtbar (räumlicher Kontext bleibt erhalten, statt Vollbild-Screens zu wechseln). Drei Rastpositionen: eingeklappt (Griffleiste + 1 Zeile), halb (ca. 45% Bildschirmhöhe), voll (ca. 90%).

### B.9 Navigation (App-weite Struktur)

Keine klassische Tab-Bar unten (kostet wertvollen Bildschirmplatz auf der Kartenansicht). Stattdessen: Karte ist die "Home Base", Suche/Einstellungen/Profil über kompakte Icon-Buttons oben, Bottom Sheets für alle Such-/Auswahl-Workflows.

### B.10 Dialoge

Nur für unterbrechende, sicherheitsrelevante Meldungen während der Fahrt (z. B. "Route neu berechnet wegen Sperrung") – kurze, automatisch verschwindende Toast-Banner oben, **niemals** modale Dialoge mit Bestätigungszwang während aktiver Navigation (Ablenkungsvermeidung, Abschnitt 11 deiner Vorgaben).

### B.11 Statusanzeigen

- Persistentes, kleines Status-Icon während Rerouting ("Route wird angepasst…", dezente Pulsanimation in `accent/secondary`).
- Verkehr/Sperrung-Marker auf der Karte: `status/warning`-Punkt mit kurzer Beschriftung, kein aufdringliches Popup ungefragt.

---

## Teil C – SCREEN-SPEZIFIKATIONEN

### 1. Splash

- Vollflächig `bg/base`, zentriertes Wortmarke-Logo, keine Ladebalken-Animation (nur kurzer Fade-in), App-typische Farbe als minimaler Akzent (z. B. Logo-Strich in `accent/primary`).
- Zweck: reine Markenmoment-Anzeige während App-Init/Session-Check, < 1 Sekunde Zielwert.

### 2. Onboarding

- 3 knappe Screens (kein langes Slideshow-Tutorial): (1) Kernversprechen "Fahrspaß statt nur Ankommen" mit visueller Andeutung der Fahrstil-Optionen, (2) Standort-Berechtigung mit klarer Erklärung *warum* ("nur während Nutzung"), (3) Fahrzeugtyp-Auswahl als erste echte Interaktion (Motorrad vorausgewählt, da Kernzielgruppe).
- Überspringen-Option immer sichtbar oben rechts.

### 3. Startseite (= Kartenseite im "Ruhezustand")

- Karte füllt den gesamten Screen (Startseite und Kartenseite sind **derselbe Screen**, kein separater Homescreen mit Kacheln – das würde vom Kernprodukt "Karte" ablenken).
- Oben: kompakte Suchleiste (tippen öffnet Zielsuche-Bottom-Sheet), Profil-/Einstellungs-Icon rechts.
- Unten: eingeklappter Bottom Sheet mit "Schnellzugriff" (letzte Ziele, gespeicherte Routen – Platzhalter im MVP, falls Konto vorhanden).
- Schwebender Zentrieren-Button unten rechts über der Karte, erscheint erst, wenn Nutzer die Karte manuell verschoben hat.
- Fahrzeugtyp-Umschalter als kompaktes Segment-Control oben (Motorrad/Auto/Fahrrad-Icon), immer sichtbar.

### 4. Kartenseite (Detailzustand mit aktivem Ergebnis)

- Gleicher Screen wie 3, aber mit sichtbaren POI-Icons (je nach aktivierten Kategorien) und ggf. bereits gesetztem Ziel-Pin.
- POI-Filter-Zugriff: kompaktes Icon-Button-Cluster, das ein Auswahl-Bottom-Sheet öffnet (siehe Screen 10).

### 5. Zielsuche

- Bottom Sheet startet halb offen, springt bei Texteingabe auf voll.
- Suchfeld oben, darunter Ergebnisliste mit Kategorien gemischt (Adressen, POIs), pro Zeile: Icon nach Typ, Name, Sekundärzeile (Adresse/Distanz), rechts Distanzangabe.
- Leerer Zustand vor Eingabe: "Zuletzt gesucht" + "In der Nähe" (Tankstellen/Eisdielen als kontextuelle Vorschläge, sofern GPS aktiv).

### 6. Routenauswahl

- Nach Zielwahl: Bottom Sheet zeigt **Fahrstil-Auswahl als große, gleichwertige Kacheln** (nicht als Dropdown versteckt – das ist das Kernfeature und muss visuell so gewichtet sein): Schnell / Kurvig / Extra kurvig / Schnell & kurvig / Unbefestigt, je mit eigenem Icon + kurzer Distanz/Zeit-Vorschau pro Option, wenn technisch vorab berechenbar (sonst on-tap berechnet).
- Darunter: "Vermeiden"-Chips (Autobahn/Fähre/Maut) als Toggle-Pills, kompakt, nicht dominant.
- Karte im Hintergrund zeigt bei Auswahl einer Kachel eine Live-Vorschau der Routen-Geometrie.

### 7. Routenübersicht

- Voller Bottom Sheet nach Bestätigung: Gesamtdistanz, Gesamtzeit, ETA groß oben (`title`-Typo), darunter kompakte Segmentliste (grobe Wegabschnitte, keine Turn-by-Turn-Detailtiefe hier).
- Wegpunkt-Leiste horizontal scrollbar (Start → Wegpunkte → Ziel) mit Möglichkeit, direkt in die Wegpunktverwaltung (Screen 9) zu wechseln.
- Prominenter "Start"-Button unten, fixiert (immer erreichbar auch nach Scrollen der Segmentliste).

### 8. Aktive Navigation

*Der sicherheitskritischste Screen – eigene Gestaltungsregeln, losgelöst vom sonstigen UI-Dichtegrad.*

- Obere Zone (ca. 30% Höhe): große Abbiege-Anweisung (`nav-instruction`-Typo) mit richtungsweisendem Pfeil-Icon, Distanz bis zur nächsten Abzweigung darunter in `display`-Größe.
- Mittelzone: Karte, perspektivisch leicht geneigt (3D-Tilt), aktuelle Position + Heading zentriert, automatische Nordausrichtung nach Fahrtrichtung (nicht Nord-oben).
- Untere Zone (kompakter Streifen): aktuelle Geschwindigkeit, Restdistanz, ETA – drei Werte, klar getrennt, keine weiteren Elemente.
- Einziger jederzeit sichtbarer Bedien-Button: Zentrieren/Beenden-Kombination als zwei große Icon-Buttons unten am Rand (linke/rechte Ecke, Daumen-erreichbar auch bei Halterung am Lenker).
- Rerouting-Hinweis erscheint als schmaler Banner direkt unter der oberen Zone, verschwindet automatisch nach Bestätigung der neuen Route (kein Tap nötig).

### 9. Wegpunktverwaltung

- Vollflächiger Bottom Sheet (nicht eigener Screen, um Kartenkontext zu behalten): Liste der Wegpunkte inkl. Start/Ziel, Drag-Handle links pro Zeile für Reihenfolge, Löschen-Icon rechts (Swipe-to-delete als Alternative).
- "+ Wegpunkt hinzufügen" öffnet dieselbe Such-Komponente wie Screen 5, zusätzlich Option "Auf Karte antippen" als expliziter Modus-Umschalter.

### 10. POI-Auswahl

- Kompakter Bottom Sheet (nicht voll): Kategorie-Kacheln mit Icon + Toggle-Zustand (aktiv = `accent/secondary`-Rahmen), ein Tap schaltet die Sichtbarkeit auf der Karte sofort um (kein "Anwenden"-Button nötig – sofortiges Feedback).
- Kategorien: Tankstellen, Motorradhotels, Biker-Treffs, Campingplätze, Eisdielen, Blitzer/Verkehrswarnungen.

### 11. Einstellungen

- Klassische, ruhige Listen-Struktur (hier darf die App "normal" aussehen, kein Ablenkungsrisiko da nicht während der Fahrt genutzt): Konto, Fahrzeugstandard, Karten-Erscheinungsbild (Dark/Light/Auto), Energiesparmodus-Toggle mit Kurzerklärung, Einheiten (km/mi), Sprachansagen-Lautstärke/Stimme, Datenschutz/Datenlöschung-Zugang, App-Version.

---

## Teil D – WAS NOCH FEHLT (bewusst offen für Phase 4)

- Konkrete Bildmarke/Logo-Gestaltung (Wortmarke reicht für MVP-Start, eigenständiges Icon-Logo kann parallel zur Implementierung entstehen).
- Animationskonzept für Übergänge (Bottom-Sheet-Physik, Kartenzoom bei Routenwahl) – wird beim Bau der Screens in Flutter iterativ festgelegt, da stark von tatsächlicher Performance auf Zielgeräten abhängt.
- Feinschliff Energiesparmodus-UI (welche Elemente genau reduziert werden) – folgt der technischen Umsetzung in Sprint 11 des MVP-Plans.

---

*Damit ist Phase 3 abgeschlossen. Nächster Schritt nach deiner Freigabe: Beginn von Phase 4 (MVP-Implementierung), startend mit der in Teil K von Phase 1/2 genannten Infrastruktur (GraphHopper-Testinstanz + Kurven-Gewichtungsmodell) parallel zum Grundgerüst der Flutter-App gemäß Projektstruktur aus Teil D.*
