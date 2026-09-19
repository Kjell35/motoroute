-- MotoRoute – Biker-POI Schema (PostgreSQL + PostGIS)

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Die 8 exakten Biker-Kategorien
CREATE TYPE poi_category AS ENUM (
  'imbiss',
  'bikertreff',
  'kneipe',
  'pension',
  'restaurant',
  'hotel',
  'zeltplatz',
  'gartenlokal'
);

CREATE TABLE pois (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name              TEXT NOT NULL,
  category          poi_category NOT NULL,
  geog              GEOGRAPHY(POINT, 4326) NOT NULL,
  address           TEXT,
  country_code      CHAR(2),

  -- Biker-Eignung: 0-100, berechnet aus amenities/tags (siehe classifier.js)
  biker_score       SMALLINT NOT NULL DEFAULT 0 CHECK (biker_score BETWEEN 0 AND 100),

  -- z.B. {"motorcycle_parking":true,"workshop_corner":false,"meeting_point":true,"covered_parking":true}
  amenities         JSONB NOT NULL DEFAULT '{}'::jsonb,

  source            TEXT NOT NULL,          -- z.B. 'osm-overpass'
  source_id         TEXT,                   -- externe ID (z.B. OSM node/way id) zur Re-Identifikation
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,  -- soft delete -> Delta-Sync kann Löschungen mitteilen

  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_verified_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (source, source_id)
);

-- Räumlicher Index für ST_DWithin-Duplikatprüfung und Umkreissuche
CREATE INDEX idx_pois_geog ON pois USING GIST (geog);
CREATE INDEX idx_pois_category ON pois (category);
CREATE INDEX idx_pois_updated_at ON pois (updated_at);
CREATE INDEX idx_pois_active ON pois (is_active);

-- updated_at automatisch pflegen
CREATE OR REPLACE FUNCTION trg_set_updated_at() RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER pois_set_updated_at
BEFORE UPDATE ON pois
FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();

-- Realtime-Hook: bei INSERT/UPDATE wird über Postgres LISTEN/NOTIFY
-- ein Event ausgelöst, das der API-Server abonniert und per Socket.IO
-- an verbundene Flutter-Clients weiterreicht (siehe src/server.js)
CREATE OR REPLACE FUNCTION trg_notify_poi_change() RETURNS TRIGGER AS $$
BEGIN
  PERFORM pg_notify('poi_changes', json_build_object(
    'id', NEW.id,
    'category', NEW.category,
    'op', TG_OP,
    'is_active', NEW.is_active
  )::text);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER pois_notify_change
AFTER INSERT OR UPDATE ON pois
FOR EACH ROW EXECUTE FUNCTION trg_notify_poi_change();
