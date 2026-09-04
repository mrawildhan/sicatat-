-- Warehouse v1 reads the approved public Google Sheets on the server and
-- exposes a searchable snapshot to the mobile application.

alter table public.app_user
  drop constraint if exists app_user_role_check;

alter table public.app_user
  add constraint app_user_role_check
  check (role in (
    'crew', 'foreman', 'supervisor_cop', 'supervisor_smg',
    'foreman_lv', 'warehouseman', 'admin'
  ));

create or replace function public.set_app_user_site_from_team()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.team_id is not null then
    select site_id into new.site_id from public.team where id = new.team_id;
  end if;
  if new.role in ('crew', 'foreman') and new.team_id is null then
    raise exception 'Crew and foreman accounts require a team.' using errcode = '23514';
  end if;
  if new.role in ('supervisor_cop', 'warehouseman') and new.site_id is null then
    raise exception 'Supervisor COP and Warehouseman accounts require a site.' using errcode = '23514';
  end if;
  if new.role in ('admin', 'supervisor_smg', 'foreman_lv') then
    new.site_id := null;
  end if;
  return new;
end;
$$;

create table if not exists public.warehouse_stock (
  id uuid primary key default gen_random_uuid(),
  source_key text not null unique,
  item_code text not null,
  description text not null,
  warehouse_code text not null,
  site_label text not null,
  site_id uuid references public.site(id),
  uoi text,
  bin_code text,
  unit_price numeric,
  stock_on_hand numeric not null default 0,
  source_updated_on date,
  synced_at timestamptz not null default now()
);

create index if not exists idx_warehouse_stock_search
  on public.warehouse_stock (warehouse_code, item_code);
create index if not exists idx_warehouse_stock_site
  on public.warehouse_stock (site_id);

create table if not exists public.warehouse_sync_log (
  id uuid primary key default gen_random_uuid(),
  status text not null check (status in ('running', 'completed', 'failed')),
  stock_rows integer not null default 0,
  item_master_rows integer not null default 0,
  detail text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  triggered_by uuid references public.app_user(id)
);

create table if not exists public.warehouse_receipt (
  id uuid primary key default gen_random_uuid(),
  source_key text not null unique,
  received_on date,
  po_number text,
  item_code text,
  stock_code text,
  description text,
  quantity numeric,
  uoi text,
  delivery_note text,
  supplier text,
  requested_by text,
  synced_at timestamptz not null default now()
);

alter table public.warehouse_stock enable row level security;
alter table public.warehouse_sync_log enable row level security;
alter table public.warehouse_receipt enable row level security;

create or replace function public.can_read_warehouse_site(p_site_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case public.current_sicatat_role()
    when 'admin' then true
    when 'supervisor_smg' then true
    when 'warehouseman' then p_site_id = public.current_sicatat_site_id()
    else false
  end;
$$;

drop policy if exists warehouse_stock_read_scoped on public.warehouse_stock;
create policy warehouse_stock_read_scoped
on public.warehouse_stock for select to authenticated
using (public.can_read_warehouse_site(site_id));

drop policy if exists warehouse_sync_log_read_scoped on public.warehouse_sync_log;
create policy warehouse_sync_log_read_scoped
on public.warehouse_sync_log for select to authenticated
using (public.current_sicatat_role() in ('admin', 'supervisor_smg', 'warehouseman'));
