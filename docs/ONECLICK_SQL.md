# Migrationen 0008 + 0009 in einem Schritt (Copy-Paste)

Diese Datei fasst zwei Migrationen zusammen, die nur im Supabase-Dashboard
ausgeführt werden können:

- **0008** – Tabelle `app_error_reports` (anonymes Fehler-Reporting)
- **0009** – Badges / „Pass-Knacker“ (PostGIS, Tabellen `badges` + `user_badges`,
  Funktion `match_badge_at(p_user_id, lat, lon)`, RLS, 19 Seed-Einträge)

Beide sind idempotent (`if not exists` / `on conflict do nothing`) und können
gefahrlos ein zweites Mal ausgeführt werden.

> **Fix 01.10.2026 (v2):** In `match_badge_at` gab es ZWEI Ambiguitätsstellen
> gegen den Output-Parameter `badge_id`: die `array_agg(badge_id)`-Zeile
> (unqualifiziert, gefixt via `ub.`-Alias) und die Spalten-Inferenz in
> `on conflict (user_id, badge_id)` (gefixt via `on constraint`). Jeder
> Check-in endete sonst in 503. Wer die Migration schon ausgeführt hat,
> muss NUR den Funktionsblock erneut ausführen
> (siehe `docs/SUPABASE_HOTFIX_MATCH_BADGE_AT.sql`).

> **Reihenfolge:** Zuerst das Backend mit dem Code dieses Releases deployen
> (es ruft `match_badge_at` mit `p_user_id` auf), dann diesen Block ausführen.

## So geht's

