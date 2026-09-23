-- 0005: Kuratierte Biker-POIs direkt im Backend.
--
-- Hintergrund: Der eigenständige TomTom-Kuratierungsdienst
-- (motoroute_poi_service) ist Code-fertig, braucht aber eine eigene
-- PostGIS-Instanz + eigenen Prozess und lief daher nirgends. Diese
-- Migration + der erweiterte PoiService bringen die Kuratierung
-- ON-DEMAND ins BFF: Der vorhandene TRAFFIC_API_KEY (TomTom) kuratiert
-- Biker-relevante Kategorien live bei der Karten-Abfrage; Ergebnisse
-- werden in dieser Tabelle gecacht (Deduplizierung gegen OSM-Funde).
--
-- Die Tabelle `poi` existierte im gesamten Migrations-Setup NICHT,
-- obwohl PoiService.queryDatabase sie selektiert (latenter 500er).
-- Sie kommt hier erstmals an - mit PostGIS-Punkt + RLS.

-- PostGIS ist in 0001 aktiviert; defensively no-op falls schon da.
create extension if not exists postgis;

create table if not exists public.poi (
  id          text primary key,
  -- App-Kategorie (FUEL, MOTO_HOTEL, BIKER_MEETUP, CAMPSITE,
  -- ICE_CREAM, SPEED_CAMERA, RESTAURANT, PUB, SNACK)
  category    text not null check (category in (
                'FUEL','MOTO_HOTEL','BIKER_MEETUP','CAMPSITE',
                'ICE_CREAM','SPEED_CAMERA','RESTAURANT','PUB','SNACK')),
  name        text not null,
  lat         double precision not null,
  lng         double precision not null,
  geom        geography(point, 4326) generated always as
              (st_setsrid(st_makepoint(lng, lat), 4326)) stored,
  -- OSM = Overpass-Fund, CURATED = TomTom-Kuratierung, COMMUNITY = Nutzer
  source      text not null default 'CURATED' check (source in ('OSM','CURATED','COMMUNITY')),
  metadata    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists poi_geom_idx on public.poi using gist (geom);
create index if not exists poi_category_idx on public.poi (category);
create index if not exists poi_updated_idx on public.poi (updated_at desc);

alter table public.poi enable row level security;

-- POIs sind öffentliche Kartendaten: JEDER (auch anonyme Tiles-Clients)
-- darf lesen; schreiben darf nur die Service-Rolle (Kuratierung im
-- Backend läuft mit Service-Key, RLS betrifft nur user-scoped Clients).
create policy "poi_read_public" on public.poi
  for select using (true);

-- update_at automatisch pflegen (idempotent).
create or replace function public.poi_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists poi_touch on public.poi;
create trigger poi_touch
  before update on public.poi
  for each row execute function public.poi_touch_updated_at();

-- Upsert-Helfer für die Kuratierung (Service-Rolle umgeht RLS eh, aber
-- der Trigger + Check-Constraints gelten auch dort).
comment on table public.poi is
  'Kuratierte Biker-POIs: TomTom on-demand (CURATED), OSM-Spiegel (OSM), Community-Meldungen (COMMUNITY).';
