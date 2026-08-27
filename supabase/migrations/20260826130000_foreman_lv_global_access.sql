-- Business decision: Foreman LV has the same cross-site operational scope as
-- Supervisor SMG. Supervisor COP remains limited to its assigned site.

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
  if new.role = 'supervisor_cop' and new.site_id is null then
    raise exception 'Supervisor COP accounts require a site.' using errcode = '23514';
  end if;
  if new.role in ('admin', 'supervisor_smg', 'foreman_lv') then
    new.site_id := null;
  end if;
  return new;
end;
$$;

update public.app_user
set site_id = null
where role = 'foreman_lv';

create or replace function public.set_operational_reminder_site()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_site uuid;
begin
  select site_id into actor_site
  from public.app_user
  where nik = split_part(coalesce(auth.jwt() ->> 'email', ''), '@', 1)
    and is_active = true
  limit 1;
  if new.site_id is null then
    new.site_id := actor_site;
  end if;
  if new.site_id is null then
    raise exception 'A reminder requires a site.' using errcode = '23514';
  end if;
  return new;
end;
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
    when 'foreman_lv' then true
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
    when 'foreman_lv' then true
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
    when 'foreman_lv' then true
    when 'supervisor_cop' then p_site_id = public.current_sicatat_site_id()
    when 'foreman' then p_team_id = public.current_sicatat_team_id()
    else false
  end;
$$;

create or replace function public.can_manage_sicatat_reminder_site(p_site_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.current_sicatat_role() in ('admin', 'supervisor_smg', 'foreman_lv');
$$;

drop policy if exists team_read_scoped on public.team;
create policy team_read_scoped on public.team for select to authenticated
using (
  public.current_sicatat_role() in ('admin', 'supervisor_smg', 'foreman_lv')
  or site_id = public.current_sicatat_site_id()
);

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
  if public.current_sicatat_role() not in ('admin', 'supervisor_smg', 'foreman_lv')
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
