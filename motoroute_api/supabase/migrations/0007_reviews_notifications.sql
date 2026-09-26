-- 0007: Verkäufer-Bewertungen + In-App-Benachrichtigungen.
--
-- 1) marketplace_reviews: Sterne (1-5) + Kommentar. Ein Review pro
--    (Listing, Autor). Bewerten darf nur, wer einen PRIVATEN Chat-Verlauf
--    mit dem Verkäufer hat (Kontaktregel) - die Prüfung läuft über die
--    conversations/messages-Tabellen (pair_key = minId|maxId).
-- 2) notifications: In-App-Aktivität. Der Backend-Service schreibt bei
--    Favorit/Meldung/Review eine Zeile für den Verkäufer. App pollt
--    GET /v1/notifications (kein Google-Push nötig).
-- 3) Denormalisierter Review-Avg auf marketplace_listings (Trigger) -
--    List/Detail-Anfragen lesen ihn ohne Extra-Join.
--
-- Ausführen im Supabase-SQL-Editor (idempotent, wie 0005/0006).
-- Prüfung danach: node scripts/check-migration-0007.mjs

-- ---------------------------------------------------------------------------
-- 1) marketplace_reviews
-- ---------------------------------------------------------------------------
create table if not exists public.marketplace_reviews (
  id          uuid primary key default gen_random_uuid(),
  listing_id  uuid not null references public.marketplace_listings(id) on delete cascade,
  author_id   uuid not null references public.users(id) on delete cascade,
  rating      smallint not null check (rating between 1 and 5),
  comment     text not null default '' check (char_length(comment) <= 500),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (listing_id, author_id)
);

create index if not exists mplr_listing_idx
  on public.marketplace_reviews (listing_id, created_at desc);

alter table public.marketplace_reviews enable row level security;

-- Lesen: jeder (auch unangemeldet über Service-Embeds) - Reviews sind
-- öffentliche Angebotsbewertungen.
drop policy if exists mplr_read on public.marketplace_reviews;
create policy mplr_read on public.marketplace_reviews
  for select using (true);

-- Schreiben: nur der Autor selbst (Backend nutzt Service-Role; dies hier
-- schützt bei direktem PostgREST-Zugriff mit User-JWT).
drop policy if exists mplr_insert on public.marketplace_reviews;
create policy mplr_insert on public.marketplace_reviews
  for insert with check (author_id = auth.uid());

drop policy if exists mplr_update on public.marketplace_reviews;
create policy mplr_update on public.marketplace_reviews
  for update using (author_id = auth.uid())
  with check (author_id = auth.uid());

drop policy if exists mplr_delete on public.marketplace_reviews;
create policy mplr_delete on public.marketplace_reviews
  for delete using (author_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 2) notifications
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.users(id) on delete cascade,
  type        text not null check (type in ('favorite','report','review')),
  listing_id  uuid references public.marketplace_listings(id) on delete cascade,
  actor_id    uuid references public.users(id) on delete set null,
  body        text not null default '',
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);

create index if not exists notifications_user_idx
  on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;

drop policy if exists notifications_read_own on public.notifications;
create policy notifications_read_own on public.notifications
  for select using (user_id = auth.uid());

drop policy if exists notifications_insert_service on public.notifications;
create policy notifications_insert_service on public.notifications
  for insert with check (true);

drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications
  for update using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 3) Denormalisierter Review-Avg auf marketplace_listings
-- ---------------------------------------------------------------------------
alter table public.marketplace_listings
  add column if not exists review_count integer not null default 0;
alter table public.marketplace_listings
  add column if not exists review_avg numeric(3,2) not null default 0;

create or replace function public.mplr_recalc() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.marketplace_listings l
  set review_count = agg.cnt,
      review_avg   = round(agg.avg::numeric, 2)
  from (
    select count(*)::int as cnt, coalesce(avg(rating), 0) as avg
    from public.marketplace_reviews
    where listing_id = coalesce(new.listing_id, old.listing_id)
  ) agg
  where l.id = coalesce(new.listing_id, old.listing_id);
  return null;
end;
$$;

drop trigger if exists mplr_recalc_ins on public.marketplace_reviews;
create trigger mplr_recalc_ins
  after insert on public.marketplace_reviews
  for each row execute function public.mplr_recalc();

drop trigger if exists mplr_recalc_upd on public.marketplace_reviews;
create trigger mplr_recalc_upd
  after update of rating on public.marketplace_reviews
  for each row execute function public.mplr_recalc();

drop trigger if exists mplr_recalc_del on public.marketplace_reviews;
create trigger mplr_recalc_del
  after delete on public.marketplace_reviews
  for each row execute function public.mplr_recalc();

-- ---------------------------------------------------------------------------
-- updated_at-Pflege (Muster aus 0006: eigene Touch-Funktion)
-- ---------------------------------------------------------------------------
create or replace function public.mplr_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists mplr_touch on public.marketplace_reviews;
create trigger mplr_touch before update on public.marketplace_reviews
  for each row execute function public.mplr_touch_updated_at();

-- ---------------------------------------------------------------------------
-- Prüf-Ausgabe: Objekte der Migration
-- ---------------------------------------------------------------------------
-- select table_name from information_schema.tables
--   where table_schema='public' and table_name in
--   ('marketplace_reviews','notifications');
