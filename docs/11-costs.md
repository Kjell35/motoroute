# MotoRoute – Kosten & API-Keys

> Status: **Zero-Budget-Beschluss des Auftraggebers (2026-09-15)** · Version 1.1
> Grundsatz: Der MVP läuft vollständig kostenlos – keine bezahlten APIs, kein bezahltes Hosting, keine Monetarisierung. Bezahlt wird erst, wenn echte Nutzer da sind.

## 1. API-Keys-Bedarf

| Wann | Key | Wofür | Kosten |
|---|---|---|---|
| MVP | **keiner** | OpenFreeMap (keyless), Valhalla/Photon/PostGIS selbst gehostet, Traffic via OSM-Stub | 0 € |
| Android-Vertrieb | Google Play Console | Play-Store-Eintrag | 25 $ einmalig |
| iOS-Vertrieb (bewusst zurückgestellt) | Apple Developer | App-Store-Vertrieb | 99 $/Jahr |
| Später (optional) | TomTom-Key | Echtzeit-Traffic | ab ~100 €/Mon |

**Konsequenzen aus dem Zero-Budget-Beschluss:**

1. **Android-first:** iOS verursacht zwingend 99 $/Jahr (Apple Developer). Wenn wirklich 0 € gelten, startet MotoRoute Android-only (Play-Eintrag 25 $ einmalig – der einzige praktisch unvermeidbare Betrag; während der reinen Tester-Beta geht sogar direkter APK-Vertrieb für 0 €). iOS folgt mit dem ersten Budget.
2. **Traffic bleibt Stub:** Echtzeit-Stau/-Unfälle sind ohne Bezahl-API nicht seriös lieferbar. Im MVP: Sperrungen/Baustellen aus OSM, UI kennzeichnet die Quelle ehrlich. Der TomTom-Adapter bleibt als vorbereitetes Feature-Flag bestehen (Port `TrafficProvider`), Aktivierung erst bei Budget-Freigabe.
3. **Keine Monetarisierung:** Die App ist kostenlos, ohne Abos/„Plans". Keine Payment-Abhängigkeit im MVP; ein Entitlement-Hook bleibt architektonisch vorgesehen (ohne Implementierung).

## 2. Laufkosten nach Phase (Zero-Budget-Pfad)

| Phase | Setup | Kosten |
|---|---|---|
| M0–M4 (Entwicklung) | docker-compose lokal auf dem Entwickler-Rechner | **0 €** |
| M5–M6 (Closed Beta) | Free-Tier-VM (z. B. Oracle Cloud „Always Free", ARM, bis 24 GB RAM – groß genug für Valhalla-DACH + Photon + Postgres); Tiles weiterhin OpenFreeMap | **0 €** |
| Öffentlicher Beta-Betrieb | erster gemieteter EU-Server (Hetzner, ~30–50 €/Mon) **oder** Free-Tier mit engen Limits | 0–50 €/Mon |
| Wachstum (> ~5.000 aktive Nutzer/Mon) | dediziertes Routing, DB-Upgrade, ggf. Traffic-Anbieter | ~180–1.200 €/Mon |

**Skalierungs-Trigger (objektiv, nicht spekulativ):** p95-Routing-Latenz > 3 s, Routing-VM-CPU > 70 % dauerhaft, 429-Rate-Limit-Quote > 1 % → jeweils nächste Stufe. Bis dahin gilt: 0 €.

## 3. Was „alles kostenlos" realistisch bedeutet (ehrliche Grenzen)

1. **Free-Tier & OpenFreeMap sind kein SLA.** Drosselung/Ausfälle sind möglich. Für Entwicklung und geschlossene Beta völlig ausreichend; für verlässliche öffentliche Verfügbarkeit mieten wir den ersten Server (Block oben: 0–50 €/Mon). Das ist die erste echte Ausgabe – bewusst aufgeschoben.
2. **Store-Gebühren sind nicht verhandelbar** (Play 25 $ einmalig, Apple 99 $/Jahr). Die Android-first-Strategie entkoppelt davon.
3. **Echtzeit-Traffic kostet woanders Geld.** Wir liefern ihn nicht „gefaked", sondern ehrlich als OSM-Sperrungen mit klarer Quellen-Kennzeichnung (Produktregel: keine Fake-Daten).
4. **Eigenleistung statt Cloud-Kosten:** Valhalla-Tile-Rebuilds, POI-Extraktion und Betrieb laufen per CI-Job/docker-compose auf eigener Infrastruktur (dev-Rechner bzw. Free-Tier).

## 4. Kostentreiber, die wir weiterhin aktiv vermeiden

1. **Tile-Traffic:** OpenFreeMap (0 €) statt Mapbox/Google.
2. **Routing-Requests:** self-hosted = keine per-Request-Kosten (wichtig für Rerouting und später Rundtouren).
3. **Geocoding:** Photon self-hosted statt pro-Anfrage-Bezahl-APIs.
4. **Traffic-Polling:** sparsame Intervalle + Sparmodus (wichtig, sobald später ein Bezahl-Provider kommt).

## 5. Einmalkosten (nur beim echten öffentlichen Launch, nicht für MVP)

| Posten | Kosten | Zeitpunkt |
|---|---|---|
| Google Play Console | 25 $ einmalig | mit öffentlicher Android-Beta |
| Apple Developer | 99 $/Jahr | erst bei Budget-Freigabe |
| Markenrecherche + Anmeldung (DPMA, optional EU) | 300–1.500 € | aufgeschoben, vor öffentlichem Launch |
| Rechtliche Texte (Impressum, Datenschutz, AGB) | 0–500 € (Generatoren/Anwalt) | vor öffentlichem Launch |
