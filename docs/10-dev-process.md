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
5. Manueller Smoke-Test auf Android-Gerät und -Emulator.

## 4. Branching & Commits

- Trunk-based: kurze Feature-Branches (`feat/nav-turn-banner`), squash-merge.
- Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`).
- PRs klein (< 400 Zeilen Diff bevorzugt); KI-Review + Selbst-Review.

## 5. CI-Pipeline (GitHub Actions)

- **mobile:** `flutter analyze`, `flutter test`, Golden-Tests, `flutter build apk --debug` (Artefakt).
- **backend:** `ruff`, `mypy`, `pytest` (inkl. Valhalla-Contract-Snapshot-Tests gegen gemockte Engine), `docker build`.
- **contracts:** OpenAPI-Diff-Check (Breaking Changes schlagen CI fehl, bis `/v2` beschlossen).
- **security:** gitleaks, pip-audit, osv-scanner wöchentlich.

## 6. Testing-Pyramide (konkret)

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
