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

- **Markenrecht „MotoRoute“:** Recherche durchgeführt 2026-10-10 (Ergebnis unten, §3.1). Code-seitig ist der Name zentral konfigurierbar (Display-Name in `apps/mobile/android/.../AndroidManifest.xml` + `apps/mobile/lib/app.dart`), Wechsel bis vor M6-Release kostengünstig möglich.

### 3.1 Markenrecherche-Status „MotoRoute“ (Stand 2026-10-10)

| Register/Quelle | Befund | Belastbarkeit |
|---|---|---|
| DPMAregister (DE) | Keine verifizierbare Wortmarke „MotoRoute“ (Aktenzeichen/Status) | Kein Nulltreffer-Garant: dynamische Suchoberfläche, keine agentengestützte Volltext-/Phonem-Suche; älterer EU-/IR-Marken beachten |
| EUIPO eSearch+/TMview (EU) | Keine verifizierbare EUTM-Eintragung | dito |
| WIPO Global Brand DB / J-PlatPat (JP) | Keine verifizierbare Eintragung; J-PlatPat nicht auslesbar | Vor-Launch erneut direkt prüfen |
| Apple App Store (JP) | Bekannte **App-Benutzung** des Namens: „MotoRoute: Motorcycle Rides“ (Entwickler Edward Felthuis, © 2026 TechVance) | App-Nutzung ≠ Markenanmeldung, aber belegt geschäftliche Benutzung unter der Marke |

**Risikobewertung:** Weder als sicher frei noch als konfliktfrei einzustufen. Der Name ist für eine Motorrad-Routing-App zudem beschreibungsnah („Moto“+„Route“) — die Eintragbarkeit (Unterscheidungskraft) ist separat zu prüfen.

### 3.2 Vor-Launch-Marken-Checkliste (abzuarbeiten vor Meilenstein M6/Release)

- [ ] **R1 – Direkt-Recherche DE:** DPMAregister (register.dpma.de): „MotoRoute“, „Moto Route“, „MOTOROUTE“ exakt + phonetisch ähnliche Varianten in Klassen 9/42/39 dokumentieren.
- [ ] **R2 – Direkt-Recherche EU:** EUIPO eSearch+ und TMview: gleiche Varianten + Verwechslungsgefahr-Prüfung gegen Navi-/Software-Marken.
- [ ] **R3 – Direkt-Recherche JP:** J-PlatPat (japanisches Amt): relevant wegen der bekannten App-Benutzung „MotoRoute: Motorcycle Rides“ (TechVance); bei geplantem EU-Launch nicht zwingend, aber Kollisionsrisiko dokumentieren.
- [ ] **R4 – Österreich + Schweiz:** Patentamt AT / IGE CH durchsuchen — **EU-Marke umfasst die Schweiz nicht**, DACH bleibt unvollständig ohne diese Prüfung.
- [ ] **R5 – App-Stores:** Abfragen auf apple.com/apps + Google Play nach gleich-/ähnlich benannten Navi-/Motorrad-Apps (Reputations- und Confusion-Risiko, nicht nur markenrechtlich).
- [ ] **R6 – Nicht eingetragene Rechte:** Nutzungsspur gleich-/ähnlich benannter Branchen-Apps + Unternehmenskennzeichen prüfen (Web, LinkedIn, Domain-Registrierungen).
- [ ] **R7 – Eintragbarkeits-Prüfung:** Unterscheidungskraft für Klassen 9/42/39 (beschreibungsnaher Charakter), i.d.R. mit Fachanwalt für IT-Recht oder Markenberatungsstelle.
- [ ] **R8 – Entscheidung dokumentieren:** Ergebnis („Name frei / mit Risiko / Wechsel nötig“) hier in §3.1 ergänzen; bei Namenswechsel Backup-Namen und Display-Name-Konfiguration umsetzen (Code-Seite vorbereitet, kein Engineering-Blocker).

- **Impressum/Provider-Kennzeichnung (TMG/DDG):** Standard, ab Beta.
- **Alters-/Fahrzeug-Bezug:** keine besonderen Anforderungen; App-Store-Rating unkritisch.
- **Geoblocking Umweltzonen (später):** Datenaktualität ist der eigentliche Risikoträger (Rechtslage ändert sich jährlich) – deshalb Phase 2+.

## 4. Checkliste vor produktivem Launch

1. [ ] Fachanwalt: AGB + Datenschutz + Haftungsausschluss (DACH-konform)
2. [ ] AVV mit Hoster, TomTom (falls aktiv), Sentry-Instanz
3. [ ] ODbL-Attribution + OSS-Lizenzscreen in App
4. [ ] Marken-Checkliste §3.2 (R1–R8) abgearbeitet und Ergebnis in §3.1 dokumentiert
5. [ ] Play Data-Safety-Formular ausgefüllt (muss mit `07-privacy-security.md` übereinstimmen)
6. [ ] Incident-Response-Plan dokumentiert: wer deaktiviert den Traffic-Provider bei Ausfall oder Lizenzproblemen innerhalb 24 h
