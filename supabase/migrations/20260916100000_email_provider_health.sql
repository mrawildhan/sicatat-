-- The reminder dispatcher only sends on the exact notification date, and the
-- next one is months away, so an expired Gmail authorization used to stay
-- invisible until that date. The daily cron now verifies the delivery
-- credentials without sending anything and records the result here; the
-- Pengingat screen shows a warning when the last check failed.

create table if not exists public.email_provider_health (
  provider text primary key,
  ok boolean not null,
  message text,
  checked_at timestamptz not null default now()
);

alter table public.email_provider_health enable row level security;

-- Written only by the dispatcher with the service role. Reminders are an
-- admin feature, so only admins read the warning.
drop policy if exists email_provider_health_read_admin on public.email_provider_health;
create policy email_provider_health_read_admin on public.email_provider_health
  for select to authenticated
  using (public.is_active_sicatat_admin());
