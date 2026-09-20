-- =============================================================================
-- MotoRoute VOLL-SETUP: ALLE Tabellen + RLS in EINER Datei (Reihenfolge fix).
-- Einmalig ausfuehren: Supabase-Dashboard > SQL Editor > New query >
-- kompletten Inhalt einfuegen > RUN. Alles ist idempotent (safe to re-run).
--
-- Reihenfolge: Extensions > Basisschema (users/chats) > PostGIS >
--              group_rides > group_routes > hazards
-- =============================================================================

create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto;
create extension if not exists postgis;

-- ============================================================================
-- MotoRoute Chat-Schema (Feature 41: Chat & Community)
--
-- Ziel-Stack: Supabase/PostgreSQL. Wird über das Supabase-Dashboard
-- (SQL-Editor) oder `supabase db push` eingespielt.
--
-- Sicherheit ist hier SERVERSEITIG durchgesetzt:
--  - RLS auf jeder Tabelle (Abschnitt 26/29 der Chat-Vorgabe)
--  - Private Nachrichten sind für Nicht-Teilnehmer physikalisch nicht
--    lesbar - nicht nur in der UI versteckt.
--  - blocked_users wird in Policies geprüft, nicht nur im Client.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- users (Profil - ergänzt auth.users, wie im UserService bereits genutzt)
-- ---------------------------------------------------------------------------
create table if not exists public.users (
  id            uuid primary key references auth.users(id) on delete cascade,
  username      text unique,
  email         text,
  display_name  text,
  avatar_url    text,
  vehicle_desc  text,                          -- "BMW R1250GS" o. ä. (optional)
  bio           text,                          -- kurze Beschreibung (optional)
  show_online   boolean not null default true, -- Datenschutz (Abschnitt 18)
  last_seen_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- conversations: public | private | group  (Abschnitt 27)
-- ---------------------------------------------------------------------------
create table if not exists public.conversations (
  id          uuid primary key default uuid_generate_v4(),
  type        text not null check (type in ('public','private','group')),
  pair_key    text,                             -- nur für private: sortiertes Paar
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Genau EIN öffentlicher Chat (Singleton).
create unique index if not exists conversations_single_public
  on public.conversations (type) where type = 'public';

-- Pair-Key verhindert private Doppel-Chats zwischen denselben zwei Nutzern.
create unique index if not exists conversations_pair_key_unique
  on public.conversations (pair_key) where type = 'private' and pair_key is not null;

-- ---------------------------------------------------------------------------
-- conversation_members (Rollen: owner | moderator | member - moderator
-- ist vorbereitet, aber noch nicht vergeben, siehe Abschnitt 14)
-- ---------------------------------------------------------------------------
create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id         uuid not null references public.users(id) on delete cascade,
  role            text not null default 'member' check (role in ('owner','moderator','member')),
  joined_at       timestamptz not null default now(),
  last_read_at    timestamptz not null default to_timestamp(0), -- Unread-Basis
  primary key (conversation_id, user_id)
);
create index if not exists conv_members_user_idx on public.conversation_members (user_id);

-- ---------------------------------------------------------------------------
-- messages (Soft-Delete via deleted_at, Abschnitt 21)
-- attachment JSONB ist die Architektur-Vorbereitung für Bilder/GPX/
-- Routen/Standort (Abschnitt 20/38) - typspezifisch:
--   {"type":"route","routeId":"...","distanceKm":245,"durationS":13200,
--    "curvyScore":92,"name":"Alpenrunde"}
--   {"type":"location","lat":47.42,"lng":11.07,"label":"Treffpunkt"}
--   {"type":"gpx","storagePath":"..."}
-- ---------------------------------------------------------------------------
create table if not exists public.messages (
  id              uuid primary key default uuid_generate_v4(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id       uuid not null references public.users(id) on delete cascade,
  content         text not null default '',
  attachment      jsonb,
  reply_to_id     uuid references public.messages(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);
create index if not exists messages_conversation_created_idx
  on public.messages (conversation_id, created_at desc);
create index if not exists messages_sender_idx on public.messages (sender_id);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists messages_set_updated_at on public.messages;
create trigger messages_set_updated_at
  before update on public.messages
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- groups (1:1 mit einer conversation vom Typ 'group', Abschnitt 7/27)
-- ---------------------------------------------------------------------------
create table if not exists public.groups (
  id             uuid primary key default uuid_generate_v4(),
  conversation_id uuid not null unique references public.conversations(id) on delete cascade,
  owner_id       uuid not null references public.users(id) on delete cascade,
  name           text not null check (char_length(name) between 1 and 60),
  description    text check (char_length(description) <= 500),
  image_url      text,
  category       text,                               -- "Tour", "Club", "Regional" (optional)
  created_at     timestamptz not null default now()
);
create index if not exists groups_owner_idx on public.groups (owner_id);

create table if not exists public.group_invitations (
  id          uuid primary key default uuid_generate_v4(),
  group_id    uuid not null references public.groups(id) on delete cascade,
  code        text not null unique,               -- "MOTO-7K4P92"
  created_by  uuid not null references public.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz,                        -- optional (Abschnitt 12)
  active      boolean not null default true
);
create index if not exists group_invitations_group_idx on public.group_invitations (group_id);
create index if not exists group_invitations_active_code_idx
  on public.group_invitations (code) where active;

-- ---------------------------------------------------------------------------
-- blocked_users + reports (Abschnitt 22/23/24)
-- ---------------------------------------------------------------------------
create table if not exists public.blocked_users (
  user_id         uuid not null references public.users(id) on delete cascade,
  blocked_user_id uuid not null references public.users(id) on delete cascade,
  created_at      timestamptz not null default now(),
  primary key (user_id, blocked_user_id),
  check (user_id <> blocked_user_id)
);
create index if not exists blocked_users_blocked_idx on public.blocked_users (blocked_user_id);

create table if not exists public.reports (
  id               uuid primary key default uuid_generate_v4(),
  reporter_id      uuid not null references public.users(id) on delete cascade,
  reported_user_id uuid not null references public.users(id) on delete cascade,
  message_id       uuid references public.messages(id) on delete set null,
  reason           text not null check (reason in
                     ('spam','harassment','insult','inappropriate','fraud','other')),
  details          text,
  status           text not null default 'open' check (status in ('open','reviewing','resolved','dismissed')),
  created_at      timestamptz not null default now()
);
create index if not exists reports_status_idx on public.reports (status) where status = 'open';

-- ---------------------------------------------------------------------------
-- Helper-Funktionen (SECURITY DEFINER, um Rekursion in RLS zu vermeiden)
-- ---------------------------------------------------------------------------
create or replace function public.is_conversation_member(conv uuid, usr uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.conversation_members
    where conversation_id = conv and user_id = usr
  );
$$;

create or replace function public.has_blocked(blocker uuid, blocked uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.blocked_users
    where user_id = blocker and blocked_user_id = blocked
  );
$$;

-- Blockierung in BEIDEN Richtungen für Sende-/Lese-Sperre (Abschnitt 23).
create or replace function public.is_blocked_either(a uuid, b uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.blocked_users
    where (user_id = a and blocked_user_id = b)
       or (user_id = b and blocked_user_id = a)
  );
$$;

-- Richtungsunabhängiger Schlüssel für 1:1-Chats.
create or replace function public.make_pair_key(a uuid, b uuid)
returns text language sql immutable as $$
  select case when a < b then a::text || '|' || b::text
              else b::text || '|' || a::text end;
$$;

-- ---------------------------------------------------------------------------
-- RLS aktivieren
-- ---------------------------------------------------------------------------
alter table public.users enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.groups enable row level security;
alter table public.group_invitations enable row level security;
alter table public.blocked_users enable row level security;
alter table public.reports enable row level security;

-- ---------------------------------------------------------------------------
-- users-Policies: Profile sind lesbar (Community braucht sie), editierbar
-- nur selbst.
-- ---------------------------------------------------------------------------
drop policy if exists users_select on public.users;
create policy users_select on public.users
  for select using (true);

drop policy if exists users_self_update on public.users;
create policy users_self_update on public.users
  for update using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists users_self_insert on public.users;
create policy users_self_insert on public.users
  for insert with check (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- conversations-Policies
--   - public:   jedes authentifizierte Mitglied darf lesen
--   - private:  NUR Teilnehmer (physikalische Abschottung, Abschnitt 26)
--   - group:    NUR Gruppenmitglieder
-- ---------------------------------------------------------------------------
drop policy if exists conv_select on public.conversations;
create policy conv_select on public.conversations
  for select to authenticated using (
    type = 'public'
    or public.is_conversation_member(id, auth.uid())
  );

drop policy if exists conv_insert on public.conversations;
create policy conv_insert on public.conversations
  for insert to authenticated with check (true);

drop policy if exists conv_update on public.conversations;
create policy conv_update on public.conversations
  for update to authenticated using (
    public.is_conversation_member(id, auth.uid())
  );

-- Gruppe löschen = Konversation löschen (cascades zu messages/members/
-- groups über FKs). Nur der Gruppen-Owner darf das.
drop policy if exists conv_delete on public.conversations;
create policy conv_delete on public.conversations
  for delete to authenticated using (
    exists (
      select 1 from public.groups g
      where g.conversation_id = id and g.owner_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- conversation_members-Policies
-- ---------------------------------------------------------------------------
drop policy if exists conv_member_select on public.conversation_members;
create policy conv_member_select on public.conversation_members
  for select to authenticated using (
    user_id = auth.uid()
    or public.is_conversation_member(conversation_id, auth.uid())
  );

-- Beitritt über Einladungscode läuft serverseitig (join_group_with_code);
-- direktes Insert erlaubt nur der Selbst-Eintrag in den öffentlichen Chat.
drop policy if exists conv_member_insert on public.conversation_members;
create policy conv_member_insert on public.conversation_members
  for insert to authenticated with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.conversations c
      where c.id = conversation_id and c.type = 'public'
    )
  );

drop policy if exists conv_member_delete on public.conversation_members;
create policy conv_member_delete on public.conversation_members
  for delete to authenticated using (
    user_id = auth.uid()                                   -- selbst verlassen
    or exists (                                            -- Owner entfernt
      select 1 from public.conversation_members m
      where m.conversation_id = conversation_id
        and m.user_id = auth.uid() and m.role = 'owner'
    )
  );

drop policy if exists conv_member_update on public.conversation_members;
create policy conv_member_update on public.conversation_members
  for update to authenticated using (
    exists (
      select 1 from public.conversation_members m
      where m.conversation_id = conversation_id
        and m.user_id = auth.uid() and m.role = 'owner'
    )
  );

-- ---------------------------------------------------------------------------
-- messages-Policies (Kern der Zugriffskontrolle, Abschnitt 26)
-- ---------------------------------------------------------------------------
drop policy if exists msg_select on public.messages;
create policy msg_select on public.messages
  for select to authenticated using (
    public.is_conversation_member(conversation_id, auth.uid())
  );

drop policy if exists msg_insert on public.messages;
create policy msg_insert on public.messages
  for insert to authenticated with check (
    sender_id = auth.uid()
    and public.is_conversation_member(conversation_id, auth.uid())
    -- Kein Senden in private Chats, wenn blockiert (serverseitig!)
    and not exists (
      select 1
      from public.conversations c
      join public.conversation_members other
        on other.conversation_id = c.id and other.user_id <> auth.uid()
      where c.id = conversation_id and c.type = 'private'
        and public.is_blocked_either(auth.uid(), other.user_id)
    )
    -- Kein Senden in Gruppen, wenn der Owner einen blockiert hat
    and not exists (
      select 1
      from public.groups g
      where g.conversation_id = conversation_id
        and public.has_blocked(g.owner_id, auth.uid())
    )
  );

drop policy if exists msg_update on public.messages;
create policy msg_update on public.messages
  for update to authenticated using (sender_id = auth.uid())
  with check (sender_id = auth.uid());

drop policy if exists msg_delete on public.messages;
create policy msg_delete on public.messages
  for delete to authenticated using (sender_id = auth.uid());

-- ---------------------------------------------------------------------------
-- groups-Policies: sichtbar für Mitglieder der zugehörigen Konversation
-- ---------------------------------------------------------------------------
drop policy if exists groups_select on public.groups;
create policy groups_select on public.groups
  for select to authenticated using (
    public.is_conversation_member(conversation_id, auth.uid())
  );

drop policy if exists groups_update on public.groups;
create policy groups_update on public.groups
  for update to authenticated using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists groups_delete on public.groups;
create policy groups_delete on public.groups
  for delete to authenticated using (owner_id = auth.uid());

-- ---------------------------------------------------------------------------
-- group_invitations-Policies: Codes NUR für den Owner lesbar
-- (Kenntnis des Codes durch Mitglieder wäre ein Leak).
-- ---------------------------------------------------------------------------
drop policy if exists invitations_select on public.group_invitations;
create policy invitations_select on public.group_invitations
  for select to authenticated using (
    exists (
      select 1 from public.groups g
      where g.id = group_id and g.owner_id = auth.uid()
    )
  );

drop policy if exists invitations_insert on public.group_invitations;
create policy invitations_insert on public.group_invitations
  for insert to authenticated with check (
    created_by = auth.uid()
    and exists (
      select 1 from public.groups g
      where g.id = group_id and g.owner_id = auth.uid()
    )
  );

drop policy if exists invitations_update on public.group_invitations;
create policy invitations_update on public.group_invitations
  for update to authenticated using (
    exists (
      select 1 from public.groups g
      where g.id = group_id and g.owner_id = auth.uid()
    )
  );

drop policy if exists invitations_delete on public.group_invitations;
create policy invitations_delete on public.group_invitations
  for delete to authenticated using (
    exists (
      select 1 from public.groups g
      where g.id = group_id and g.owner_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- blocked_users / reports: nur eigene Zeilen
-- ---------------------------------------------------------------------------
drop policy if exists blocked_select on public.blocked_users;
create policy blocked_select on public.blocked_users
  for select to authenticated using (user_id = auth.uid());

drop policy if exists blocked_insert on public.blocked_users;
create policy blocked_insert on public.blocked_users
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists blocked_delete on public.blocked_users;
create policy blocked_delete on public.blocked_users
  for delete to authenticated using (user_id = auth.uid());

drop policy if exists reports_select on public.reports;
create policy reports_select on public.reports
  for select to authenticated using (reporter_id = auth.uid());

drop policy if exists reports_insert on public.reports;
create policy reports_insert on public.reports
  for insert to authenticated with check (reporter_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Seed: öffentlicher Chat als Singleton (idempotent)
-- ---------------------------------------------------------------------------
insert into public.conversations (id, type)
values ('00000000-0000-0000-0000-000000000001', 'public')
on conflict (id) do nothing;

-- ============================================================================
-- RPC-Funktionen (über supabase.rpc() aus dem Backend aufgerufen)
-- ============================================================================

-- Privatchat zwischen zwei Nutzern anlegen/finden (idempotent).
create or replace function public.get_or_create_private_chat(other uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  key text := public.make_pair_key(me, other);
  conv uuid;
begin
  if me is null then raise exception 'not authenticated'; end if;
  if me = other then raise exception 'cannot chat with yourself'; end if;
  if public.is_blocked_either(me, other) then
    raise exception 'BLOCKED' using errcode = 'P0001';
  end if;

  select c.id into conv from public.conversations c
  where c.type = 'private' and c.pair_key = key;

  if conv is null then
    insert into public.conversations (type, pair_key) values ('private', key)
      returning id into conv;
    insert into public.conversation_members (conversation_id, user_id)
      values (conv, me), (conv, other);
  end if;

  return conv;
end $$;

-- Gruppe anlegen: erzeugt Gruppe + Gruppen-Konversation in einer Transaktion.
create or replace function public.create_group(
  p_name text, p_description text default null,
  p_image_url text default null, p_category text default null
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  g uuid;
  conv uuid;
begin
  if me is null then raise exception 'not authenticated'; end if;

  insert into public.conversations (type) values ('group')
    returning id into conv;

  insert into public.groups (conversation_id, owner_id, name, description, image_url, category)
    values (conv, me, p_name, p_description, p_image_url, p_category)
    returning id into g;

  insert into public.conversation_members (conversation_id, user_id, role)
    values (conv, me, 'owner');

  return g;
end $$;

-- Per Einladungscode beitreten (serverseitige Validierung, Abschnitt 11/12).
create or replace function public.join_group_with_code(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  inv record;
  g record;
  member_count int;
begin
  if me is null then raise exception 'not authenticated'; end if;

  select * into inv from public.group_invitations
  where code = upper(trim(p_code)) and active
    and (expires_at is null or expires_at > now())
  order by created_at desc limit 1;

  if not found then
    raise exception 'INVALID_CODE' using errcode = 'P0002';
  end if;

  select * into g from public.groups where id = inv.group_id;
  if not found then raise exception 'INVALID_CODE' using errcode = 'P0002'; end if;

  if public.is_conversation_member(g.conversation_id, me) then
    return json_build_object('alreadyMember', true, 'groupId', g.id, 'name', g.name);
  end if;

  -- Blockierte Nutzer können nicht beitreten (Owner hat sie blockiert).
  if public.has_blocked(g.owner_id, me) then
    raise exception 'BLOCKED' using errcode = 'P0001';
  end if;

  select count(*) into member_count
  from public.conversation_members where conversation_id = g.conversation_id;

  insert into public.conversation_members (conversation_id, user_id)
    values (g.conversation_id, me);

  return json_build_object('alreadyMember', false, 'groupId', g.id,
                           'name', g.name, 'memberCount', member_count + 1);
end $$;

-- Gruppe per Vorschau-Code ansehen (vor dem Beitreten, Abschnitt 11):
-- zeigt Name + Mitgliederzahl, ohne Mitglied sein zu müssen.
create or replace function public.preview_group_by_code(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare
  inv record;
  g record;
  member_count int;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;

  select * into inv from public.group_invitations
  where code = upper(trim(p_code)) and active
    and (expires_at is null or expires_at > now())
  order by created_at desc limit 1;

  if not found then
    raise exception 'INVALID_CODE' using errcode = 'P0002';
  end if;

  select * into g from public.groups where id = inv.group_id;
  if not found then raise exception 'INVALID_CODE' using errcode = 'P0002'; end if;

  select count(*) into member_count
  from public.conversation_members where conversation_id = g.conversation_id;

  return json_build_object('groupId', g.id, 'name', g.name,
                           'description', g.description, 'imageUrl', g.image_url,
                           'memberCount', member_count);
end $$;

-- Public-Chat-Mitgliedschaft sicherstellen (beim ersten Chat-Aufruf).
create or replace function public.ensure_public_membership()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  insert into public.conversation_members (conversation_id, user_id)
  values ('00000000-0000-0000-0000-000000000001', auth.uid())
  on conflict do nothing;
end $$;

-- Öffentliche Konversations-ID konstant halten (für Backend/App).
create or replace function public.public_conversation_id()
returns uuid language sql stable set search_path = public as $$
  select '00000000-0000-0000-0000-000000000001'::uuid;
$$;

-- Ungelesene Nachrichten pro Konversation (Abschnitt 17) - effizient in
-- einer Abfrage statt N Rundtrips.
create or replace function public.unread_counts()
returns table (conversation_id uuid, unread bigint)
language sql security definer stable set search_path = public as $$
  select m.conversation_id, count(*) as unread
  from public.messages m
  join public.conversation_members cm
    on cm.conversation_id = m.conversation_id
   and cm.user_id = auth.uid()
  where m.created_at > cm.last_read_at
    and m.sender_id <> auth.uid()
    and m.deleted_at is null
  group by m.conversation_id;
$$;

-- Nachrichten als gelesen markieren (beim Öffnen eines Chats).
create or replace function public.mark_read(conv uuid)
returns void language sql security definer set search_path = public as $$
  update public.conversation_members
  set last_read_at = now()
  where conversation_id = conv and user_id = auth.uid();
$$;

-- Nachrichten-Historie mit Pagination (Abschnitt 36): letzte N Nachrichten
-- VOR einem Cursor (created_at).
create or replace function public.fetch_messages(
  conv uuid, p_before timestamptz default null, p_limit int default 30
)
returns setof public.messages
language sql security definer stable set search_path = public as $$
  select * from public.messages
  where conversation_id = conv
    and (p_before is null or created_at < p_before)
  order by created_at desc
  limit p_limit;
$$;

-- Presence: last_seen aktualisieren (Abschnitt 18).
create or replace function public.touch_presence()
returns void language sql security definer set search_path = public as $$
  update public.users set last_seen_at = now() where id = auth.uid();
$$;

-- ============================================================================
-- MotoRoute: COMMUNITY-SPERRUNGS-RADAR (Gefahrenmeldungen)
--
-- Migration ZU schema.sql (+ schema_group_routes/schema_group_rides).
-- Idempotent.
--
-- Biker melden unterwegs Gefahrenstellen: Rollsplitt, Straßensperrungen,
-- Baustellen, Ölspuren. Kern-Regeln:
--
-- 1. POSTGIS: Die Position liegt als geography(POINT) in der DB - alle
--    Umkreis-Abfragen laufen über ST_DWithin (indexgestützt, in Metern).
--    latitude/longitude sind zusätzlich denormalisiert gespeichert (die
--    App braucht die flachen Werte; die POINT-Spalte ist für die Räum-
--    abfragen).
-- 2. ABLAUF: Eine Meldung ist standardmäßig 24 h aktiv. Ein Upvote
--    ("Gefahr ist noch da") verlängert um 6 h, hart gedeckelt auf 72 h
--    ab Erstellung - eine von vielen Fahrern bestätigte Gefahr verschwin-
--    det nicht nach 24 h, vergammelt aber auch nie in der Karte.
-- 3. KONSOLIDIERUNG: Mehrere Meldungen desselben Typs innerhalb 100 m
--    verschmelzen zu EINEM Report (upvotes + 1) statt die Karte zu
--    fluten - die erste Fahrt durch die Baustelle erzeugt den Eintrag,
--    jede weitere bestätigt ihn.
-- 4. 1 UPVOTE PRO NUTZER: Erzwungen in SQL (Tabelle hazard_report_votes),
--    nicht im Client. Der Zähler bleibt dadurch belastbar.
-- ============================================================================

do $$ begin
  create type public.hazard_report_type as enum ('rollsplitt', 'sperrung', 'baustelle', 'oelspur');
exception when duplicate_object then null; end $$;

create table if not exists public.hazard_reports (
  id          uuid primary key default gen_random_uuid(),
  report_type public.hazard_report_type not null,
  description text not null default '',
  location    public.geography(point, 4326) not null,
  latitude    double precision not null,
  longitude   double precision not null,
  upvotes     integer not null default 1,      -- Erstmeldung zählt als erster Upvote
  created_by  uuid references public.users(id) on delete set null,
  is_active   boolean not null default true,   -- Moderation/Deaktivierung
  expires_at  timestamptz not null default now() + interval '24 hours',
  created_at  timestamptz not null default now()
);

-- Umkreis-Abfrage (ST_DWithin) indexgestützt.
create index if not exists hazard_reports_location_idx
  on public.hazard_reports using gist (location);
-- Radar-Scan filtert auf aktiv + nicht abgelaufen.
create index if not exists hazard_reports_active_idx
  on public.hazard_reports (is_active, expires_at);

-- 1 Upvote pro Nutzer pro Report (Serverseitig erzwungen, Abschnitt 23/29
-- der Chat-Vorgabe analog: Blockierung von Missbrauch nie nur im Client).
create table if not exists public.hazard_report_votes (
  report_id  uuid not null references public.hazard_reports(id) on delete cascade,
  user_id    uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (report_id, user_id)
);

-- RLS: Direkte Tabellenzugriffe bleiben gesperrt - der gesamte Schreib-
-- weg läuft über die SECURITY DEFINER-RPCs (Konsolidierung/Validierung
-- dort), das Lesen über den RPC unten. Es gibt bewusst KEINE Policy für
-- anon - die Daten fließen nur über das authentifizierte BFF.
alter table public.hazard_reports enable row level security;
alter table public.hazard_report_votes enable row level security;

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

-- Neue Gefahrenmeldung. Konsolidiert mit einer aktiven Meldung desselben
-- Typs im 100-m-Umkreis (statt Duplikat: bestehender Report + 1 Upvote,
-- Gültigkeit refreshed). Antwort: { id, merged, upvotes }.
create or replace function public.hazard_report_create(
  p_type        public.hazard_report_type,
  p_lat         double precision,
  p_lng         double precision,
  p_description text default ''
)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_point public.geography;
  v_id    uuid;
  v_row   public.hazard_reports%rowtype;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'INVALID_COORDS' using errcode = '22023';
  end if;

  v_point := public.st_setsrid(public.st_makepoint(p_lng, p_lat), 4326);

  select * into v_row
  from public.hazard_reports h
  where h.report_type = p_type
    and h.is_active
    and h.expires_at > now()
    and public.st_dwithin(h.location, v_point, 100)
  order by h.created_at desc
  limit 1
  for update;

  if found then
    update public.hazard_reports
      set upvotes = upvotes + 1,
          expires_at = now() + interval '24 hours'
      where id = v_row.id;
    return json_build_object('id', v_row.id, 'merged', true, 'upvotes', v_row.upvotes + 1);
  end if;

  insert into public.hazard_reports
    (report_type, description, location, latitude, longitude, upvotes, created_by)
  values
    (p_type, left(coalesce(p_description, ''), 500), v_point, p_lat, p_lng, 1, auth.uid())
  returning id into v_id;

  return json_build_object('id', v_id, 'merged', false, 'upvotes', 1);
end $$;

-- Aktive Gefahren im Umkreis (Standard 24-h-Ablauf via expires_at > now()).
-- Radius wird auf [100 m, 100 km] geklemmt (Missbrauch-Deckel). Keine
-- Nutzer-Identitäten in der Antwort - nur aggregierte Gefahrenorte.
create or replace function public.hazard_report_nearby(
  p_lat      double precision,
  p_lng      double precision,
  p_radius_m double precision default 50000
)
returns json language sql security definer stable set search_path = public as $$
  select coalesce(json_agg(row_to_json(h)), '[]'::json)
  from (
    select h.id, h.report_type, h.description, h.latitude, h.longitude,
           h.upvotes, h.created_at, h.expires_at,
           public.st_distance(h.location, public.st_setsrid(public.st_makepoint(p_lng, p_lat), 4326))::int as distance_m
    from public.hazard_reports h
    where h.is_active
      and h.expires_at > now()
      and public.st_dwithin(
            h.location,
            public.st_setsrid(public.st_makepoint(p_lng, p_lat), 4326),
            least(greatest(p_radius_m, 100), 100000))
    order by h.created_at desc
  ) h;
$$;

-- Upvote = Bestätigung "die Gefahr existiert noch". Validierung:
-- - Report existiert nicht        -> NOT_FOUND (P0002)
-- - Report abgelaufen             -> wird deaktiviert, EXPIRED (P0001)
-- - bereits upgevotet (dieser     -> idempotent, kein erneutes Inkrement
--   Nutzer)                          ({ alreadyVoted: true })
-- Bestätigung verlängert die Gültigkeit um 6 h, max. 72 h ab Erstellung.
create or replace function public.hazard_report_upvote(p_id uuid)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_row      public.hazard_reports%rowtype;
  v_inserted timestamptz;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;

  select * into v_row from public.hazard_reports where id = p_id for update;
  if not found then raise exception 'NOT_FOUND' using errcode = 'P0002'; end if;

  -- "Existiert die Gefahr noch?"-Prüfung: Abgelaufene Meldungen nehmen
  -- keine Upvotes mehr an und werden beim Versuch deaktiviert.
  if v_row.expires_at <= now() then
    update public.hazard_reports set is_active = false where id = v_row.id;
    raise exception 'EXPIRED' using errcode = 'P0001';
  end if;

  insert into public.hazard_report_votes (report_id, user_id)
  values (p_id, auth.uid())
  on conflict (report_id, user_id) do nothing
  returning created_at into v_inserted;

  if v_inserted is null then
    return json_build_object('upvotes', v_row.upvotes, 'alreadyVoted', true, 'expiresAt', v_row.expires_at);
  end if;

  update public.hazard_reports
    set upvotes = upvotes + 1,
        expires_at = least(expires_at + interval '6 hours', created_at + interval '72 hours')
    where id = v_row.id
    returning upvotes, expires_at into v_row.upvotes, v_row.expires_at;

  return json_build_object('upvotes', v_row.upvotes, 'alreadyVoted', false, 'expiresAt', v_row.expires_at);
end $$;

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

-- ============================================================================
-- PREMIUM-VORBEREITUNG (nur Architektur - KEINE Zahlung, KEINE Paywall)
--
-- Aktuelle Testphase: alles kostenlos und voll freigeschaltet. Diese Sektion
-- haelt nur den Status vor: users.plan ('free' ab Werk) + subscriptions-Tabelle
-- (fuer einen spaeteren Zahlungsdienst, z.B. Stripe-Webhook via service_role).
-- Das Frontend haelt keine eigene Premium-Logik - Entitlements werden nur im
-- Backend gelesen und in /v1/auth/me mitgeliefert.
-- ============================================================================

alter table public.users
  add column if not exists plan text not null default 'free'
    check (plan in ('free', 'premium'));

create table if not exists public.subscriptions (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references public.users(id) on delete cascade,
  plan               text not null default 'free' check (plan in ('free', 'premium')),
  status             text not null default 'active'
                       check (status in ('active', 'trialing', 'past_due', 'canceled')),
  provider           text,
  provider_ref       text,
  current_period_end timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

-- Ein aktives Abo pro Nutzer (Teilabbos nur mit anderem Status).
create unique index if not exists subscriptions_user_active_idx
  on public.subscriptions (user_id)
  where status in ('active', 'trialing', 'past_due');

alter table public.subscriptions enable row level security;

-- Lesen darf der Nutzer nur das eigene Abo. Schreiben (insert/update) bewusst
-- OHNE Policy: nur service_role (RLS-Bypass, spaeterer Zahlungs-Webhook).
drop policy if exists subscriptions_select_own on public.subscriptions;
create policy subscriptions_select_own on public.subscriptions
  for select to authenticated
  using (auth.uid() = user_id);
