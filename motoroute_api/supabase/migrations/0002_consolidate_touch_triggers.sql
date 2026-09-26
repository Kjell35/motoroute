-- 0002: Konsolidierung - gemeinsame updated_at-Trigger-Funktion.
--
-- Historie der Nummernlücke: 0002 wurde nie committet (vermutlich beim
-- Auflösen eines Konflikts verloren gegangen). Diese Datei schließt die
-- Lücke als bereinigte Konsolidierungs-Migration.
--
-- Inhalt: Die Migrationen 0005/0006/0007 legten jeweils eine EIGENE,
-- inhaltlich identische Trigger-Funktion zur Pflege von updated_at an:
--   poi_touch_updated_at()   (0005, Tabelle poi)
--   mpl_touch()              (0006, marketplace_listings)
--   mplr_touch_updated_at()  (0007, marketplace_reviews)
-- Alle drei tun exakt dasselbe (new.updated_at = now()). Diese Migration
-- führt sie auf EINE Funktion zusammen:
--   public.touch_updated_at()
-- Die drei alten Funktionen bleiben NICHT als Leichen zurück - sie werden
-- gedroppt, nachdem ihre Trigger auf die gemeinsame Funktion umgehängt
-- wurden.
--
-- Eigenschaften:
-- - Idempotent (mehrfaches Ausführen ist gefahrlos).
-- - Sicher in jeder Reihenfolge: Fehlen die Tabellen aus 0005/0006/0007
--   (weil diese Migrationen noch nicht gelaufen sind), tut dieser Skript
--   nichts - die dortigen Trigger-Definitionen greifen dann wie gehabt.
--   In einem frischen Projekt führt man 0001-0007 ohnehin aufsteigend aus.
--
-- Ausführen im Supabase-SQL-Editor (wie alle Migrationen).
-- Prüfung danach: siehe Kommentar am Dateiende.

-- ---------------------------------------------------------------------------
-- 1) Gemeinsame Funktion anlegen
-- ---------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- 2) Bestehende Trigger auf die gemeinsame Funktion umhängen
--    (DO-Blöcke: einzelne Tabellen dürfen fehlen, ohne den Lauf zu killen)
-- ---------------------------------------------------------------------------

-- poi (0005)
do $$
begin
  if to_regclass('public.poi') is not null then
    drop trigger if exists poi_touch on public.poi;
    create trigger poi_touch
      before update on public.poi
      for each row execute function public.touch_updated_at();
  end if;
end $$;

-- marketplace_listings (0006)
do $$
begin
  if to_regclass('public.marketplace_listings') is not null then
    drop trigger if exists mpl_touch_trigger on public.marketplace_listings;
    create trigger mpl_touch_trigger
      before update on public.marketplace_listings
      for each row execute function public.touch_updated_at();
  end if;
end $$;

-- marketplace_reviews (0007)
do $$
begin
  if to_regclass('public.marketplace_reviews') is not null then
    drop trigger if exists mplr_touch on public.marketplace_reviews;
    create trigger mplr_touch
      before update on public.marketplace_reviews
      for each row execute function public.touch_updated_at();
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 3) Alte Doppel-Funktionen entfernen
--    (Nur droppen, wenn kein Trigger mehr darauf referenziert - nach
--    Schritt 2 ist das der Fall. Die IF EXISTS-Kette ist gegen Überras-
--    chungen bei Teilausführung.)
-- ---------------------------------------------------------------------------
drop function if exists public.poi_touch_updated_at() cascade;
drop function if exists public.mpl_touch() cascade;
drop function if exists public.mplr_touch_updated_at() cascade;

-- Hinweis: CASCADE droppt hierbei nur die (bereits umgehängten bzw. noch
-- vorhandenen) Trigger der alten Funktionen, keine Tabellen oder Daten.

-- ---------------------------------------------------------------------------
-- Prüf-Ausgabe: Alle updated_at-Trigger nach der Konsolidierung
-- ---------------------------------------------------------------------------
-- select tgname, tgrelid::regclass as tabelle, tgfoid::regproc as funktion
--   from pg_trigger
--  where tgfoid::regproc::text in ('touch_updated_at',
--                                  'poi_touch_updated_at',
--                                  'mpl_touch',
--                                  'mplr_touch_updated_at')
--    and not tgisinternal;
--
-- Erwartet: 3 Zeilen (poi, marketplace_listings, marketplace_reviews),
-- ALLE mit funktion = touch_updated_at.
