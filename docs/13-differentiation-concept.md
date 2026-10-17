# MotoRoute – Differenzierungskonzept: Wie MotoRoute die Konkurrenz übertrifft

> Status: Empfehlung zur Prüfung · Version 1.0 · Stand 2026-10-10
> Grundlage: Web-Recherche vom 10.10.2026 (drei vertiefte Realtime-Recherchen: Wettbewerbslandschaft, Nutzerbeschwerden 2024–2026, technische Nischen), interne Analyse (`LINIEN_VERGLEICH.md`, Revision 2) und bestehende interne Standards (00-product-vision, 06-ux-safety, 08-energy-saving, 09-mvp-plan).

---

## 1. Marktbefund: Die Konkurrenz ist spezialisiert, nicht integrativ

### 1.1 Wettbewerbslandschaft in Kürze

| App | USP | Herausforderung (belegt in Store-/Forum-Befunden) |
|---|---|---|
| Calimoto | Kurven-Routing | Ortsdurchfahrten im „Kurvig“-Profil, Handschuhbedienung, keine Traffic-Warnungen |
| Kurviger | UX-Stabilität, Cloud-Sync | GPS-/Tracking-Probleme (Juli-2025-Rezension), Premium-Kernfunktionen |
| Scenic | Offline, iPad-/Planungsorientierung | Admins bestätigen im Forum: **keine Traffic-Integration** |
| REVER | Butler-Maps, Community | App-Instabilität (Mai-2025-Rezension), Abo-Muster |
| Cardo Ride | Gruppen, Intercom-Ökosystem | Hardware-/Abo-Bindung |
| Detecht | Crash-Erkennung | Download-/Verfügbarkeitsschwächen, Premium-Grenzen |
| MotoRoute (Japan) | Einmalkauf, kein Abo | Sehr schlichter Funktionsumfang |

→ **Lücke im Markt:** Kein Angebot verbindet Kurven-Routing + Verkehr/Sperrungen + Wetter entlang der Route + motorradspezifische Gefahrenmeldungen in **einer** App ohne Bezahl-Hürde im Kern – das ist die offene Position, die MotoRoute besetzt.

**Namenshinweis:** Es existiert bereits eine japanische iOS-App „MotoRoute“; Markenrecherche (DPMA/EUIPO) vor Launch ist Pflicht (steht in 00-product-vision.md §7).

### 1.2 Top-Schmerzpunkte bei den Wettbewerbern (2024–2026)

| Rang | Schmerzpunkt | Belegt bei |
|---|---|---|
| 1 | Unzuverlässige/unpassende Routen (falsches Abbiegen, ungeeignete Straßen) | Calimoto, Scenic, Kurviger |
| 2 | App-/GPS-/Tracking-Zuverlässigkeit | Kurviger (Juli 2025), REVER (Mai 2025) |
| 3 | Fehlende Echtzeit-Traffic-/Sperrungsdaten | Scenic (by Design), Calimoto, REVER |
| 4 | Bedienbarkeit/Ablenkung während der Fahrt (Handschuhbedienung, Kartenübersicht) | Calimoto, breiter über Apps vertreten |
| 5 | Akkubelastung/Wärmeentwicklung | alle Anbieter (warnen selbst in Store-Dokumentation) |
| 6 | Abo-Frust (Kern-Navigation hinter Premium) | Calimoto, REVER, Scenic, Detecht, Kurviger |

### 1.3 Technische Nischen (ohne Hardware-Zwang umsetzbar)

