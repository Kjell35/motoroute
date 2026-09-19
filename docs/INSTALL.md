# MotoRoute auf dem eigenen Android-Smartphone — ohne Google Play Store

Diese Anleitung beschreibt den kompletten Weg **Code → GitHub → APK → Handy**.
Kein Play-Store-Entwicklerkonto, keine Gebühren — die APK wird direkt
(sideloading) installiert. Später ist der Weg in den Play Store aber offen
(siehe ganz unten).

---

## 1. Der Workflow auf einen Blick

```text
Code ändern (Claude/Cursor/lokal)
    ↓
git push (GitHub)
    ↓
GitHub Actions baut automatisch
    ├─ jeder Push auf main / jedes PR  → Tests + Debug-APK als Artefakt
    └─ Tag v0.1.0 pushen               → signierte Release-APK + GitHub Release
    ↓
APK auf dem Handy herunterladen (GitHub-Website oder Mobile-App)
    ↓
APK öffnen → Installation erlauben → installieren
    ↓
MotoRoute starten
```

Zwei Build-Varianten:

| | Debug (`android-build.yml`) | Release (`android-release.yml`) |
|---|---|---|
| Auslöser | Push auf `main`, Pull Request | Tag `v*` |
| Zweck | Schneller Funktionstest | Tägliche Nutzung auf dem Handy |
| Optimierung | nein (schnelle Builds) | ja (R8 + Ressourcen-Shrink) |
| App-ID | `de.motoroute.app.debug` | `de.motoroute.app` |
| Signatur | Android-Debug-Key | eigener Keystore (Fallback: Debug-Key) |
| Verfügbar als | Workflow-Artefakt (30 Tage) | GitHub Release (dauerhaft) + Artefakt (90 Tage) |

Die Debug-App (`.debug`-Suffix) kann **parallel** zur Release-App installiert
sein — sie stört sich gegenseitig nicht und teils keine Daten.

---

## 2. APK herunterladen und installieren (Schritt für Schritt)

1. **GitHub öffnen** — im Browser auf dem Handy: `github.com/<dein-name>/<repo>`
   (oder GitHub-Android-App).
2. **Neueste Version auswählen**: auf der Repo-Startseite rechts unten im
   Bereich *Releases* auf den neuesten Eintrag klicken (z. B. *MotoRoute 0.1.0*),
   oder direkt `…/<repo>/releases` aufrufen.
3. **APK herunterladen**: unter *Assets* auf
   `MotoRoute-v0.1.0.apk` tippen — Chrome lädt sie in den Ordner
   *Downloads*.
4. **APK öffnen**: Hinweis „Datei könnte schädlich sein“ →
   *Trotzdem herunterladen/öffnen* (Standard-Warnung für alle APKs außerhalb
   des Play Store; die Datei kommt aus deinem eigenen Repository).
5. **Installation aus dieser Quelle erlauben** (nur beim ersten Mal):
   Android fragt: *„Aus dieser Quelle installieren nicht zulassen“* →
   *Einstellungen* → Schalter **„Aus dieser Quelle zulassen“** aktivieren →
   zurück. Das pro App und pro Quelle (z. B. Chrome oder GitHub-App);
   Chrome brauchen wir also einmalig freigeben.
   *Ältere Anleitungen nennen „Unbekannte Quellen“ global — das gibt es so
   seit Android 8 nicht mehr; modern ist die pro-App-Berechtigung.*
6. **Installieren** tippen → ggf. Google-Play-Schutz-Scan bestätigen
   („Trotzdem installieren“).
7. **MotoRoute starten.** Fertig.

Hinweise:

- **Google Play Protect** (Hinweis „Unbekannter Entwickler“) erscheint bei
  jeder selbst gebauten APK — das ist normal und keine Störung. Die Signatur
  deines eigenen Keystores ist dem Play Protect naturgemäß unbekannt.
