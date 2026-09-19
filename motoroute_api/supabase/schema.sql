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
