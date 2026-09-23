-- 0006: Marktplatz (Fahrzeugteile & Zubehör).
--
-- Nur drei Hauptkategorien: motorradteile / autoteile / fahrradteile.
-- Jedes Angebot durchlaeuft SERVERSEITIG eine KI-Pruefung, bevor es
-- oeffentlich erscheint:
--   review_status: 'pending' (wartet auf Pruefung) | 'approved' (sichtbar)
--                | 'rejected' (abgelehnt, Grund in review_reason)
--                | 'manual_review' (unsicherer Fall - Admin entscheidet)
--   review_source: 'ai' | 'admin'
-- Das Backend prueft ERNEUT vor jeder oeffentlichen Anzeige - ein Client
-- kann review_status nie selbst setzen.
--
-- Admins: users.role = 'admin' (unprivilegiert per RLS lesbar, aber nur
-- vom Service-Role-Backend schreibbar - Accounts werden serverseitig
-- vergeben, z.B. ueber PATCH /v1/marketplace/admin/users/:id/role).

alter table public.users
  add column if not exists role text not null default 'user'
  check (role in ('user', 'admin', 'banned'));

-- ---------------------------------------------------------------- listings
create table if not exists public.marketplace_listings (
  id              uuid primary key default gen_random_uuid(),
  seller_id       uuid not null references public.users(id) on delete cascade,
  title           text not null check (char_length(title) between 3 and 120),
  description     text not null default '' check (char_length(description) <= 4000),
  price_cents     integer not null check (price_cents >= 0 and price_cents <= 100000000),
  condition       text not null check (condition in ('neu','sehr_gut','gut','gebraucht','defekt')),
  category        text not null check (category in ('motorradteile','autoteile','fahrradteile')),
  subcategory     text not null,
  brand           text,
  model           text,
  year            integer,
  location_label  text not null,
  lat             double precision,
  lng             double precision,
  shipping        boolean not null default false,
  status          text not null default 'active'
                  check (status in ('active','paused','sold','blocked')),
  review_status   text not null default 'pending'
                  check (review_status in ('pending','approved','rejected','manual_review')),
  review_reason   text,
  review_source   text check (review_source in ('ai','admin')),
  reviewed_at     timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists mpl_active_idx
  on public.marketplace_listings (created_at desc)
  where status = 'active' and review_status = 'approved';
create index if not exists mpl_seller_idx
  on public.marketplace_listings (seller_id, created_at desc);
create index if not exists mpl_category_idx
  on public.marketplace_listings (category, subcategory);
create index if not exists mpl_geo_idx
  on public.marketplace_listings (lat, lng);

-- Trigger: updated_at pflegen (wie poi_touch in 0005)
create or replace function public.mpl_touch()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists mpl_touch_trigger on public.marketplace_listings;
create trigger mpl_touch_trigger
  before update on public.marketplace_listings
  for each row execute function public.mpl_touch();

-- ---------------------------------------------------------------- images
create table if not exists public.marketplace_images (
  id          uuid primary key default gen_random_uuid(),
  listing_id  uuid not null references public.marketplace_listings(id) on delete cascade,
  storage_path text not null,          -- Pfad im Storage-Bucket marketplace-photos
  position    integer not null default 0,
  created_at  timestamptz not null default now()
);

create index if not exists mpl_images_listing_idx
  on public.marketplace_images (listing_id, position);

-- ---------------------------------------------------------------- Kategorien
-- Katalog liegt IM Backend-Code (marketplace.taxonomy.ts) als Single Source
-- of Truth fuer Validierung; hier nur die suchbaren Zeilen fuer Filter-UIs.
create table if not exists public.marketplace_categories (
  key   text primary key,           -- 'motorradteile' | 'autoteile' | 'fahrradteile'
  label_de text not null,
  label_en text not null,
  icon  text not null,
  position integer not null default 0
);

create table if not exists public.marketplace_subcategories (
  id          bigserial primary key,
  category    text not null references public.marketplace_categories(key) on delete cascade,
  key         text not null,
  label_de    text not null,
  label_en    text not null,
  position    integer not null default 0,
  unique (category, key)
);

insert into public.marketplace_categories (key, label_de, label_en, icon, position) values
  ('motorradteile', 'Motorradteile', 'Motorcycle parts', 'motorcycle', 1),
  ('autoteile',     'Autoteile',     'Car parts',        'car',        2),
  ('fahrradteile',  'Fahrradteile',  'Bicycle parts',    'bicycle',    3)
on conflict (key) do nothing;

-- Unterkategorien (Spiegel zu marketplace.taxonomy.ts; Beispiele aus der
-- Anforderung, plus sinnvolle Ergaenzungen pro Fahrzeugtyp)
insert into public.marketplace_subcategories (category, key, label_de, label_en, position) values
  -- Motorrad + Auto teilen die technische Struktur
  ('motorradteile', 'motor',      'Motor',            'Engine',        1),
  ('motorradteile', 'motorenteile','Motorenteile',    'Engine parts',  2),
  ('motorradteile', 'zylinder',   'Zylinder',         'Cylinders',     3),
  ('motorradteile', 'kolben',     'Kolben',           'Pistons',       4),
  ('motorradteile', 'kupplung',   'Kupplung',         'Clutch',        5),
  ('motorradteile', 'auspuff',    'Auspuff',          'Exhaust',       6),
  ('motorradteile', 'kruemmer',   'Krümmer',          'Headers',       7),
  ('motorradteile', 'schalldaempfer','Schalldämpfer', 'Mufflers',      8),
  ('motorradteile', 'fahrwerk',   'Fahrwerk',         'Suspension',    9),
  ('motorradteile', 'stossdaempfer','Stoßdämpfer',    'Shock absorbers',10),
  ('motorradteile', 'gabel',      'Gabel',            'Forks',         11),
  ('motorradteile', 'bremsen',    'Bremsen',          'Brakes',        12),
  ('motorradteile', 'bremsscheiben','Bremsscheiben',  'Brake discs',   13),
  ('motorradteile', 'bremsbelaege','Bremsbeläge',     'Brake pads',    14),
  ('motorradteile', 'bremssaettel','Bremssättel',     'Calipers',      15),
  ('motorradteile', 'bremsleitungen','Bremsleitungen','Brake lines',   16),
  ('motorradteile', 'elektrik',   'Elektrik',         'Electrics',     17),
  ('motorradteile', 'batterie',   'Batterie',         'Battery',       18),
  ('motorradteile', 'licht',      'Licht',            'Lights',        19),
  ('motorradteile', 'steuergeraete','Steuergeräte',  'ECUs',          20),
  ('motorradteile', 'kabel',      'Kabel',            'Cables',        21),
  ('motorradteile', 'elektronik', 'Elektronik',       'Electronics',   22),
  ('motorradteile', 'raeder',     'Räder',            'Wheels',        23),
  ('motorradteile', 'felgen',     'Felgen',           'Rims',          24),
  ('motorradteile', 'reifen',     'Reifen',           'Tires',         25),
  ('motorradteile', 'radteile',   'Radteile',         'Wheel parts',   26),
  ('motorradteile', 'verkleidung','Verkleidung',      'Fairings',      27),
  ('motorradteile', 'kotfluegel', 'Kotflügel',        'Fenders',       28),
  ('motorradteile', 'karosserieteile','Karosserieteile','Body parts',  29),
  ('motorradteile', 'zubehoer',   'Zubehör',          'Accessories',   30),
  ('motorradteile', 'gepaeck',    'Gepäck',           'Luggage',       31),
  ('motorradteile', 'halterungen','Halterungen',      'Mounts',        32),
  ('motorradteile', 'schutzteile','Schutzteile',      'Protection',    33),
  ('motorradteile', 'sonstiges',  'Sonstiges',        'Other',         99),
  ('autoteile',     'motor',      'Motor',            'Engine',        1),
  ('autoteile',     'motorenteile','Motorenteile',    'Engine parts',  2),
  ('autoteile',     'zylinder',   'Zylinder',         'Cylinders',     3),
  ('autoteile',     'kolben',     'Kolben',           'Pistons',       4),
  ('autoteile',     'kupplung',   'Kupplung',         'Clutch',        5),
  ('autoteile',     'auspuff',    'Auspuff',          'Exhaust',       6),
  ('autoteile',     'kruemmer',   'Krümmer',          'Headers',       7),
  ('autoteile',     'schalldaempfer','Schalldämpfer', 'Mufflers',      8),
  ('autoteile',     'fahrwerk',   'Fahrwerk',         'Suspension',    9),
  ('autoteile',     'stossdaempfer','Stoßdämpfer',    'Shock absorbers',10),
  ('autoteile',     'bremsen',    'Bremsen',          'Brakes',        12),
  ('autoteile',     'bremsscheiben','Bremsscheiben',  'Brake discs',   13),
  ('autoteile',     'bremsbelaege','Bremsbeläge',     'Brake pads',    14),
  ('autoteile',     'bremssaettel','Bremssättel',     'Calipers',      15),
  ('autoteile',     'bremsleitungen','Bremsleitungen','Brake lines',   16),
  ('autoteile',     'elektrik',   'Elektrik',         'Electrics',     17),
  ('autoteile',     'batterie',   'Batterie',         'Battery',       18),
  ('autoteile',     'licht',      'Licht',            'Lights',        19),
  ('autoteile',     'steuergeraete','Steuergeräte',  'ECUs',          20),
  ('autoteile',     'kabel',      'Kabel',            'Cables',        21),
  ('autoteile',     'elektronik', 'Elektronik',       'Electronics',   22),
  ('autoteile',     'raeder',     'Räder',            'Wheels',        23),
  ('autoteile',     'felgen',     'Felgen',           'Rims',          24),
  ('autoteile',     'reifen',     'Reifen',           'Tires',         25),
  ('autoteile',     'radteile',   'Radteile',         'Wheel parts',   26),
  ('autoteile',     'karosserie', 'Karosserie',       'Body',          27),
  ('autoteile',     'verkleidung','Verkleidung',      'Fairings',      28),
  ('autoteile',     'kotfluegel', 'Kotflügel',        'Fenders',       29),
  ('autoteile',     'tueren',     'Türen',            'Doors',         30),
  ('autoteile',     'seitenteile','Seitenteile',      'Side panels',   31),
  ('autoteile',     'karosserieteile','Karosserieteile','Body parts',  32),
  ('autoteile',     'zubehoer',   'Zubehör',          'Accessories',   33),
  ('autoteile',     'gepaeck',    'Gepäck',           'Luggage',       34),
  ('autoteile',     'halterungen','Halterungen',      'Mounts',        35),
  ('autoteile',     'schutzteile','Schutzteile',      'Protection',    36),
  ('autoteile',     'innenraum',  'Innenraum',        'Interior',      37),
  ('autoteile',     'sonstiges',  'Sonstiges',        'Other',         99),
  ('fahrradteile',  'antrieb',    'Antrieb',          'Drivetrain',    1),
  ('fahrradteile',  'schaltung',  'Schaltung',        'Gears',         2),
  ('fahrradteile',  'kette',      'Kette',            'Chain',         3),
  ('fahrradteile',  'kurbel',     'Kurbel',           'Crankset',      4),
  ('fahrradteile',  'bremsen',    'Bremsen',          'Brakes',        5),
  ('fahrradteile',  'bremsscheiben','Bremsscheiben',  'Brake discs',   6),
  ('fahrradteile',  'bremsbelaege','Bremsbeläge',     'Brake pads',    7),
  ('fahrradteile',  'raeder',     'Räder',            'Wheels',        8),
  ('fahrradteile',  'laufräder',  'Laufräder',        'Wheelsets',     9),
  ('fahrradteile',  'felgen',     'Felgen',           'Rims',          10),
  ('fahrradteile',  'reifen',     'Reifen',           'Tires',         11),
  ('fahrradteile',  'gabel',      'Gabel',            'Forks',         12),
  ('fahrradteile',  'federung',   'Federung',         'Suspension',    13),
  ('fahrradteile',  'rahmen',     'Rahmen',           'Frames',        14),
  ('fahrradteile',  'lenker',     'Lenker',           'Handlebars',    15),
  ('fahrradteile',  'sattel',     'Sattel',           'Saddles',       16),
  ('fahrradteile',  'pedale',     'Pedale',           'Pedals',        17),
  ('fahrradteile',  'beleuchtung','Beleuchtung',      'Lights',        18),
  ('fahrradteile',  'akku',       'Akku (E-Bike)',    'Battery (E-Bike)', 19),
  ('fahrradteile',  'ebike_motor','E-Bike Motor',     'E-Bike motor',  20),
  ('fahrradteile',  'zubehoer',   'Zubehör',          'Accessories',   21),
  ('fahrradteile',  'gepaeck',    'Gepäck',           'Luggage',       22),
  ('fahrradteile',  'sonstiges',  'Sonstiges',        'Other',         99)
on conflict (category, key) do nothing;

-- ---------------------------------------------------------------- favorites
create table if not exists public.marketplace_favorites (
  user_id    uuid not null references public.users(id) on delete cascade,
  listing_id uuid not null references public.marketplace_listings(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, listing_id)
);

create index if not exists mpl_fav_listing_idx
  on public.marketplace_favorites (listing_id);

-- ---------------------------------------------------------------- reports
create table if not exists public.marketplace_reports (
  id         bigserial primary key,
  listing_id uuid not null references public.marketplace_listings(id) on delete cascade,
  reporter_id uuid not null references public.users(id) on delete cascade,
  reason     text not null check (reason in
             ('falsche_kategorie','nicht_erlaubter_artikel','betrug','falsche_beschreibung','falsche_bilder','sonstiges')),
  details    text check (char_length(details) <= 1000),
  resolved   boolean not null default false,
  created_at timestamptz not null default now(),
  unique (listing_id, reporter_id)          -- 1 Meldung pro Nutzer & Angebot
);

create index if not exists mpl_reports_open_idx
  on public.marketplace_reports (resolved, created_at desc);

-- ---------------------------------------------------------------- RLS
alter table public.marketplace_listings   enable row level security;
alter table public.marketplace_images     enable row level security;
alter table public.marketplace_categories enable row level security;
alter table public.marketplace_subcategories enable row level security;
alter table public.marketplace_favorites  enable row level security;
alter table public.marketplace_reports    enable row level security;

-- Katalog: oeffentlich lesbar
drop policy if exists mpl_categories_read on public.marketplace_categories;
create policy mpl_categories_read on public.marketplace_categories
  for select using (true);
drop policy if exists mpl_subcategories_read on public.marketplace_subcategories;
create policy mpl_subcategories_read on public.marketplace_subcategories
  for select using (true);

-- Listings:
--  * oeffentlich: nur 'active' + 'approved' (das Backend prueft das ERNEUT)
--  * seller: eigene Zeilen in jedem Status (Verwaltung im Profil)
--  * admin: alles (Moderation)
--  * SCHREIBEN: niemals oeffentlich - nur Service-Role-Backend
drop policy if exists mpl_listings_read_public on public.marketplace_listings;
create policy mpl_listings_read_public on public.marketplace_listings
  for select using (
    (status = 'active' and review_status = 'approved')
    or seller_id = auth.uid()
    or exists (
      select 1 from public.users u
      where u.id = auth.uid() and u.role = 'admin'
    )
  );

drop policy if exists mpl_images_read on public.marketplace_images;
create policy mpl_images_read on public.marketplace_images
  for select using (
    exists (
      select 1 from public.marketplace_listings l
      where l.id = marketplace_images.listing_id
        and ((l.status = 'active' and l.review_status = 'approved')
             or l.seller_id = auth.uid()
             or exists (select 1 from public.users u where u.id = auth.uid() and u.role = 'admin'))
    )
  );

drop policy if exists mpl_favorites_rw on public.marketplace_favorites;
create policy mpl_favorites_rw on public.marketplace_favorites
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists mpl_reports_insert on public.marketplace_reports;
create policy mpl_reports_insert on public.marketplace_reports
  for insert with check (reporter_id = auth.uid());
drop policy if exists mpl_reports_read on public.marketplace_reports;
create policy mpl_reports_read on public.marketplace_reports
  for select using (
    exists (select 1 from public.users u where u.id = auth.uid() and u.role = 'admin')
  );

-- users.role: oeffentlich lesbar (App muss Admin-UI zeigen koennen),
-- schreibbar nur durch Service-Role (keine Policy = kein clientseitiger
-- Schreibzugriff, Service-Role umgeht RLS).
drop policy if exists mpl_users_role_read on public.users;
create policy mpl_users_role_read on public.users
  for select using (true);

-- ---------------------------------------------------------------- Storage
insert into storage.buckets (id, name, public)
values ('marketplace-photos', 'marketplace-photos', true)
on conflict (id) do nothing;

-- Oeffentliche Lese-URLs (Produktfotos), Upload NUR authentifiziert & nur
-- in den eigenen Ordner (Pfad-Präfix = auth.uid()).
drop policy if exists mpl_photos_read on storage.objects;
create policy mpl_photos_read on storage.objects
  for select using (bucket_id = 'marketplace-photos');

drop policy if exists mpl_photos_insert on storage.objects;
create policy mpl_photos_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'marketplace-photos'
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists mpl_photos_delete on storage.objects;
create policy mpl_photos_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'marketplace-photos'
         and (storage.foldername(name))[1] = auth.uid()::text);
