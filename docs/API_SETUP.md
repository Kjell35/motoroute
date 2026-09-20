# Welche APIs braucht MotoRoute — und wo trägt man was ein?

Kurzantwort: **Die App selbst braucht keinen einzigen API-Key.** Keys gehören
nur auf den Server (`motoroute_api/.env`). Auf dem Handy stellst du in den
**Einstellungen → Server & Verbindung** nur die Adresse deines Backends ein.

---

## 1. Auf dem Smartphone (nichts installieren, nichts eintragen)

Die App spricht ausschließlich mit deinem Backend. Karte, GPS, Suche im
Offline-Fall funktionieren ohne jegliche Zusatzkonfiguration:

| Funktion | Quelle | Key nötig? |
|---|---|---|
| Karte (Dark-Style) | OpenStreetMap-Kacheln von CARTO (keyless) | ❌ nein |
| GPS / Navigation | Android-LocationManager | ❌ nein |
| Alle anderen Daten (Routing, Verkehr, Wetter, POIs, Chat) | dein Backend | — nur dessen Adresse |

**Einstellungen → Server & Verbindung → Backend-URL**: Hier trägst du die
Adresse ein, unter der dein Backend läuft — z. B. `http://192.168.1.50:3000`,
wenn der Server auf deinem PC im WLAN läuft (Windows-Firewall muss Port 3000
erlauben), oder `https://dein-server.de` von außen. Leer lassen = eingebaute
Standard-URL (`--dart-define=API_BASE_URL` bzw. Emulator-Loopback).

## 2. Auf dem Backend-Server (`motoroute_api/.env`)

Diese Datei ist **gitignored** und nie im Repo. Kopiervorlage:
`.env.example`. Variablen und Wirkung:

| Variable | Wofür | Ohne Key… |
|---|---|---|
| `SUPABASE_URL` | Postgres + Auth (Login, Chat, Gruppen) | App startet, aber Auth/Chat/Gruppen melden Fehler |
| `SUPABASE_SERVICE_ROLE_KEY` | Serverseitiger DB-Zugriff (RLS-Umgehung fürs BFF) | Auth/Chat nicht nutzbar |
| `SUPABASE_JWT_SECRET` | Verifikation der Login-Tokens | Login-Schläge werden abgewiesen |
| `GRAPHHOPPER_URL` | Routing-Engine (lokal `http://127.0.0.1:8989`) — **optional**: ohne ihn läuft Routing über den OSRM-Fallback (Auto-Profil, Kurven-Präferenzen entfallen) | nichts — Routing läuft dann über OSRM |
| `TRAFFIC_API_KEY` | **TomTom** — Echtzeitverkehr, Umleitungen **UND Ortssuche/Reverse-Geocoding** | Verkehr + **Ortssuche** deaktiviert, Rest läuft |
| `OPENWEATHER_API_KEY` | **OpenWeatherMap One Call 3.0** — OPTIONALER Wetter-Upgrade (Standard: Open-Meteo, keyless) | egal — Wetter-Radar läuft ab Werk über Open-Meteo |
| `OVERPASS_URL` | OSM-POIs (Tankstellen) | POI-Abfrage leer/fehlerhaft |
| `RIDE_RELAY_SECRET` | Gemeinsames Secret BFF ↔ POI-Dienst (Live-Gruppenfahrt) | Ride-Radar deaktiviert (fail-closed) |
| `BIKER_POI_SERVICE_URL` | Adresse des kuratierten POI-Dienstes | Kuratierte POIs aus (OSM-POIs weiter da) |
| `PUBLIC_URL` | Öffentliche Backend-Adresse (OAuth-Redirects) | Nur für OAuth relevant |

**Zusammengefasst: Mit genau 1 externem Key (TomTom) läuft ALLES:** Verkehr,
Umleitungen, **Ortsuche** und Wegpunkt-Namen. Das Wetter-Radar läuft ab Werk
ohne jeden Key über **Open-Meteo** (keyless, Attribution im Widget); ein
OpenWeatherMap-Key (openweathermap.org, Free-Tier, einmalig „One Call 3.0"
aktivieren) schaltet auf die höher aufgelöste OWM-Vorhersage um — reines
Upgrade, keine Pflicht. Beide Keys gehören NUR in `.env`.