1. Supabase-Dashboard öffnen → Projekt `icdjggzlwyeacuwsudtu`
2. Links **SQL Editor** → **New query**
3. **Den kompletten SQL-Block unten** einfügen (nur den Inhalt zwischen den
   ```` ```sql ````-Zeilen)
4. **Run** klicken. Erwartet: „Success. No rows returned“
5. Prüfen (neue Query):

```sql
select table_name from information_schema.tables
 where table_schema='public' and table_name in ('app_error_reports','badges','user_badges');  -- 3 Zeilen
select count(*) from public.badges;                                                            -- 19
select proname from pg_proc where proname = 'match_badge_at';                                  -- 1 Zeile
select relname, relrowsecurity from pg_class where relname in ('badges','user_badges');        -- beide true
```

## Seed-Koordinaten: Stand der Prüfung

- **Geprüft (gegen Wikipedia) und korrigiert:** Jaufenpass (46.8400 / 11.3075),
  Sustenpass (46.7300 / 8.4490), Passo Pordoi (46.4847 / 11.8361), Furkapass
  (46.5725 / 8.4142), Oberalppass (46.6586 / 8.6711), Nufenenpass (46.4746 /
  8.3883) und Bastei (50.9619 / 14.0732). Die ursprünglichen Werte lagen teils
  400 m bis 4,4 km daneben (Bastei war der größte Ausreißer).
- **Nicht verifizierbar:** Namen und genaue Lage einiger Bikertreffs (z. B.
  „Mosel-Coil“, „Hafenrummel Bikerstop“) - hier bitte die Punkte auf der Karte
  gegenprüfen und bei Abweichung korrigieren.
- Pässe haben jetzt 300 m Radius (Wikipedia-Koordinaten sind gerundet).
- Korrekturen sind jederzeit möglich, ohne diese Migration zu ändern:
  per `update public.badges set pass_lat = …, pass_lon = … where title = '…';`
  oder über das neue Admin-Formular in der App (Plus-Symbol im Pass-Knacker).

## SQL

```sql
-- ---------------------------------------------------------------------------
-- 0008: Anonymes Fehler-/Crash-Reporting (app_error_reports)
--
-- Zweck: Die App meldet fehlgeschlagene Aktionen (Chat laden, Marktplatz
-- einreichen, Garage verbinden, Abstuerze) OHNE personenbezogene Daten an
-- diese Tabelle. Support/Admin sieht dann im Backend, WELCHE Bereiche bei
-- WIE VIELEN Nutzern haken - ohne Screenshots.
--
-- Anonymisierung (durchgesetzt in der App, hier nur Spaltenstruktur):
--   - user_hash = SHA-256(user_id + tageswechselndes Salz): erlaubt
--     "wie viele EINZELNE Nutzer betroffen" ohne Rückschluss auf IDs.
--   - Keine user_id, keine E-Mail, keine Free-Text-Logs. Nur Kategorie,
--     technische Ursache (kurz), HTTP-Status, Plattform, App-Version.
-- ---------------------------------------------------------------------------

create table if not exists public.app_error_reports (
  id uuid primary key default gen_random_uuid(),
  user_hash text not null,                -- SHA-256, 64 Hex-Zeichen, tageswechselnd
  category text not null,                 -- z. B. chat.load, mp.create, crash
  cause text not null,                    -- technische Ursache (max 300 Zeichen)
  http_status int,                        -- null bei Netz-/Timeout-Fehlern
  platform text not null,                 -- android / ios / web
  app_version text not null,              -- z. B. 0.4.6
  created_at timestamptz not null default now()
);

create index if not exists app_error_reports_created_idx
  on public.app_error_reports (created_at desc);
create index if not exists app_error_reports_category_idx
  on public.app_error_reports (category, created_at desc);

-- RLS: Standardmaessig alles zu. Der Service-Client (Backend, SERVICE_ROLE)
-- schreibt/liest ueber RLS-hinweg; die App insertet mit USER-Token:
--   - INSERT nur fuer eingeloggte Nutzer (anonym = verworfen)
--   - SELECT/UPDATE/DELETE fuer Endnutzer: nie
alter table public.app_error_reports enable row level security;

drop policy if exists "app_error_reports_insert_authed" on public.app_error_reports;
create policy "app_error_reports_insert_authed"
  on public.app_error_reports for insert
  to authenticated
  with check (true);

-- Admin-Lesezugriff (Dashboard/SQL-Editor & Backend-Admin-Endpunkt):
drop policy if exists "app_error_reports_admin_select" on public.app_error_reports;
create policy "app_error_reports_admin_select"
  on public.app_error_reports for select
  to authenticated
  using (
    exists (
      select 1 from public.users u
      where u.id = auth.uid() and u.role = 'admin'
    )
  );

-- ----------------------------------------------------------------------
-- Pruef-Ausgabe: Objekte der Migration
-- ----------------------------------------------------------------------
-- select table_name from information_schema.tables
--   where table_schema='public' and table_name='app_error_reports';

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
-- Security: SECURITY DEFINER, SET search_path hart gesetzt. Das Backend
-- ruft die RPC mit dem SERVICE-ROLE-Client auf (dort ist auth.uid()
-- NULL) und übergibt die bereits per JWT verifizierte user_id als
-- p_user_id. Deshalb darf die Funktion NUR service_role ausführen
-- (revoke unten) - sonst könnte jeder mit dem anon-Key fremde
-- Freischaltungen erzeugen.
-- -------------------------------------------------------------------------

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
  -- ON CONSTRAINT statt Spaltenliste: Bei Spalten-Inferenz in ON CONFLICT
  -- kollidiert 'badge_id' mit dem gleichnamigen Output-Parameter aus
  -- 'returns table (...)' (42702, zweite Ambiguitaetsstelle neben der
  -- array_agg-Zeile). Die Constraint-Variante braucht keine Spaltennamen.
  on conflict on constraint user_badges_pkey do nothing;

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

-- Alte 2-Arg-Ueberladung (auth.uid()-basiert, Claudes Original) entfernen,
-- damit PostgREST eindeutig die 3-Arg-Version (p_user_id) auftreibt:
drop function if exists public.match_badge_at(double precision, double precision);

revoke all on function public.match_badge_at(uuid, double precision, double precision) from public, anon, authenticated;
grant execute on function public.match_badge_at(uuid, double precision, double precision) to service_role;

-- -------------------------------------------------------------------------
-- RLS: Tabellen in public sind sonst per PostgREST/anon-Key les- und
-- schreibbar. Das Backend nutzt den Service-Role-Key (umgeht RLS);
-- Endnutzer dürfen höchstens lesen, nie schreiben.
-- -------------------------------------------------------------------------
alter table public.badges enable row level security;
alter table public.user_badges enable row level security;

drop policy if exists "badges_select_authed" on public.badges;
create policy "badges_select_authed"
  on public.badges for select to authenticated using (true);

drop policy if exists "user_badges_select_own" on public.user_badges;
create policy "user_badges_select_own"
  on public.user_badges for select to authenticated using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Pruef-Ausgabe: Objekte der Migration
-- ---------------------------------------------------------------------------
-- select proname from pg_proc where proname = 'match_badge_at';
-- select count(*) from public.badges;

-- ---------------------------------------------------------------------------
-- Seed: bekannte Pässe & Bikertreffs (DE/AT/CH/IT) - Stand 09/2026.
-- Koordinaten NAH an Passhöhe/Treffpunkt. Pässe: Radius 300 m (Wikipedia-
-- Koordinaten sind gerundet, GPS-Toleranz im Gebirge), Treffs/Sehenswürdigkeiten
-- 120-150 m. ACHTUNG: nicht alle Punkte sind gegen eine Karte geprüft (siehe
-- docs/ONECLICK_SQL.md) - Korrekturen später per UPDATE oder Admin-Endpunkt. idempotent via ON CONFLICT.
-- ---------------------------------------------------------------------------
insert into public.badges (title, description, icon_url, required_category, pass_lat, pass_lon, radius_meters) values
  ('Stilfser Joch',      '48 Kurven auf 2.757 m - die Königin der Alpenpässe.',            NULL, 'pass',    46.52847, 10.45255, 300),
  ('Großglockner Hochalpenstraße', 'Die spektakulärste Panoramastraße der Alpen.',         NULL, 'pass',    47.12130, 12.82290, 300),
  ('Timmelsjoch',        'Hochalpenstraße zwischen Tirol und Südtirol.',                    NULL, 'pass',    46.91005, 11.09663, 300),
  ('Passo Gardena',      'Dolomiten-Pass in traumhafter Kulisse.',                          NULL, 'pass',    46.55930, 11.77560, 300),
  ('Passo Pordoi',       'Sella-Runde - Kernstück jeder Dolomiten-Tour.',                   NULL, 'pass',    46.48470, 11.83610, 300),
  ('Nufenenpass',        'Zweitgrößter befahrener Pass der Schweiz, 2.478 m.',               NULL, 'pass',    46.47460, 8.38830,  300),
  ('Furkapass',          'Belvedere, Rhonegletscher - James-Bond-Kulisse.',                 NULL, 'pass',    46.57250, 8.41420,  300),
  ('Sustenpass',         'Alpenpass-Baukunst mit Steingletscher-Blick.',                    NULL, 'pass',    46.73000, 8.44900,  300),
  ('Oberalppass',        'Verbindung Graubünden - Uri, 2.044 m.',                           NULL, 'pass',    46.65860, 8.67110,  300),
  ('Jaufenpass',         'Nördlichster Alpenpass, der vollständig in Italien liegt.',       NULL, 'pass',    46.84000, 11.30750, 300),
  ('Krummholz am Kümmersbruck', 'Kult-Treff in der Oberpfalz.',                             NULL, 'meeting', 49.44980, 11.92940, 120),
  ('Köterberg',          'Höchster Berg Ostwestfalen-Lippes mit Rennstrecke-Pub.',          NULL, 'meeting', 51.92450, 9.33080,  120),
  ('Lorenzer Adler',     'Biker-Treff an der A9 - Kuriosum mit Kultstatus.',                NULL, 'meeting', 49.39310, 11.19430, 120),
  ('Kaffeemühle',        'Biker-Treff am Niederrhein - Sonntagsinstitution.',               NULL, 'meeting', 51.61860, 6.33420,  120),
  ('Mosel-Coil',         'Treff am Moselufer bei Cochem.',                                  NULL, 'meeting', 50.13330, 7.16000,  120),
  ('Hafenrummel Bikerstop', 'Elbtal-Treff bei Bad Schandau.',                               NULL, 'meeting', 50.91280, 14.21170, 120),
  ('Deutsches Eck',      'Koblenz: Rhein + Mosel - Klassiker jeder Mittelrhein-Tour.',      NULL, 'sight',   50.36120, 7.60940,  150),
  ('Loreley',            'Schieferfelsen und engste Rhein-Schleife.',                       NULL, 'sight',   50.13870, 7.72950,  150),
  ('Bastei',             'Sandstein-Brücke über der sächsischen Schweiz.',                  NULL, 'sight',   50.96190, 14.07320, 150)
on conflict (title) do nothing;
```
