# MotoRoute – Datenmodelle

> Status: Empfehlung zur Freigabe · Version 1.0 · Stand 2026-09-15
> Prinzip: Domain-First. Flutter-Entities und DB-Schema spiegeln dieselbe Sprache (Ubiquitäre Sprache), DTOs trennen nur den Transport.

## 1. Domain-Value-Objects (geteilte Sprache App + Backend)

```dart
/// GeoPoint: [lon, lat] in WGS84 (EPSG:4326) – Reihenfolge wie GeoJSON-Spec.
class GeoPoint { final double lon; final double lat; }

enum VehicleType { motorcycle, car, bicycle }

enum RideStyle { fast, curvy, extraCurvy, fastAndCurvy, unpaved }

enum Avoidance { motorway, ferry, toll }   // später: tunnel, urbanZone, lowEmissionZone

class RoutingPreferences {
  final VehicleType vehicle;
  final RideStyle style;
  final Set<Avoidance> avoid;
  // Invariante: unpaved-Style + bicycle => use_trails aktiv;
  // motorcycle + unpaved => UI-Warnung (siehe Vision-Doku).
}

class Waypoint {
  final String id;          // UUID v4
  final GeoPoint position;
  final String? label;      // „Start“, „Treffpunkt“, oder POI-Name
  final WaypointKind kind;  // start, intermediate, destination
}

class CurveScore {
  final double value;        // 0–100
  final double curveDensityPerKm;  // für Höhenprofil/Kurven-Highlights später
}
```

## 2. Zentrale Entities

```dart
class RoutePlan {
  final String id;                  // UUID
  final List<RouteCandidate> candidates;   // 1–3 Alternativen
  final RoutingPreferences requestedWith;  // bewusst gespeichert: Rerouting muss identisch bleiben
  final DateTime createdAt;
}

class RouteCandidate {
  final String providerRouteId;   // Valhalla-Resp-Hash (Cache-Key)
  final List<GeoPoint> geometry;  // Polyline-dekodiert
  final double distanceMeters;
  final Duration duration;
  final CurveScore curveScore;
  final List<Maneuver> maneuvers; // Turn-by-Turn
  final List<RouteLeg> legs;
}

class Maneuver {
  final GeoPoint location;
  final ManeuverType type;        // left, right, roundabout, merge, arrive …
  final String instruction;       // für TTS+UI, vom Backend geliefert (Sprache des Geräts)
  final double distanceToNextMeters;
  final Duration timeToNext;
}

class Poi {
  final String id;                // UUID (backend) bzw. `osm:<type>:<osm_id>`
  final PoiCategory category;     // fuel, motoHotel, bikerMeet, campsite, iceCream, speedCamera (später)
  final GeoPoint position;
  final String name;
  final Map<String, String>? tags;   // opening_hours etc., soweit vorhanden
  final PoiSource source;            // osm, curated, community (später)
}

class NavigationSession {
  final String routePlanId;
  final RouteCandidate activeRoute;
  final NavigationPhase phase;    // idle, preview, guiding, rerouting, arrived
  final double progressFraction;  // 0..1
  final DistanceRemaining remaining;
  final DateTime? eta;
}
```

**Wichtig (Produktregel im Modell verankert):** `RoutePlan.requestedWith` reist mit jeder Reroute-Anfrage mit – so ist „Präferenzen bleiben stabil“ strukturell garantiert, nicht nur Disziplin im Code.

## 3. PostgreSQL-Schema (PostGIS)

