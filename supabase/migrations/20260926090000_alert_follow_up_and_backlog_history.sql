-- Audit features requested by the owner on 2026-09-26.
--
-- 1. Critical temperature alerts get a follow-up: open -> in progress ->
--    closed, with the action taken, an optional work order number and an
--    optional (compressed) photo. Every change is written to audit_log.
-- 2. PM and CM backlog counts are kept once per day, so the PM & CM screen
--    can show whether the backlog shrinks. The Weekly Meeting upload replaces
--    the work orders themselves, so without this the history is lost.

-- 1. Follow-up of critical temperature alerts ------------------------------

alter table public.temperature_alert
  add column if not exists followup_status text not null default 'open',
  add column if not exists followup_action text,
  add column if not exists followup_work_order text,
  add column if not exists followup_photo_path text,
  add column if not exists followup_by uuid references public.app_user(id),
  add column if not exists followup_at timestamptz,
  add column if not exists closed_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'temperature_alert_followup_status_check'
  ) then
    alter table public.temperature_alert
      add constraint temperature_alert_followup_status_check
      check (followup_status in ('open', 'in_progress', 'closed'));
  end if;
end $$;

create index if not exists temperature_alert_followup_open
  on public.temperature_alert (occurred_at desc)
  where followup_status <> 'closed';

-- Reviewers (foreman: own team, supervisor COP: own site, supervisor SMG and
-- admin: all) record the follow-up only through this function, so the
-- delivery columns stay server-owned.
create or replace function public.temperature_alert_follow_up(
  p_id uuid,
  p_status text,
  p_action text,
  p_work_order text,
  p_photo_path text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  alert public.temperature_alert;
  actor uuid := public.current_sicatat_user_id();
  new_action text := nullif(btrim(coalesce(p_action, '')), '');
  new_work_order text := nullif(btrim(coalesce(p_work_order, '')), '');
  new_photo text := nullif(btrim(coalesce(p_photo_path, '')), '');
begin
  select * into alert from public.temperature_alert where id = p_id for update;
  if not found then
    raise exception 'Peringatan suhu tidak ditemukan.';
  end if;
  if actor is null or not public.can_review_daily_check(alert.site_id, alert.team_id) then
    raise exception 'Anda tidak berwenang menindaklanjuti peringatan ini.';
  end if;
  if p_status not in ('open', 'in_progress', 'closed') then
    raise exception 'Status tindak lanjut tidak dikenal.';
  end if;
  if p_status = 'closed' and new_action is null then
    raise exception 'Tuliskan tindakan yang dilakukan sebelum menutup peringatan.';
  end if;
  if char_length(coalesce(new_action, '')) > 2000 then
    raise exception 'Tindakan maksimal 2000 karakter.';
  end if;
  if char_length(coalesce(new_work_order, '')) > 60 then
    raise exception 'Nomor WO maksimal 60 karakter.';
  end if;
  if new_photo is not null and split_part(new_photo, '/', 1) <> p_id::text then
    raise exception 'Foto tidak sesuai dengan peringatan ini.';
  end if;

  update public.temperature_alert
  set followup_status = p_status,
      followup_action = new_action,
      followup_work_order = new_work_order,
      followup_photo_path = new_photo,
      followup_by = actor,
      followup_at = now(),
      closed_at = case
        when p_status = 'closed' then coalesce(alert.closed_at, now())
        else null
      end
  where id = p_id;

  insert into public.audit_log (entity_type, entity_id, action, old_value, new_value, changed_by)
  values (
    'temperature_alert',
    p_id,
    'follow_up',
    jsonb_build_object(
      'status', alert.followup_status,
      'action', alert.followup_action,
      'work_order', alert.followup_work_order,
      'photo', alert.followup_photo_path
    ),
    jsonb_build_object(
      'status', p_status,
      'action', new_action,
      'work_order', new_work_order,
      'photo', new_photo
    ),
    actor
  );
end;
$$;

revoke all on function public.temperature_alert_follow_up(uuid, text, text, text, text) from public, anon;
grant execute on function public.temperature_alert_follow_up(uuid, text, text, text, text) to authenticated;

-- Reviewers who can see an alert also see its follow-up history.
drop policy if exists audit_log_read_temperature_alert on public.audit_log;
create policy audit_log_read_temperature_alert on public.audit_log
  for select to authenticated
  using (
    entity_type = 'temperature_alert'
    and exists (
      select 1 from public.temperature_alert a
      where a.id = audit_log.entity_id
        and public.can_review_daily_check(a.site_id, a.team_id)
    )
  );

-- Follow-up photos: private, JPEG only, compressed in the app to about
-- 300 KB (Supabase free plan). Path: <alert id>/<file>.jpg.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('temperature-alert-photos', 'temperature-alert-photos', false, 1048576, array['image/jpeg'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.can_review_temperature_alert_object(p_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.temperature_alert a
    where a.id::text = split_part(p_name, '/', 1)
      and public.can_review_daily_check(a.site_id, a.team_id)
  );
$$;

revoke all on function public.can_review_temperature_alert_object(text) from public, anon;
grant execute on function public.can_review_temperature_alert_object(text) to authenticated;

drop policy if exists temperature_alert_photo_read on storage.objects;
create policy temperature_alert_photo_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'temperature-alert-photos'
    and public.can_review_temperature_alert_object(name)
  );

drop policy if exists temperature_alert_photo_insert on storage.objects;
create policy temperature_alert_photo_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'temperature-alert-photos'
    and public.can_review_temperature_alert_object(name)
  );

drop policy if exists temperature_alert_photo_delete on storage.objects;
create policy temperature_alert_photo_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'temperature-alert-photos'
    and public.can_review_temperature_alert_object(name)
  );

