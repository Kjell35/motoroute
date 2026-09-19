# GitHub-Secrets für die APK-Signierung — Schritt-für-Schritt

Einmalig ausführen, dauert ~2 Minuten. Danach signiert GitHub Actions jede
Release-APK automatisch mit deinem Keystore.

## Werte vorbereiten

Auf deinem PC liegen (außerhalb des Projekts, **nicht** im Git):

| Datei | Inhalt |
|---|---|
| `C:/Users/treis/motoroute-keystore-b64.txt` | Der Keystore als Base64 (**eine einzige lange Zeile**) |
| `C:/Users/treis/motoroute-keystore-info.txt` | Alias und Passwort |

## 1. Secrets-Seite öffnen

1. `github.com/Kjell35/motoroute` im Browser öffnen (eingeloggt)
2. **Settings** → links unten **Secrets and variables** → **Actions**
3. Tab **Secrets** (nicht Variables)

## 2. Vier Secrets anlegen

Je einmal **New repository secret**, Name eintragen, Wert einfügen,
**Add secret**:

| Secret-Name | Wert: woher? |
|---|---|
| `MOTOROUTE_KEYSTORE_B64` | Kompletten Inhalt von `motoroute-keystore-b64.txt` kopieren (Strg+A, Strg+C, Strg+V) — **eine lange Zeile, nichts weglassen** |
| `MOTOROUTE_KEYSTORE_PASSWORD` | Passwort aus `motoroute-keystore-info.txt` |
| `MOTOROUTE_KEY_ALIAS` | `motoroute` |
| `MOTOROUTE_KEY_PASSWORD` | Dasselbe Passwort wie bei KEYSTORE_PASSWORD |

Kontrolle: Nach dem vierten Secret stehen unter *Repository secrets*
genau 4 Einträge mit diesen Namen.

## 3. Danach

Melde dich bei mir („jetzt pushen") — ich pushe Commit + Tag, GitHub
baut die APK mit deinem echten Schlüssel und erstellt das Release.

> Passwörter niemals im Chat, in Tickets oder Commits nennen. Die Dateien
> außerhalb des Projekts sichern (Passwort-Manager) und wenn alles läuft
> die Klartext-Kopien löschen.
