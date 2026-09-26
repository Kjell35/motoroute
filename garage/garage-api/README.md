# 🏁 Garage-API

Eigenständiges Fahrzeuggarage-Backend: Motorräder und Autos verwalten, technische
Daten aus einer zentralen Fahrzeugdatenbank, Wartung mit automatischen
Erinnerungen, Reifen, Tankbuch, Dokumente — komplett über eine dokumentierte
REST-API.

**Bewusst unabhängig:** Keine Abhängigkeit zu MotoRoute. Eine spätere Anbindung
erfolgt ausschließlich über die HTTP-API (siehe unten, „Anbindung an MotoRoute").

---

## 1. Features

| Bereich | Umfang |
|---|---|
| **Fahrzeuge** | Nur 🏍️ Motorrad und 🚗 Auto. Mehrere Fahrzeuge pro Benutzer, Foto, Spitzname, Kilometerstand-Update |
| **Technische Daten** | Zentrale Katalog-DB (Manufacturer → Model → Variant → Specs). Beim Anlegen wird die Variante verknüpft, Specs werden ausgeliefert — der Benutzer tippt sie nicht ab. Elektro: Batterie, Reichweite, Ladeleistung, Ladezeit |
| **Wartung** | 17 vorkonfigurierte Typen (Ölwechsel … HU/TÜV … Sonstige) mit Standard-Intervallen, Historie chronologisch, Kosten je Eintrag |
| **Erinnerungen** | Automatisch aus_km_ UND/ODER _Tagen_: 🟢 ok / 🟡 bald (≤ 14 Tage oder ≤ 500 km) / 🔴 überfällig |
| **Kosten** | Pro Jahr, gesamt, pro Fahrzeug — aus den Wartungseinträgen |
| **Reifen** | Sätze vorne/hinten, Montage-Datum + km-Stand, Profil; Erinnerung via `replacementDueDate` |
| **Tankbuch** | Einträge mit Liter/Preis/Stationsname; Verbrauch (l/100 km) und Kosten/km werden berechnet |
| **Dokumente** | Referenzen auf private Dateien (Base64-Upload durch den späteren Client oder URL); **niemals** in öffentlichen Antworten |
| **Privatsphäre** | Kennzeichen, Kaufpreis, Kaufdatum, Notizen sind privat — es gibt **keine** öffentlichen Fahrzeug-Endpunkte. Sharing-Flag `isPublic` ist vorbereitet (default `false`) |
| **Admin** | Katalog-Verwaltung: Hersteller/Modelle/Varianten/Specs/Baujahre, Fahrzeuge deaktivieren |
| **API-Doku** | OpenAPI 3.0 JSON unter `/api/docs` + **Swagger UI** unter `/api/docs/ui` |

## 2. Tech-Stack

- **Node.js 20+ / TypeScript (strict)**
- **Express 4** — schlanke REST-Schicht
- **Prisma + PostgreSQL** — eigene Datenbank
- **JWT (HS256) + bcrypt (12 Runden)** — Access-Token 12 h, Refresh-Token 30 Tage (Rotation)
- **Jest** — 18 Unit-Tests (Erinnerungslogik, Verbrauch, Privatsphäre, Wartungskatalog)
- **zod** — env-Validierung (keine stillen Defaults bei Pflicht-Werten)

## 3. Installation

```bash
cd garage/garage-api
npm install
cp .env.example .env          # Werte eintragen (siehe Abschnitt 5)

# Datenbank-Schema anlegen (migrations)
npx prisma migrate dev --name init

# optional: Katalog-Startdaten (BMW, Yamaha, VW, Toyota + Specs)
npm run seed

# Entwicklung
npm run dev                   # ts-node-dev auf :4100

# Produktion
npm run build && npm start
```

**PostgreSQL bereitstellen** — lokal per Docker:

```bash
docker run -d --name garage-db -p 5432:5432 \
  -e POSTGRES_USER=garage -e POSTGRES_PASSWORD=garage -e POSTGRES_DB=garage \
  postgres:16
```

oder gehostet (Neon, Supabase Postgres, Railway): nur `DATABASE_URL` eintragen.

## 4. Datenbankstruktur (Prisma-Modelle)

```
User                 id, email (unique), passwordHash, displayName, role (user|admin), refreshToken
Manufacturer         id, name (unique), country, vehicleTypes, isActive
Model                id, manufacturerId, name, vehicleType (MOTORCYCLE|CAR), isActive
Variant              id, modelId, name, yearFrom, yearTo, isActive
VehicleSpec          variantId (unique), kind (COMBUSTION|ELECTRIC), engine, displacementCc,
                     powerHp, torqueNm, fuelType, gearbox, weightKg, tankLiters,
                     consumption, topSpeedKmh, accelerationSec, drive,
                     tireSizesFront/Rear, brakes,
                     batteryKwh, rangeKm, chargingKw, chargingTime   ← nur Elektro
Vehicle              id, userId, category, manufacturerId, modelId, variantId?, year,
                     firstRegistration?, odometerKm, color?, nickname?,
                     licensePlate? 🔒, purchaseDate? 🔒, purchasePrice? 🔒, notes? 🔒,
                     photoUrl?, isPublic (default false), isActive
MaintenanceRecord    id, vehicleId, typeKey, performedAt, odometerKm, nextDueDate?,
                     nextDueKm?, notes? 🔒, cost?
TireSet              id, vehicleId, manufacturer, model, size, position (front|rear),
                     mountedAt, mountedOdometerKm?, treadMm?, notes? 🔒,
                     replacementDueDate?
FuelEntry            id, vehicleId, date, odometerKm, liters, totalPrice, stationName?
Document             id, vehicleId, title, kind (invoice|inspection|tuv|other),
                     url/contentBase64 🔒, mime?
```

🔒 = privat, verlässt das Backend in anderen Nutzern sichtbaren Kontexten nie.
Integrität: Foreign Keys mit `onDelete: Cascade` (Fahrzeug löschen ⇒ Wartungen,
Reifen, Tankbuch, Dokumente mit weg).

### Seed-Katalog (Start, erweiterbar)

| Hersteller | Modelle |
|---|---|
| BMW | R 1250 GS (2019–), S 1000 RR |
| Yamaha | MT-07, MT-09 |
| Volkswagen | Golf 8 (2019–) |
| Toyota | Corolla (E210) |

mit echten Eckdaten (z. B. R 1250 GS: 1254 cm³, 136 PS, 143 Nm, 30 l Tank,
23,6 m³/h …; Golf 8 1.5 eTSI: 150 PS, 250 Nm …). Der Admin erweitert frei
über `/api/admin/*`.

## 5. Environment Variables

| Variable | Pflicht | Bedeutung |
|---|---|---|
| `DATABASE_URL` | ✅ | Postgres-Connection-String |
| `JWT_SECRET` | ✅ | ≥ 32 Zeichen, zufällig. Erzeugen: `node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"` |
| `PORT` | – | Default 4100 |
| `NODE_ENV` | – | `development` / `production` |
| `REFRESH_TOKEN_TTL_DAYS` | – | Default 30 |
| `ACCESS_TOKEN_TTL_HOURS` | – | Default 12 |
| `CORS_ORIGIN` | – | Komma-separierte erlaubte Origins; Default `*` |
| `SWAGGER_ENABLED` | – | Default `true`; in Produktion ggf. `false` |

Fehlt eine Pflicht-Variable, **verweigert der Server den Start** (zod-Validierung) —
keine stillen Defaults.

## 6. API-Überblick

Basis-URL: `http://localhost:4100` · alle Antworten JSON · Fehlerformat:

```json
{ "error": { "code": "VALIDATION", "message": "…", "details": {} } }
```

Codes: `VALIDATION` (400), `AUTH` (401), `FORBIDDEN` (403), `NOT_FOUND` (404),
`CONFLICT` (409), `SERVER` (500).

### Auth

| Methode | Pfad | Beschreibung |
|---|---|---|
| POST | `/api/auth/register` | `{email, password, displayName}` → User + Tokens |
| POST | `/api/auth/login` | `{email, password}` → Tokens |
| POST | `/api/auth/refresh` | `{refreshToken}` → neue Tokens (Rotation) |
| POST | `/api/auth/logout` | refresh-Token invalide machen |

### Fahrzeuge

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/vehicles?category= MOTORCYCLE\|CAR` | eigene Garage (Gruppierung motos/cars, Erinnerungs-Zusammenfassung je Fahrzeug) |
| POST | `/api/vehicles` | anlegen (`manufacturerId`, `modelId`, `variantId` aus dem Katalog) |
| GET | `/api/vehicles/:id` | Detail **inkl. technischer Daten** (aus `VehicleSpec` der Variante) |
| PUT | `/api/vehicles/:id` | aktualisieren (auch `odometerKm` — Anforderung „Kilometerstand aktualisieren") |
| DELETE | `/api/vehicles/:id` | löschen (kaskadiert) |
| GET | `/api/vehicles/:id/specifications` | nur die technischen Daten |

### Wartung & Erinnerungen

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/vehicles/:id/maintenance` | Historie, chronologisch (neueste zuerst), Summe der Kosten |
| POST | `/api/vehicles/:id/maintenance` | Eintrag erfassen; `nextDueDate`/`nextDueKm` optional — fehlen sie, berechnet der Server sie aus dem Standard-Intervall des Typs |
| PUT | `/api/maintenance/:recordId` | nachtragen/korrigieren |
| DELETE | `/api/maintenance/:recordId` | löschen |
| GET | `/api/vehicles/:id/reminders` | Statusliste 🟢🟡🔴 je Wartungstyp (km- UND Zeitanteil, der dringendere gewinnt) |
| GET | `/api/vehicles/:id/costs?year=2026` | Summen: dieses Jahr, gesamt, je Typ |

### Reifen / Tankbuch / Dokumente

| Methode | Pfad |
|---|---|
| GET / POST | `/api/vehicles/:id/tires` · DELETE/PUT `/api/tires/:tireId` |
| GET / POST | `/api/vehicles/:id/fuel` — berechnet bei zwei aufeinanderfolgenden Einträgen Verbrauch (l/100 km) und Kosten/km |
| GET / POST | `/api/vehicles/:id/documents` · DELETE `/api/documents/:docId` |

### Katalog & Suche (für die Fahrzeug-Anlage)

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/api/catalog/manufacturers?type=MOTORCYCLE` | nur aktive, mit Modellanzahl |
| GET | `/api/catalog/manufacturers/:id/models` | Modelle eines Herstellers |
| GET | `/api/catalog/models/:id/variants` | Varianten + Baujahresspanne |
| GET | `/api/catalog/models/:id/specs` | techn. Daten des Modells (aggregiert) |
| GET | `/api/catalog/search?q=r1250&type=MOTORCYCLE&year=2024` | kaskadierte Suche: „BMW → R 1250 GS → 2024" |
| GET | `/api/catalog/maintenance-types` | die 17 Wartungstypen + Standard-Intervalle |

### Admin (Rolle `admin`)

| Methode | Pfad |
|---|---|
| POST | `/api/admin/manufacturers` · PUT `/api/admin/manufacturers/:id` |
| POST | `/api/admin/manufacturers/:id/models` · PUT `/api/admin/models/:id` |
| POST | `/api/admin/models/:id/variants` · PUT `/api/admin/variants/:id` |
| PUT | `/api/admin/variants/:id/specs` (upsert) |
| GET | `/api/admin/vehicles` (alle Benutzer, Administration) |
| DELETE | `/api/admin/vehicles/:id` (deaktivieren = `isActive=false`, nicht zerstören) |

Admin machen (per SQL auf der Garage-DB):

```sql
UPDATE "User" SET role = 'admin' WHERE email = 'du@example.com';
```

## 7. Erinnerungslogik (im Detail)

Ein Wartungstyp hat ein Standard-Intervall `intervalKm` und/oder `intervalDays`
(siehe `src/common/maintenance-types.ts`, z. B. `OIL_CHANGE`: 10.000 km **oder**
365 Tage; `HU`: 730 Tage). Beim Erfassen ohne explizites „nächstes fällig"
berechnet der Server `nextDueOdometerKm = odometerKm + intervalKm` bzw.
`nextDueDate = performedAt + intervalDays`.

Wichtig: Wartungstypen werden in **GROSSBUCHSTABEN** angegeben
(`OIL_CHANGE`, `INSPECTION`, `HU`, `CHAIN` …) — vollständige Liste:
`GET /api/catalog/maintenance-types`.

Preise werden durchgängig in **Cents** übergeben (`costCents`,
`priceCentsTotal`, `purchasePriceCents`).

Status pro Typ (der **schlechtere** von km- und Zeit-Anteil zählt):

| Status | Bedingung |
|---|---|
| 🔴 `overdue` | `kmRemaining ≤ 0` oder `daysRemaining ≤ 0` |
| 🟡 `dueSoon` | km-Rest ≤ 500 **oder** Tage-Rest ≤ 14 |
| 🟢 `ok` | sonst |

Reiftypen mit `replacementDueDate` werden im Garage-Übersichts-Response als
`dueSoon`-Hinweis gemeldet.

## 8. Tests

```bash
npm test          # 18 Tests
```

Abgedeckt: Status-Berechnung inkl. Grenzen (0 Tage/km = überfällig),
Intervall-Ableitung, Verbrauchs-Mathe (Teilfüllungen ausgeschlossen,
Letzter-Eintrag-für-Tank-Größe), Privatsphäre-Serializer (alle 🔒-Felder
entfernt), Wartungskatalog-Konsistenz.

## 9. Anbindung an MotoRoute (später)

Die MotoRoute-App braucht dann nur:

1. **Basis-URL + Auth**: User meldet sich in der Garage-API (eigener Account) —
   die MotoRoute-App speichert das Garage-Access-Token getrennt vom
   MotoRoute-Token. Kein geteilter SECRET, keine gemischten Datenbanken.
2. **Beispiel-Ablauf „Meine Garage" in der App**:
   `POST /api/auth/login` → `GET /api/vehicles` → Karten (Foto, Name, km, Status)
   → `GET /api/vehicles/:id` (technische Daten) → `GET /api/vehicles/:id/reminders`
   → `PUT /api/vehicles/:id` (Kilometerstand) → `GET /api/vehicles/:id/maintenance`
   → `GET /api/vehicles/:id/documents`.
3. **CORS**: `CORS_ORIGIN` der Garage-API um die App-/Backend-Origin ergänzen.
4. **Deployment-Ablauf wie bei MotoRoute**: Render/Railway-Service, nur
   `DATABASE_URL` + `JWT_SECRET` als Secrets, **keine** Zugangsdaten im
   App-Frontend.

## 10. Bewusste Grenzen

- **Kein Datei-Storage**: Dokumente speichern Referenz (`url` oder Base64);
  echten Blob-Upload (S3/Supabase Storage) bindet man bei Bedarf an.
- **Katalog-Wachstum**: Startkatalog ist klein und bewusst admin-pflegbar;
  Import großer Hersteller-Daten (z. B. per CSV) ist über
  `/api/admin/*`-Skripte nachrüstbar, ohne Schema-Änderung.
- **Kein E-Mail-Flow**: Passwort-Reset kommt, wenn die App-Anbindung steht.