-- 2. Daily PM and CM backlog history ----------------------------------------

create table if not exists public.maintenance_backlog_snapshot (
  taken_on    date not null,
  kind        text not null check (kind in ('pm', 'cm')),
  crew_code   text not null default '',
  site_code   text not null,
  outstanding integer not null check (outstanding >= 0),
  -- PM: planned start already passed. CM: raised more than 30 days ago.
  overdue     integer not null default 0 check (overdue >= 0),
  recorded_at timestamptz not null default now(),
  primary key (taken_on, kind, crew_code, site_code)
);

alter table public.maintenance_backlog_snapshot enable row level security;
revoke all on public.maintenance_backlog_snapshot from anon;
grant select on public.maintenance_backlog_snapshot to authenticated;

drop policy if exists maintenance_backlog_snapshot_read on public.maintenance_backlog_snapshot;
create policy maintenance_backlog_snapshot_read on public.maintenance_backlog_snapshot
  for select to authenticated
  using (public.current_sicatat_user_id() is not null);

-- Records today's (WITA) counts, replacing an earlier run of the same day.
create or replace function public.maintenance_record_backlog()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  today date := (now() at time zone 'Asia/Makassar')::date;
  written integer;
begin
  delete from public.maintenance_backlog_snapshot where taken_on = today;

  insert into public.maintenance_backlog_snapshot (taken_on, kind, crew_code, site_code, outstanding, overdue)
  select today, 'pm', coalesce(crew_code, ''), coalesce(site_code, ''), count(*),
         count(*) filter (where planned_start_on < today)
  from public.preventive_maintenance_work_order
  group by coalesce(crew_code, ''), coalesce(site_code, '');

  insert into public.maintenance_backlog_snapshot (taken_on, kind, crew_code, site_code, outstanding, overdue)
  select today, 'cm', '', coalesce(site_code, ''), count(*),
         count(*) filter (where raised_on < today - 30)
  from public.corrective_maintenance_work_order
  group by coalesce(site_code, '');

  select count(*) into written from public.maintenance_backlog_snapshot where taken_on = today;
  return written;
end;
$$;

revoke all on function public.maintenance_record_backlog() from public, anon, authenticated;
grant execute on function public.maintenance_record_backlog() to service_role;

create extension if not exists pg_cron;

select cron.unschedule(jobid)
from cron.job
where jobname = 'sicatat-maintenance-backlog-daily';

-- 23:30 WITA, after the day's uploads.
select cron.schedule(
  'sicatat-maintenance-backlog-daily',
  '30 15 * * *',
  $$ select public.maintenance_record_backlog(); $$
);

-- The first point of the history.
select public.maintenance_record_backlog();
