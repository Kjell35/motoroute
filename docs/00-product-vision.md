# MotoRoute – Produktvision

> Status: **Phase 1/2 abgeschlossen, wartet auf Freigabe** · Version 1.0 · Stand 2026-09-15
> Grundlage: Produktanforderungen des Auftraggebers (Kap. 1–12 des Briefings) + dokumentierte Annahmen.

## 1. One-Liner

**MotoRoute** ist eine professionelle Navigations-App für Motorradfahrer, die Routen nach **Fahrspaß und Straßencharakter** plant – nicht nur nach Geschwindigkeit.

## 2. Positionierung & Differenzierung

Klassische Navi-Apps (Google Maps, Apple Maps, OsmAnd, organic maps u. a.) optimieren auf Zeit und Distanz. MotoRoute optimiert auf das **Fahrerlebnis**:

| Differenzierungsmerkmal | Umsetzung |
|---|---|
| Fahrstile statt „schnellste Route" | 5 Fahrstile als echte Routing-Parameter (Kantenbewertung, nicht nur Alternativliste) |
| Motorrad-spezifische POIs | eigene POI-Domäne (Biker-Treffs, Motorradhotels), später community-erweiterbar |
| Stabile Präferenzen bei Rerouting | Neuberechnung behält Fahrstil + Vermeidungen zwingend bei (Produktregel, geprüft im Code) |
| Eigenständige Premium-Visualität | eigenes Design-System „Midnight Asphalt", keine Google-Maps-Kopie |

## 3. Zielgruppen

| Segment | Kernbedürfnis | Priorität |
|---|---|---|
| Tagestourer (DACH) | „Schnell & kurvig", Tankstopps, Treffpunkte | P0 |
| Sportfahrer | „Extra kurvig", später Kurven-Score, GPX-Austausch | P1 |
| Tourer/Reisende | Rundtouren, Hotels, Camping, später Wetter | P1 |
| Pkw-/Alltagsnutzer | zuverlässige Navigation + Vermeidungen | P1 (Sekundärmodus) |
| Fahrrad/Gravel | unbefestigte Straßen, Verkehr meidend | P2 |
| Community | Teilen, Bewerten, Gefahrenmeldungen | P2 (Phase 2+) |

## 4. Produktprinzipien (verbindlich für alle Entscheidungen)

1. **Fahrspaß ist ein Routing-Parameter, kein Zusatzmodus.** „Kurvig" verändert die Routenbewertung selbst, nicht nur die Reihenfolge von Alternativen.
2. **Präferenzen sind stabil.** Jede Neuberechnung (auch bei Verkehr) nutzt dasselbe Routen-Profil wie die Ursprungsroute.
3. **Weniger ist mehr während der Fahrt.** Die Navigationsansicht zeigt nur fahrtrelevante Informationen; alles Weitere lebt in nicht-fahrtaktiven Screens.
4. **Fahrzeugtyp ist Routing-Input, kein Icon.** Motorrad / Auto / Fahrrad wählen unterschiedliche Routing-Profile, Zugriffsebenen und Geschwindigkeitsmodelle.
5. **Datenschutz by design.** Der Standort verlässt das Gerät nur für Routing/POI-/Traffic-Abfragen und wird serverseitig nicht persistiert.
6. **Ablösbarkeit.** Karten- und Routing-Anbieter hängen nur hinter definierte Adapter-Interfaces (Ports & Adapters); kein Vendor-Lock-in der Produktlogik.
7. **Keine Fake-Daten.** Jede noch nicht produktive Funktion ist im Code klar als `TODO`/`UNIMPLEMENTED` gekennzeichnet statt simuliert.

## 5. Erfolgskriterien MVP (messbar)

| Kriterium | Zielwert |
|---|---|
| GPS Time-to-First-Fix (im Freien) | < 10 s |
| Routenberechnung (bis 600 km, Empfang der Geometrie) | < 4 s (p95) |
| Rerouting nach Off-Route-Erkennung | < 5 s bis neue Guidance aktiv |
| Positions-Update-Rate während Navigation | ≥ 1 Hz |
| App-Kaltstart bis interaktive Karte | < 3 s |
| Absturzrate (Sessions mit Crash) | < 0,3 % |
| Touch-Ziele in Fahrtscreens | ≥ 56 dp, Kontrast ≥ 4,5:1 |

## 6. Annahmen

- Zielmarkt zuerst **DACH** (Datenqualität OSM, Motorrad-Dichte), danach EU-Erweiterung.
- Startplattform: **Android** (Beschluss 2026-09-15). Flutter hält die iOS-Option technisch offen; ein iOS-Port ist eine spätere, separate Entscheidung (siehe `11-costs.md`).
- Monetarisierung: **keine** (Zero-Budget-/Kostenlos-Beschluss 2026-09-15). Ein Entitlement-Hook bleibt vorgesehen, wird aber nicht implementiert; falls später doch ein Modell kommt, ist das eine neue Entscheidung.
- 1 Entwickler (Auftraggeber) + AI-Assistenz als Team-Annahme für den Plan; der Plan skaliert aber auf 2–3 Personen.

## 7. Entscheidungen & offene Fragen

1. **Entschieden (2026-09-15, Zero-Budget):** Die App ist kostenlos und ohne bezahlte Dienste umzusetzen. Traffic im MVP = OSM-Sperrungen (ehrlich gekennzeichnet); Echtzeit-Traffic (TomTom) ist aufgeschoben, Port bleibt vorbereitet. Details: `11-costs.md`.
2. Markenname „MotoRoute": Markenrecherche nötig (DPMA/EUIPO) vor Launch; Arbeitstitel im Code ist austauschbar (App-Display-Name zentral konfiguriert).
3. **Entschieden:** Keine Monetarisierung im MVP (keine Abos, keine „Plans"). Ein Entitlement-Hook bleibt architektonisch vorgesehen, wird aber nicht implementiert.