- **Kurven-Score pro Segment** – CurveScorer v1 ist in M3 bereits vorgesehen; Segment-Highlights bieten die Wettbewerber nicht.
- **Schräglage per Smartphone** (Formel φ ≈ arctan(v·ω/g)) – bisher nur OEM-Apps (Pirelli, BMW Connected); als marken-unabhängiges Feature mit ehrlichem Qualitätsmarker unbesetzt.
- **Community-Gefahrenmeldungen mit Motorrad-Typologie** – REVER/BARRACUDA und Waze existieren, aber ohne Splitt/Diesel/Laub/Schotter-Kategorien.
- **Wetter entlang der Route** – OpenWeather Road Risk API liefert Temperatur, Regenrate und weitere Messwerte (OpenWeather Add-on-Modell, EU/US); als integrierte Route-Warnung unbesetzt.
- **Intercom-SDKs sind nicht öffentlich** (Cardo/Sena) – Integrationsstrategie: OS-Bluetooth-Audio + TTS statt proprietärer SDK-Versprechen.

---

## 2. Strategie: Konvergenz statt Feature-Liste

Wir konkurrieren nicht frontal gegen Google Maps und nicht allein „nur kurvig“ gegen Calimoto. Die Positionierung ist die **Verknüpfung vierer Themen** in einer App, die bei Wettbewerbern einzeln existiert, aber nie zusammen:

- **A – Kurven-Routing** mit aktiver Plausibilitäts-Kontrolle (kein „Kurvig um jeden Preis um die Häuser“)
- **B – Wetter/Grip-Warnungen entlang der Route** (zeitlich und geografisch aufgelöst, nicht nur Start/Ziel)
- **C – Motorradspezifische Gefahrenmeldungen** (Splitt, Dieselfilm, Laub, Schotter, Wildwechsel) mit Verfall-/Bestätigungs-Mechanik
- **D – Gruppen-Live-Position ohne Hardware-Lock-in** (nach aktuellem Recherche-Stand das andere Ende des Marktes: kein Intercom-SDK-Zwang, kein Abo)

MotoRoute arbeitet bewusst auf der Nische **„Ich will die kurvige Route, die mir nichts vorhält“** – nicht auf der Nische „noch mehr Features als die anderen“.

---

## 3. Konkrete Features mit Umsetzungs-Check

Prüfpunkt je Feature: implementierbar bei Zero-Budget und auf der vorhandenen/geplanten MVP-Infrastruktur (Valhalla, Overpass, PostGIS, Postgres).

### 3.1 Tier 1 – „Kurven trifft Kontext“ (Produkt-Identität)

| Feature | Was es tut | Warum es gewinnt | Implementierbar | Technik |
|---|---|---|---|---|
| **CurveScore v2 mit Segment-Highlights** | Kurvenscore pro Streckenabschnitt; im Route-Preview farbig markiert | Calimoto/Scenic/Kurviger zeigen, wenn überhaupt, nur einen Gesamtscore | ✔ (M3-Pflichtpunkt) | Valhalla-Edge-Attribute + CurveScorer v→v2 |
| **Ortsdurchfahrten-Meidung** | „Kurvig“-Profil meidet OSM-Ortskerne (place=village/town/suburb) als einstellbare Präferenz | Adressiert den häufigsten Calimoto-Befund direkt; keine App bietet das als einstellbare Regel | ✔ (M3-Erweiterung) | Valhalla-Costing + OSM-Ortsdaten (Avoid-Regeln) |
| **Sperrungs- und Baustellen-Layer** | OSM-/Verkehrsnahe Sperrungen entlang der Route | Scenic bestätigt im Forum offiziell: „keine Traffic-Integration“ | ✔ (M5-geplant) | Valhalla-Traffic-Layer / Overpass-Abfrage |
| **TTS-„Kurven-Ansage“** | „In 500 m 6 Kurven – Blick behalten“ | Kein Wettbewerber macht kurvigeart-spezifische Sprachansagen | ✔ (M4-Erweiterung) | flutter_tts + CurveScorer-Events |

### 3.2 Tier 2 – „Biker-Waze-Layer“ (Sicherheits-Differenzierer)

