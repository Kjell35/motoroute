# MotoRoute – Geräte-Checkliste vor einem Release

> Status: Arbeitsanweisung · Stand 2026-11-24 · gilt ab v1.0.14

Diese Liste prüft, was auf dem Rechner nicht prüfbar ist: Installation, Update,
TTS, Karte, QR und das Verhalten ohne Netz. Sie ersetzt keine Tests, sondern
bestätigt die gebaute APK auf echter Hardware.

## 0. Vorbereitung

- `adb` erreichbar (`adb devices` zeigt das Gerät), USB-Debugging an.
- Release-Seite des Repos offen (Assets unter `Releases`).
- App-ID: `de.motoroute.app`. Ein **Debug**-Build trägt eine eigene ID und kann
  parallel installiert bleiben – für diese Liste nur mit Release-APKs arbeiten.

## 1. Installation der arm64-APK

- [ ] `MotoRoute-vX.Y.Z-arm64-v8a.apk` (~40 MB) herunterladen und installieren
      ("Unbekannte Quellen" erlauben).
- [ ] App startet bis zur Karte, ohne Absturz im ersten Bildschirm.
- [ ] Variante bestätigen:
      `adb shell dumpsys package de.motoroute.app | grep -m1 versionCode`
      → bei v1.0.14 `2050` (arm64), Universal wäre `50`.
- [ ] Anmeldung funktioniert, App-Neustart behält die Sitzung (Secure Storage).

## 2. Einmalige Neuinstallation aus einer v1.0.13-Installation

Alle Releases bis einschließlich v1.0.13 waren mit dem Debug-Schlüssel des
jeweiligen CI-Runners signiert. Ein Update darüber ist technisch unmöglich.

- [ ] Über eine bestehende v1.0.13-Installation installieren → erwarteter Fehler
      "App nicht installiert" (Signaturen unterscheiden sich). **Das ist korrekt
      und kein Regressionsbefund.**
- [ ] Alte App deinstallieren, dann die neue installieren.
- [ ] Bewusst einplanen: Mit `android:allowBackup="false"` sind danach lokale
      Daten weg (Offline-Cache, Sitzung) – neu anmelden ist Teil des Tests.
- [ ] Ab jetzt update-fähig: siehe Punkt 3.

## 3. Update auf die nächste Version ohne Datenverlust

- [ ] **Gleiche Variante** wie installiert nehmen (arm64 → arm64). Ein Wechsel
      zur Universal-APK wäre ein Downgrade (versionCode 50 < 2050) und scheitert
      mit "App nicht installiert".
- [ ] Neue APK über die installierte legen, ohne zu deinstallieren.
- [ ] Danach prüfen: noch angemeldet, Fahrzeuge/Touren vorhanden, Chat-Verlauf da,
      Einstellungen (Theme, Telemetrie-Schalter) unverändert.
- [ ] `versionCode` ist gestiegen (bei v1.0.14 → v1.0.15 arm64: `2050` → `2051`).

## 4. TTS im Vordergrund und nach Rückkehr aus dem Hintergrund

Der Sprachkanal ist an die Activity gebunden; genau dort brechen TTS-Umsetzungen
gern.

- [ ] Navigation starten, Ansage kommt (Abbiegehinweis, nicht nur ein Piep).
- [ ] App in den Hintergrund (Home), 30–60 s warten, zurück → die **nächste**
      Ansage kommt weiterhin, ohne App-Neustart.
- [ ] Bildschirm aus während aktiver Navigation → Ansage bleibt aktiv
      (Foreground-Service).
- [ ] Ansage während eines Anrufs/Medienplayer: keine Dauerschleife, danach
      wieder normal.

## 5. Karte

- [ ] Kacheln laden nach dem Start (nicht nur grauer Hintergrund).
- [ ] Zoomen, Drehen, Verschieben flüssig; Attribution sichtbar.
- [ ] Kartenstil-Wechsel (dunkel/hell) überlebt einen App-Neustart.
- [ ] Nach Punkt 3 (Update) lädt die Karte weiterhin – MapLibre 0.28 ist neu im
      Build.

## 6. QR-Scanner

- [ ] Kamera-Berechtigung wird erfragt; Ablehnen führt zu einer verständlichen
      Meldung, nicht zu einem schwarzen Bildschirm.
- [ ] Gruppe per QR beitreten und App-zu-App-Routenübernahme scannen.
- [ ] Nach Abbruch/zurück ist die Kamera freigegeben (kein dauerhaft laufender
      Sucher, Akku-/Wärmeprüfung).

## 7. Verhalten im Funkloch

- [ ] Flugmodus an: App bleibt bedienbar, keine endlosen Spinner; Fehlermeldungen
      sind verständlich.
- [ ] Navigation mit bereits geladener Route läuft weiter, Ansagen kommen.
- [ ] Aktion im Funkloch (z. B. Chat senden) → Fehler wird sichtbar, App stürzt
      nicht ab.
- [ ] Flugmodus aus: ausstehende Berichte/Nachrichten laufen nach, ohne Duplikate.
- [ ] Erster Aufruf nach längerer Pause: Der Free-Tier-Server schläft ein; die
      App soll die Wartezeit überbrücken und danach normal antworten.

## Ergebnis festhalten

| Punkt | Gerät / Android | Ergebnis | Notiz |
|---|---|---|---|
| 1 Installation | | | |
| 2 Neuinstallation | | | |
| 3 Update | | | |
| 4 TTS | | | |
| 5 Karte | | | |
| 6 QR | | | |
| 7 Funkloch | | | |

Befunde gehören als Issue ins Repo, mit Version, Gerät, Android-Stand und
`adb logcat -s flutter`-Auszug.
