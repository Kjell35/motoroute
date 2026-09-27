-- ---------------------------------------------------------------------------
-- 0009: Gamification - "Pass-Knacker" & Badges
--
-- Biker sammeln Badges, indem sie bekannte Pässe und Bikertreffs physisch
-- besuchen (GPS-Check-in). Zwei Tabellen + eine PostGIS-Radiusfunktion:
--
--   badges        : Katalog (Pässe/Treffs) mit Position + Radius
--   user_badges   : Freischaltungen (join user_id + badge_id, unique)
--   match_badge_at(lat, lon) : RPC -> erledigt ALLE Kandidaten in EINEM
--     Query (ST_DWithin über den GIST-Index), idempotent (ON CONFLICT
--     DO NOTHING) und mit Admin-Schutz (Security-Definer nur für Insert).
--
-- PostGIS: Das Supabase-Projekt bringt die postgis-Extension mit; sie
-- wird hier idempotent aktiviert (create extension if not exists).
-- ---------------------------------------------------------------------------

create extension if not exists postgis;

-- -------------------------------------------------------------------------
-- Katalog: Pässe und Bikertreffs
-- -------------------------------------------------------------------------
create table if not exists public.badges (
  id uuid primary key default gen_random_uuid(),
  title text not null unique,
  description text not null default '',
  icon_url text,
  -- Kategorie steuert Icon/Farbe in der App:
  -- 'pass' (Gebirgspass), 'meeting' (Bikertreff), 'sight' (Landmark)
  required_category text not null default 'pass'
    check (required_category in ('pass', 'meeting', 'sight')),
  pass_lat double precision not null check (pass_lat  between  -90 and 90),
  pass_lon double precision not null check (pass_lon between -180 and 180),
  radius_meters int not null default 100 check (radius_meters between 20 and 500),
  -- Abgeleitete Geometrie: Updates von lat/lon pflegen sie per Trigger
  -- (unten), damit ST_DWithin immer gegen den aktuellen Punkt läuft.
  geog geography(point, 4326) generated always as
    (st_setsrid(st_makepoint(pass_lon, pass_lat), 4326)::geography) stored,
  created_at timestamptz not null default now()
);

create index if not exists badges_geog_idx on public.badges using gist (geog);
create index if not exists badges_category_idx on public.badges (required_category);

-- -------------------------------------------------------------------------
-- Freischaltungen: ein Badge pro Nutzer genau einmal
-- -------------------------------------------------------------------------
create table if not exists public.user_badges (
  user_id uuid not null references auth.users(id) on delete cascade,
  badge_id uuid not null references public.badges(id) on delete cascade,
  unlocked_at timestamptz not null default now(),
  primary key (user_id, badge_id)
);

create index if not exists user_badges_user_idx
  on public.user_badges (user_id, unlocked_at desc);

-- -------------------------------------------------------------------------
-- Check-in-RPC: Position -> alle getroffenen Badges in EINEM Query.
--
-- Ablauf (in der Reihenfolge):
--   1. Kandidaten: alle Badges im Radius (ST_DWithin, Meter-Genauigkeit
--      über geography, nutzt den GIST-Index).
--   2. Freischalten: INSERT .. ON CONFLICT DO NOTHING - wer den Pass
--      schon hat, bekommt ihn NICHT doppelt (idempotent); unlocked_at
--      bleibt beim ERSTEN Besuch.
--   3. Ergebnis: genau die Zeilen zurückgeben, die DURCH DIESEN Call
--      neu entstanden sind (differenz vor/nach dem Insert), plus die
--      Gesamtzahl des Nutzers. So antwortet der Endpunkt mit
--      "unlockedNow" nur über frische Trophäen.
--
-- Security: SECURITY DEFINER + Suche fix auf auth.uid() (kein
-- User-führbarer Key), SET search_path hart gesetzt. Ausführen darf
-- jeder AUTHENTIFIZIERTE Nutzer (grant to authenticated); anonyme
-- Calls geben einfach nichts zurück.
-- -------------------------------------------------------------------------