| Feature | Was es tut | Warum es gewinnt | Implementierbar | Technik |
|---|---|---|---|---|
| **Motorrad-Gefahrenmeldungen** | Splitt/Gravel, Diesel/Öl, Laub, Schotter-Übergänge, Wildwechsel, „Baustelle, dreckige Fahrbahn“ | Waze kennt diese Motorrad-Kategorien **nicht**; REVER/BARRACUDA existiert, ist aber nicht Motorrad-zugeschnitten | Phase 2 (Backend-Feld in MVP vorbereiten) | PostGIS-Punkt-Layer + Kategorie-Codes + Rate-Limit |
| **Meldungs-Qualitätsmechanik** | Verfall nach Zeit/Fahrten, Bestätigung erhöht Priorität, Falschmeldungen verfallen | Crowd-Reports leben/sterben an der Falschmeldungs-Bewältigung | Phase 2 | PostGIS TTL + Bestätigungs-Counter |
| **Wetter- und Fahrbahn-Risiken entlang der Route** | „Regen ab km 47 in ca. 20 min“, „Fahrbahntemperatur < 5 °C“ | Konkurrenz zeigt Wetter nur für Start/Ziel; Routing-Integrierte Risiko-Anzeige entlang der Route gibt es bei keinem Wettbewerber | Phase 2a (Free-Tier der API unverifiziert) | Route-Sampling + OpenWeather Road Risk API |

### 3.3 Tier 3 – „Gruppe ohne Lock-in“ (Community-Differenzierer)

| Feature | Was es tut | Warum es gewinnt | Implementierbar | Technik |
|---|---|---|---|---|
| **Gruppen-Live-Position ohne Hardware-Zwang** | Live-Standort aller Gruppenmitglieder, unabhängig vom Headset | Cardo Ride/Sena Wave binden Hardware-Ökosysteme; REVER will dafür ein Abo | Phase 2 | Realtime-Kanal auf eigenem Backend (WebSocket) – kein proprietäres SDK |
| **Nachzügler-Erkennung** | Wer hängt ab? Wer macht Pause? | „Riding behind“ gibt es nur bei Cardo Ride (Hardware-gebunden) | Phase 2 | Positions-Delta-Monitoring auf Server |

### 3.4 Tier 4 – Fahrmetriken mit Vertrauensmarker

| Feature | Was es tut | Warum es gewinnt | Implementierbar | Technik |
|---|---|---|---|---|
| **Schräglagen-Indikator (Smartphone)** | IMU/GPS-Schätzwert mit explizitem ** Qualitätsmarker** („Schätzung“, Konfidenz) – Authentizität statt Scheinpräzision | Pirelli/BMW Connected leisten das nur in OEM-Apps; niemand zeigt die Grenzen der Messung offen | Phase 2b | Sensor-Stream + Formel φ ≈ arctan(v·ω/g); Anzeige NUR nach Fahrt (nicht live während Fahrt) |
| **Ride-Log + Kurvenanalyse** | Score pro Segment + Deeplink „Zeig mir diesen Abschnitt auf der Karte“ | Keine App verlinkt Fahrt-Statistik mit der Route selbst | Phase 2b | Sensor-Stream + Segment-Matching (Vorbereitung in M3) |

### 3.5 Einreihung in den bestehenden MVP-Plan

Der aktuelle MVP-Plan (docs/09-mvp-plan.md, M0–M6) bleibt Maßstab. Die Differenzierungs-Features werden **hinter die bestehenden Gate-Kriterien** eingereiht – nichts kippt einen bestehenden Meilenstein:

| Feature | Slot | DoD |
|---|---|---|
| CurveScore v2 mit Segment-Highlights | M3-Erweiterung | Route-Preview zeigt kurvige Segmente farbig hervorgehoben |
| Ortsdurchfahrten-Meidung | M3-Erweiterung | Kurvig-Profil meidet OSM-Ortskerne; Test mit Referenz-Route |
| TTS-Kurven-Ansage | M4-Erweiterung | Sprachausage nennt Kurvenanzahl des kommenden Segments |
| Gefahrenmeldungen (nur lesbar) | M5-Erweiterung | Layer-Toggle mit 7 Motorrad-Kategorien, noch ohne Crowd-Reports |
| Wetter entlang der Route | Phase 2a | Prognose pro Streckenabschnitt |
| Schräglagen-Schätzer + Ride-Log | Phase 2b | Ride-Log zeigt CurveScore pro Segment; Qualitätsmarker sichtbar |

