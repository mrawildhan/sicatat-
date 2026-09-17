-- Daily check sheets that sit next to the Feeder/Sizer temperature sheet:
--   hydraulic_feeder  Daily Check Sheet Hydraulic Pump Feeder CPP
--   coal_valve        Data Temperature Coal Valve
--
-- Both are online-only and small (one row per sheet, readings in JSONB), so
-- they do not reuse the round/unit_status/reading tables that are shaped
-- around the Breaker/Sizer West/East form.
--
-- readings shape: { "<slot>": { "<field>": number | text, ... }, ... }
-- The Flutter form definition (daily_check_forms.dart) owns the slot and
-- field keys; the database only stores them.

create table if not exists public.daily_check_sheet (
  id            uuid primary key default gen_random_uuid(),
  form_type     text not null check (form_type in ('hydraulic_feeder', 'coal_valve')),
  tanggal       date not null,
  shift_id      uuid not null references public.shift(id),
  team_id       uuid not null references public.team(id),
  site_id       uuid references public.site(id),
  status        text not null default 'draft' check (status in ('draft', 'submitted')),
  readings      jsonb not null default '{}'::jsonb check (jsonb_typeof(readings) = 'object'),
  notes         text check (notes is null or char_length(notes) <= 2000),
  created_by    uuid not null references public.app_user(id),
  created_at    timestamptz not null default now(),
  updated_by    uuid references public.app_user(id),
  updated_at    timestamptz not null default now(),
  submitted_by  uuid references public.app_user(id),
  submitted_at  timestamptz,
  -- Keeps a runaway client from filling the free-plan database.
  constraint daily_check_sheet_readings_size check (pg_column_size(readings) < 65536)
);

-- Same rule as the temperature sheet: one sheet per form, date, and shift at a site.
create unique index if not exists daily_check_sheet_one_per_shift
  on public.daily_check_sheet (form_type, tanggal, shift_id, site_id);
create index if not exists daily_check_sheet_list
  on public.daily_check_sheet (form_type, tanggal desc);

create or replace function public.daily_check_sheet_before_write()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- The site always follows the team, never the client.
  select t.site_id into new.site_id from public.team t where t.id = new.team_id;
  if new.site_id is null then
    raise exception 'The selected team has no site.';
  end if;
  new.updated_at := now();
  new.updated_by := public.current_sicatat_user_id();
  if tg_op = 'INSERT' then
    new.created_at := now();
    new.status := 'draft';
    new.submitted_at := null;
    new.submitted_by := null;
  else
    -- Identity of a sheet never changes after it is created.
    new.form_type := old.form_type;
    new.created_by := old.created_by;
    new.created_at := old.created_at;
    if new.status = 'submitted' and old.status = 'draft' then
      new.submitted_at := now();
      new.submitted_by := public.current_sicatat_user_id();
    elsif new.status = 'draft' then
      new.submitted_at := null;
      new.submitted_by := null;
    else
      new.submitted_at := old.submitted_at;
      new.submitted_by := old.submitted_by;
    end if;
    -- A submitted sheet is final; only reopening it (status -> draft) is allowed.
    if old.status = 'submitted' and new.status = 'submitted'
       and (new.readings is distinct from old.readings
            or new.notes is distinct from old.notes
            or new.tanggal is distinct from old.tanggal
            or new.shift_id is distinct from old.shift_id
            or new.team_id is distinct from old.team_id) then
      raise exception 'This sheet was submitted. Reopen it before editing.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_daily_check_sheet_before_write on public.daily_check_sheet;
create trigger trg_daily_check_sheet_before_write
before insert or update on public.daily_check_sheet
for each row execute function public.daily_check_sheet_before_write();

-- Access mirrors the temperature sheet, except that crew members work on
-- their whole team's sheet (the one-per-shift rule means the crew on duty
-- share it).
create or replace function public.can_read_daily_check(p_site_id uuid, p_team_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(case public.current_sicatat_role()
    when 'admin' then true
    when 'supervisor_smg' then true
    when 'supervisor_cop' then p_site_id = public.current_sicatat_site_id()
    when 'foreman' then p_team_id = public.current_sicatat_team_id()
    when 'crew' then p_team_id = public.current_sicatat_team_id()
    else false
  end, false);
$$;

create or replace function public.can_write_daily_check(p_team_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(case public.current_sicatat_role()
    when 'admin' then true
    when 'supervisor_smg' then true
    when 'crew' then p_team_id = public.current_sicatat_team_id()
    else false
  end, false);
$$;

revoke all on function public.can_read_daily_check(uuid, uuid) from public, anon;
revoke all on function public.can_write_daily_check(uuid) from public, anon;
grant execute on function public.can_read_daily_check(uuid, uuid) to authenticated;
grant execute on function public.can_write_daily_check(uuid) to authenticated;

alter table public.daily_check_sheet enable row level security;
revoke all on public.daily_check_sheet from anon;
grant select, insert, update, delete on public.daily_check_sheet to authenticated;

drop policy if exists daily_check_select on public.daily_check_sheet;
create policy daily_check_select on public.daily_check_sheet for select to authenticated
using (public.can_read_daily_check(site_id, team_id));

drop policy if exists daily_check_insert on public.daily_check_sheet;
create policy daily_check_insert on public.daily_check_sheet for insert to authenticated
with check (
  public.can_write_daily_check(team_id)
  and created_by = public.current_sicatat_user_id()
);

drop policy if exists daily_check_update on public.daily_check_sheet;
create policy daily_check_update on public.daily_check_sheet for update to authenticated
using (public.can_write_daily_check(team_id))
with check (public.can_write_daily_check(team_id));

-- Drafts only; submitted sheets stay for the audit trail.
drop policy if exists daily_check_delete on public.daily_check_sheet;
create policy daily_check_delete on public.daily_check_sheet for delete to authenticated
using (status = 'draft' and public.can_write_daily_check(team_id));

-- Lets the "New sheet" screen lock shifts that already have a sheet at the
-- team's site without exposing another team's readings.
create or replace function public.daily_check_occupied_shifts(
  p_form_type text,
  p_tanggal date,
  p_team_id uuid
)
returns setof uuid language sql stable security definer set search_path = public as $$
  select d.shift_id
  from public.daily_check_sheet d
  join public.team t on t.id = p_team_id
  where d.form_type = p_form_type
    and d.tanggal = p_tanggal
    and d.site_id = t.site_id
    and public.current_sicatat_role() is not null;
$$;

revoke all on function public.daily_check_occupied_shifts(text, date, uuid) from public, anon;
grant execute on function public.daily_check_occupied_shifts(text, date, uuid) to authenticated;
