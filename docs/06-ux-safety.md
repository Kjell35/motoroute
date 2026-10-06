# MotoRoute – UI/UX-Konzept & Fahrsicherheit

> Status: Empfehlung zur Freigabe · Version 1.0 · Stand 2026-09-15
> Gilt für: alle Screens des MVP (Phase 3 liefert die konkreten Wireframes auf Basis dieser Regeln).

## 1. Navigationsstruktur der App

- **5 Tabs (Bottom Navigation):** Karte (Home) · Suchen · Touren (später) · Favoriten (später) · Einstellungen. MVP liefert Karte, Suchen, Einstellungen voll; Tabs 3/4 als klarer „Coming in Phase 2"-Platzhalter mit Erklärtext (kein toter Klick).
- Routen-Workflow ist ein **eigenes Stack-Modul** über den Tabs: Suchen/Tipp → Ziel → Routen-Preview → Navigation → Angekommen.
- Zurück-Verhalten: Navigation beenden erfordert Bestätigungsdialog (Fehlbedienung mit Handschuhen).

## 2. Screen-Verträge (MVP, konsistent mit Briefing-Kapitel 11)

| # | Screen | Kerninhalt | Fahrtaktiver Modus? |
|---|---|---|---|
| 1 | Splash | Logo, Ladezustand (Karte/Style-Init) | nein |
| 2 | Onboarding | 3 Slides: Fahrstil-Philosophie · Standort-Berechtigung (Warum-Text vor OS-Dialog) · Fahrzeugwahl | nein |
| 3 | Startseite | Letzte Ziele, „Wohin?"-Suche, Fahrzeug- & Fahrstil-Chips | nein |
| 4 | Karte | Vollflächige Karte, POI-Toggle-Chip-Reihe, FABs (Zentrieren/Layers), Suchleiste | ja (reduziert) |
| 5 | Zielsuche | Suchfeld + Ergebnisse (Ort/Adresse/POI), Verlauf (lokal), „Auf Karte wählen" | nein |
| 6 | Routenauswahl | 1–3 Kandidaten als Cards: Zeit/Distanz/**CurveScore-Badge**/Anteile (Landstraße/Autobahn/Unbefestigt) | nein |
| 7 | Routenübersicht | Route komplett auf Karte, Waypoint-Liste (drag & drop), „Navigation starten" | nein |
| 8 | Aktive Navigation | Turn-Banner (oben), Restzeit/ETA/Restdistanz (unten, eine Zeile), sonst nichts | **ja** |
| 9 | Waypunktverwaltung | Liste, Reihenfolge, Hinzufügen (Suche/Karte/POI), Löschen | nein |
| 10 | POI-Auswahl | Kategorie-Toggles mit Zählern im Viewport | nein |
| 11 | Einstellungen | Fahrzeug, Standard-Fahrstil, Vermeidungen, Sprache/TTS, Energiesparmodus, Kartenquellen-Info, Datenschutz | nein |

## 3. Aktive Navigation – Layout-Vertrag (streng)

```
┌──────────────────────────────────────┐
│  MrTurnBanner                        │  ← Maneuver + Distanz + Straße
│        (Höhe 96–120 dp)              │
│                                      │
│           KARTE (follow mode)        │
│                                      │
│  [FAB Zentrieren]        [FAB Stumm] │  ← 64 dp, nur 2 Aktionen
├──────────────────────────────────────┤
│  12 min · 8,4 km · Ankunft 14:32     │  ← EINE Zeile, ≥ 24 dp Text
└──────────────────────────────────────┘
```

- **Keine** POIs, keine Chips, keine Stats während der Fahrt. Alles andere ist im Preview-Screen.
- Off-Route: Statuszeile wechselt auf `status/danger` „Route neu berechnen…" – kein Dialog (Ablenkung).
- Ankommen: Vollflächen-„Angekommen"-State (Ziel + „Parken/Route beenden") statt sofortigem Zurückfallen in die Karte.

## 4. Bedienbarkeit unter Motorradbedingungen

- Alle Fahrtscreen-Aktionen unten rechts (Daumenzone beim Lenker), Mindestabstand 8 dp zwischen Zielen.
- Buttons mit Haptik-Feedback (leichte Vibration bei Bestätigung) – Bestätigung auch ohne Blick.
- Sprachausagen-Knopf „Ansage wiederholen" als Headset-Taste-Event (Bluetooth-Headset-Multifunktionstaste, Phase 2) – MVP: FAB.
- Sonnentauglichkeit: max. Kontrast im Turn-Banner, keine halbtransparenten Flächen über Text.

## 5. Onboarding & Berechtigungen (DSGVO-freundlich)

1. Slide „Fahrspaß-Philosophie" (Werte-Vermittlung: kurvig ≠ schneller).
2. Pre-Prompt: Warum Standort? → erst OS-Dialog danach (bessere Accept-Rate + DSGVO-Informationspflicht).
3. Fahrzeugwahl (beeinflusst Routing sofort – sichtbarer Nutzen).
Überspringen möglich; Berechtigungen werden lazy beim ersten Bedarf angefordert.

## 6. Fehler- & Ladezustände (einheitlich)

- Skeleton-Spinner statt Spinners auf Karte; Routenberechnung zeigt Progress + Abbrechen.
- Fehler als Inline-Banner im Sheet (nie als Modal während fahrtaktiver Screens).
- GPS-Signal schwach: `MrStatusPill` „GPS schwach – Position ungenau", Navigation läuft mit letztem Fix weiter, Reroute-Trigger pausiert.
