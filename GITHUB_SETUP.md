# APK bauen & über GitHub teilen – Schritt für Schritt

> Lokal fehlen Flutter/Java/Docker, deshalb baut **GitHub Actions** die APK.
> Das ist kostenlos (Public-Repo) und liefert dir eine installierbare APK.

## 1. Repo auf GitHub anlegen

1. Auf <https://github.com/new> ein neues Repo erstellen, z. B. `motoroute`.
   - Sichtbarkeit: **Public** (dann läuft der Build kostenlos; bei Private würden GitHub-Actions-Minuten verbraucht – Free-Konto hat 2.000 Min./Monat, der Build braucht ~10–15).
2. Repo-Klon-URL kopieren, z. B. `https://github.com/DEIN-NAME/motoroute.git`.

## 2. Code pushen

Das lokale Repo ist bereits vorbereitet: initialisiert, `.gitignore` geprüft,
erster Commit liegt auf `main`. Im Projektordner nur noch remote setzen und pushen:

```bash
git remote add origin https://github.com/Kjell35/motoroute.git
git push -u origin main
```

## 3. APK automatisch bauen lassen

Der Workflow `.github/workflows/android-release.yml` läuft bei jedem Push auf `main`:

1. GitHub-Repo öffnen → Tab **Actions**
2. Links „Android Build & Release“ wählen
3. Neuesten Run öffnen → unten im Abschnitt **Artifacts** → `motoroute-apk` herunterladen
4. ZIP entpacken → darin liegt die **`app-release.apk`**

**Alternative (empfohlen zum Teilen):** Tag setzen, dann landet die APK automatisch als
**Release-Anhang** mit fixem Download-Link:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Danach: Repo → **Releases** → `v0.1.0` → APK direkt herunterladen.

## 4. APK auf dem Handy installieren

1. APK auf das Android-Handy übertragen (Download-Link öffnen)
2. Datei antippen → ggf. „Installation aus dieser Quelle erlauben“
3. Installieren → MotoRoute öffnen → Karte „Midnight Asphalt“ sollte erscheinen

> Hinweis: Die APK ist aktuell mit dem Debug-Key signiert (TODO M6: echtes Release-Signing).
> Sie ist installierbar, aber für den Play-Store wird später ein Keystore benötigt.

## 5. Optional: Backend lokal starten (für erste Funktionen ab M2)

Erst mit Docker installiert nötig:

```bash
docker compose -f infra/docker-compose.yml up -d
curl http://localhost:8000/health   # → {"status":"ok",...}
```

Die App im Emulator erreicht das Backend automatisch unter `10.0.2.2:8000`
(siehe `apps/mobile/lib/core/config/env.dart`).

## Troubleshooting

| Problem | Lösung |
|---|---|
| Actions-Tab zeigt roten X | Run öffnen → Log des fehlgeschlagenen Steps prüfen; häufigste Ursache: Pub-Resolve (pubspec anpassen) |
| `minSdk`-Fehler beim Build | `android/app/build.gradle` prüfen (minSdk 26 ist gesetzt) |
| Kein `Artifacts`-Abschnitt | Run muss vollständig grün sein; PR-Runs bauen bewusst keine APK |
| APK installiert nicht | „Installation aus unbekannten Quellen“ für den Browser/Dateimanager erlauben |
