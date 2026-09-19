-- ============================================================================
-- MotoRoute: LIVE-GRUPPENFAHRT (Feature: Gemeinsam fahren)
--
-- Migration ZU schema.sql + schema_group_routes.sql. Idempotent.
--
-- Kernprinzip (Abschnitt 18 der Chat-Vorgabe, übernommen): Die
-- Standortfreigabe ist OPT-IN pro Fahrer. Ohne Freigabe existiert KEINE
-- Zeile in group_ride_states - Nicht-Teilnehmen ist der Default, "aus"
-- bedeutet physisches Löschen (nicht nur ein Flag).
--
-- Sieht ein Mitglied die Position eines anderen? Zwei unabhängige
-- Schlösser muessen zusammen aufgehen:
--   1. Der Fahrer hat geteilt (Zeile existiert, sharing = true)
--   2. Der Betrachter ist Mitglied derselben Gruppe (RLS)
-- Positionen laufen über den Gruppenrouten-RPC-Kontext - sie sind NUR
-- für Mitglieder der Gruppe sichtbar, die die Route teilen.
-- ============================================================================

create table if not exists public.group_ride_states (
  route_id        uuid not null references public.group_routes(id) on delete cascade,
  user_id         uuid not null references public.users(id) on delete cascade,
  sharing         boolean not null default true,   -- opt-in (siehe oben)
  last_lat        double precision not null,
  last_lng        double precision not null,
  started         boolean not null default false,  -- hat die Tour begonnen?
  finished        boolean not null default false,
  last_beat_at    timestamptz not null default now(),
  primary key (route_id, user_id)
);
create index if not exists group_ride_states_route_idx on public.group_ride_states (route_id);

-- RLS: Lesen NUR für Mitglieder der Gruppe, zu der die Route gehört.
alter table public.group_ride_states enable row level security;

drop policy if exists ride_states_select on public.group_ride_states;
create policy ride_states_select on public.group_ride_states
  for select to authenticated using (
    exists (
      select 1 from public.group_routes gr
      where gr.id = route_id
        and public.is_group_member_for_route(gr.id, auth.uid())
    )
  );

-- Upsert/Heartbeat/Beenden läuft über die RPCs unten; kein direktes
-- Insert/Update/Delete für Clients (minimale Angriffsfläche).

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

-- Fahrer startet Positionsteilen (OPT-IN): Zeile anlegen oder reaktivieren.
create or replace function public.ride_start_sharing(p_route uuid, p_lat double precision, p_lng double precision)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not public.is_group_member_for_route(p_route, auth.uid()) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  insert into public.group_ride_states (route_id, user_id, sharing, last_lat, last_lng, started, last_beat_at)
  values (p_route, auth.uid(), true, p_lat, p_lng, true, now())
  on conflict (route_id, user_id) do update
    set sharing = true,
        last_lat = excluded.last_lat,
        last_lng = excluded.last_lng,
        started = true,
        last_beat_at = now();
end $$;

-- Heartbeat: Position aktualisieren (nur wenn noch geteilt wird).
create or replace function public.ride_heartbeat(p_route uuid, p_lat double precision, p_lng double precision)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  update public.group_ride_states
  set last_lat = p_lat, last_lng = p_lng, last_beat_at = now()
  where route_id = p_route and user_id = auth.uid() and sharing = true;
end $$;

-- Freigabe beenden: Zeile PHYSISCH löschen (kein toter Datensatz).
create or replace function public.ride_stop_sharing(p_route uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  delete from public.group_ride_states
  where route_id = p_route and user_id = auth.uid();
end $$;

-- Fahrer markiert sich als "fertig gefahren".
create or replace function public.ride_finish(p_route uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  update public.group_ride_states
  set finished = true, last_beat_at = now()
  where route_id = p_route and user_id = auth.uid() and sharing = true;
end $$;

-- Live-Ansicht: alle teilenden Fahrer mit Profil. NUR Gruppenmitglieder
-- kommen durch (Prüfung im RPC zusätzlich zu RLS, Defense in Depth).
create or replace function public.ride_live_state(p_route uuid)
returns json language sql security definer stable set search_path = public as $$
  select coalesce(json_agg(row_to_json(h)), '[]'::json) from (
    select s.user_id, s.last_lat, s.last_lng, s.started, s.finished, s.last_beat_at,
           u.username, u.display_name, u.avatar_url
    from public.group_ride_states s
    left join public.users u on u.id = s.user_id
    where s.route_id = p_route
      and s.sharing = true
    order by s.started desc, s.last_beat_at desc
  ) h;
$$;
