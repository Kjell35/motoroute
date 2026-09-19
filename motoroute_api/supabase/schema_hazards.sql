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
