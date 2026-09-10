-- Searchable per-account budget snapshot. This is intentionally compact:
-- Drive retains the full source workbook and Supabase stores only app fields.

create table if not exists public.operational_budget_item (
  id uuid primary key default gen_random_uuid(),
  source_key text not null unique,
  site_code text not null check (site_code in ('CPP', 'PORT')),
  account_code text not null,
  description text not null,
  budget_usd numeric(16,2) not null default 0,
  actual_usd numeric(16,2) not null default 0,
  budget_months jsonb not null default '{}'::jsonb,
  actual_months jsonb not null default '{}'::jsonb,
  peak_period text,
  peak_actual_usd numeric(16,2) not null default 0,
  largest_transaction_usd numeric(16,2) not null default 0,
  largest_transaction_date date,
  largest_transaction_no text,
  source_fingerprint text not null,
  synced_at timestamptz not null default now(),
  unique (site_code, account_code)
);

create index if not exists idx_operational_budget_item_site_actual
  on public.operational_budget_item (site_code, actual_usd desc);

create index if not exists idx_operational_budget_item_search
  on public.operational_budget_item (site_code, account_code, description);

alter table public.operational_budget_item enable row level security;

drop policy if exists operational_budget_item_read_active on public.operational_budget_item;
create policy operational_budget_item_read_active
on public.operational_budget_item for select to authenticated
using (public.current_sicatat_user_id() is not null);
