-- Notulen rapat/inspeksi dibuat di SICATAT, dapat tetap berstatus draf,
-- dan memiliki daftar tindak lanjut terpisah agar setiap PIC serta tenggat
-- dapat ditelusuri tanpa menyimpan berkas Office sebagai sumber data utama.

create table if not exists public.meeting_minute (
  id uuid primary key default gen_random_uuid(),
  title text not null default '',
  meeting_date date,
  start_time time,
  end_time time,
  location text not null default '',
  attendees text not null default '',
  apologies text not null default '',
  minute_taker text not null default '',
  distribution_list text not null default '',
  new_business_agenda text not null default '',
  proposed_by text not null default '',
  note text not null default '',
  status text not null default 'draft'
    check (status in ('draft', 'completed')),
  created_by uuid not null references public.app_user(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists public.meeting_minute_action (
  id uuid primary key default gen_random_uuid(),
  meeting_minute_id uuid not null references public.meeting_minute(id)
    on delete cascade,
  item_date date,
  subject_discussion text not null default '',
  assigned_to text not null default '',
  due_date date,
  position integer not null default 0 check (position >= 0),
  created_at timestamptz not null default now()
);

create index if not exists meeting_minute_created_by_updated_at_idx
  on public.meeting_minute(created_by, updated_at desc);
create index if not exists meeting_minute_action_parent_position_idx
  on public.meeting_minute_action(meeting_minute_id, position);

create or replace function public.set_meeting_minute_updated_at()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.updated_at = now();
  if new.status = 'completed' and old.status is distinct from 'completed' then
    new.completed_at = now();
  elsif new.status = 'draft' then
    new.completed_at = null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_set_meeting_minute_updated_at on public.meeting_minute;
create trigger trg_set_meeting_minute_updated_at
before update on public.meeting_minute
for each row execute function public.set_meeting_minute_updated_at();

create or replace function public.can_read_meeting_minute(p_created_by uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select p_created_by = public.current_sicatat_user_id()
    or public.current_sicatat_role() in ('admin', 'supervisor_smg', 'foreman_lv');
$$;

create or replace function public.can_write_meeting_minute(p_created_by uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select p_created_by = public.current_sicatat_user_id()
    or public.current_sicatat_role() in ('admin', 'supervisor_smg', 'foreman_lv');
$$;

alter table public.meeting_minute enable row level security;
alter table public.meeting_minute_action enable row level security;

drop policy if exists meeting_minute_read_scoped on public.meeting_minute;
create policy meeting_minute_read_scoped on public.meeting_minute
for select to authenticated
using (public.can_read_meeting_minute(created_by));

drop policy if exists meeting_minute_insert_own on public.meeting_minute;
create policy meeting_minute_insert_own on public.meeting_minute
for insert to authenticated
with check (created_by = public.current_sicatat_user_id());

drop policy if exists meeting_minute_update_scoped on public.meeting_minute;
create policy meeting_minute_update_scoped on public.meeting_minute
for update to authenticated
using (public.can_write_meeting_minute(created_by))
with check (public.can_write_meeting_minute(created_by));

drop policy if exists meeting_minute_delete_scoped on public.meeting_minute;
create policy meeting_minute_delete_scoped on public.meeting_minute
for delete to authenticated
using (public.can_write_meeting_minute(created_by));

drop policy if exists meeting_minute_action_read_scoped on public.meeting_minute_action;
create policy meeting_minute_action_read_scoped on public.meeting_minute_action
for select to authenticated
using (
  exists (
    select 1 from public.meeting_minute m
    where m.id = meeting_minute_id
      and public.can_read_meeting_minute(m.created_by)
  )
);

drop policy if exists meeting_minute_action_write_scoped on public.meeting_minute_action;
create policy meeting_minute_action_write_scoped on public.meeting_minute_action
for all to authenticated
using (
  exists (
    select 1 from public.meeting_minute m
    where m.id = meeting_minute_id
      and public.can_write_meeting_minute(m.created_by)
  )
)
with check (
  exists (
    select 1 from public.meeting_minute m
    where m.id = meeting_minute_id
      and public.can_write_meeting_minute(m.created_by)
  )
);