```sql
CREATE EXTENSION IF NOT EXISTS postgis;

-- POIs: Kern-Tabelle für Karte & Suche
CREATE TABLE pois (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category      TEXT NOT NULL,             -- enum-ähnlich, CHECK-Constraint
  name          TEXT NOT NULL,
  location      GEOGRAPHY(POINT, 4326) NOT NULL,
  osm_type      TEXT,                      -- 'node'|'way'|'relation' (bei OSM-Quelle)
  osm_id        BIGINT,
  tags          JSONB NOT NULL DEFAULT '{}',
  source        TEXT NOT NULL DEFAULT 'osm',   -- osm | curated | community
  verified      BOOLEAN NOT NULL DEFAULT FALSE, -- kuratiert/geprüft
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at    TIMESTAMPTZ,               -- Soft-Delete (Sync-tauglich)
  CONSTRAINT pois_category_check CHECK (category IN
    ('fuel','moto_hotel','biker_meet','campsite','ice_cream','speed_camera')),
  UNIQUE (osm_type, osm_id)
);
CREATE INDEX pois_location_gix ON pois USING GIST (location);
CREATE INDEX pois_category_idx ON pois (category) WHERE deleted_at IS NULL;

-- Gespeicherte Routen (MVP: lokal-first, Sync später)
CREATE TABLE saved_routes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id   UUID,                    -- NULL = anonym/lokal (MVP ohne Accounts)
  name            TEXT NOT NULL,
  preferences     JSONB NOT NULL,          -- RoutingPreferences als JSON
  waypoints       JSONB NOT NULL,          -- geordnete Liste mit Koordinaten
  geometry        GEOGRAPHY(LINESTRING, 4326),
  curve_score     REAL,
  distance_m      INTEGER,
  duration_s      INTEGER,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  synced_at       TIMESTAMPTZ,             -- für späteres Geräte-Sync
  deleted_at      TIMESTAMPTZ
);

-- Favoriten (Ziele/POIs)
CREATE TABLE favorites (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id UUID,
  kind        TEXT NOT NULL,               -- place | poi | waypoint
  label       TEXT NOT NULL,
  location    GEOGRAPHY(POINT, 4326) NOT NULL,
  poi_id      UUID REFERENCES pois(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at  TIMESTAMPTZ
);

-- Benutzer (erst ab Community-Phase aktiv; MVP-App läuft anonym)
CREATE TABLE users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email         TEXT UNIQUE,               -- nullable: passkey-only-Accounts
  display_name  TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at    TIMESTAMPTZ,               -- DSGVO: Löschung = Soft-Delete + Anon-Job
  CONSTRAINT users_has_contact CHECK (email IS NOT NULL) -- an Passkey-Design angepasst in M4
);

-- Aktive Nav-Sessions NICHT serverseitig speichern (Datenschutz!).
-- Nur anonyme, rollierende Metriken (keine Positionsdaten):
CREATE TABLE routing_metrics (
  id           BIGSERIAL PRIMARY KEY,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  vehicle      TEXT NOT NULL,
  ride_style   TEXT NOT NULL,
  distance_m   INTEGER,
  duration_ms  INTEGER,      -- Server-Latenz
  cache_hit    BOOLEAN,
  -- bewusst KEINE Koordinaten, KEINE User-IDs
  CONSTRAINT no_coords CHECK (true)       -- dokumentiert: Schema enthält nie Standorte
);
```

**Bewusste Nicht-Entscheidung:** keine `trips`/`tracks`-Tabelle im MVP. Standortverläufe werden nicht gespeichert (DSGVO-Minimierung). Wenn später „Fahrt aufgezeichnet“ kommt, ist das ein Opt-in mit separater Tabelle + Löschfunktion.

## 4. DTO-Konventionen (App ⇄ Backend)

- Geometrien: GeoJSON-kompatible Koordinatenlisten `[lon, lat]`, gepackt via Polyline6 im Transport (kleiner), DTO-Doku definiert das Format verbindlich.
- Zeiten: ISO-8601 mit TZ-Offset.
- IDs: UUID v4 als String.
- Kein Feld wird „still“ umbenannt: DTO-Klassen mit `json_serializable`/`freezed` (App) bzw. Pydantic (Backend) + Schema-Tests in beiden Richtungen (Contract-Tests).