- Die **Release-APK braucht keinen GPS-Test im Hintergrund** — Standort wird
  nur während der Navigation abgefragt.

---

## 3. Debug-APK aus einem CI-Run laden (für schnelle Tests)

1. Repo auf GitHub öffnen → Reiter **Actions**.
2. Neuesten grünen Run von **android-build** anklicken.
3. Ganz unten im Abschnitt **Artifacts** auf `motoRoute-debug-apk` klicken
   (ZIP; die APK liegt darin).
4. Wie in Abschnitt 2 installieren.

Wichtig: Die Debug-APK hat eine **andere App-ID** (`de.motoroute.app.debug`)
und installiert sich parallel zur Release-App. Sie eignet sich zum Ausprobieren
neuer Features, NICHT als Update einer bestehenden Release-Installation.

---

## 4. Eigene Version bauen (Release)

```bash
# 1. Version in motoroute_app/pubspec.yaml erhöhen:
#    version: 0.1.1+2        <- Name+1, Code+1 (beides gemeinsam!)
#    (Versionsname für Menschen, VersionCode für Android-Update-Logik)

# 2. Committen und taggen:
git add motoroute_app/pubspec.yaml
git commit -m "Release v0.1.1"
git tag v0.1.1

# 3. Pushen — der Tag-Press startet android-release.yml automatisch:
git push origin main --tags

# 4. ~10–15 Minuten später liegt die signierte APK unter
#    GitHub → Releases → MotoRoute v0.1.1
```

Jeder Versionssprung braucht **beide** Zahlen:

```text
version: 0.1.0+1   ← Code 1
version: 0.1.1+2   ← Code 2   (Bugfix-Release)
version: 0.2.0+3   ← Code 3   (neues Feature)
version: 1.0.0+4   ← Code 4
```

Der VersionCode muss **strikt steigen** — Android lehnt ein Update mit
gleichem/niedrigerem Code als „App nicht installiert“ ab. Der Versionsname
ist rein kosmetisch.

---

## 5. Updates installieren (Daten bleiben erhalten)

Neue Release-APK wie in Abschnitt 2 herunterladen und öffnen. Android erkennt
die bereits installierte App (gleiche App-ID `de.motoroute.app`, **höherer**
VersionCode) und bietet **„Update“** statt „Installieren“ an:

- ✅ **Alle lokalen Daten bleiben erhalten**: Einstellungen (shared_preferences),
  gespeicherte Routen/Favoriten, Sitzungs-/Chat-Zustand, App-Konfiguration.
- ✅ **Kontodaten sind serverseitig** (Supabase): Login-Session wird über
  SharedPreferences auf dem Gerät persistiert und überlebt Updates.
- ✅ **Heruntergeladene/offline Karten**: MapLibre nutzt je nach Konfiguration
  einen eigenen Cache im App-Verzeichnis — bleibt bei Updates erhalten.
- ⚠️ Nur bei **Debug↔Release-Wechsel** (unterschiedliche Signatur oder
  App-ID) muss zuerst deinstalliert werden — dabei gehen lokale Daten der
  alten Installation verloren. Deshalb: auf dem persönlichen Handy immer die
  **Release-Variante** nutzen, Debug nur zusätzlich.
- ⚠️ Falls Android „App nicht installiert“ meldet: fast immer
  Versionscode nicht gestiegen (Abschnitt 4) oder ein Signaturwechsel.

Sobald die Server-/Backend-Infrastruktur produktiv genutzt wird, sollten
Routen/Favoriten/Gruppen ohnehin in Supabase synchronisiert werden — dann
überlebt sogar eine Deinstallation die Daten (App neu installieren, einloggen,
alles ist da).

---

## 6. Keystore einrichten (einmalig, dann für immer wiederverwenden)

Der Keystore enthält den privaten Signierschlüssel. **Verlierst du ihn,
können installierte Geräte später keine Updates mehr installieren** (Android
pruft die Signatur bei jedem Update). Deshalb:

