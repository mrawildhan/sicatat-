-- Improvements after the owner's user-perspective review (2026-09-18):
--   * digital "Mengetahui" approval of submitted daily check sheets
--   * per-point temperature limits for the daily check sheets
--   * critical-temperature email alerts (recipients managed by admin)

-- ---------------------------------------------------------------------------
-- 1. Approval ("Mengetahui, Pengawas/Foreman")
-- ---------------------------------------------------------------------------
alter table public.daily_check_sheet
  add column if not exists approved_by uuid references public.app_user(id),
  add column if not exists approved_at timestamptz;

create or replace function public.can_review_daily_check(p_site_id uuid, p_team_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(case public.current_sicatat_role()
    when 'admin' then true
    when 'supervisor_smg' then true
    when 'supervisor_cop' then p_site_id = public.current_sicatat_site_id()
    when 'foreman' then p_team_id = public.current_sicatat_team_id()
    else false
  end, false);
$$;
revoke all on function public.can_review_daily_check(uuid, uuid) from public, anon;
grant execute on function public.can_review_daily_check(uuid, uuid) to authenticated;

create or replace function public.daily_check_sheet_before_write()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- The site always follows the team, never the client.
  select t.site_id into new.site_id from public.team t where t.id = new.team_id;
  if new.site_id is null then
    raise exception 'Regu yang dipilih belum memiliki lokasi.';
  end if;
  new.updated_at := now();
  new.updated_by := public.current_sicatat_user_id();
  if tg_op = 'INSERT' then
    new.created_at := now();
    new.status := 'draft';
    new.submitted_at := null;
    new.submitted_by := null;
    new.approved_at := null;
    new.approved_by := null;
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
    -- Approval is set only through daily_check_approve(), and a reopened
    -- sheet loses it because its values may change.
    if new.status = 'draft' then
      new.approved_at := null;
      new.approved_by := null;
    elsif coalesce(current_setting('sicatat.daily_check_approving', true), '') <> 'on' then
      new.approved_at := old.approved_at;
      new.approved_by := old.approved_by;
    end if;
    -- A submitted sheet is final; only reopening it (status -> draft) is allowed.
    if old.status = 'submitted' and new.status = 'submitted'
       and (new.readings is distinct from old.readings
            or new.notes is distinct from old.notes
            or new.tanggal is distinct from old.tanggal
            or new.shift_id is distinct from old.shift_id
            or new.team_id is distinct from old.team_id) then
      raise exception 'Lembar ini sudah dikirim. Buka kembali lembar sebelum mengubahnya.';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.daily_check_approve(p_id uuid, p_approve boolean default true)
returns void language plpgsql security definer set search_path = public as $$
declare
  target public.daily_check_sheet;
begin
  select * into target from public.daily_check_sheet where id = p_id;
  if target.id is null then
    raise exception 'Lembar tidak ditemukan.';
  end if;
  if not public.can_review_daily_check(target.site_id, target.team_id) then
    raise exception 'Hanya foreman atau supervisor yang dapat menyetujui lembar ini.';
  end if;
  if target.status <> 'submitted' then
    raise exception 'Lembar harus dikirim sebelum disetujui.';
  end if;
  perform set_config('sicatat.daily_check_approving', 'on', true);
  update public.daily_check_sheet
     set approved_by = case when p_approve then public.current_sicatat_user_id() end,
         approved_at = case when p_approve then now() end
   where id = p_id;
  perform set_config('sicatat.daily_check_approving', '', true);
end;
$$;
revoke all on function public.daily_check_approve(uuid, boolean) from public, anon;
grant execute on function public.daily_check_approve(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Temperature limits per measurement point of the daily check sheets
-- ---------------------------------------------------------------------------
create table if not exists public.daily_check_threshold (
  id           uuid primary key default gen_random_uuid(),
  form_type    text not null check (form_type in ('hydraulic_feeder', 'coal_valve')),
  field_key    text not null check (field_key ~ '^[a-z0-9_]{1,40}$'),
  warning_from numeric not null,
  critical_from numeric not null,
  note         text check (note is null or char_length(note) <= 300),
  updated_by   uuid references public.app_user(id),
  updated_at   timestamptz not null default now(),
  constraint daily_check_threshold_order check (warning_from < critical_from),
  constraint daily_check_threshold_range check (
    warning_from between -50 and 250 and critical_from between -50 and 250
  ),
  unique (form_type, field_key)
);

create or replace function public.can_manage_sicatat_master()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.current_sicatat_role() in ('admin', 'supervisor_smg'), false);
$$;
revoke all on function public.can_manage_sicatat_master() from public, anon;
grant execute on function public.can_manage_sicatat_master() to authenticated;

alter table public.daily_check_threshold enable row level security;
revoke all on public.daily_check_threshold from anon;
grant select, insert, update, delete on public.daily_check_threshold to authenticated;
drop policy if exists daily_check_threshold_read on public.daily_check_threshold;
create policy daily_check_threshold_read on public.daily_check_threshold
  for select to authenticated using (public.current_sicatat_role() is not null);
drop policy if exists daily_check_threshold_write on public.daily_check_threshold;
create policy daily_check_threshold_write on public.daily_check_threshold
  for all to authenticated
  using (public.can_manage_sicatat_master())
  with check (public.can_manage_sicatat_master());

-- ---------------------------------------------------------------------------
-- 3. Critical-temperature email alerts
-- ---------------------------------------------------------------------------
create table if not exists public.temperature_alert_recipient (
  id         uuid primary key default gen_random_uuid(),
  email      text not null unique check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  name       text check (name is null or char_length(name) <= 120),
  site_id    uuid references public.site(id),
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.temperature_alert_recipient enable row level security;
revoke all on public.temperature_alert_recipient from anon;
grant select, insert, update, delete on public.temperature_alert_recipient to authenticated;
drop policy if exists temperature_alert_recipient_manage on public.temperature_alert_recipient;
create policy temperature_alert_recipient_manage on public.temperature_alert_recipient
  for all to authenticated
  using (public.can_manage_sicatat_master())
  with check (public.can_manage_sicatat_master());

-- One row per critical value, so each value is emailed once.
create table if not exists public.temperature_alert (
  id           uuid primary key default gen_random_uuid(),
  source       text not null check (source in ('daily_check', 'sheet')),
  source_key   text not null unique,
  site_id      uuid references public.site(id),
  team_id      uuid references public.team(id),
  form_label   text not null,
  point_label  text not null,
  value        numeric not null,
  limit_value  numeric not null,
  sheet_date   date,
  shift_label  text,
  occurred_at  timestamptz not null,
  status       text not null default 'pending' check (status in ('pending', 'sent', 'failed', 'no_recipient')),
  error        text,
  sent_at      timestamptz,
  created_at   timestamptz not null default now()
);
create index if not exists temperature_alert_recent on public.temperature_alert (occurred_at desc);
alter table public.temperature_alert enable row level security;
revoke all on public.temperature_alert from anon;
grant select on public.temperature_alert to authenticated;
drop policy if exists temperature_alert_read on public.temperature_alert;
create policy temperature_alert_read on public.temperature_alert
  for select to authenticated using (public.can_review_daily_check(site_id, team_id));
