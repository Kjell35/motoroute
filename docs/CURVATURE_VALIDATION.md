# MotoRoute – Kurvigkeits-Validierung

Dieses Dokument beschreibt den Validierungsprozess für das Kurvigkeits-Modell,
das im `graphhopper-curvature-ext/`-Modul implementiert ist.

## Stand

Das Modul existiert, ist aber **noch nicht an echten OSM-Daten validiert**.
Die folgenden Schritte müssen vor dem ersten produktiven Einsatz durchgeführt werden.

## 1. Testregion importieren

Vorschlag: **Bayern/Alpenraum** – hat sowohl echte Alpenpässe als auch
Autobahnen als Kontrastfälle.

```bash
# OSM-Daten für die Testregion herunterladen
# z. B. von https://download.geofabrik.de/europe/germany/bayern.html

# GraphHopper importieren
java -jar graphhopper.jar graphhopper/config.yml
```

## 2. Referenzstrecken-Liste

Eine Referenzliste bekannter kurviger Strecken zusammenstellen:

| Strecke | Erwarteter Score-Bereich |
|---|---|
| Kesselbergstraße | hoch (obere 10–15 %) |
| Sudelfeldstraße | hoch |
| Roßfeld-Panoramastraße | hoch |
| A 95 (Autobahn) | nahe 0 |
| A 8 (Autobahn) | nahe 0 |

## 3. Score-Auslesen

GraphHopper bietet einen Debug-/Analyse-Endpunkt bzw. lässt sich der Wert
über ein kleines Testskript pro Kante abfragen.

## 4. Erwartung

Diese Referenzstrecken müssen in den oberen 10–15 % der Score-Verteilung liegen.
Falls nicht: `SCORE_CEILING` und/oder die Gewichtung von Abbiegewinkel vs.
Sinuosität in `CurvatureTagParser.computeScore()` nachjustieren.

## 5. Gegenprobe

Gegenprobe mit bekannten Autobahnabschnitten – Score muss nahe 0 sein.

## 6. Feinjustierung

Erst nach dieser Validierung: `style_curvy.json` /
`style_extra_curvy.json`-Faktoren anhand echter Testfahrten-Rückmeldung
feinjustieren, nicht anhand der Kartenansicht allein.

## 7. Reguläre Neukalibration

Bei jeder neuen OSM-Daten-Version (mindestens einmal im Jahr):
- Neue Referenzstrecken-Liste erstellen
- Score-Verteilung neu kalibrieren
- `SCORE_CEILING` anpassen, falls nötig
- Gewichtungsfaktoren in `style_*.json` neu abgleichen