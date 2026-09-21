-- 0003: Profil-Erweiterungen fuer Chat-Anzeigename + Sprachwahl.
--
-- 1) plan: fehlte bisher im Schema, obwohl user.service.getMe sie
--    selektiert (Profil-Fallback griff dadurch immer) - jetzt vorhanden.
-- 2) first_name: optionale Vorname-Angabe.
-- 3) chat_name_mode: welcher Name im Chat angezeigt wird
--    ('username' | 'first_name' | 'custom'), Default 'username'.
-- 4) chat_display_name: benutzerdefinierter Anzeigename (nur relevant
--    im Modus 'custom').
--
-- Idempotent: mehrfaches Ausfuehren im SQL-Editor ist gefahrlos.

-- plan (Free/Premium-Vorbereitung; Entitlements entscheidet allein das Backend)
alter table public.users
  add column if not exists plan text not null default 'free'
    check (plan in ('free', 'premium'));

-- Vorname (optional; Grundlage fuer Modus 'first_name')
alter table public.users
  add column if not exists first_name text
    constraint users_first_name_len check (char_length(first_name) <= 80);

-- Chat-Anzeigename-Modus
alter table public.users
  add column if not exists chat_name_mode text not null default 'username'
    check (chat_name_mode in ('username', 'first_name', 'custom'));

-- Benutzerdefinierter Chat-Anzeigename (Modus 'custom')
alter table public.users
  add column if not exists chat_display_name text
    constraint users_chat_display_name_len check (char_length(chat_display_name) <= 80);

-- Konsistenz: im Modus 'custom' braucht es einen Namen - nicht als
-- Constraint (harte Pflicht macht Migrationen mit Bestandsdaten
-- spruedig), sondern als dokumentierter Client-Vertrag: Die App
-- erlaubt das Speichern von Modus 'custom' nur mit nicht-leerem Namen,
-- der UserService validiert serverseitig nach.
comment on column public.users.chat_name_mode is
  'Welcher Name im Chat erscheint: username | first_name | custom (dann chat_display_name). Client + UserService erzwingen non-empty im custom-Modus.';
comment on column public.users.first_name is
  'Optionaler Vorname - Grundlage fuer chat_name_mode = first_name.';
comment on column public.users.plan is
  'Premium-Vorbereitung. Aktuelle Testphase: alle Entitlements frei (entscheidet UserService.entitlementsFor).';
