# Garage-API auf Render deployen — Schritt für Schritt

Ziel: Die Garage ist von überall erreichbar (`https://garage-api-…onrender.com`),
die Android-APK bekommt die URL fest eingebacken. Der Endnutzer (Vater) trägt
**nichts** ein.

---

## Voraussetzungen (bereits erledigt / vorhanden)

- ✅ `render.yaml` im Repo-Root enthält jetzt den `garage-api`-Dienst
- ✅ Garage-DB existiert (Supabase-Projekt „garage", Session-Pooler-Verbindung
  steht in der lokalen `garage/garage-api/.env`)
- ✅ App-Code liest `--dart-define=GARAGE_API_URL` (mit Leer-String-Absicherung)
- ✅ Beide Workflows übergeben das Secret `GARAGE_API_URL`

---

## Schritt 1 — Code pushen (Voraussetzung: Commit erlaubt)

Die Änderungen an `render.yaml` und den beiden Workflows müssen auf GitHub sein,
damit Render den neuen Dienst sieht. Erst committen + pushen (oder mich bitten,
es zu tun), dann weiter mit Schritt 2.

## Schritt 2 — Blueprint-Sync in Render (~2 Minuten)

1. **https://dashboard.render.com** öffnen → dein Blueprint-Projekt
   (das mit `motoroute-api`)
2. Oben rechts **„New +" → Blueprint** — Render erkennt das Repo erneut und
   zeigt: **1 neuer Dienst: `garage-api`** (der bestehende `motoroute-api`
   bleibt unangetastet) → **„Apply"** / „Create resources"
3. Der erste Deploy schlägt garantiert fehl (fehlende `DATABASE_URL`) —
   das ist normal, weiter zu Schritt 3.

## Schritt 3 — Environment-Variablen setzen (~3 Minuten)

Dashboard → Dienst **garage-api** → linker Rand **„Environment"** →
**„Add environment variable"** für jede Zeile (Werte stehen in deiner lokalen
`garage/garage-api/.env`):

| Key | Value (aus deiner `.env`) |
|---|---|
| `DATABASE_URL` | Die Pooler-URL: `postgresql://postgres.abcd…:Passwort@aws-0-eu-central-1.pooler.supabase.com:5432/postgres` |
| `JWT_SECRET` | Der 96-Zeichen-Schlüssel (`JWT_SECRET="…"` — nur der Inhalt, ohne Anführungszeichen) |
| `NODE_ENV` | `production` |
| `CORS_ORIGINS` | `*` (später: die App-/Backend-Herkunft) |
| `ADMIN_EMAIL` | dein Garage-Admin |
| `ADMIN_PASSWORD` | dein Garage-Admin-Passwort |
| `ADMIN_DISPLAY_NAME` | `Kjell` |

**Save changes** → Render startet automatisch einen neuen Deploy.

## Schritt 4 — Deploy prüfen (~1 Minute)

Deploys-Tab abwarten (Free Tier: 3–6 Minuten) → dann:

```
https://garage-api-XXXX.onrender.com/api/health
```

Erwartet:

```json
{"status":"ok","service":"garage-api","time":"…"}
```

Sollte `Invalid environment configuration` kommen: Ein Variablenname falsch
getippt (Groß-/Kleinschreibung!), Deploy manuell neu starten
(Deploys → „Deploy latest commit").

## Schritt 5 — Admin-Account anlegen (einmalig)

Lokal gegen die Cloud-DB (dein PC darf drauf, der Pooler ist öffentlich):

```
cd garage\garage-api
npm run seed
```

Der Seed legt Hersteller/Modelle **und** deinen Admin an — er ist idempotent,
läuft also auch gefahrlos mehrfach.

## Schritt 6 — GitHub-Secret setzen (~1 Minute)

GitHub-Repo **Kjell35/motoroute** →
**Settings → Secrets and variables → Actions → „New repository secret"**:

| Name | Value |
|---|---|
| `GARAGE_API_URL` | `https://garage-api-XXXX.onrender.com` (deine Render-URL, **ohne** `/api/health`) |

## Schritt 7 — Neues Release bauen (~10 Minuten, läuft automatisch)

Im Terminal (Projekt-Root):

```
git tag v0.4.0
git push origin main v0.4.0
```

Der Release-Workflow backt jetzt beide URLs ins APK:

- `API_BASE_URL` = MotoRoute-Backend
- `GARAGE_API_URL` = deine Garage-API

Sobald der Run grün ist (GitHub → Actions), steht im Release die neue APK
bereit — darin ist die Garage dauerhaft online erreichbar, ohne Eintragungen.

---

## Danach: Erster Test in der App

1. APK installieren → MotoRoute öffnen
2. Tab **Garage** (Motorrad-Icon) → Login mit deinem Garage-Admin
3. „+ Fahrzeug anlegen" → BMW → R 1250 GS → Variante → speichern
4. Detail-Screen: technische Daten, Erinnerungen 🟢, Wartung erfassen,
   Tankbuch — alles live gegen die Render-API

## Stolperfallen

| Symptom | Ursache / Lösung |
|---|---|
| Erster Blueprint-Deploy rot | Normal — Env-Vars fehlten noch. Nach Schritt 3 „Manual Deploy" |
| „Invalid environment configuration" | Name falsch (z. B. `database_url`) — exakt wie oben, dann neu deployen |
| App zeigt „Garage-Server nicht erreichbar" | Secret fehlt/leer → Schritt 6, neues Release; oder lokale Test-URL noch in Einstellungen gespeichert (Feld leeren) |
| Server schläft ein (30–60 s Kaltstart) | Free-Tier-Normalität. Keep-Alive für die Garage später ergänzen (Workflows/keep-alive erweitern) |
| „relation \"Vehicle\" does not exist" | `prisma db push` war nur lokal — Render-Shell: `npx prisma db push` einmalig ausführen (nutzt dieselbe DATABASE_URL) |
