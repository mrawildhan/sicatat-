-- The source workbook remains in Google Drive.  This compact snapshot makes
-- PR lookups fast in SICATAT without downloading the spreadsheet per search.

create table if not exists public.purchase_requisition (
  id uuid primary key default gen_random_uuid(),
  source_key text not null unique,
  no_pr text not null,
  no_po text,
  description text,
  equip_ref text,
  closed_date date,
  release_date date,
  status text,
  notes text,
  source_fingerprint text not null,
  synced_at timestamptz not null default now()
);

create index if not exists idx_purchase_requisition_no_pr
  on public.purchase_requisition (no_pr);
create index if not exists idx_purchase_requisition_no_po
  on public.purchase_requisition (no_po);
create index if not exists idx_purchase_requisition_release_date
  on public.purchase_requisition (release_date desc nulls last);

create table if not exists public.purchase_requisition_sync_log (
  id uuid primary key default gen_random_uuid(),
  status text not null check (status in ('completed', 'failed')),
  snapshot_rows integer not null default 0,
  source_fingerprint text,
  detail text,
  completed_at timestamptz not null default now(),
  triggered_by uuid references public.app_user(id)
);

create index if not exists idx_purchase_requisition_sync_log_completed
  on public.purchase_requisition_sync_log (completed_at desc)
  where status = 'completed';

alter table public.purchase_requisition enable row level security;
alter table public.purchase_requisition_sync_log enable row level security;

drop policy if exists purchase_requisition_read_active on public.purchase_requisition;
create policy purchase_requisition_read_active
on public.purchase_requisition for select to authenticated
using (public.current_sicatat_user_id() is not null);

drop policy if exists purchase_requisition_sync_log_read_active on public.purchase_requisition_sync_log;
create policy purchase_requisition_sync_log_read_active
on public.purchase_requisition_sync_log for select to authenticated
using (public.current_sicatat_user_id() is not null);
