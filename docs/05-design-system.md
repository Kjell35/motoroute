# MotoRoute – Design-System „Midnight Asphalt"

> Status: Empfehlung zur Freigabe · Version 1.0 · Stand 2026-09-15
> Ziel: eigenständige, premium-wirkende Identität – lesbar bei Sonne, bedienbar mit Handschuhen, kein Google-Maps-Klon.

## 1. Design-Prinzipien

1. **Glanceability:** fahrtkritische Info in < 1 s erfassbar (große Ziffern, max. 2 Info-Zonen gleichzeitig).
2. **Dunkel zuerst:** Dark Mode ist Primärthema; die Karte ist das hellste Element, UI-Elemente treten dahinter zurück.
3. **Große Ziele:** Touch-Targets ≥ 56×56 dp in Fahrtscreens, ≥ 44 dp überall sonst.
4. **Kontrast nach WCAG:** Text ≥ 4.5:1, fahrtkritisch ≥ 7:1 auf Karten-Overlays.
5. **Ein Akzent, keine Regenbögen:** Farbe kodiert Bedeutung (Route, Warnung, Erfolg) – nicht Dekoration.

## 2. Farb-Tokens (Dark, primär)

| Token | Wert (Hex) | Verwendung |
|---|---|---|
| `surface/base` | `#0E1116` | App-Hintergrund |
| `surface/card` | `#161B22` | Cards, Bottom Sheets |
| `surface/raised` | `#1F2630` | Elevated Controls, Chips |
| `stroke/subtle` | `#2A323D` | Trennlinien, Card-Borders |
| `text/primary` | `#F2F5F7` | Primärtext |
| `text/secondary` | `#9AA6B2` | Sekundärtext |
| `accent/primary` | `#FF6A2B` („Signal Orange") | Route, primäre Buttons, aktive Zustände |
| `accent/secondary` | `#3DD6C3` („Tour Teal") | POIs aktiv, Erfolgsstatus, Wegpunkte |
| `status/warning` | `#FFC53D` | Verkehr/Verzögerung |
| `status/danger` | `#FF3B30` | Sperrung, Off-Route, Gefahr |
| `map/routeCase` | `#12151A` (Casing) / `#FF6A2B` | Routen-Darstellung mit dunklem Rand für Kontrast |
| `map/trafficSlow` | `#FFC53D @ 60 %` | Traffic-Overlay |

Helle Variante („Daylight", sekundär): `base #F5F7FA`, `card #FFFFFF`, Akzente identisch (A11y: Orange wird auf `#E1550F` abgedunkelt).

## 3. Typografie

- Familie: **Inter** (kostenlos, exzellente Lesbarkeit, Tabular-Figures für Distanzen/Zeiten).
| Stil | Größe/Gewicht | Nutzung |
|---|---|---|
| `displayManeuver` | 44 / 700 / tabular | „800 m" in Navigation |
| `streetName` | 24 / 600 | aktuell befahrene Straße |
| `title` | 20 / 600 | Screen-Titel |
| `body` | 16 / 400 | Fließtext |
| `label` | 13 / 500 + 0.2px tracking | Chips, Meta-Infos |

## 4. Formen, Elevation, Motion

- Radien: Cards 20 dp, Buttons 16 dp, Chips 999 (pill), Sheets 28 dp top.
- Elevation: Schatten sparsam; stattdessen Flächenabhebung über `surface/raised` + 1px `stroke/subtle`.
- Motion: 150–250 ms, Kurve `easeOutCubic`; **im Navigationsmodus keine Einblende-Animationen** (nur Kamera-Bewegung).
- Energiesparmodus: Motion global auf 0 ms (siehe `08-energy-saving.md`).

## 5. Komponenten-Bibliothek (`lib/design/components/`)

| Komponente | Spezifikation (Kurzfassung) |
|---|---|
| `MrButton` | primary (orange, Text dunkel), secondary (raised), ghost; Höhen 56 dp (Standard) / 48 (kompakt); Icon-Slot links |
| `MrChip` | auswählbare Filter (Fahrstile, POIs), aktiv = Akzentfläche + dunkler Text |
| `MrCard` | surface/card, Radius 20, Padding 16, optional Leading-Icon |
| `MrSheet` | Bottom Sheet mit Griff, Snap-Punkte 25 %/50 %/90 %, Drag-Handle ≥ 48 dp |
| `MrFab` | 64 dp runde Aktion (Zentrieren, Start), Akzent oder raised |
| `MrTurnBanner` | Maneuver-Icon 40 dp + `displayManeuver`-Distanz + Straßenname; volle Breite, Höhe ≥ 96 dp |
| `MrStatusPill` | GPS-Qualität, Traffic-Lag, Offline-Modus |
| `MrDialog` | Radius 24, Aktionen als volle Breite Buttons (Handschuh-tauglich) |
| `MrStepper` | Waypoint-Reihenfolge (Drag-Handle + Pfeile als Fallback) |

Icons: eigener Satz auf Basis von Material Symbols (gepatchte Strichstärke 2.0), als Font-Asset gebündelt; Maneuver-Icons zusätzlich 3-fach (links/geradeaus/rechts-Varianten) für Turn-Banner.

## 6. Karteneditor-Richtlinien (Style-JSON)

- Basiskarte entsättigt und dunkel (`background #0E1116`, Straßen `#1F2630`), Landcover gedämpft.
- Route (Akzent-Orange, 8 dp + 12 dp dunkles Casing) ist immer das hellste/reaktionsschnellste Element.
- POI-Farben: Kategorie-abhängig aus Teal-Familie, Symbols nur ab Zoom ≥ 13 (Reduktion Visual Noise).
- Text auf Karte: Inter, Halo in `surface/base` für Lesbarkeit.

## 7. Barrierefreiheit & Bedienbarkeit

- Alle interaktiven Elemente: semantische Labels (TalkBack/VoiceOver) – auch im Fahrbetrieb relevant (bedienbar per Headset-Taste für „nochmals ansagen" später).
- Dynamische Schriftgrößen bis 130 % in nicht-fahrtaktiven Screens; Navigation-Screen fix (Glanceability).
- Kontrast-Tests als Golden-Tests gegen Tokens (CI).