---

## 4. Anti-Konkurrenz: Was wir bewusst NICHT tun

| Vermeidung | Warum |
|---|---|
| Kern-Navigation nie paywallen | Das ist der #1-Frust in Reviews aller Wettbewerber |
| Kein „Pro“-Modus mit versteckten Kernfunktionen | Feature-Stripping macht die App wertlos |
| Kein Intercom-SDK-Lock-in | Cardo/Sena SDKs sind nicht öffentlich dokumentiert; wir arbeiten über OS-Bluetooth-Audio + TTS |
| Keine simulierten „Fake-Daten“ | Produktprinzip 7: Unproduktive Funktionen bleiben ehrlich gekennzeichnet |
| Keine „Kurvig um jeden Preis“-Routes | Kurvig ≠ langsam/durch Dörfer – das Kurvig-Profil muss kurvenreich über Landstraßen bleiben, nicht Umwege erzwingen |

---

## 5. Fazit

Die Recherche zeigt: Die Konkurrenz ist **breit, aber nicht integrativ**. Calimoto/Kurviger/Scenic optimieren auf Kurven; REVER/Cardo auf Community; Detecht/EatSleepRIDE auf Sicherheit. **Kein Anbieter verbindet** Kurven-Routing + Verkehr/Sperrungen + Wetter entlang der Route + Motorrad-Gefahren-Typologie + Gruppen ohne Hardware-Lock-in – und kostenlos dazu. MotoRoute kann diese Konvergenz als Identität besetzen und die Abo-Frust-Top-Schmerzpunkte aktiv vermeiden.

Ein klassischer „Feature-Checklisten-Vorteil“ reicht nicht: MotoRoute sollte ab Tag 1 die Frage in 4 Sekunden beantworten: **„Ich will die kurvige Route, die mir nichts vorhält.“**

**Tagline-Kandidat:** „Ride smarter, not richer.“

---

## 6. Verifikations-Grenzen

- Befunde sind qualitative Web-Recherche vom 10.10.2026; konkrete Effektivpreise (Calimoto/Kurviger-Abos) ließen sich aus den geöffneten Seiten nicht belastbar auslesen – sollten separat verifiziert werden.
- „Implementierbar“-Checks sind Planungsannahmen, kein Prototyp: Free-Tier-Limits der OpenWeather Road Risk API und die Effektivität der Valhalla-Avoidance für Ortsdurchfahrten sind **ungeprüft** und müssten in einem M3-Spike bestätigt werden.
- Der beschriebene Feature-Umfang **überschreitet** den MVP-Scope M0–M6 – Einreihung „hinter bestehende M-Gates“ ist ein Vorschlag dieses Dokuments, kein Beschluss.
- Namenskollision „MotoRoute“ (japanische iOS-App) ist erkannt, aber nicht abgesichert; DPMA/EUIPO-Check steht aus (steht bereits in 00-product-vision.md §7).

## 7. Empfohlene nächste Schritte

1. MVP-Plan M0–M6 ausführen; die vier Tier-1-Erweiterungen (CurveScore v2, Ortsdurchfahrten-Meidung, TTS-Kurvenansage, Sperrungs-Layer) in M3/M4/M5 einverleiben.
2. Nach M6: OpenWeather-Road-Risk-API-Spike + PostGIS-Schema für Motorrad-Gefahren-Typologie anlegen.
3. Phase 2: Gefahrenmeldungen + Wetter-Konvergenz + Gruppen-Live-Position als identitätsstiftender „Biker-Waze-Layer“.
4. Parallel: Markenrecherche „MotoRoute“ (DPMA/EUIPO), da ein japanisches iOS-Produkt den Namen bereits nutzt.
5. Tagline „Ride smarter, not richer“ als Marketing-Platzhalter testen.