- ❌ Niemals in das Git-Repository (ist via `.gitignore` geblockt:
  `*.jks`, `*.keystore`, `key.properties`)
- ✅ Lokal sicher aufbewahren (z. B. Passwort-Manager-Tresor für die Datei)
- ✅ Für CI: als **GitHub Secret** hinterlegen

### 6.1 Keystore erstellen (einmalig)

Auf deinem Entwicklungsrechner (keytool liegt im JDK, z. B. dem von
Android Studio):

```bash
keytool -genkeypair -v \
  -keystore motoroute-release.jks \
  -alias motoroute \
  -keyalg RSA -keysize 4096 -validity 10000
```

Es fragt nach einem Keystore-Passwort, dem Schlüsselpasswort und
Identitätsdaten (Common Name z. B. „MotoRoute“ — der Rest darf leer
bleiben mit Enter). **Beide Passwörter notieren** (Passwort-Manager!).

> Gültigkeit 10000 Tage ≈ 27 Jahre: Absichtlich. Ein Keystore sollte ein
> „App-Leben“ überdauern.

### 6.2 Keystore als GitHub-Secret hinterlegen

Die Datei kann GitHub Secrets nicht direkt sein (nur Text) — daher
Base64-Kodierung:

```bash
# Linux/macOS/Git-Bash:
base64 -w0 motoroute-release.jks > motoroute-release.b64
# Windows PowerShell:
# [Convert]::ToBase64String([IO.File]::ReadAllBytes("motoroute-release.jks")) | Set-Content motoroute-release.b64
```

Dann auf GitHub: **Repo → Settings → Secrets and variables → Actions →
New repository secret** — vier Secrets anlegen:

| Secret-Name | Wert |
|---|---|
| `MOTOROUTE_KEYSTORE_B64` | Kompletter Inhalt der Datei `motoroute-release.b64` (eine lange Zeile) |
| `MOTOROUTE_KEYSTORE_PASSWORD` | Keystore-Passwort aus 6.1 |
| `MOTOROUTE_KEY_ALIAS` | `motoroute` (bzw. dein Alias) |
| `MOTOROUTE_KEY_PASSWORD` | Schlüsselpasswort aus 6.1 |

Ab dem nächsten `android-release`-Run signiert GitHub die APK mit deinem
echten Schlüssel. Ohne Secrets läuft der Workflow durch und signiert mit
dem Android-Debug-Key (ausdrückliche Warnung im Build-Log) — das ist der
bewusste Fallback, damit die Pipeline nie am Signing scheitert.

### 6.3 Signatur verifizieren

```bash
# Nach dem Build (lokal oder CI-Artefakt entpackt):
apksigner verify --print-certs MotoRoute-v0.1.0.apk
# Erwartet bei echtem Keystore: CN=MotoRoute, nicht "Android Debug"
```

### 6.4 Backup

Sicherung der `motoroute-release.jks` + Passwörter im Passwort-Manager
(Tresor-Anhang) oder verschlüsselter Cloud-Ordner. Ohne diesen Schlüssel
gibt es kein Update für bereits installierte Geräte — nur eine
Deinstallation + Neuinstallation mit Datenverlust.

---

## 7. Warum die App ohne Google Play Store funktioniert

MotoRoute ist bewusst so gebaut, dass **keine Komponente Google Play
Services oder Firebase braucht**:

| Funktion | Technologie | Braucht Play Services? |
|---|---|---|
| Karten | **MapLibre GL** (OpenStreetMap-Kacheln) | ❌ nein |
| GPS/Standort | **geolocator** (Android LocationManager) | ❌ nein |
| Navigation/Routing | eigenes BFF → GraphHopper | ❌ nein |
| Echtzeitverkehr | eigenes BFF → TomTom Traffic | ❌ nein |
| Wetter-Radar | eigenes BFF → OpenWeatherMap | ❌ nein |
| Chat / Gruppen | eigenes BFF → Supabase + Socket.IO | ❌ nein |
| POI-Dienst / Radar | eigener POI-Service + Socket.IO | ❌ nein |
| Push-Benachrichtigungen | (derzeit nicht verbaut) | — |
| Karten-Offline-Cache | MapLibre-eigener Cache | ❌ nein |