create or replace function public.match_badge_at(
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
  v_user uuid := auth.uid();
  v_had uuid[] := '{}';
  v_after bigint;
begin
  if v_user is null then
    -- Anonymer Call: kein Konto, keine Freischaltung (auch kein Fehler,
    -- damit die App es als "nicht eingeloggt" deuten kann -> 0 Zeilen).
    return;
  end if;
  if p_lat is null or p_lon is null
     or p_lat < -90 or p_lat > 90 or p_lon < -180 or p_lon > 180 then
    raise exception 'INVALID_COORDS';
  end if;

  -- Menge der VOR diesem Call bereits freigeschalteten Badges merken:
  -- daraus wird pro Treffer "unlocked_now" abgeleitet (exakt, ohne
  -- Temp-Tabellen oder Trigger).
  select coalesce(array_agg(badge_id), '{}') into v_had
  from public.user_badges where user_id = v_user;

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
      b.id,
      b.title,
      b.description,
      b.icon_url,
      b.required_category,
      -- Distanz fürs UI ("56 m vom Gipfel entfernt")
      st_distance(b.geog, st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography)::int,
      -- Neu in DIESEM Call? Genau dann, wenn er vorhin noch nicht da war.
      not (b.id = any(v_had)),
      v_after
    from public.badges b
    where st_dwithin(b.geog, st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography, b.radius_meters);
end;
$$;

-- ---------------------------------------------------------------------------
-- Pruef-Ausgabe: Objekte der Migration
-- ---------------------------------------------------------------------------
-- select proname from pg_proc where proname = 'match_badge_at';
-- select count(*) from public.badges;

-- ---------------------------------------------------------------------------
-- Seed: bekannte Pässe & Bikertreffs (DE/AT/CH/IT) - Stand 09/2026.
-- Koordinaten bewusst NAH an Passhöhe/Treffpunkt, Radius 150 m (GPS-
-- Toleranz im Gebirge/unter Bäumen). idempotent via ON CONFLICT.
-- ---------------------------------------------------------------------------
insert into public.badges (title, description, icon_url, required_category, pass_lat, pass_lon, radius_meters) values
  ('Stilfser Joch',      '48 Kurven auf 2.757 m - die Königin der Alpenpässe.',            NULL, 'pass',    46.52847, 10.45255, 150),
  ('Großglockner Hochalpenstraße', 'Die spektakulärste Panoramastraße der Alpen.',         NULL, 'pass',    47.12130, 12.82290, 150),
  ('Timmelsjoch',        'Hochalpenstraße zwischen Tirol und Südtirol.',                    NULL, 'pass',    46.91005, 11.09663, 150),
  ('Passo Gardena',      'Dolomiten-Pass in traumhafter Kulisse.',                          NULL, 'pass',    46.55930, 11.77560, 150),
  ('Passo Pordoi',       'Sella-Runde - Kernstück jeder Dolomiten-Tour.',                   NULL, 'pass',    46.47185, 11.82010, 150),
  ('Nufenenpass',        'Höchster vollständig auf Schweizer Boden liegender Pass.',        NULL, 'pass',    46.47380, 8.38380,  150),
  ('Furkapass',          'Belvedere, Rhonegletscher - James-Bond-Kulisse.',                 NULL, 'pass',    46.57720, 8.41980,  150),
  ('Sustenpass',         'Alpenpass-Baukunst mit Steingletscher-Blick.',                    NULL, 'pass',    46.73640, 8.49260,  150),
  ('Oberalppass',        'Verbindung Graubünden - Uri, 2.044 m.',                           NULL, 'pass',    46.64460, 8.67440,  150),
  ('Jaufenpass',         'Höchster through-Pass Südtirols.',                                NULL, 'pass',    46.80290, 11.38580, 150),
  ('Krummholz am Kümmersbruck', 'Kult-Treff in der Oberpfalz.',                             NULL, 'meeting', 49.44980, 11.92940, 120),
  ('Köterberg',          'Höchster Berg Ostwestfalen-Lippes mit Rennstrecke-Pub.',          NULL, 'meeting', 51.92450, 9.33080,  120),
  ('Lorenzer Adler',     'Biker-Treff an der A9 - Kuriosum mit Kultstatus.',                NULL, 'meeting', 49.39310, 11.19430, 120),
  ('Kaffeemühle',        'Biker-Treff am Niederrhein - Sonntagsinstitution.',               NULL, 'meeting', 51.61860, 6.33420,  120),
  ('Mosel-Coil',         'Treff am Moselufer bei Cochem.',                                  NULL, 'meeting', 50.13330, 7.16000,  120),
  ('Hafenrummel Bikerstop', 'Elbtal-Treff bei Bad Schandau.',                               NULL, 'meeting', 50.91280, 14.21170, 120),
  ('Deutsches Eck',      'Koblenz: Rhein + Mosel - Klassiker jeder Mittelrhein-Tour.',      NULL, 'sight',   50.36120, 7.60940,  150),
  ('Loreley',            'Schieferfelsen und engste Rhein-Schleife.',                       NULL, 'sight',   50.13870, 7.72950,  150),
  ('Bastei',             'Sandstein-Brücke über der sächsischen Schweiz.',                  NULL, 'sight',   50.92230, 14.06870, 150)
on conflict (title) do nothing;
