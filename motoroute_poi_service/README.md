# MotoRoute – Biker-POI Backend (TomTom, weltweit)

> Teil des MotoRoute-Monorepos.Dieser Dienst läuft BEI SEINEM
> EIGENEN Provider (eigene Postgres/PostGIS-Instanz, eigener Prozess)
> und wird vom NestJS-BFF (`motoroute_api`) unter `/v1/biker-pois`
> proxyt – die Flutter-App kennt ihn nie direkt (Kommunikations-
> prinzip Teil C: nur ein Backend für den Client).
>
> Der TomTom-Key dieses Dienstes ist ein ZWEITER, separater Key
> (Scan-Kontingent), unabhängig vom Traffic-Key des BFF.

Automatisiertes Backend, das täglich weltweit neue bikerfreundliche POIs
über die TomTom Search API findet, dedupliziert speichert und per
Delta-Sync + Realtime-Push an die Flutter-App ausliefert.

## Architektur

```
src/
  countries.js         ISO-3166-1 Ländercodes für die länderweise Weltabdeckung
  tomtomClient.js       Roher HTTP-Client für die TomTom Search API
  categoryResolver.js   Löst unsere 8 Kategorien LIVE gegen TomTom-Kategorie-IDs auf
  classifier.js         TomTom-Ergebnis -> unser POI-Format + Biker-Score
  poiRepository.js      ST_DWithin-Duplikatprüfung, Upsert, Delta-Query
  dailyPoiScan.js        node-cron Job: alle Länder x 8 Kategorien
  server.js              Express REST-API + Socket.IO Realtime-Bridge
schema.sql               PostGIS-Tabelle, Indizes, Notify-Trigger
```

## Warum "Land für Land" statt einer globalen Anfrage?

Eine einzelne weltweite Suchanfrage ist bei der TomTom Search API nicht
vorgesehen – Ergebnisse sind pro Anfrage gedeckelt (max. 100/Seite) und
eine Kategorie wie "Restaurant" hat weltweit Millionen Treffer. Die
Suche wird daher pro Land (`countrySet`) und Kategorie einzeln
ausgeführt und paginiert (`SCAN_MAX_RESULTS`, Standard 300 Treffer pro
Land×Kategorie – anpassbar). Damit ist "weltweit" **innerhalb eines
Laufs** durch alle ~195 Länder tatsächlich abgedeckt, nicht nur eine
Handvoll manuell gewählter Regionen.

## Kategorie-Mapping: warum keine hartcodierten IDs?

Die TomTom-REST-API erwartet **numerische** Kategorie-IDs (z.B. `7315`),
die nicht öffentlich stabil dokumentiert sind und sich unterscheiden
können. Statt Zahlen zu raten, ruft `categoryResolver.js` beim Start
`/search/2/poiCategories.json` **live** ab und matcht die Namen unserer
8 Kategorien exakt gegen den aktuellen TomTom-Katalog (verifiziert u.a.
über den TomTom-Connector: `Fast Food`, `Pub`/`Bar`, `B&B/Guest House`,
`Restaurant`, `Hotel`, `Campground`, `Motorcycle Dealer`/`Motorcycle
Repair`). Findet TomTom-seitig eine Umbenennung statt, loggt der
Resolver eine Warnung statt still Ergebnisse zu verlieren – so bleibt
das System robust gegenüber API-Änderungen.

**Zwei unserer 8 Kategorien haben keine eigene TomTom-Kategorie:**
- `bikertreff`: keine "Biker-Treff"-Kategorie bei TomTom. Lösung:
  (1) offizielle `Motorcycle Dealer`/`Motorcycle Repair`-Kategorie
  (Schrauberecke-Charakter), plus (2) Freitext-Suche ("Biker Treff",
  "Motorradtreff", "Biker Bar") eingeschränkt auf Café/Pub/Bar/Restaurant.
- `gartenlokal`: keine "Biergarten"-Kategorie bei TomTom. Lösung:
  Freitext-Suche ("Biergarten", "Gartenlokal", "Beer Garden")
  eingeschränkt auf Restaurant/Café-Pub.

Diese beiden Fallbacks liefern spürbar weniger Treffer als eine echte
Kategorie – für den Start reicht das, sollte aber beobachtet und bei
Bedarf um weitere Sprachvarianten/Länder-Synonyme ergänzt werden.

## Realtime-Sync: zwei Bausteine

1. **REST Delta-Sync** (`GET /api/pois/sync?since=...`) – robuster
   Grundmechanismus, funktioniert auch nach App-Neustart/Offline-Phasen.
2. **Socket.IO Push** – der API-Server lauscht per Postgres
   `LISTEN/NOTIFY` auf den DB-Trigger `pois_notify_change` und pusht
   Änderungen sofort an verbundene Clients; entkoppelt vom Scan-Prozess
   und funktioniert mit mehreren API-Server-Instanzen.

Die App nutzt beides – aber **immer über das BFF, nie direkt**:

1. **REST Delta-Sync**: Das NestJS-BFF proxyt den Endpunkt
   authentifiziert unter `GET /v1/biker-pois/sync` (Kategorie-Mapping,
   `biker-`-ID-Präfix, 60-s-TTL-Cache).
