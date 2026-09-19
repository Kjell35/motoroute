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
| `GRAPHHOPPER_URL` | Routing-Engine (lokal `http://127.0.0.1:8989`, kein externer Key) | Routing zeigt Fehler |
| `TRAFFIC_API_KEY` | **TomTom** — Echtzeitverkehr + Umleitungen | Verkehr-Feature meldet „deaktiviert", Rest läuft |
| `OPENWEATHER_API_KEY` | **OpenWeatherMap One Call 3.0** — Wetter-Radar | Wetter-Widget bleibt aus (`isEnabled:false`), Rest läuft |
| `OVERPASS_URL` | OSM-POIs (Tankstellen) | POI-Abfrage leer/fehlerhaft |
| `RIDE_RELAY_SECRET` | Gemeinsames Secret BFF ↔ POI-Dienst (Live-Gruppenfahrt) | Ride-Radar deaktiviert (fail-closed) |
| `BIKER_POI_SERVICE_URL` | Adresse des kuratierten POI-Dienstes | Kuratierte POIs aus (OSM-POIs weiter da) |
| `PUBLIC_URL` | Öffentliche Backend-Adresse (OAuth-Redirects) | Nur für OAuth relevant |

**Zusammengefasst für das volle Erlebnis brauchst du genau 2 externe Keys:**
TomTom (developer.tomtom.com, Free-Tier reicht) und OpenWeatherMap
(openweathermap.org, Free-Tier reicht; einmalig im Dashboard die
„One Call 3.0"-Subscription aktivieren). Beide gehören NUR in `.env`.

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

## 4. Was niemals in die App gehört

Fahrzeug-Regel des Projekts: Keys liegen nur im Backend. Konkret verboten im
App-Bundle: TomTom-Key, OpenWeatherMap-Key, Supabase-Service-Role-Key.
Der Chat-Login (Supabase-JWT) landet bewusst nur im Gerät-Speicher der
angemeldeten Session, nie im Build.

## 5. Eigener Karten-Stil (optional)

Der eingebaute Stil ist keyless (CARTO-Dark). Wer einen eigenen Vektor-Stil
nutzen will (z. B. MapTiler/Stadia): beim Build

```bash
flutter build apk --release --dart-define=MAP_STYLE_URL=https://api.maptiler.com/maps/.../style.json?key=DEIN_KEY
```

— oder `MAP_STYLE_URL` beim `flutter run`. Ohne dieses Flag gilt der
keyless Standard-Stil.
