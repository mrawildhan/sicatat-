-- SICATAT multi-site access model.
-- Global roles: admin and supervisor_smg. Site-scoped: supervisor_cop and
-- foreman_lv. Team-scoped: foreman. Crew can work only on its own sheets.

create table if not exists public.site (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.site (code, name)
values
  ('ASAMASAM', 'Asam-Asam'),
  ('KINTAP', 'Kintap')
on conflict (code) do update set name = excluded.name;

alter table public.team add column if not exists site_id uuid references public.site(id);
update public.team
set site_id = (select id from public.site where code = 'ASAMASAM')
where site_id is null;
alter table public.team alter column site_id set not null;
alter table public.team drop constraint if exists team_code_key;
alter table public.team drop constraint if exists team_site_code_key;
alter table public.team add constraint team_site_code_key unique (site_id, code);

alter table public.app_user add column if not exists site_id uuid references public.site(id);
update public.app_user
set site_id = (select id from public.site where code = 'ASAMASAM')
where site_id is null;
update public.app_user u
set site_id = t.site_id
from public.team t
where u.team_id = t.id;
update public.app_user set role = 'supervisor_smg' where role = 'supervisor';
update public.app_user
set site_id = null
where role in ('admin', 'supervisor_smg');
alter table public.app_user drop constraint if exists app_user_role_check;
alter table public.app_user add constraint app_user_role_check
  check (role in (
    'crew', 'foreman', 'supervisor_cop', 'supervisor_smg', 'foreman_lv', 'admin'
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
  if new.role in ('supervisor_cop', 'foreman_lv') and new.site_id is null then
    raise exception 'This role requires a site.' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_set_app_user_site_from_team on public.app_user;
create trigger trg_set_app_user_site_from_team
before insert or update of role, team_id, site_id on public.app_user
for each row execute function public.set_app_user_site_from_team();

alter table public.roster add column if not exists site_id uuid references public.site(id);
update public.roster r set site_id = t.site_id from public.team t where r.team_id = t.id and r.site_id is null;
alter table public.roster drop constraint if exists roster_tanggal_shift_id_key;
alter table public.roster add constraint roster_site_tanggal_shift_key unique (site_id, tanggal, shift_id);

create or replace function public.set_roster_site_from_team()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  select site_id into new.site_id from public.team where id = new.team_id;
  return new;
end;
$$;
drop trigger if exists trg_set_roster_site_from_team on public.roster;
create trigger trg_set_roster_site_from_team
before insert or update of team_id on public.roster
for each row execute function public.set_roster_site_from_team();

alter table public.sheet add column if not exists site_id uuid references public.site(id);
update public.sheet s set site_id = t.site_id from public.team t where s.team_id = t.id and s.site_id is null;
alter table public.sheet alter column site_id set not null;
alter table public.sheet drop constraint if exists sheet_module_id_tanggal_shift_id_key;
alter table public.sheet drop constraint if exists sheet_module_date_shift_site_key;
-- Historical test data contains duplicate pre-rule sheets. Preserve it for
-- audit instead of deleting records during a production migration. New rows
-- are made race-safe by the advisory lock in prevent_duplicate_shift_sheet().

create or replace function public.set_sheet_site_from_team()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  select site_id into new.site_id from public.team where id = new.team_id;
  if new.site_id is null then
    raise exception 'The selected team has no site.' using errcode = '23514';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_set_sheet_site_from_team on public.sheet;
drop trigger if exists trg_00_set_sheet_site_from_team on public.sheet;
create trigger trg_00_set_sheet_site_from_team
before insert or update of team_id on public.sheet
for each row execute function public.set_sheet_site_from_team();

create or replace function public.prevent_duplicate_shift_sheet()
returns trigger
language plpgsql
as $$
begin
  perform pg_advisory_xact_lock(
    hashtext(concat_ws('|', new.module_id::text, new.tanggal::text, new.shift_id::text, new.site_id::text))
  );
  if exists (
    select 1
    from public.sheet existing
    where existing.module_id = new.module_id
      and existing.tanggal = new.tanggal
      and existing.shift_id = new.shift_id
      and existing.site_id = new.site_id
      and existing.id <> new.id
  ) then
    raise exception
      'A sheet already exists for this module, date, shift, and site.'
      using errcode = '23505';
  end if;
  return new;
end;
$$;

alter table public.operational_reminder add column if not exists site_id uuid references public.site(id);
update public.operational_reminder
set site_id = (select id from public.site where code = 'ASAMASAM')
where site_id is null;
alter table public.operational_reminder alter column site_id set not null;
create index if not exists idx_operational_reminder_site_due_date
  on public.operational_reminder (site_id, due_date);

create or replace function public.set_operational_reminder_site()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_role text;
  actor_site uuid;
begin
  select role, site_id into actor_role, actor_site
  from public.app_user
  where nik = split_part(coalesce(auth.jwt() ->> 'email', ''), '@', 1)
    and is_active = true
  limit 1;
  if actor_role = 'foreman_lv' then
    new.site_id := actor_site;
  elsif new.site_id is null then
    new.site_id := actor_site;
  end if;
  if new.site_id is null then
    raise exception 'A reminder requires a site.' using errcode = '23514';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_set_operational_reminder_site on public.operational_reminder;
create trigger trg_set_operational_reminder_site
before insert or update of site_id on public.operational_reminder
for each row execute function public.set_operational_reminder_site();

create or replace function public.current_sicatat_user_id()
returns uuid language sql stable security definer set search_path = public as $$
  select id from public.app_user
  where nik = split_part(coalesce(auth.jwt() ->> 'email', ''), '@', 1)
    and is_active = true
  limit 1;
$$;

create or replace function public.current_sicatat_role()
returns text language sql stable security definer set search_path = public as $$
  select role from public.app_user where id = public.current_sicatat_user_id();
$$;

create or replace function public.current_sicatat_team_id()
returns uuid language sql stable security definer set search_path = public as $$
  select team_id from public.app_user where id = public.current_sicatat_user_id();
$$;

create or replace function public.current_sicatat_site_id()
returns uuid language sql stable security definer set search_path = public as $$
  select site_id from public.app_user where id = public.current_sicatat_user_id();
$$;

create or replace function public.can_read_sicatat_sheet(
  p_site_id uuid,
  p_team_id uuid,
  p_created_by uuid
)
returns boolean language sql stable security definer set search_path = public as $$
  select case public.current_sicatat_role()
    when 'admin' then true
    when 'supervisor_smg' then true
    when 'supervisor_cop' then p_site_id = public.current_sicatat_site_id()
    when 'foreman' then p_team_id = public.current_sicatat_team_id()
    when 'crew' then p_created_by = public.current_sicatat_user_id()
    else false
  end;
$$;

create or replace function public.can_write_sicatat_sheet(
  p_site_id uuid,
  p_team_id uuid,
  p_created_by uuid
)
returns boolean language sql stable security definer set search_path = public as $$
  select case public.current_sicatat_role()
    when 'admin' then true
    when 'supervisor_smg' then true
    when 'crew' then p_team_id = public.current_sicatat_team_id()
      and p_created_by = public.current_sicatat_user_id()
    else false
  end;
$$;

create or replace function public.can_review_sicatat_sheet(
  p_site_id uuid,
  p_team_id uuid
)
returns boolean language sql stable security definer set search_path = public as $$
  select case public.current_sicatat_role()
    when 'admin' then true
    when 'supervisor_smg' then true
    when 'supervisor_cop' then p_site_id = public.current_sicatat_site_id()
    when 'foreman' then p_team_id = public.current_sicatat_team_id()
    else false
  end;
$$;

create or replace function public.can_manage_sicatat_reminder_site(p_site_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case public.current_sicatat_role()
    when 'admin' then true
    when 'supervisor_smg' then true
    when 'foreman_lv' then p_site_id = public.current_sicatat_site_id()
    else false
  end;
$$;

create or replace function public.can_manage_sicatat_reminders()
returns boolean language sql stable security definer set search_path = public as $$
  select public.current_sicatat_role() in ('admin', 'supervisor_smg', 'foreman_lv');
$$;

-- Returns only occupied shifts, not another crew's sheet contents. This keeps
-- duplicate prevention visible to crew while My Sheets remains personal.
create or replace function public.occupied_temperature_shift_ids(
  p_module_id uuid,
  p_tanggal date,
  p_site_id uuid
)
returns table (shift_id uuid)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if public.current_sicatat_role() not in ('admin', 'supervisor_smg')
     and p_site_id is distinct from public.current_sicatat_site_id() then
    raise exception 'The selected site is outside your access scope.' using errcode = '42501';
  end if;
  return query
    select s.shift_id
    from public.sheet s
    where s.module_id = p_module_id
      and s.tanggal = p_tanggal
      and s.site_id = p_site_id;
end;
$$;
grant execute on function public.occupied_temperature_shift_ids(uuid, date, uuid) to authenticated;

-- Profile and organisational master data.
alter table public.site enable row level security;
alter table public.app_user enable row level security;
alter table public.team enable row level security;

drop policy if exists site_read_active_users on public.site;
create policy site_read_active_users on public.site for select to authenticated
using (public.current_sicatat_user_id() is not null);
drop policy if exists site_manage_global_roles on public.site;
create policy site_manage_global_roles on public.site for all to authenticated
using (public.current_sicatat_role() in ('admin', 'supervisor_smg'))
with check (public.current_sicatat_role() in ('admin', 'supervisor_smg'));

drop policy if exists app_user_select_scoped on public.app_user;
create policy app_user_select_scoped on public.app_user for select to authenticated
using (
  id = public.current_sicatat_user_id()
  or public.current_sicatat_role() in ('admin', 'supervisor_smg')
);
drop policy if exists app_user_manage_admin on public.app_user;
create policy app_user_manage_admin on public.app_user for all to authenticated
using (public.current_sicatat_role() = 'admin')
with check (public.current_sicatat_role() = 'admin');

drop policy if exists team_read_scoped on public.team;
create policy team_read_scoped on public.team for select to authenticated
using (
  public.current_sicatat_role() in ('admin', 'supervisor_smg')
  or site_id = public.current_sicatat_site_id()
);
drop policy if exists team_manage_global_roles on public.team;
create policy team_manage_global_roles on public.team for all to authenticated
using (public.current_sicatat_role() in ('admin', 'supervisor_smg'))
with check (public.current_sicatat_role() in ('admin', 'supervisor_smg'));

-- Temperature data and its child records.
alter table public.sheet enable row level security;
alter table public.round enable row level security;
alter table public.unit_status enable row level security;
alter table public.reading enable row level security;
alter table public.sheet_contributor enable row level security;

drop policy if exists sheet_select_scoped on public.sheet;
create policy sheet_select_scoped on public.sheet for select to authenticated
using (public.can_read_sicatat_sheet(site_id, team_id, created_by));
drop policy if exists sheet_insert_temperature_writer on public.sheet;
create policy sheet_insert_temperature_writer on public.sheet for insert to authenticated
with check (public.can_write_sicatat_sheet(site_id, team_id, created_by));
drop policy if exists sheet_update_scoped on public.sheet;
create policy sheet_update_scoped on public.sheet for update to authenticated
using (
  public.can_write_sicatat_sheet(site_id, team_id, created_by)
  or public.can_review_sicatat_sheet(site_id, team_id)
)
with check (public.can_read_sicatat_sheet(site_id, team_id, created_by));
drop policy if exists sheet_delete_temperature_writer on public.sheet;
create policy sheet_delete_temperature_writer on public.sheet for delete to authenticated
using (public.can_write_sicatat_sheet(site_id, team_id, created_by));

drop policy if exists round_select_scoped on public.round;
create policy round_select_scoped on public.round for select to authenticated
using (exists (select 1 from public.sheet s where s.id = sheet_id and public.can_read_sicatat_sheet(s.site_id, s.team_id, s.created_by)));
drop policy if exists round_write_scoped on public.round;
create policy round_write_scoped on public.round for all to authenticated
using (exists (select 1 from public.sheet s where s.id = sheet_id and public.can_write_sicatat_sheet(s.site_id, s.team_id, s.created_by)))
with check (exists (select 1 from public.sheet s where s.id = sheet_id and public.can_write_sicatat_sheet(s.site_id, s.team_id, s.created_by)));

drop policy if exists unit_status_select_scoped on public.unit_status;
create policy unit_status_select_scoped on public.unit_status for select to authenticated
using (exists (select 1 from public.round r join public.sheet s on s.id = r.sheet_id where r.id = round_id and public.can_read_sicatat_sheet(s.site_id, s.team_id, s.created_by)));
drop policy if exists unit_status_write_scoped on public.unit_status;
create policy unit_status_write_scoped on public.unit_status for all to authenticated
using (exists (select 1 from public.round r join public.sheet s on s.id = r.sheet_id where r.id = round_id and public.can_write_sicatat_sheet(s.site_id, s.team_id, s.created_by)))
with check (exists (select 1 from public.round r join public.sheet s on s.id = r.sheet_id where r.id = round_id and public.can_write_sicatat_sheet(s.site_id, s.team_id, s.created_by)));

drop policy if exists reading_select_scoped on public.reading;
create policy reading_select_scoped on public.reading for select to authenticated
using (exists (select 1 from public.round r join public.sheet s on s.id = r.sheet_id where r.id = round_id and public.can_read_sicatat_sheet(s.site_id, s.team_id, s.created_by)));
drop policy if exists reading_write_scoped on public.reading;
create policy reading_write_scoped on public.reading for all to authenticated
using (exists (select 1 from public.round r join public.sheet s on s.id = r.sheet_id where r.id = round_id and public.can_write_sicatat_sheet(s.site_id, s.team_id, s.created_by)))
with check (exists (select 1 from public.round r join public.sheet s on s.id = r.sheet_id where r.id = round_id and public.can_write_sicatat_sheet(s.site_id, s.team_id, s.created_by)));

drop policy if exists sheet_contributor_select_scoped on public.sheet_contributor;
create policy sheet_contributor_select_scoped on public.sheet_contributor for select to authenticated
using (exists (select 1 from public.sheet s where s.id = sheet_id and public.can_read_sicatat_sheet(s.site_id, s.team_id, s.created_by)));
drop policy if exists sheet_contributor_write_scoped on public.sheet_contributor;
create policy sheet_contributor_write_scoped on public.sheet_contributor for all to authenticated
using (exists (select 1 from public.sheet s where s.id = sheet_id and public.can_write_sicatat_sheet(s.site_id, s.team_id, s.created_by)))
with check (exists (select 1 from public.sheet s where s.id = sheet_id and public.can_write_sicatat_sheet(s.site_id, s.team_id, s.created_by)));

-- Reminder access replaces the former admin-only policy.
drop policy if exists operational_reminder_admin_only on public.operational_reminder;
drop policy if exists operational_reminder_site_scoped on public.operational_reminder;
create policy operational_reminder_site_scoped on public.operational_reminder for all to authenticated
using (public.can_manage_sicatat_reminder_site(site_id))
with check (public.can_manage_sicatat_reminder_site(site_id));

drop policy if exists reminder_recipient_admin_only on public.reminder_recipient;
drop policy if exists reminder_recipient_manager_only on public.reminder_recipient;
create policy reminder_recipient_manager_only on public.reminder_recipient for all to authenticated
using (public.can_manage_sicatat_reminders())
with check (public.can_manage_sicatat_reminders());

drop policy if exists operational_reminder_delivery_admin_only on public.operational_reminder_delivery;
drop policy if exists operational_reminder_delivery_site_scoped on public.operational_reminder_delivery;
create policy operational_reminder_delivery_site_scoped on public.operational_reminder_delivery for select to authenticated
using (exists (select 1 from public.operational_reminder r where r.id = reminder_id and public.can_manage_sicatat_reminder_site(r.site_id)));

drop policy if exists operational_reminder_activity_admin_only on public.operational_reminder_activity;
drop policy if exists operational_reminder_activity_site_scoped on public.operational_reminder_activity;
create policy operational_reminder_activity_site_scoped on public.operational_reminder_activity for select to authenticated
using (exists (select 1 from public.operational_reminder r where r.id = reminder_id and public.can_manage_sicatat_reminder_site(r.site_id)));
