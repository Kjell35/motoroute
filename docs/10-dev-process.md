# MotoRoute – Entwicklungsprozess & Konventionen

> Status: verbindlich ab M0 · Version 1.0 · Stand 2026-09-15

## 1. Monorepo

```
motoroute/
├── apps/
│   ├── mobile/          # Flutter-App
│   └── backend/         # FastAPI + docker-compose (valhalla, photon, postgres)
├── packages/
│   └── contracts/       # OpenAPI-Schema + generierte DTOs (single source of truth)
├── infra/               # Deployment (Docker-Compose prod, später Terraform)
├── docs/                # dieses Verzeichnis
└── README.md
```

## 2. Environments & Secrets

| Env | Zweck | Konfiguration |
|---|---|---|
| `dev` | lokale Entwicklung | `.env.dev` (git-ignored), `--dart-define` |
| `staging` | Closed Testing | Free-Tier-VM oder docker-compose lokal, andere Quota (Zero-Budget-Pfad, siehe `11-costs.md`) |
| `prod` | Live | erster gemieteter EU-Server (Hetzner) ab öffentlichem Betrieb, strenge Rate-Limits, Monitoring |

- App liest Konfiguration ausschließlich via `lib/core/config/env.dart` (typisiert, validiert beim Start).
- Backend via Pydantic-Settings (Env-Pflichtfelder → Start schlägt fehl, wenn unvollständig: „fail fast").
- **Regel:** Nie Keys committen, nie Keys in die APK bauen. Pre-Commit-Hook (gitleaks) + CI-Scan.
- Benötigte Keys (später zu beschaffen, siehe `11-costs.md`): aktuell **keiner** für MVP-Kern; optional TomTom-Key ab Traffic-Aktivierung; App-Signatur-Keys der Stores.

## 3. Definition of Done (jede Story)

1. Code + Tests (Domain/Application: Unit; UI: Widget/Golden bei Design-Änderung).
2. `flutter analyze` / `ruff + mypy` sauber, CI grün.
3. Doku aktualisiert, wenn Verhalten/Architektur betroffen ist.
4. Kein `TODO` ohne Issue-Referenz (`TODO(M3): … #12`).
5. Manueller Smoke-Test auf Android-Gerät und -Emulator (Punkte: [15-device-checklist.md](15-device-checklist.md)).

## 4. Branching & Commits

- Trunk-based: kurze Feature-Branches (`feat/nav-turn-banner`), squash-merge.
- Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`).
- PRs klein (< 400 Zeilen Diff bevorzugt); KI-Review + Selbst-Review.

## 5. CI-Pipeline (GitHub Actions)

- **mobile:** `flutter analyze`, `flutter test`, Golden-Tests, `flutter build apk --debug` (Artefakt).
- **backend:** `ruff`, `mypy`, `pytest` (inkl. Valhalla-Contract-Snapshot-Tests gegen gemockte Engine), `docker build`.
- **contracts:** OpenAPI-Diff-Check (Breaking Changes schlagen CI fehl, bis `/v2` beschlossen).
- **security:** gitleaks, pip-audit, osv-scanner wöchentlich.

### 5.1 Release-Signierung (Android-APK)

- Jeder Tag `v*` wird aus dem Release-Keystore signiert. Fehlt der Keystore, bricht der Job ab, statt eine debug-signierte APK zu veröffentlichen.
- Pro Tag entstehen vier Assets mit demselben Schlüssel: `MotoRoute-vX.Y.Z.apk` (Universal, enthält alle ABIs, ~110 MB), `MotoRoute-vX.Y.Z-arm64-v8a.apk` (~40 MB, richtige Wahl für praktisch alle Geräte), `MotoRoute-vX.Y.Z-armeabi-v7a.apk` (Altgeräte) und `MotoRoute-vX.Y.Z-x86_64.apk` (Emulator/Chromebook).
- Zu jedem Release-Tag gehört das R8-Mapping (mapping.txt aus dem Gradle-Release-Build): es liegt als eigenes Asset `MotoRoute-vX.Y.Z-mapping.txt` am Release und zusätzlich 90 Tage als CI-Artifact `motoroute-mapping-<ref>`. Ohne Mapping bleiben Stacktraces aus den opt-in-Fehlerberichten unlesbar; fehlt die Datei oder ist sie leer, bricht der Job ab.
- Ein Schritt prueft vor dem Release beides aus denselben `aapt2`-Metadaten (ein Lookup, ein Durchlauf ueber `dist/`): Der Tag `vX.Y.Z` muss zum `versionName` **aller** gebauten APKs passen - ohne Bump in `apps/mobile/pubspec.yaml` bricht der Job ab, statt eine Release-Seite mit falscher Version anzulegen. Zugleich muss die Build-Nummer `+N` aus `pubspec.yaml` hoeher sein als beim vorherigen Release-Tag; gleicher Wert hiesse, dass Android kein Update anbietet. Die Universal-APK bekommt per `--build-number` denselben `versionCode` wie das arm64-Paket (+2000; `-armeabi-v7a` +1000, `-x86_64` +4000), damit der Wechsel von arm64 auf den Fallback kein Downgrade ist - weicht das ab, bricht der Job ab. Der Vergleich liest nur Git-Tags, es wird nichts zwischen Laeufen gespeichert.
- Dieselben Pruefungen laufen zusaetzlich bei Branch-Pushes als Warnung (`::warning::`, Job bleibt gruen): Sollwert fuer den `versionName` ist dann `pubspec.yaml`, Vergleichswert fuer den `versionCode` der letzte Release-Tag. Ein vergessener Bump oder eine Universal-APK mit falschem Offset faellt damit vor dem Taggen auf, ohne Zwischenstaende rot zu machen.
- Secrets: `MOTOROUTE_KEYSTORE_B64` (Keystore als Base64), `MOTOROUTE_KEYSTORE_PASSWORD`, `MOTOROUTE_KEY_ALIAS`, `MOTOROUTE_KEY_PASSWORD`, `MOTOROUTE_SIGNING_CERT_SHA256` (Soll-Fingerabdruck; der Job vergleicht ihn nach dem Build und schlägt bei Abweichung fehl).
- Der Keystore liegt nicht im Repo (lokal unter `.artifacts/signing/`, nicht versioniert) und muss zusätzlich extern gesichert werden: Bei Verlust ist kein Update der installierten App mehr möglich, nur eine neue App-Identität.
- Alle Releases vor dieser Umstellung waren mit dem Zufalls-Debug-Schlüssel des jeweiligen CI-Runners signiert. Für ein Update von einer dieser Versionen ist einmalig eine Neuinstallation nötig.

## 6. Testing-Pyramide (konkret)
### 5.2 Keystore-Backup (ausserhalb dieses Rechners)

- Die Arbeitskopie unter `.artifacts/signing/` (nicht versioniert) ist **keine** Sicherung: Sie liegt auf derselben Platte wie das Repo.
- Gesichert wird auf ein **externes Medium** (USB-Stick) in den Ordner `MotoRoute-KeyBackup/`: `signing/motoroute-release.jks`, `signing/motoroute-release.jks.b64` (dieselben Bytes als Base64 fuer `MOTOROUTE_KEYSTORE_B64`) und `RESTORE.md` mit der Wiederherstellungsanleitung samt Pruefsummen.
- Das Passwort steht **nicht** auf diesem Medium, sondern im Passwort-Manager unter dem Eintrag "MotoRoute Release-Keystore"; dort haengt die `.jks` zusaetzlich als Dateianhang (zweite Kopie an einem anderen Ort).
- Nach jedem Kopieren die Pruefsummen aus `RESTORE.md` vergleichen statt hoffen.
- Offen (Stand 2026-11-25): Die Kopie auf ein externes Medium steht noch aus - beim Einrichten war kein Medium angeschlossen. Bis dahin existiert der Keystore nur auf dieser Platte.

### 5.3 Keystore-Wiederherstellung

Anlass: neuer Rechner, geloeschtes `.artifacts/signing/`, oder die CI-Secrets muessen neu gesetzt werden. Die Anleitung steht bewusst auch hier - der Backup-Ordner allein liegt auf derselben Platte, die er absichern soll. Die Datei-Pruefsummen dazu stehen in `RESTORE.md` im Backup-Ordner.

**Quelle**: externe Sicherung aus 5.2 (`signing/motoroute-release.jks` oder `signing/motoroute-release.jks.b64`), Passwort aus dem Passwort-Manager. Alias `motoroute`; Keystore und Schluessel teilen sich dasselbe Passwort. `RESTORE.md` nennt daneben `signing/keystore-password.txt` - diese Klartextdatei gehoert **nicht** auf das externe Medium und ist nach dem Umzug in den Passwort-Manager zu loeschen.

**Lokal bauen** - dieselben vier Variablen, die der CI-Job setzt:

```bash
export MOTOROUTE_KEYSTORE_PATH="<Backup>/signing/motoroute-release.jks"
export MOTOROUTE_KEYSTORE_PASSWORD="<Passwort aus dem Passwort-Manager>"
export MOTOROUTE_KEY_ALIAS=motoroute
export MOTOROUTE_KEY_PASSWORD="$MOTOROUTE_KEYSTORE_PASSWORD"
cd apps/mobile && flutter build apk --release --split-per-abi
```

**CI-Secrets neu setzen** (Settings -> Secrets and variables -> Actions), Namen wie in 5.1:

| Secret | Inhalt |
|---|---|
| `MOTOROUTE_KEYSTORE_B64` | kompletter Inhalt von `signing/motoroute-release.jks.b64` |
| `MOTOROUTE_KEYSTORE_PASSWORD` | Passwort aus dem Passwort-Manager |
| `MOTOROUTE_KEY_PASSWORD` | dasselbe Passwort |
| `MOTOROUTE_KEY_ALIAS` | `motoroute` |
| `MOTOROUTE_SIGNING_CERT_SHA256` | `95d17c32a101e4e182423ccfc9b8650c1470338e3f09583d0461c1bac3e66f59` |

**Pruefen, dass es wirklich der richtige Schluessel ist** - nicht der Vorgang zaehlt, sondern das Ergebnis:

```bash
apksigner verify --print-certs <apk> | grep "SHA-256 digest"
```

Erwartet wird `95d17c32...`; der Release-Job vergleicht genau diesen Wert und bricht ab, wenn eine APK debug-signiert ist oder abweicht. Ein Restore gilt erst als gelungen, wenn eine so gebaute APK sich ueber die installierte Version legen laesst: gleiche Signatur, `versionCode` hoeher als bei der installierten App (dafuer `apps/mobile/pubspec.yaml` bumpen). Dieser Test wurde am 2026-11-24 zweimal gefahren - einmal nur neu signiert aus der Kopie, einmal mit frischem Clone ohne `.artifacts/signing`; Ergebnis jeweils `de.motoroute.app`, versionName 1.0.14, versionCode 50, Zertifikat `95d17c32...`.

**Nicht ins Repo**: Keystore, `.b64` und Passwort - auch nicht in Issues, Chats oder Screenshots; das Repo ist oeffentlich.


| Ebene | Umfang | Beispiel |
|---|---|---|
| Domain-Unit | ~50 % der Tests | OffRouteDetector-Szenarien, CurveScorer-Referenzrouten |
| Application-Tests | ~30 % | RerouteController: Präferenzen-Invarianz |
| Contract | ~10 % | OpenAPI ↔ DTO-Schema-Tests |
| Widget/Golden | ~10 % | Turn-Banner, Kandidaten-Cards |
| Integration/GPX-Replay | wenige, automatisiert nachts | M4-DoD-Szenario |

## 7. Beobachtbarkeit (ab Staging)

- Backend: strukturierte Logs (JSON, ohne PII), `/metrics` (Prometheus-Format), Latenz-Alerts.
- App: opt-in Crash-Reporting; anonyme Performance-Metriken (Cold-Start, TTFF) im Debug-Build.

## 8. Runbook-Grundlagen (Details mit M6)

- Deploy: `infra/deploy.sh` (compose pull + rollout), Rollback = vorheriges Image-Tag.
- Backups: Postgres täglich (pg_dump → Object-Storage, 30 Tage), Restore-Test monatlich.
- Valhalla-Daten-Update: monatlicher Rebuild-Job (OSM-Extract DACH), dokumentierter Downtime-freier Ablauf (Blue/Green-Container).
