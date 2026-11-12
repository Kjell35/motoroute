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

> Abgeglichen mit `apps/mobile/lib/core/theme/app_colors.dart` am 2026-11-06. Die
> Konstantenspalte ist maßgeblich; die Hex-Werte sind die tatsächlich gebauten.

| Token | Konstante | Wert (Hex) | Verwendung |
|---|---|---|---|
| `surface/base` | `bgBaseDark` | `#0B0E11` | App-Hintergrund |
| `surface/card` | `bgSurfaceDark` | `#151A1F` | Cards, Bottom Sheets |
| `surface/raised` | `bgSurfaceRaisedDark` | `#1E252C` | Elevated Controls, Chips, Schalter-Track |
| `stroke/subtle` | `borderHairlineDark` | `rgba(255,255,255,0.08)` | Trennlinien, Card-Borders |
| `text/primary` | `textPrimaryDark` | `#F5F6F4` | Primärtext |
| `text/secondary` | `textSecondaryDark` | `#9AA3AD` | Sekundärtext und alle kleine Schrift (≥ 4,5:1, siehe 7.1) |
| `text/muted` | `textMutedDark` | `#5B6470` | nur dekorative Grafik – **kein Text** (2,92:1) |
| `state/idle` | `stateIdleDark` | `#68707B` | inaktive Zustandsanzeigen (≥ 3:1) |
| `accent/primary` | `accentPrimaryDark` | `#FF5A1F` („Signal Orange") | Route, primäre Buttons, aktive Zustände |
| `accent/secondary` | `accentSecondary` | `#2EC4B6` („Tour Teal") | POIs aktiv, Erfolgsstatus, Wegpunkte |
| `status/warning` | `statusWarning` | `#F5A623` | Verkehr/Verzögerung |
| `status/danger` | `statusDanger` | `#E5484D` | Sperrung, Off-Route, Gefahr |
| `status/success` | `statusSuccess` | `#46A758` | Freigabe, Bestätigung |

Helle Variante („Daylight", sekundär): `bgBaseLight` `#F5F6F4`, `bgSurfaceLight` `#FFFFFF`,
`bgSurfaceRaisedLight` `#F0F1EE`, `textPrimaryLight` `#12151A`, `textSecondaryLight` `#5B6470`.
Akzente werden für ausreichenden Kontrast abgedunkelt: `accentPrimaryLight` `#E64E17`,
`accentSecondaryLight` `#1E9A8F`, `statusWarningLight` `#C97F0E`, `statusDangerLight`
`#C7333A`, `statusSuccessLight` `#3B8A4A`. In der App ist der helle Modus noch unvollständig:
die Screens setzen `bgBaseDark` fest, das helle Schema färbt bislang nur Theme-Flächen
(Dialoge, Inputs) – siehe 7.1.

**Nicht umgesetzt (Zielvorgabe):** `map/routeCase` `#12151A` (Casing) / `#FF6A2B` (Route) und
`map/trafficSlow` `#FFC53D @ 60 %`. Es gibt dafür keine Map-Layer: Routen und Vorfälle zeichnet
die App als Annotationen in abweichenden Farben (`#FF5A1F`, `#E5484D`, `#F5A623`, siehe 6.1).

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

### 6.1 Befund: woher Routen und Verkehr kommen (2026-11-06)

Der Karten-Style enthält **keine** Routen- oder Traffic-Layer. `moto-route-dark.json` besteht
aus den Layern `background` und `carto-dark` und ist laut Kommentar in `map_style.dart` ein
Stilllegungs-Kandidat; geladen werden die CARTO-Vektorstile `carto-positron-gl-style.json`
(Standard, hell) und `carto-dark-matter.json` (dunkel), beide über `loadMapStyle()` mit
optionalem Key-Inject.

Routen, Vorfälle und POIs zeichnet die App zur Laufzeit als **Annotationen** auf den
`MapLibreMapController` (`addLine` / `addCircle` / `addSymbol`) – kein GeoJSON-Source, kein
Style-Layer, kein Casing.

| Element | Umsetzung | Werte im Code |
|---|---|---|
| Route, verbleibend | `LineOptions` | `#FF5A1F`, 6 dp, 95 % |
| Route, gefahren | `LineOptions` | `#6B7280`, 4 dp, 55 % |
| Vorfall blockierend | `CircleOptions` | `#E5484D`, r 10, Rand `#0B0E11` |
| Vorfall sonst | `CircleOptions` | `#F5A623`, r 7, Rand `#0B0E11` |
| Start / Ziel / Wegpunkt | `SymbolOptions` | `#3DD68C` / `#E5484D` / `#FF5A1F` |
| Eigene Position | `SymbolOptions` | `#3B82F6` |
| POI-Kategorien | `CircleOptions` | Tanken `#FF5A1F`, Treffs/Hotels/Camping `#2EC4B6`, Gastro `#F5A623`, Blitzer `#E5484D` |

Folgen für das Design-System:

- `map/routeCase` und `map/trafficSlow` haben **keine** Entsprechung im Code: es gibt kein
  dunkles Casing um die Route, und Verkehr erscheint als Punktwolke, nicht als
  Verzögerungs-Overlay. Beide bleiben Zielvorgabe.
- Bis 2026-11-06 standen die Farben als Hex-Literale im Code. Seitdem liefern die Tokens sie
  über die Erweiterung `Color.mapHex` (`'#RRGGBB'` via `toARGB32()`), sodass Theme-Wechsel und
  Kontrast-Audit die Kartenebene erfassen. Drei Tokens kamen dafür neu: `mapRouteTraveled`
  `#6B7280`, `mapRouteStart` `#3DD68C`, `mapUserPosition` `#3B82F6`; alle übrigen bilden auf
  bestehende ab (`accentPrimaryDark`, `statusDanger`, `statusWarning`, `accentSecondary`,
  `bgBaseDark`, `textPrimaryDark`).
- Der Test `test/core/theme/map_hex_test.dart` verhindert Rückfälle: er schlägt fehl, sobald in
  den vier Karten-Dateien wieder ein `'#RRGGBB'`-Literal auftaucht.
- Die Label-Schrift auf der Karte nutzt jetzt `textPrimaryDark` statt Reinweiß – gleiche Rolle,
  ein Token statt eines Literals.
- Bei einem Umzug auf Style-Layer wandern die Werte in die Style-JSON. Dann müssen
  `map/*`-Tokens definiert und gegen die **Basiskarte** gemessen werden (dunkles Casing auf
  dunkler Karte ist der kritische Fall, helles Positron der zweite).


### 6.2 Kartenfarben gegen die Basiskarte (Stand 2026-11-06)

Gemessen gegen die in den CARTO-Stilen gesetzten Flächen, jeweils der **ungünstigste**
Untergrund (WCAG-Formel). Positron: Hintergrund `#FAFAF8`, Straßen `#FDFDFD` / `#E6E6E6` /
`#D5D5D5`, Wasser `#D4DADC`, Gebäude `#DFDFDF`. Dark Matter: `#0E0E0E`, `#0B0B0B`, `#1C1C1C`,
`#262626`, Wasser `#2C353C`. Anforderung: 3:1 für Grafik (WCAG 1.4.11), 4,5:1 für Text.

| Element | Farbe | Positron (hell) | Dark Matter (dunkel) | Umsetzung |
|---|---|---|---|---|
| Route verbleibend | `#FF5A1F` | 2,12:1 | 4,00:1 | Linie 6 dp, kein Rand |
| Route gefahren (vor 6.3) | `#6B7280` | 3,29:1 | 2,58:1 | Linie 4 dp, kein Rand |
| Vorfall blockierend | `#E5484D` | 2,67:1 | 3,19:1 | Kreis r 10, Rand 2 dp |
| Vorfall sonst | `#F5A623` | 1,38:1 | 6,16:1 | Kreis r 7, Rand 2 dp |
| Startmarker | `#3DD68C` | 1,28:1 | 6,66:1 | Symbol, kein Rand |
| Zielmarker | `#E5484D` | 2,67:1 | 3,19:1 | Symbol, kein Rand |
| Wegpunkt | `#FF5A1F` | 2,12:1 | 4,00:1 | Symbol, kein Rand |
| Eigene Position | `#3B82F6` | 2,51:1 | 3,40:1 | Symbol, kein Rand |
| POI Tanken | `#FF5A1F` | 2,12:1 | 4,00:1 | Kreis, Rand 2 dp |
| POI Teal | `#2EC4B6` | 1,48:1 | 5,76:1 | Kreis, Rand 2 dp |
| POI Gastro | `#F5A623` | 1,38:1 | 6,16:1 | Kreis, Rand 2 dp |
| POI Blitzer | `#E5484D` | 2,67:1 | 3,19:1 | Kreis, Rand 2 dp |
| Label-Schrift | `#F5F6F4` | 17,85:1 (auf Halo) | 17,85:1 (auf Halo) | Text mit Halo 1,2 |

Unter 3:1 auf dem hellen Positron:
  - Route verbleibend: 2,12:1 auf Positron
  - Vorfall blockierend: 2,67:1 auf Positron
  - Vorfall sonst: 1,38:1 auf Positron
  - Startmarker: 1,28:1 auf Positron
  - Zielmarker: 2,67:1 auf Positron
  - Wegpunkt: 2,12:1 auf Positron
  - Eigene Position: 2,51:1 auf Positron
  - POI Tanken: 2,12:1 auf Positron
  - POI Teal: 1,48:1 auf Positron
  - POI Gastro: 1,38:1 auf Positron
  - POI Blitzer: 2,67:1 auf Positron

Folgen für das Design-System:

- Die Kreise (Vorfälle, POIs) tragen ihren eigenen Rand in `#0B0E11`; die Form bleibt dadurch
  auch auf hellem Untergrund erkennbar, selbst wenn die Füllfarbe darunter liegt. Die
  gemessenen Werte oben gelten für die Füllung allein.
- Betroffen ist fast die gesamte Kartenebene, nicht nur einzelne Marker: auf Positron liegen
  elf von zwölf Annotationen unter 3:1, darunter die Route selbst mit 2,12:1. Nur die
  gefahrene Strecke (`#6B7280`) besteht mit 3,29:1. Positron ist der **Standardstil**
  (`MapStyleChoice.light` ist der Default), die Mehrheit der Nutzer sieht also den Fall.
- Randlose Symbole (Start, Ziel, Wegpunkt, eigene Position) haben zusätzlich kein
  Rand-Äquivalent als Ausgleich und liegen zwischen 1,28 und 2,67:1.
- Die Textlabels auf Karte und Markern sitzen auf einem Halo in `#0B0E11` und sind mit
  17,85:1 unabhängig vom Untergrund lesbar.
- Die vorhandenen hellen Tokens lösen das nicht (Tabelle unten): sie heben die Route nur von
  2,12:1 auf 2,62:1. Wirksam wäre ein Rand bzw. Halo um Linien und Symbole – wie ihn die
  Kreise bereits haben – oder eine eigene, deutlich dunklere Kartenpalette für den hellen
  Stil. Beides ist nicht umgesetzt.

Was die hellen Tokens leisten würden (gegen dieselben Positron-Flächen, ungünstigster Fall):

| Rolle | Token | Wert | Kontrast |
|---|---|---|---|
| Route / aktive Markierung | `accentPrimaryLight` | `#E64E17` | 2,62:1 |
| Warnung / Sekundär-POI | `statusWarningLight` | `#C97F0E` | 2,19:1 |
| Teal / Erfolg-POI | `accentSecondaryLight` | `#1E9A8F` | 2,36:1 |
| Gefahr / Blitzer | `statusDangerLight` | `#C7333A` | 3,61:1 |

Damit käme die Route von 2,12:1 auf 2,62:1 und bliebe unter der 3:1-Schwelle; die POI-Farben
lägen bei 2,19 bis 2,36:1. Nur `statusDangerLight` erreicht mit 3,61:1 die Anforderung. Die
hellen Tokens mildern den Befund also, beheben ihn aber nicht – ein reiner Token-Wechsel
nach Kartenstil genügt nicht.

Die Annotationen nutzen heute durchgehend die Dark-Tokens, unabhängig vom Kartenstil.

### 6.3 Kartenränder und Deckkraft: Messung nach der Änderung (2026-11-06)

Routenlinien bekommen ein Casing (breitere dunkle Linie darunter), Marker einen Icon-Halo in
`#0B0E11`. Die gefahrene Strecke hat zusätzlich einen neuen Token: `mapRouteTraveled`
`#B8BBC2` statt `#6B7280`.

Wichtig für alle Werte: sie sind **gemischt** gerechnet, also mit der Deckkraft aus dem Code
(Route 0,95 · gefahren 0,55 · Vorfälle 0,85 · POIs 0.90 · Marker 1,0) über dem jeweiligen
Untergrund – nicht als reiner Token-Wert. Die frühere Messung in 6.2 hatte das für die gefahrene
Strecke nicht getan: sie nannte 2,58:1, gerendert waren es 1,71:1.

| Rolle | Körper | Opazität | Körper ↔ Rand | Körper ↔ Karte Dark (ungünstigste Fläche) |
|---|---|---|---|---|
| Route verbleibend | `#FF5A1F` | 0,95 | 5,68:1 | 3,72:1 |
| Route gefahren | `#B8BBC2` | 0,55 | 3,73:1 | 3,09:1 |
| Vorfall blockierend / Zielmarker | `#E5484D` | 0,85 | 3,82:1 | 2,64:1 |
| Vorfall sonst | `#F5A623` | 0,85 | 7,09:1 | 4,89:1 |
| POI Tanken | `#FF5A1F` | 0,90 | 5,18:1 | 3,48:1 |
| POI Teal | `#2EC4B6` | 0,90 | 7,39:1 | 4,99:1 |
| POI Gastro | `#F5A623` | 0,90 | 7,88:1 | 5,30:1 |
| Startmarker / eigene Position | `#3DD68C` | 1,00 | 10,32:1 | 6,66:1 |

Rand `#0B0E11` gegen die Karte: 13,19:1 auf Positron (Fußweg, bis 19,03:1
auf Straßenweiß); auf Dark Matter 1,02 bis 1,55:1, dort also
unsichtbar.

Was das löst:

- **Positron**: der Rand trägt die Trennung, und jedes Element liegt gegen seinen Rand über
  3:1 – die Route bei 5,68:1, die gefahrene Strecke bei 3,73:1.
- **Dark Matter**: der Rand verschwindet, deshalb trägt dort der Körper. Die gefahrene Strecke
  liegt jetzt gemischt bei 3,09:1 gegen Wasser (vorher 1,71:1) und bei
  3,42 bis 3,74:1 gegen die übrigen dunklen Flächen.
- Die gefahrene Strecke ist damit heller als zuvor und liegt nahe `textSecondaryDark`. Sie
  bleibt durch 4 statt 6 dp Breite und die Deckkraft unterscheidbar. Gegen die orange
  Reststrecke misst die Kante 1,52:1 – die beiden Segmente grenzen direkt aneinander,
  unterscheidbar sind sie also über Helligkeit und Breite, nicht über einen Kontrast über 3:1.
  Wird das zum Problem, hilft nur ein anderer Farbton (z. B. Blaugrau) statt eines Grautons.

Grenze dieser Messung: gerechnet gegen die im Style gesetzten Flächen, nicht gegen gerenderte
Pixel. Kacheln mischen Farben, Straßen liegen über Landschaft, und MapLibre blendet je nach
Zoom unterschiedliche Layer ein.

## 7. Barrierefreiheit & Bedienbarkeit

- Alle interaktiven Elemente: semantische Labels (TalkBack/VoiceOver) – auch im Fahrbetrieb relevant (bedienbar per Headset-Taste für „nochmals ansagen" später).
- Dynamische Schriftgrößen bis 130 % in nicht-fahrtaktiven Screens; Navigation-Screen fix (Glanceability).
- Kontrast-Tests als Golden-Tests gegen Tokens (CI).

### 7.1 Kontrast-Audit (Stand 2026-11-06)

Gemessen gegen die implementierten Tokens aus `apps/mobile/lib/core/theme/app_colors.dart`
(WCAG-Formel, jeweils auf `bgBaseDark` / `bgSurfaceDark` / `bgSurfaceRaisedDark`):

| Rolle | Token | Wert | Kontrast |
|---|---|---|---|
| Fließtext, klein (10–13 px) | `textSecondaryDark` | `#9AA3AD` | 7,57 / 6,85 / 6,06:1 |
| Fließtext, primär | `textPrimaryDark` | `#F5F6F4` | 17,85 / 16,15 / 14,28:1 |
| Zustandsanzeige inaktiv | `stateIdleDark` | `#68707B` | 3,86 / 3,50 / 3,09:1 |
| rein dekorativ | `textMutedDark` | `#5B6470` | 3,23 / 2,92 / 2,58:1 |

Regeln, die daraus folgen:

- `textMutedDark` **nie für Text** verwenden: 2,92:1 auf Kartenfläche liegt unter den 4,5:1
  aus Abschnitt 1. Zulässig ist der Token nur für rein dekorative Grafik ohne Bedeutung
  (Trennlinien, Track-Flächen) und für Zustände, die anderweitig erkennbar sind.
- Zustandsanzeigen (Icons, Indikator-Punkte, Drag-Griffe, inaktive Schalter-Thumbs) nutzen
  `stateIdleDark` und werden gegen **ihren Track** geprüft, nicht gegen die Karte: der Thumb
  steht auf `bgSurfaceRaisedDark`, dort sind es 3,09:1.
- Neue Farben gegen alle drei dunklen Flächen rechnen, nicht nur gegen die Basis –
  `surface/raised` ist immer der ungünstigste Fall.
- Der helle Modus ist offen: die Screens setzen `bgBaseDark` fest, `AppTheme.light` färbt nur
  Theme-Flächen (Dialoge, Inputs). Die Werte oben gelten für den dunklen Pfad.

Hinweis: die Tokentabelle in Abschnitt 2 wurde am 2026-11-06 an diese Werte angeglichen.
Maßgeblich bleibt `app_colors.dart` – bei Abweichungen gilt der Code, nicht das Dokument.
