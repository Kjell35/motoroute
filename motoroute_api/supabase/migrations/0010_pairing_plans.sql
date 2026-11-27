-- Route am Computer planen: kurzlebige Pläne für den QR-/Pairing-Flow.
-- Zugriff ausschließlich über den Service-Role-Client der API (RLS an, keine
-- Policies) - das Token im Pfad ist das Geheimnis, nicht eine Session.
create table if not exists public.pairing_plans (
  token       text primary key,
  points      jsonb not null default '[]'::jsonb,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null
);

create index if not exists pairing_plans_expires_at_idx
  on public.pairing_plans (expires_at);

alter table public.pairing_plans enable row level security;
