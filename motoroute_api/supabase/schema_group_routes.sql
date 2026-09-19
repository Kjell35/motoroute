-- ============================================================================
-- MotoRoute: GEMEINSAME ROUTENPLANUNG (Kollaborativer Gruppen-Routenplaner)
--
-- Migration zusätzlich zu schema.sql. Idempotent - kann mehrfach
-- ausgeführt werden. Im Supabase-SQL-Editor NACH schema.sql ausführen.
--
-- Eine Gruppenroute gehört der GRUPPE (Abschnitt 24): Verlässt ein Mitglied
-- die Gruppe, bleibt die Route bestehen. Bearbeitungsrechte sind SERVER-
-- SEITIG durchgesetzt (Abschnitt 25/32): editing_permission entscheidet in
-- RLS + RPCs, nie der Client.
-- ============================================================================

create table if not exists public.group_routes (
  id                  uuid primary key default uuid_generate_v4(),
  group_id            uuid not null references public.groups(id) on delete cascade,
  created_by          uuid not null references public.users(id) on delete cascade,
  name                text not null check (char_length(name) between 1 and 80),
  description         text check (char_length(description) <= 1000),
  status              text not null default 'planning'
                      check (status in ('planning','final','riding','completed','locked')),
  editing_permission  text not null default 'all_members'
                      check (editing_permission in ('all_members','owner_only')),
  start_name          text,
  start_lat           double precision not null,
  start_lng           double precision not null,
  dest_name           text,
  dest_lat            double precision not null,
  dest_lng            double precision not null,
  vehicle_type        text not null default 'MOTORCYCLE'
                      check (vehicle_type in ('MOTORCYCLE','CAR','BICYCLE')),
  routing_style       text not null default 'CURVY'
                      check (routing_style in ('FAST','CURVY','EXTRA_CURVY','FAST_AND_CURVY','UNPAVED')),
  avoid_highways      boolean not null default false,
  avoid_ferries       boolean not null default false,
  avoid_tolls         boolean not null default false,
  distance_meters     double precision,
  duration_seconds    double precision,
  curve_score         int,
  elevation_meters    int,
  version             bigint not null default 1,   -- Konflikt-Erkennung (Abschnitt 14)
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index if not exists group_routes_group_idx on public.group_routes (group_id);
create index if not exists group_routes_status_idx on public.group_routes (group_id, status);

create table if not exists public.route_stops (
  id          uuid primary key default uuid_generate_v4(),
  route_id    uuid not null references public.group_routes(id) on delete cascade,
  position    int not null,                       -- 1 = direkt nach Start, ... N = vor Ziel
  lat         double precision not null,
  lng         double precision not null,
  name        text not null check (char_length(name) between 1 and 120),
  category    text not null default 'other'
              check (category in ('fuel','moto_hotel','biker_meetup','campsite','ice_cream','viewpoint','other')),
  description text check (char_length(description) <= 500),
  address     text,
  created_by  uuid not null references public.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists route_stops_route_idx on public.route_stops (route_id, position);

create table if not exists public.route_comments (
  id          uuid primary key default uuid_generate_v4(),
  stop_id     uuid not null references public.route_stops(id) on delete cascade,
  user_id     uuid not null references public.users(id) on delete cascade,
  content     text not null check (char_length(content) between 1 and 500),
  created_at  timestamptz not null default now()
);
create index if not exists route_comments_stop_idx on public.route_comments (stop_id);

create table if not exists public.route_changes (
  id          uuid primary key default uuid_generate_v4(),
  route_id    uuid not null references public.group_routes(id) on delete cascade,
  user_id     uuid not null references public.users(id) on delete cascade,
  action      text not null check (action in
               ('created','stop_added','stop_removed','stop_moved','reordered','updated','recalculated','status_changed','permission_changed','locked','unlocked','started','completed','duplicated')),
  target_id   uuid,
  detail      text,
  created_at  timestamptz not null default now()
);
create index if not exists route_changes_route_idx on public.route_changes (route_id, created_at desc);

drop trigger if exists group_routes_set_updated_at on public.group_routes;
create trigger group_routes_set_updated_at
  before update on public.group_routes
  for each row execute function public.set_updated_at();

drop trigger if exists route_stops_set_updated_at on public.route_stops;
create trigger route_stops_set_updated_at
  before update on public.route_stops
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Helper (SECURITY DEFINER, rekursionsfrei)
-- ---------------------------------------------------------------------------
create or replace function public.is_group_member_for_route(p_route uuid, usr uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1
    from public.group_routes gr
    join public.groups g on g.id = gr.group_id
    join public.conversation_members cm on cm.conversation_id = g.conversation_id
    where gr.id = p_route and cm.user_id = usr
  );
$$;

create or replace function public.is_group_member(p_group uuid, usr uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1
    from public.groups g
    join public.conversation_members cm on cm.conversation_id = g.conversation_id
    where g.id = p_group and cm.user_id = usr
  );
$$;

create or replace function public.is_group_owner(p_group uuid, usr uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.groups where id = p_group and owner_id = usr
  );
$$;

create or replace function public.is_route_creator(p_route uuid, usr uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.group_routes where id = p_route and created_by = usr
  );
$$;

-- Zentrale Server-Regel (Abschnitt 25/32): Darf `usr` diese Route bearbeiten?
-- Gruppen-Owner und Ersteller immer; andere nur bei editing_permission =
-- 'all_members'. GESPERTE Routen kann nur der Gruppen-Owner ändern.
create or replace function public.can_edit_route(p_route uuid, usr uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select
    public.is_group_member_for_route(p_route, usr)
    and (
      public.is_group_owner((select group_id from public.group_routes where id = p_route), usr)
      or public.is_route_creator(p_route, usr)
      or (
        (select editing_permission from public.group_routes where id = p_route) = 'all_members'
        and (select status from public.group_routes where id = p_route) not in ('locked')
      )
    );
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.group_routes enable row level security;
alter table public.route_stops enable row level security;
alter table public.route_comments enable row level security;
alter table public.route_changes enable row level security;

-- Lesen: nur Gruppenmitglieder (Abschnitt 25: Mitglied bei 'owner_only'
-- darf ansehen/öffnen/navigieren - nur eben nicht bearbeiten).
drop policy if exists group_routes_select on public.group_routes;
create policy group_routes_select on public.group_routes
  for select to authenticated using (
    public.is_group_member_for_route(id, auth.uid())
  );

-- Erstellen: NUR der Gruppen-Owner (Abschnitt 1).
drop policy if exists group_routes_insert on public.group_routes;
create policy group_routes_insert on public.group_routes
  for insert to authenticated with check (
    created_by = auth.uid()
    and public.is_group_owner(group_id, auth.uid())
  );

-- Bearbeiten über zentrale Regel; gesperrte Routen nur über Owner-RPCs.
drop policy if exists group_routes_update on public.group_routes;
create policy group_routes_update on public.group_routes
  for update to authenticated
  using (public.can_edit_route(id, auth.uid()))
  with check (public.can_edit_route(id, auth.uid()));

drop policy if exists group_routes_delete on public.group_routes;
create policy group_routes_delete on public.group_routes
  for delete to authenticated using (
    public.is_group_owner(group_id, auth.uid())
  );

drop policy if exists route_stops_select on public.route_stops;
create policy route_stops_select on public.route_stops
  for select to authenticated using (
    public.is_group_member_for_route(route_id, auth.uid())
  );

-- Stopps: ALLE Operationen über can_edit_route (Abschnitt 7-10/25).
drop policy if exists route_stops_write on public.route_stops;
create policy route_stops_write on public.route_stops
  for all to authenticated
  using (public.can_edit_route(route_id, auth.uid()))
  with check (public.can_edit_route(route_id, auth.uid()));

-- Kommentare: Lesen = Gruppenmitglied; Schreiben = Mitglied (auch bei
-- 'owner_only' - Kommentieren ist keine Routen-Änderung, Abschnitt 21).
drop policy if exists route_comments_select on public.route_comments;
create policy route_comments_select on public.route_comments
  for select to authenticated using (
    exists (
      select 1 from public.route_stops rs
      join public.group_routes gr on gr.id = rs.route_id
      where rs.id = stop_id and public.is_group_member_for_route(gr.id, auth.uid())
    )
  );

drop policy if exists route_comments_write on public.route_comments;
create policy route_comments_write on public.route_comments
  for all to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.route_stops rs
      join public.group_routes gr on gr.id = rs.route_id
      where rs.id = stop_id and public.is_group_member_for_route(gr.id, auth.uid())
    )
  );

-- Änderungsverlauf: Lesen = Gruppenmitglied. Schreiben NUR serverseitig
-- über die RPCs unten (kein Insert-Policy = kein Client-Insert).
drop policy if exists route_changes_select on public.route_changes;
create policy route_changes_select on public.route_changes
  for select to authenticated using (
    public.is_group_member_for_route(route_id, auth.uid())
  );

-- ---------------------------------------------------------------------------
-- RPCs: Routen-Flow (Erstellen/Rechte/Status/Sperre/Duplizieren/Start)
-- ---------------------------------------------------------------------------

-- Neue Gruppenroute: NUR Owner (RLS + doppelte Prüfung im RPC).
create or replace function public.create_group_route(
  p_group uuid, p_name text, p_description text default null,
  p_start_name text default null, p_start_lat double precision default 0, p_start_lng double precision default 0,
  p_dest_name text default null, p_dest_lat double precision default 0, p_dest_lng double precision default 0,
  p_vehicle text default 'MOTORCYCLE', p_style text default 'CURVY',
  p_avoid_highways boolean default false, p_avoid_ferries boolean default false, p_avoid_tolls boolean default false,
  p_permission text default 'all_members'
)
returns json language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  rid uuid;
begin
  if me is null then raise exception 'not authenticated'; end if;
  if not public.is_group_owner(p_group, me) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_permission not in ('all_members','owner_only') then
    raise exception 'INVALID_PERMISSION' using errcode = 'P0001';
  end if;

  insert into public.group_routes (
    group_id, created_by, name, description,
    start_name, start_lat, start_lng, dest_name, dest_lat, dest_lng,
    vehicle_type, routing_style, avoid_highways, avoid_ferries, avoid_tolls,
    editing_permission
  ) values (
    p_group, me, p_name, p_description,
    p_start_name, p_start_lat, p_start_lng, p_dest_name, p_dest_lat, p_dest_lng,
    p_vehicle, p_style, p_avoid_highways, p_avoid_ferries, p_avoid_tolls,
    p_permission
  ) returning id into rid;

  insert into public.route_changes (route_id, user_id, action, detail)
  values (rid, me, 'created', p_name);

  return json_build_object('routeId', rid);
end $$;

-- Bearbeitungsrechte umstellen (nur Owner, Abschnitt 5).
create or replace function public.set_route_permission(p_route uuid, p_permission text)
returns void language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not authenticated'; end if;
  if not public.is_group_owner((select group_id from public.group_routes where id = p_route), me) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_permission not in ('all_members','owner_only') then
    raise exception 'INVALID_PERMISSION' using errcode = 'P0001';
  end if;
  update public.group_routes set editing_permission = p_permission where id = p_route;
  insert into public.route_changes (route_id, user_id, action)
  values (p_route, me, 'permission_changed', p_permission);
end $$;

-- Status ändern (Owner; 'riding'/'completed' auch vom Ersteller, Abschnitt 15).
create or replace function public.set_route_status(p_route uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  gr record;
begin
  if me is null then raise exception 'not authenticated'; end if;
  select * into gr from public.group_routes where id = p_route;
  if not found then raise exception 'ROUTE_NOT_FOUND' using errcode = 'P0002'; end if;
  if not (public.is_group_owner(gr.group_id, me)
          or (gr.created_by = me and p_status in ('riding','completed'))) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_status not in ('planning','final','riding','completed') then
    raise exception 'INVALID_STATUS' using errcode = 'P0001';
  end if;
  update public.group_routes set status = p_status where id = p_route;
  insert into public.route_changes (route_id, user_id, action, detail)
  values (p_route, me, 'status_changed', p_status);
end $$;

-- Route sperren (nur Gruppen-Owner, Abschnitt 16).
create or replace function public.lock_route(p_route uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not authenticated'; end if;
  if not public.is_group_owner((select group_id from public.group_routes where id = p_route), me) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  update public.group_routes set status = 'locked' where id = p_route;
  insert into public.route_changes (route_id, user_id, action) values (p_route, me, 'locked');
end $$;

-- Route wieder freigeben (nur Gruppen-Owner).
create or replace function public.unlock_route(p_route uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not authenticated'; end if;
  if not public.is_group_owner((select group_id from public.group_routes where id = p_route), me) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  update public.group_routes set status = 'planning' where id = p_route;
  insert into public.route_changes (route_id, user_id, action) values (p_route, me, 'unlocked');
end $$;

-- ---------------------------------------------------------------------------
-- RPCs: Stopps (serverseitige can_edit-Prüfung, Abschnitt 7-10)
-- ---------------------------------------------------------------------------

create or replace function public.add_route_stop(
  p_route uuid, p_lat double precision, p_lng double precision,
  p_name text, p_category text default 'other', p_description text default null, p_address text default null
)
returns json language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  next_pos int;
  sid uuid;
begin
  if me is null then raise exception 'not authenticated'; end if;
  if not public.can_edit_route(p_route, me) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select coalesce(max(position), 0) + 1 into next_pos
  from public.route_stops where route_id = p_route;

  insert into public.route_stops (route_id, position, lat, lng, name, category, description, address, created_by)
  values (p_route, next_pos, p_lat, p_lng, p_name, p_category, p_description, p_address, me)
  returning id into sid;

  update public.group_routes set version = version + 1 where id = p_route;
  insert into public.route_changes (route_id, user_id, action, target_id, detail)
  values (p_route, me, 'stop_added', sid, p_name);

  return json_build_object('stopId', sid, 'position', next_pos);
end $$;

create or replace function public.delete_route_stop(p_stop uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  rs record;
begin
  if me is null then raise exception 'not authenticated'; end if;
  select * into rs from public.route_stops where id = p_stop;
  if not found then raise exception 'STOP_NOT_FOUND' using errcode = 'P0002'; end if;
  if not public.can_edit_route(rs.route_id, me) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  delete from public.route_stops where id = p_stop;
  update public.group_routes set version = version + 1 where id = rs.route_id;
  insert into public.route_changes (route_id, user_id, action, detail)
  values (rs.route_id, me, 'stop_removed', rs.name);
end $$;

-- Reihenfolge setzen (komplette ID-Liste, Abschnitt 9). Atomar + Audit +
-- Konsistenzprüfung: Liste muss genau die vorhandenen Stopps enthalten
-- (verlorene Updates durch gleichzeitiges Reordern werden abgewiesen).
create or replace function public.reorder_route_stops(p_route uuid, p_stop_ids uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  i int;
begin
  if me is null then raise exception 'not authenticated'; end if;
  if not public.can_edit_route(p_route, me) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if (select count(*) from public.route_stops where route_id = p_route)
     <> coalesce(array_length(p_stop_ids, 1), 0) then
    raise exception 'STOP_LIST_MISMATCH' using errcode = 'P0001';
  end if;

  for i in 1..coalesce(array_length(p_stop_ids, 1), 0) loop
    update public.route_stops set position = i
    where id = p_stop_ids[i] and route_id = p_route;
  end loop;

  update public.group_routes set version = version + 1 where id = p_route;
  insert into public.route_changes (route_id, user_id, action)
  values (p_route, me, 'reordered');
end $$;

-- ---------------------------------------------------------------------------
-- RPCs: Duplizieren (Abschnitt 23) + Verlauf
-- ---------------------------------------------------------------------------

-- Route duplizieren: Kopie mit "- Alternative"-Suffix, Stopps werden
-- mitkopiert, Verlauf startet neu. Berechtigt: Owner oder (bei
-- all_members) derjenige, der die Route ohnehin bearbeiten darf -
-- die Kopie gehört weiterhin dem GRUPPEN-Owner als Ersteller? Nein:
-- created_by = aufrufende Person, Gruppe bleibt dieselbe.
create or replace function public.duplicate_group_route(p_route uuid, p_new_name text default null)
returns json language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  src record;
  new_id uuid;
  s record;
begin
  if me is null then raise exception 'not authenticated'; end if;
  select * into src from public.group_routes where id = p_route;
  if not found then raise exception 'ROUTE_NOT_FOUND' using errcode = 'P0002'; end if;
  if not public.can_edit_route(p_route, me) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  insert into public.group_routes (
    group_id, created_by, name, description,
    start_name, start_lat, start_lng, dest_name, dest_lat, dest_lng,
    vehicle_type, routing_style, avoid_highways, avoid_ferries, avoid_tolls,
    editing_permission, status
  ) values (
    src.group_id, me,
    coalesce(p_new_name, src.name || ' - Alternative'),
    src.description,
    src.start_name, src.start_lat, src.start_lng, src.dest_name, src.dest_lat, src.dest_lng,
    src.vehicle_type, src.routing_style, src.avoid_highways, src.avoid_ferries, src.avoid_tolls,
    src.editing_permission, 'planning'
  ) returning id into new_id;

  for s in select * from public.route_stops where route_id = p_route order by position loop
    insert into public.route_stops (route_id, position, lat, lng, name, category, description, address, created_by)
    values (new_id, s.position, s.lat, s.lng, s.name, s.category, s.description, s.address, s.created_by);
  end loop;

  insert into public.route_changes (route_id, user_id, action, detail)
  values (new_id, me, 'duplicated', 'Kopie von ' || src.name);

  return json_build_object('routeId', new_id);
end $$;

-- Änderungsverlauf (Abschnitt 13) mit Namen der Akteure.
create or replace function public.get_route_history(p_route uuid, p_limit int default 50)
returns json language sql security definer stable set search_path = public as $$
  select coalesce(json_agg(row_to_json(h)), '[]'::json) from (
    select c.action, c.detail, c.created_at,
           u.username, u.display_name, u.avatar_url
    from public.route_changes c
    left join public.users u on u.id = c.user_id
    where c.route_id = p_route
    order by c.created_at desc
    limit p_limit
  ) h;
$$;

-- Kommentare zu einem Stopp (Abschnitt 21) mit Autoren-Profil.
create or replace function public.get_stop_comments(p_stop uuid)
returns json language sql security definer stable set search_path = public as $$
  select coalesce(json_agg(row_to_json(h)), '[]'::json) from (
    select cm.id, cm.content, cm.created_at,
           u.id as user_id, u.username, u.display_name, u.avatar_url
    from public.route_comments cm
    left join public.users u on u.id = cm.user_id
    where cm.stop_id = p_stop
    order by cm.created_at asc
  ) h;
$$;
