-- Foreman LV operates reminders across all sites, but must not be able to
-- access, create, edit, or review Temperature sheets.

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

drop policy if exists team_read_scoped on public.team;
create policy team_read_scoped on public.team for select to authenticated
using (
  public.current_sicatat_role() in ('admin', 'supervisor_smg')
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
