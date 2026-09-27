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
