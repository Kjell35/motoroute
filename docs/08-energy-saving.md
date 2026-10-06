# MotoRoute – Energiesparmodus

> Status: Empfehlung zur Freigabe · Version 1.0 · Stand 2026-09-15
> Langtouren ohne Lademöglichkeit machen den Sparmodus zur Pflichtfunktion, nicht zum Gimmick.

## 1. Ziele

- Deutlich reduzierter Verbrauch (Ziel: −30–50 % gegenüber Normalmodus) **ohne** dass Navigation, Rerouting oder Sicherheit leiden.
- Vorbereitung auf OLED-Effizienz (dunkle Flächen = echte Ersparnis).

## 2. Maßnahmen (konkret)

| Bereich | Normal | Energiesparmodus |
|---|---|---|
| Karten-Rendering | 60 fps, alle Layer | 30 fps (throttled), POI-Symbole aus, 3D-Tilt aus |
| Kamera | smooth follow + Rotation | follow ohne Interpolation (Sprung-Snapping), kein Kompass-Rotation |
| GPS | 1 Hz, hoher Genauigkeitsmodus | 1 Hz bleibt (Guidance!), aber `LocationSettings` ohne Altitude/Bearing-Extras |
| Off-Route-Check | jede Position | jede Position (Sicherheit) |
| Re-Route-Precheck | kontinuierlich | reduziert (nur Off-Route-Trigger + Verkehr-Poll) |
| Traffic-Poll | alle 2 min | alle 5 min |
| Animationen | Design-System-Standard | global 0 ms (Tokens-Switch) |
| UI-Refresh | Stream-getrieben | Throttling auf 1 Hz für nicht-kritische UI-Teile |
| Hintergrund | normale Dienste | keine POI-Prefetches, keine Statistik-Syncs |
| Bildschirm | Standard-Helligkeit (System) | Hinweis-Pill „Sparmodus aktiv" (keine eigene Helligkeitssteuerung) |

## 3. Aktivierung

- Manuell: Toggle in Settings + Schnellzugriff im Nav-Screen (Icon, nicht fahrtkritisch-Position).
- Automatisch (Phase 2): Batterie < 20 % → Vorschlag als nicht-blockierender Banner.
- Der Modus persistiert über Sessions (Settings).

## 4. Guards (Sicherheit zuerst)

- Turn-by-Turn-Manöver, Sprachausagen, Off-Route-Neuberechnung und ETA sind **niemals** gedrosselt.
- Sparmodus verschlechtert nur Visualisierung/Hintergrund – nie Guidance-Datenqualität.
- Unit-Tests: Sparmodus-Toggle ändert ausschließlich Rendering-/Polling-Parameter (verifiziert per Provider-Tests).

## 5. Messung

- Akku-Telemetrie opt-in (Battery-Stats-Sampling 5 min, nur im Debug/Test-Build) zum Verifizieren der Zielwerte; Produkt-Builds erfassen keine Batteriedaten.
