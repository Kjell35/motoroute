-- ---------------------------------------------------------------------------
-- HOTFIX (01.10.2026): match_badge_at - 42702 "column reference badge_id is ambiguous"
--
-- Wer Migration 0009 bzw. den SQL-Block aus docs/ONECLICK_SQL.md VOR diesem
-- Datum ausgefuehrt hat, hat die gebrochene Funktion im Dashboard: Jeder
-- Badge-Check-in endet in HTTP 503 BADGES_RPC_FAILED, obwohl Tabellen und
-- Seeds korrekt angelegt wurden.
--
-- Ursache: In
--     select coalesce(array_agg(badge_id), '{}') into v_had ...
-- kollidiert die unqualifizierte Spalte badge_id (user_badges) mit dem
-- gleichnamigen Output-Parameter aus 'returns table (badge_id, ...)'. PL/pgSQL
-- bricht mit 42702 ab, sobald die Funktion das erste Mal laeuft. Fix: alle
-- Spaltenreferenzen qualifiziert (ub.-Alias) und die Ausgaben des return
-- query eindeutig benannt.
--
-- ANWENDUNG: Diesen GESAMTEN Inhalt in den Supabase-SQL-Editor kopieren und
-- ausfuehren. CREATE OR REPLACE ersetzt NUR die Funktion - Tabellen, Seeds,
-- Policies und RLS bleiben unangetastet. Danach in der App einen Check-in
-- testen (oder motoroute_api/scripts/verify-badges-e2e.mjs laufen lassen).
-- ---------------------------------------------------------------------------

create or replace function public.match_badge_at(
  p_user_id uuid,
  p_lat double precision,
  p_lon double precision
)
returns table (
  badge_id uuid,
  title text,
  description text,
  icon_url text,
  required_category text,
  distance_m int,
  unlocked_now boolean,
  total_user_badges bigint
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user uuid := p_user_id;
  v_had uuid[] := '{}';
  v_after bigint;
begin
  if v_user is null then
    -- Ohne Nutzer keine Freischaltung (0 Zeilen, kein Fehler).
    return;
  end if;
  if p_lat is null or p_lon is null
     or p_lat < -90 or p_lat > 90 or p_lon < -180 or p_lon > 180 then
    raise exception 'INVALID_COORDS';
  end if;

  -- Menge der VOR diesem Call bereits freigeschalteten Badges merken:
  -- daraus wird pro Treffer "unlocked_now" abgeleitet (exakt, ohne
  -- Temp-Tabellen oder Trigger).
  -- WICHTIG: Alle Spaltenreferenzen qualifiziert (ub.-Alias). Unqualifiziert
  -- wuerde 'badge_id' hier mit dem gleichnamigen Output-Parameter aus
  -- 'returns table (...)' kollidieren -> 42702 'column reference is ambiguous'
  -- beim ERSTEN Aufruf (diese Zeile laeuft vor dem return query!).
  select coalesce(array_agg(ub.badge_id), '{}') into v_had
  from public.user_badges ub where ub.user_id = v_user;

  -- Kandidaten im Radius freischalten (idempotent): unlocked_at bleibt
  -- beim ERSTEN Besuch, Duplikate laufen ins leere DO NOTHING.
  insert into public.user_badges (user_id, badge_id)
  select v_user, b.id
  from public.badges b
  where st_dwithin(b.geog, st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography, b.radius_meters)
  on conflict (user_id, badge_id) do nothing;

  select count(*) into v_after from public.user_badges where user_id = v_user;

  return query
    select
      b.id as matched_badge_id,
      b.title,
      b.description,
      b.icon_url,
      b.required_category,
      -- Distanz fürs UI ("56 m vom Gipfel entfernt")
      st_distance(b.geog, st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography)::int as matched_distance,
      -- Neu in DIESEM Call? Genau dann, wenn er vorhin noch nicht da war.
      not (b.id = any(v_had)) as is_new_unlock,
      v_after as matched_total
    from public.badges b
    where st_dwithin(b.geog, st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography, b.radius_meters);
end;
$$;

revoke all on function public.match_badge_at(uuid, double precision, double precision) from public, anon, authenticated;
grant execute on function public.match_badge_at(uuid, double precision, double precision) to service_role;
