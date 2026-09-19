-- ============================================================================
-- MotoRoute POI-Service: LIVE-RADAR (active_bikers)
--
-- Migration ZU schema.sql (PostGIS erforderlich). Idempotent.
--
-- Zweck: Aktuelle GPS-Positionen für das Biker-Meetup-Radar über
-- Socket.IO (update_location -> ST_DWithin-Umkreis).
--
-- Datenschutz-Regeln (dieselben wie im BFF-Gruppenfahrt-Modul):
-- - TRANSIENT: Nur der AKTUELLE Punkt je Biker, KEINE Historie, kein
--   Tracking (jede Aktualisierung überschreibt die Zeile).
-- - 30-MINUTEN-REGEL: Positionen älter als 30 Min. werden durch den
--   Bereinigungs-Job physisch gelöscht - "aus dem Radar" bedeutet
--   wirklich weg, kein schlafender Datensatz.
-- - GHOST MODE: Bei ghostMode=true wird NICHTS gespeichert (siehe
--   bikerRadar.js) - Nicht-Speichern ist der Schutz, nicht ein Flag.
-- ============================================================================

create table if not exists public.active_bikers (
  user_id    text primary key,                -- userId des Clients (nicht verknüpft mit Auth)
  location   public.geography(point, 4326) not null,
  latitude   double precision not null,
  longitude  double precision not null,
  last_seen  timestamptz not null default now()
);

-- ST_DWithin-Umkreis-Abfragen indexgestützt.
create index if not exists active_bikers_location_gix
  on public.active_bikers using gist (location);
-- Der Bereinigungs-Job scannt auf last_seen.
create index if not exists active_bikers_last_seen_idx
  on public.active_bikers (last_seen);
