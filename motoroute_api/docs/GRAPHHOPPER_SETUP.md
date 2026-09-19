# GraphHopper-Setup & Kurvigkeits-Validierung

Dieses Dokument beschreibt den Aufbau der Routing-Engine und – wichtiger –
was vor dem ersten produktiven Einsatz noch **geprüft und nicht als
gegeben angenommen** werden darf. Ehrlich gesagt: Das hier ist der Teil
des Projekts mit dem größten "sieht auf dem Papier gut aus, muss an
echten Daten validiert werden"-Risiko.

## 1. Was bereits existiert (dieser Commit)

- `graphhopper-curvature-ext/` – eigenständiges Java-Modul mit einer
  neuen `curvature`-EncodedValue plus einem `TagParser`, der beim
  Kartenimport aus der Weg-Geometrie einen Kurvigkeits-Score (0–1) pro
  Kante berechnet (Sinuosität + gewichtete Abbiege-Häufigkeit).
- Unit-Tests für die reine Score-Berechnung (`CurvatureTagParserTest`)
  gegen synthetische Geometrien (gerade Linie, sanfte Kurve,
  Haarnadel-Cluster).
- `graphhopper/config.yml` + `custom_models/*.json` – Profile für alle
  fünf Fahrstile × Motorrad, plus Auto/Fahrrad-Basisprofile.

## 2. Was noch NICHT validiert ist (bitte nicht als fertig behandeln)

1. **GraphHopper-API-Kompatibilität.** Die Java-Klassen
   (`TagParser`, `EdgeIntAccess`, `DecimalEncodedValueImpl`) sind gegen
   die GraphHopper-9.x-Ära geschrieben. GraphHopper ändert diese
   Kern-SPI zwischen Major-Versionen regelmäßig. **Vor dem ersten Build:
   exakte Zielversion festlegen und `CurvatureTagParser`/`Curvature`
   gegen deren tatsächliche Klassensignaturen kompilieren – nicht
   ungeprüft übernehmen.**
2. **Feldnamen im Custom-Model-JSON** (`road_access`,
   `motorcycle_access`, `bike_access`, `car_access`) sind so benannt,
   wie es der GraphHopper-Dokumentation zum Zeitpunkt der Erstellung
   entsprach – die tatsächlich verfügbaren Encoded-Value-Namen müssen
   gegen die konkret importierte GraphHopper-Version + den
   Vehicle-Tag-Parser-Satz abgeglichen werden, bevor `config.yml` das
   erste Mal startet.
3. **Sinuosität-Normierungs-Konstante (`SCORE_CEILING = 3.2`).** Aktuell
   ein Schätzwert, kein gemessener. Muss mit echten OSM-Daten aus einer
   Testregion kalibriert werden (siehe Schritt 4 unten).
4. **Die Gewichtungsfaktoren in `style_curvy.json` /
   `style_extra_curvy.json`** (z. B. `multiply_by: 1.6`) sind
   Startwerte, keine validierten Produktionswerte.

## 3. Empfohlener Validierungsprozess (Sprint 3/4 laut MVP-Plan)

1. Kleine Testregion importieren (Vorschlag: Bayern/Alpenraum – hat
   sowohl echte Alpenpässe als auch Autobahnen als Kontrastfälle).
2. Eine Referenzliste bekannter kurviger Strecken zusammenstellen
   (z. B. Kesselbergstraße, Sudelfeldstraße, Roßfeld-Panoramastraße)
   und deren `curvature`-Score nach Import stichprobenartig auslesen
   (GraphHopper bietet dafür einen Debug-/Analyse-Endpunkt bzw. lässt
   sich der Wert über ein kleines Testskript pro Kante abfragen).
3. Erwartung: Diese Referenzstrecken müssen in den oberen 10–15 % der
   Score-Verteilung liegen. Falls nicht: `SCORE_CEILING` und/oder die
   Gewichtung von Abbiegewinkel vs. Sinuosität in
   `CurvatureTagParser.computeScore()` nachjustieren.
4. Gegenprobe mit bekannten Autobahnabschnitten – Score muss nahe 0
   sein.
5. Erst nach dieser Validierung: `style_curvy.json` /
   `style_extra_curvy.json`-Faktoren anhand echter Testfahrten-
   Rückmeldung feinjustieren, nicht anhand der Kartenansicht allein.

## 4. Betrieb

- `config.yml` bindet den HTTP-Port nur auf `127.0.0.1` – GraphHopper
  ist nie direkt aus dem Internet erreichbar, nur über das eigene
  Backend (siehe Systemarchitektur in Phase 1/2).
- OSM-Rohdaten (`data/region.osm.pbf`) und der generierte Graph-Cache
  werden **nicht** ins Repo committed (Größe + reproduzierbar aus der
  Quelle) – Import-Skript folgt, sobald die Zielregion für den MVP
  final feststeht.