2. **Socket.IO Push**: Das BFF hält eine server-interne Socket.IO-
   Client-Verbindung zu diesem Server (`BIKER_POI_SERVICE_URL`),
   koalesziert den Event-Strom (5-s-Fenster, 30-s-Hartlimit) und
   verteilt `bikerpoi.batch`-Frames über seine authentifizierte
   App-WebSocket (`/v1/chat/ws`). Die App zieht die betroffenen IDs
   sofort per Delta-Sync nach und zeichnet die Karte neu.

Beide Pfade degradieren sauber: Läuft dieser Dienst nicht, läuft
die App unverändert mit OSM-POIs weiter (Delta-Sync antwortet 503,
keine Push-Events).

## Live-Radar (Biker Meetup, Socket.IO)

Neben dem POI-Sync betreibt derselbe Socket.IO-Server ein **Echtzeit-
Radar**: Biker sehen, wer in ihrem Umkreis unterwegs ist.

**Setup:** `psql "$DATABASE_URL" -f schema_radar.sql` (Tabelle
`active_bikers` mit GEOGRAPHY(Point, 4326) + GiST-Index).

**Protokoll:**

```
Client -> Server:  emit('update_location', { userId, latitude, longitude, ghostMode }, ack)
Server -> Sender:  ack({ ok, ghostMode, nearbyBikers: [{ userId, lat, lng, distanceM, lastSeen }] })
Server -> Andere:  emit('location_update', { userId, lat, lng, lastSeen })   // nur betroffene Biker
```

Regeln (alle serverseitig durchgesetzt):
- **ghostMode=true**: NICHTS wird gespeichert - Nicht-Speichern ist der
  Schutz, kein Flag. Der Client bekommt `nearbyBikers: []`.
- **ghostMode=false**: Position per UPSERT gespeichert (eine Zeile pro
  Biker, KEINE Historie), dann ST_DWithin-15-km-Umkreis mit
  30-Minuten-Frische-Filter über den GiST-Index.
- **Datenschutz**: Bereinigungs-Job löscht Positionen älter als
  30 Minuten PHYSISCH (Default alle 5 min, `RADAR_PRUNE_INTERVAL_MS`);
  Disconnect entfernt den eigenen Eintrag sofort. Es gibt bewusst KEINE
  REST-Route, die Radar-Positionen ausleitet.
- **Drosselung**: max. 1 Positionsupdate je 2 s pro Socket.

## Duplikatprüfung

`poiRepository.findNearbyDuplicate()` nutzt `ST_DWithin(geog, ..., 75m)`
je Kategorie – ein neuer Fund innerhalb von 75 m zu einem bereits
gespeicherten POI derselben Kategorie wird als Update statt als
Duplikat behandelt (Konstante `DUPLICATE_RADIUS_METERS` anpassbar).

## Setup

```bash
cp .env.example .env   # DATABASE_URL + TOMTOM_API_KEY eintragen (Key liegt bereits in .env)
psql "$DATABASE_URL" -f schema.sql
npm install
npm start               # startet API + Cron-Job + Realtime-Bridge
npm run scan:now        # einmaligen Scan sofort auslösen (zum Testen, dauert je nach SCAN_MAX_RESULTS)
```

Beim ersten `scan:now` unbedingt die Logzeile
`[categoryResolver] Keine TomTom-Kategorie-ID gefunden für "..."`
im Auge behalten – taucht sie auf, hat TomTom eine Kategorie umbenannt
und `CATEGORY_NAME_CANDIDATES` in `categoryResolver.js` muss angepasst werden.

## Beispiel-Request (App-Client)

```
GET /api/pois/sync?since=2026-09-17T00:00:00Z&lat=47.5&lon=11.0&radiusKm=150&categories=bikertreff,zeltplatz
```

```json
{
  "serverTime": "2026-09-18T10:00:00.000Z",
  "upserted": [
    {
      "id": "…",
      "name": "Zum Kurvenkönig",
      "category": "bikertreff",
      "lat": 47.51,
      "lon": 11.02,
      "bikerScore": 85,
      "amenities": { "motorcycle_parking": true, "meeting_point": true },
      "updatedAt": "2026-09-18T03:12:44.000Z"
    }
  ],
  "deletedIds": []
}
```

## Kosten-/Rate-Limit-Hinweis

195 Länder × 8 Kategorien × mehrere Seiten pro Kategorie ergeben pro
vollem Tageslauf potenziell mehrere tausend TomTom-API-Calls. Vor dem
produktiven Scharfschalten unbedingt:
- `SCAN_MAX_RESULTS` und `SCAN_THROTTLE_MS` an das gebuchte TomTom-Kontingent anpassen,
- ggf. `COUNTRIES` in `countries.js` zunächst auf die für MotoRoute
  relevanten Kernmärkte reduzieren und schrittweise erweitern,
- das TomTom-Preismodell für die erwartete Aufrufzahl gegenprüfen.

## Nächste sinnvolle Ausbaustufen

- Fortschritts-Tracking pro Land (welches Land wurde wann zuletzt
  gescannt), um Läufe bei Abbruch fortzusetzen statt neu zu starten.
- Auth/API-Key für den Sync-Endpunkt, sobald die App live geht.
- Moderations-Queue für neue POIs mit niedrigem `biker_score`, bevor sie
  live geschaltet werden.
- Mehrsprachige Freitext-Suchbegriffe für `bikertreff`/`gartenlokal`
  (aktuell nur deutsch/englisch).
