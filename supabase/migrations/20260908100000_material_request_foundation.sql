-- Fondasi permintaan order barang LV dan Drilling. Form serta alur planner
-- akan memakai tabel ini pada rilis berikutnya; data tidak diisi oleh tampilan
-- awal supaya angka operasional tidak menampilkan contoh palsu.
create table if not exists public.material_request (
  id uuid primary key default gen_random_uuid(),
  request_area text not null check (request_area in ('lv', 'drilling')),
  item_name text not null,
  quantity numeric(12, 2) not null check (quantity > 0),
  unit text not null default 'unit',
  need_type text not null check (need_type in ('replacement', 'new_item', 'repair')),
  reason text not null,
  status text not null default 'submitted'
    check (status in ('submitted', 'processed', 'rejected')),
  planner_note text not null default '',
  requested_by uuid not null references public.app_user(id),
  processed_by uuid references public.app_user(id),
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists material_request_status_created_at_idx
  on public.material_request(status, created_at desc);
create index if not exists material_request_requested_by_created_at_idx
  on public.material_request(requested_by, created_at desc);

create or replace function public.set_material_request_updated_at()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.updated_at = now();
  if new.status in ('processed', 'rejected') and old.status is distinct from new.status then
    new.processed_at = now();
  elsif new.status = 'submitted' then
    new.processed_at = null;
    new.processed_by = null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_set_material_request_updated_at on public.material_request;
create trigger trg_set_material_request_updated_at
before update on public.material_request
for each row execute function public.set_material_request_updated_at();

create or replace function public.can_manage_material_request()
returns boolean language sql stable security definer set search_path = public as $$
  select public.current_sicatat_role() in ('admin', 'supervisor_smg', 'foreman_lv');
$$;

alter table public.material_request enable row level security;

create policy material_request_read_scoped on public.material_request
for select to authenticated
using (
  requested_by = public.current_sicatat_user_id()
  or public.can_manage_material_request()
);

create policy material_request_insert_own on public.material_request
for insert to authenticated
with check (requested_by = public.current_sicatat_user_id());

create policy material_request_update_manager on public.material_request
for update to authenticated
using (public.can_manage_material_request())
with check (public.can_manage_material_request());
