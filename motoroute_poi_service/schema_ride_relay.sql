-- ============================================================================
-- MotoRoute POI-Service: GRUPPENFAHRT-RELAIS (active_ride_bikers)
--
-- Migration ZU schema.sql + schema_radar.sql. Idempotent.
--
-- Zweck: Das BFF speichert Herzen von Live-Gruppenfahrten hier, damit
-- Mitglieder EINER Route in Echtzeit Positionen sehen - UNABHÄNGIG vom
-- Umkreis (ST_DWithin des öffentlichen Radars greift hier bewusst NICHT).
--
-- STRUKTUR-TRENNUNG ZUM ÖFFENTLICHEN RADAR (schema_radar.sql):
--   - EIGENE Tabelle: active_ride_bikers (kein Zugriffsweg von Radar-
--     Queries auf Ride-Positionen, keine geteilten Index-/Query-Pfade).
--   - EIGENE Events: ride_position_update / ride_position_leave (nie
--     'location_update' des öffentlichen Radars).
--   - EIGENE Authentifizierung: Nur das BFF darf schreiben/lesen
--     (Relay-Secret); Clients sprechen das Relais NIE direkt an.
--
-- Autorisierung lebt im BFF: Wer eine Position einspeist, wurde dort
-- gegen Supabase-RLS als Gruppenmitglied verifiziert (hazard-/
-- group-rides-Muster). Das Relais speichert nur noch - ein manipulierter
-- Client kann hier nichts erreichen.
--
-- Datenschutz: Nur der AKTUELLE Punkt je (route_id, user_id), keine
-- Historie; der Bereinigungs-Job löscht veraltete Zeilen physisch
-- (30 Minuten ohne Beat = aus dem Relais, Default-Radar-Prune bleibt
-- parallel aktiv für active_bikers).
-- ============================================================================

create table if not exists public.active_ride_bikers (
  route_id   text not null,
  user_id    text not null,
  location   public.geography(point, 4326) not null,
  latitude   double precision not null,
  longitude  double precision not null,
  last_seen  timestamptz not null default now(),
  primary key (route_id, user_id)
);

create index if not exists active_ride_bikers_route_idx
  on public.active_ride_bikers (route_id);
-- Bereinigungs-Job scannt auf last_seen.
create index if not exists active_ride_bikers_last_seen_idx
  on public.active_ride_bikers (last_seen);
