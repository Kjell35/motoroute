-- 0004: Fahrhistorie im Benutzerprofil - rides, visited places, privacy.
--
-- DATENSCHUTZ ZUERST: Alles DEFAULT PRIVAT. Kein Standort-Datum ist
-- oeffentlich, das der Nutzer nicht ausdruecklich freigegeben hat.
--
-- users-Erweiterungen (5 Schalter, spiegeln die Anforderung 1:1):
--   ride_history_enabled  bool (Default true)    Aufzeichnung ueberhaupt
--   auth_privacy          'private' | 'public'   (Default: private)
--   share_rides           bool (Default false)   gefahrene Strecken
--   share_places          bool (Default false)   besuchte Orte
--   hide_start_end        bool (Default true)    exakte Start/Ziel-Punkte verbergen
--
-- ride_history: eine Zeile pro abgeschlossener Navigation (automatisch
-- aus der Tour-Aufzeichnung synchronisiert - NIE erfundene Daten).
--   is_public: pro-Tour OPT-IN (die globale Einstellung filtert nur das
--   bereits freigegebene; pro Tour kann man zusätzlich zurückziehen).
--   share_track: nur die Statistik zeigen, die GPS-Linie zurückziehen.
--
-- place_visits: abgeleitete Orte aus den Touren (POI-Stopps, Start-/Ziel-
-- Ortsnamen). Kategorien: fuel, restaurant, hotel, camping, bikertreff, other.

create table if not exists public.ride_history (
  id                    bigserial primary key,
  user_id               uuid not null references public.users(id) on delete cascade,
  external_id           text not null,
  title                 text not null,
  started_at            timestamptz not null,
  ended_at              timestamptz not null,
  distance_meters       double precision not null default 0,
  duration_seconds      double precision not null default 0,
  elevation_gain_meters double precision not null default 0,
  track                 jsonb not null default '[]'::jsonb,
  pois                  jsonb not null default '[]'::jsonb,
  start_label           text,
  end_label             text,
  start_lat             double precision,
  start_lng             double precision,
  end_lat               double precision,
  end_lng               double precision,
  region                text,
  description           text,
  photos                jsonb not null default '[]'::jsonb,
  is_public             boolean not null default false,
  share_track           boolean not null default false,
  created_at            timestamptz not null default now(),
  unique (user_id, external_id)
);

create index if not exists ride_history_user_idx
  on public.ride_history (user_id, started_at desc);

create table if not exists public.place_visits (
  id              bigserial primary key,
  user_id         uuid not null references public.users(id) on delete cascade,
  external_id     text not null,
  category        text not null default 'other'
                  check (category in ('fuel','restaurant','hotel','camping','bikertreff','other')),
  label           text not null,
  lat             double precision not null,
  lng             double precision not null,
  visit_count     integer not null default 1,
  last_visited_at timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  unique (user_id, external_id)
);

create index if not exists place_visits_user_idx
  on public.place_visits (user_id, last_visited_at desc);

-- users: 5 Privacy-Flags (idempotent)
alter table public.users
  add column if not exists ride_history_enabled boolean not null default true;
alter table public.users
  add column if not exists auth_privacy text not null default 'private'
    check (auth_privacy in ('private','public'));
alter table public.users
  add column if not exists share_rides boolean not null default false;
alter table public.users
  add column if not exists share_places boolean not null default false;
alter table public.users
  add column if not exists hide_start_end boolean not null default true;

comment on column public.users.auth_privacy is
  'Fahrhistorie sichtbar: private (Default) oder public. Sensible Standortdaten sind NIE per Default oeffentlich.';
comment on column public.users.hide_start_end is
  'Exakte Start-/Ziel-Koordinaten in der oeffentlichen Tour-Ansicht unterdruecken (Default: an = verbergen).';

-- ================= RLS =================
alter table public.ride_history enable row level security;
alter table public.place_visits enable row level security;

-- Schreibzugriff: nur eigene Zeilen (Client-RLS; der Sync läuft über
-- das Backend mit Service-Role, das ist nicht RLS-gebunden).
drop policy if exists ride_history_all_own on public.ride_history;
create policy ride_history_all_own on public.ride_history
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists place_visits_all_own on public.place_visits;
create policy place_visits_all_own on public.place_visits
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Oeffentliche Lesesicht: Ein Profil ist lesbar, wenn der Besitzer es
-- oeffentlich geschaltet hat (auth_privacy='public' UND Kategorie-
-- Freigabe) UND der Betrachter nicht blockiert ist. Blockaden wirken
-- in beide Richtungen (b.user_id = Besitzer ODER Betrachter).
drop policy if exists ride_history_public_read on public.ride_history;
create policy ride_history_public_read on public.ride_history
  for select using (
    auth.uid() = user_id
    or (
      is_public = true
      and exists (
        select 1 from public.users u
        where u.id = ride_history.user_id
          and u.auth_privacy = 'public'
          and u.share_rides = true
          and not exists (
            select 1 from public.blocked_users b
            where (b.user_id = ride_history.user_id and b.blocked_user_id = auth.uid())
               or (b.user_id = auth.uid() and b.blocked_user_id = ride_history.user_id)
          )
      )
    )
  );

drop policy if exists place_visits_public_read on public.place_visits;
create policy place_visits_public_read on public.place_visits
  for select using (
    auth.uid() = user_id
    or exists (
      select 1 from public.users u
      where u.id = place_visits.user_id
        and u.auth_privacy = 'public'
        and u.share_places = true
        and not exists (
          select 1 from public.blocked_users b
          where (b.user_id = place_visits.user_id and b.blocked_user_id = auth.uid())
             or (b.user_id = auth.uid() and b.blocked_user_id = place_visits.user_id)
        )
    )
  );