Konkret geprüft und bewusst vermieden:

- **Kein Firebase / FCM**: Push-Benachrichtigungen über Firebase Cloud
  Messaging bräuchten Play Services (auf nicht-Google-Geräten wäre
  sonst kein Push möglich). Falls MotoRoute später Push braucht, ist
  der passgenaue Ersatz **ntfy** oder **UnifiedPush** — funktioniert ohne
  Google und mit eigenem Server.
- **Keine Google Maps SDK**: MapLibre ist quelloffen und
  unabhängig (OSM-Kacheln).
- **Kein Google-Sign-in**: Login läuft über Supabase (E-Mail/Passwort)
  — kein Google-Konto nötig.
- **Kein Play Core / In-App-Updates**: Der Play-Store-Kram, den Android
  intern für Split-APKs nutzt, ist bewusst nicht aktiviert; die
  Release-APK ist eine universelle APK (alle ABIs, alle Sprachen) und
  installiert sich überall direkt.

**Fazit:** Die App läuft auf jedem Android 5.0+-Gerät, auch ohne
Google-Konto und ohne installierten Play Store (z. B. LineageOS, Fairphone
ohne GApps). GPS funktioniert über den Android-LocationManager — das ist
Teil von AOSP, nicht von Play Services.

---

## 8. Später: Play Store öffnen (keine Sackgasse)

Diese Struktur wurde absichtlich so gewählt, dass ein späterer
Play-Store-Launch **kein Umbau** braucht:

- **App-ID stabil**: `de.motoroute.app` — Play-Store-Konvention
  (eigene Domain als Prefix) ist erfüllt.
- **Versionierung** kommt aus der pubspec.yaml — dort wie im Play Store
  üblich VersionCode stark steigern.
- **Signierter Release-Build** existiert bereits; der Play Store nimmt
  denselben Keystore (oder Play App Signing, das beim ersten Upload
  eingerichtet wird).
- **AAB statt APK**: Für den Play Store genügt ein zusätzlicher
  Workflow-Step `flutter build appbundle` — die Struktur ist identisch.
  Du kannst ein `android-playstore.yml`-Workflow später ergänzen, das
  `build/app/outputs/bundle/release/app-release.aab` hochlädt.

Reihenfolge dann: Play-Store-Entwicklerkonto (25 $, einmalig) →
App in der Play Console anlegen → AAB hochladen → fertig. Am
Anwendungscode ändert sich nichts.

---

## 9. Troubleshooting

| Symptom | Ursache | Lösung |
|---|---|---|
| „App nicht installiert“ | VersionCode nicht gestiegen oder Signaturwechsel | pubspec `+N` erhöhen; wenn vorher Debug-APK installiert war: deinstallieren |
| „Aus dieser Quelle installieren nicht zulassen“ | fehlende Pro-App-Berechtigung | Einstellungen in der Fehlermeldung → Schalter aktivieren |
| Play Protect blockiert dauerhaft | unbekannte Signatur (normal) | „Trotzdem installieren“ oder Play-Protect-Warnung für diese App ignorieren |
| Debug- und Release-App beide installiert | beides gewollt | Unterscheidung über App-ID-Suffix `.debug` |
| Update fragt „Deinstallieren?“ statt „Update“ | Signaturwechsel (z. B. erst Debug-, dann Release-APK) | deinstallieren und sauber mit Release-Keystore neu installieren |
| APK lässt sich gar nicht herunterladen | nur 1 Asset sichtbar | direkt auf den Dateinamen unter *Assets* klicken, nicht auf den Release-Titel |
