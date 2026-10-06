# MotoRoute – Rechtliche & lizenzrechtliche Risiken

> Status: Risikoregister · Version 1.0 · Stand 2026-09-15
> **Disclaimer:** Keine Rechtsberatung. Vor Go-live: Fachanwalt für IT-Recht/Datenschutz prüfen lassen.

## 1. Lizenzen der Kernbausteine

| Baustein | Lizenz | Folge für uns |
|---|---|---|
| OSM-Daten | **ODbL 1.0** | Nutzung frei, aber **ShareAlike**: Bei Ableitung der Daten (z. B. eigene POI-DB aus OSM) müssen Ableitungen unter ODbL bleiben. **Wichtig:** Reine „Produktion über OSM“ (Routing/Tiles rendern) ist keine Derivate-Pflicht – aber eigene angereicherte POI-Datenbanken können als Derivat gelten. Struktur: OSM-Anteil und kuratierte Eigen-Daten **getrennt** halten (deshalb `pois.source` im Schema). |
| MapLibre (Native + Flutter-Plugin) | BSD-2 | frei, auch kommerziell; Attribution nötig |
| Valhalla | BSD-2 | frei; Attribution + ODbL-Datenhinweis nötig |
| Photon/Nominatim | Apache-2.0 / ODbL-Daten | Nominatim-*Usage-Policy* gilt für public-Instanzen – self-hosted umgeht das; Photon-Ergebnisse basieren trotzdem auf ODbL-Daten |
| OpenFreeMap | MIT (Software), Daten ODbL | kommerziell ok; Bedingung: OSM-Attribution im Karten-Credits |
| Inter (Font) | SIL OFL | frei, auch in Apps |
| GraphHopper (Fallback) | Apache-2.0 (Engine) | self-hosted frei; **Cloud-API nicht kommerziell im Free-Plan** |

**Pflicht (M6):** Attributions-Screen („Karten Daten © OpenStreetMap Contributors (ODbL)“ etc.) + Lizenzbildschirm für OSS-Pakete (Flutter: `LicensePage`).

## 2. Hohe Risiken

| # | Risiko | Bewertung | Maßnahme |
|---|---|---|---|
| 1 | **Blitzer-Warnungen** | In Frankreich, Schweiz (teilweise), u. a. verboten; Abmahn-/Strafrisiken für Betreiber | MVP: Feature **nicht** umsetzen; Phase 4 mit Geo-Fencing pro Land (deaktiviert in gesperrten Ländern) + Rechtscheck vorher |
| 2 | **ODbL-ShareAlike** bei kuratierten POI-Daten | mittel bis hoch (je nach Verflechtung) | saubere Daten-Trennung (`source`-Attribut), Anwaltliche Prüfung vor Community-Phase |
| 3 | **Navigations-Haftung** | Fahrer verlässt sich auf Route (z. B. unbefestigt ungeeignet) | AGB: Hinweispflicht „Straßenverhältnisse selbst prüfen“, Disclaimer bei `unpaved`-Stil, keine rechtswidrigen Routen (Einbahn/Verbotseinschränkungen respektiert via Routing-Daten) |
| 4 | **TomTom/HERE-Lizenzbedingungen** | Redistributons-Bedingungen (Attribution, Keine Weitergabe von Rohdaten), Preisänderungen | **im MVP nicht aktiv (Zero-Budget)**; bei späterer Aktivierung: AVV vorher abschließen; Traffic-Port macht Wechsel billig |
| 5 | **DSGVO** | Standort = personenbezogen | Konzept in `07-privacy-security.md`; AVVs (Hoster, TomTom, Sentry); Privacy-Policy ab Beta |
| 6 | **Store-Regularien (Google Play)** | Standort-Hintergrundnutzung, Foreground-Service-Deklaration (Android 14+), Data-Safety-Formular | MVP bewusst „While-In-Use“ + sichtbare Service-Notification; Hintergrund-Location als Phase 2 mit sauberem Review-Case |

## 3. Mittlere Risiken

- **Markenrecht „MotoRoute“:** DPMA/EUIPO-Recherche vor Launch; Kollisionen im Navi-Bereich möglich. Code-seitig ist der Name zentral konfigurierbar.
- **Impressum/Provider-Kennzeichnung (TMG/DDG):** Standard, ab Beta.
- **Alters-/Fahrzeug-Bezug:** keine besonderen Anforderungen; App-Store-Rating unkritisch.
- **Geoblocking Umweltzonen (später):** Datenaktualität ist der eigentliche Risikoträger (Rechtslage ändert sich jährlich) – deshalb Phase 2+.

## 4. Checkliste vor produktivem Launch

1. [ ] Fachanwalt: AGB + Datenschutz + Haftungsausschluss (DACH-konform)
2. [ ] AVV mit Hoster, TomTom (falls aktiv), Sentry-Instanz
3. [ ] ODbL-Attribution + OSS-Lizenzscreen in App
4. [ ] Markenrecherche „MotoRoute“ (DPMA + EUIPO + übliche App-Stores)
5. [ ] Play Data-Safety-Formular ausgefüllt (muss mit `07-privacy-security.md` übereinstimmen)
6. [ ] Incident-Response-Plan dokumentiert: wer deaktiviert den Traffic-Provider bei Ausfall oder Lizenzproblemen innerhalb 24 h
