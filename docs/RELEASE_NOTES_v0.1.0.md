# MotoRoute v0.1.0 — erstes Release

Erste vollständige Version der Motorrad-Navigations-App. Diese Version enthält
App, Backend und den kompletten Weg von GitHub zu deinem Android-Smartphone —
ohne Google-Play-Store-Konto und ohne Play-Services-Abhängigkeit.

## Navigations-App (Flutter)

- **Karte**: MapLibre GL mit OpenStreetMap-Kacheln, Ortsuche (Ortsname/PLZ),
  Wegpunkte setzen, Zentrieren-Button
- **Routing**: Fahrzeugauswahl (Auto / Motorrad / Fahrrad), Streckenstile
  (schnell, kurvig, extra kurvig, schnell + kurvig, unbefestigt),
  Vermeidung von Autobahn, Fähren und Mautstraßen, Dauer + Entfernung in km
- **Navigation**: GPS-Tracking, Off-Route-Erkennung mit proaktivem Rerouting,
  Energiesparmodus während der Fahrt
- **Echtzeitverkehr** (TomTom): Vorfälle und Sperrungen auf der Route,
  automatische Umleitungsvorschläge
- **Wetter-Radar mit Sturm-Frühwarnung** (OpenWeatherMap): Unwetterwarnung mit
  Streckenabschnitt („In 20 km zieht ein Gewitter auf") und Vorschlägen für
  Schutz-POIs (Motorradhotels, Bikertreffs, Camping) in der Nähe
- **Community-Gefahrenradar**: Biker melden Rollsplitt, Sperrungen, Baustellen
  und Ölspuren mit zwei Klicks; Upvotes bestätigen Gefahren, Meldungen laufen
  nach 24 h ab
- **POIs auf der Karte**: Tankstellen, Motorradhotels, Bikertreffs,
  Campingplätze, Eisdielen, Blitzer — kuratiert, mit Sofort-Update über
  Socket.IO

## Chat & Community

- **Chat-System**: öffentlicher Chat, private Chats, Gruppen
- **Gemeinsame Routenplanung**: Gruppe plant eine Tour zusammen, Stopps und
  Wegpunkte in Echtzeit abstimmen
- **Live-Gruppenfahrt**: Fahrer teilen opt-in ihre Position, Gruppenmitglieder
  auf derselben Route sehen einander in Echtzeit — ohne Umkreis-Limit
- **Biker-Radar**: Biker im 15-km-Umkreis entdecken (Ghost-Mode = nicht
  sichtbar, Positionen nach 30 Minuten gelöscht)

## Technik

- Flutter-App (Riverpod, MapLibre), NestJS-Backend (Supabase-Auth, GraphHopper,
  TomTom, OpenWeatherMap), eigener POI-Dienst (Node.js, PostGIS, Socket.IO)
- **Kein Google Play Services, kein Firebase**: Karten (OSM), GPS
  (Android LocationManager), Login (Supabase) — läuft auf jedem Android-Gerät
- **83 App-Tests, 81 Backend-Tests, 17 POI-Dienst-Tests**

## Installation

APK unten herunterladen → öffnen → „Aus dieser Quelle installieren" erlauben
→ installieren. Vollständige Anleitung inkl. Updates und Keystore:
[docs/INSTALL.md](docs/INSTALL.md)

> **Hinweis für Updates**: Nach diesem ersten Release immer die Version in
> `motoroute_app/pubspec.yaml` erhöhen (z. B. `0.1.1+2`) und neu taggen —
> sonst verweigert Android das Update.
