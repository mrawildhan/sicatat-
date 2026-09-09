-- PM outstanding is a server-managed snapshot of the two approved work-order
-- spreadsheets. CP2 and PR2 are normalised to CPP and PORT when syncing.

create table if not exists public.preventive_maintenance_work_order (
  id uuid primary key default gen_random_uuid(),
  source_key text not null unique,
  work_order text not null,
  work_order_description text not null,
  equipment_reference text not null,
  crew_code text not null check (crew_code in ('A', 'B', 'C')),
  site_code text not null check (site_code in ('CPP', 'PORT')),
  status_code text not null,
  raised_on date,
  planned_start_on date,
  assigned_to text,
  assigned_to_description text,
  priority text,
  priority_description text,
  source_fingerprint text not null,
  synced_at timestamptz not null default now()
);

create index if not exists idx_pm_outstanding_crew_site
  on public.preventive_maintenance_work_order (site_code, crew_code, planned_start_on, work_order);

create table if not exists public.preventive_maintenance_sync_log (
  id uuid primary key default gen_random_uuid(),
  status text not null check (status in ('completed', 'failed')),
  snapshot_rows integer not null default 0,
  source_fingerprint text,
  detail text,
  completed_at timestamptz not null default now(),
  triggered_by uuid references public.app_user(id)
);

alter table public.preventive_maintenance_work_order enable row level security;
alter table public.preventive_maintenance_sync_log enable row level security;

drop policy if exists preventive_maintenance_work_order_read_active on public.preventive_maintenance_work_order;
create policy preventive_maintenance_work_order_read_active
on public.preventive_maintenance_work_order for select to authenticated
using (public.current_sicatat_user_id() is not null);

drop policy if exists preventive_maintenance_sync_log_read_management on public.preventive_maintenance_sync_log;
create policy preventive_maintenance_sync_log_read_management
on public.preventive_maintenance_sync_log for select to authenticated
using (public.current_sicatat_role() in ('admin', 'supervisor_smg', 'foreman'));
