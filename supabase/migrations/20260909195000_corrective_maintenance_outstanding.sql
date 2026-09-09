create table if not exists public.corrective_maintenance_work_order (
  id uuid primary key default gen_random_uuid(),
  source_key text not null unique,
  work_order text not null,
  work_order_description text not null,
  equipment_reference text not null,
  site_code text not null check (site_code in ('CPP', 'PORT')),
  priority text,
  raised_on date,
  latest_progress text,
  source_fingerprint text not null,
  synced_at timestamptz not null default now()
);
create index if not exists idx_cm_outstanding_site_date on public.corrective_maintenance_work_order (site_code, raised_on, work_order);
alter table public.corrective_maintenance_work_order enable row level security;
create policy corrective_maintenance_work_order_read_active on public.corrective_maintenance_work_order for select to authenticated using (public.current_sicatat_user_id() is not null);
