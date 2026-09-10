-- Asam-Asam budget snapshot. The first rollout covers CPP and PORT for
-- January through June 2026, in USD.

create table if not exists public.operational_budget_month (
  id uuid primary key default gen_random_uuid(),
  source_key text not null unique,
  site_code text not null check (site_code in ('CPP', 'PORT')),
  period_start date not null check (period_start >= date '2026-01-01' and period_start <= date '2026-06-01'),
  budget_usd numeric(16,2) not null default 0,
  actual_usd numeric(16,2) not null default 0,
  source_fingerprint text not null,
  synced_at timestamptz not null default now(),
  unique (site_code, period_start)
);

create index if not exists idx_operational_budget_month_site_period
  on public.operational_budget_month (site_code, period_start);

create table if not exists public.operational_budget_sync_log (
  id uuid primary key default gen_random_uuid(),
  status text not null check (status in ('completed', 'failed')),
  snapshot_rows integer not null default 0,
  source_fingerprint text,
  detail text,
  completed_at timestamptz not null default now(),
  triggered_by uuid references public.app_user(id)
);

alter table public.operational_budget_month enable row level security;
alter table public.operational_budget_sync_log enable row level security;

drop policy if exists operational_budget_month_read_active on public.operational_budget_month;
create policy operational_budget_month_read_active
on public.operational_budget_month for select to authenticated
using (public.current_sicatat_user_id() is not null);

drop policy if exists operational_budget_sync_log_read_management on public.operational_budget_sync_log;
create policy operational_budget_sync_log_read_management
on public.operational_budget_sync_log for select to authenticated
using (public.current_sicatat_role() in ('admin', 'supervisor_smg', 'foreman'));