## 3. Optionaler POI-Dienst (`motoroute_poi_service/.env`)

Eigenständiger Node-Dienst (PostGIS + eigene DB), kuratiert Motorrad-POIs:

| Variable | Wofür |
|---|---|
| `DATABASE_URL` | Postgres/PostGIS-Verbindung |
| `TOMTOM_API_KEY` | Eigener TomTom-Key fürs POI-Scanning (dieselbe Key-Quelle wie oben) |
| `RIDE_RELAY_SECRET` | Muss IDENTISCH mit dem im BFF sein |
| `SCAN_CRON`, `SCAN_THROTTLE_MS`, `SCAN_MAX_RESULTS`, `RADAR_PRUNE_INTERVAL_MS` | Scan-/Prune-Tuning (Defaults reichen) |

Ohne diesen Dienst läuft die App normal — nur die kuratierten Motorradhotels/
Bikertreffs fehlen und das Biker-Radar/Ride-Radar sind aus.

## 4. Setup ("App für Papa" — der Endnutzer trägt GAR NICHTS ein)

**Einmalig von dir (nicht vom Nutzer):**

1. **Datenbank anlegen** (einmalig): Supabase-Dashboard → SQL-Editor →
   Inhalt von `motoroute_api/supabase/migrations/0001_full_setup.sql`
   einfügen → Run. Idempotent, mehrfach ausführen ist harmlos.
2. **Backend dauerhaft online** (2 Minuten): https://dashboard.render.com/select-repo?type=blueprint
   öffnen → Repo `Kjell35/motoroute` verbinden → Render liest `render.yaml`
   und fragt 5 Werte ab (aus der lokalen `motoroute_api/.env` kopieren:
   `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`,
   `TRAFFIC_API_KEY`, `RIDE_RELAY_SECRET`). Danach läuft das Backend
   dauerhaft unter `https://motoroute-api.onrender.com` — Free Tier,
   keine Kreditkarte. Routing läuft dort automatisch über den
   OSRM-Fallback (Auto-Profil).
3. **APK installieren**: aktuelles Release laden → registrieren → fertig.
   Die Backend-URL ist im Release-APK fest eingebaut
   (`--dart-define=API_BASE_URL=…` in den GitHub-Workflows) — der Nutzer
   gibt NIE eine URL und NIE einen Key ein.

**Alternativ LAN** (Backend auf dem eigenen PC statt Render): App in den
Einstellungen → Server & Verbindung auf die PC-IP setzen
(`http://192.168.1.50:3000` + Firewall-Regel). Das Feld bleibt als
Override erhalten — leer = eingebaute Produktions-URL.

Für die Live-Gruppenfahrt zusätzlich `RIDE_RELAY_SECRET` (BFF + POI-Dienst
identisch) und den POI-Dienst starten (eigene PostGIS-DB, siehe unten).

## 5. Was niemals in die App gehört

Fahrzeug-Regel des Projekts: Keys liegen nur im Backend. Konkret verboten im
App-Bundle: TomTom-Key, OpenWeatherMap-Key, Supabase-Service-Role-Key.
Der Chat-Login (Supabase-JWT) landet bewusst nur im Gerät-Speicher der
angemeldeten Session, nie im Build.

## 6. Eigener Karten-Stil (optional)

Der eingebaute Stil ist keyless (CARTO-Dark). Wer einen eigenen Vektor-Stil
nutzen will (z. B. MapTiler/Stadia): beim Build

```bash
flutter build apk --release --dart-define=MAP_STYLE_URL=https://api.maptiler.com/maps/.../style.json?key=DEIN_KEY
```

— oder `MAP_STYLE_URL` beim `flutter run`. Ohne dieses Flag gilt der
keyless Standard-Stil.
