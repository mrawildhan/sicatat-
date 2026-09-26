-- Critical temperatures are the task of the crew on that sheet and their
-- foreman (owner decision 2026-09-26). Crew now see their own crew's alerts
-- and may record handling (open / in progress, action, WO, photo); closing
-- stays with reviewers (foreman, supervisors, admin), so the person who did
-- the work is not the one who signs it off.

create or replace function public.can_follow_up_temperature_alert(p_site_id uuid, p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_review_daily_check(p_site_id, p_team_id)
    or (
      public.current_sicatat_role() = 'crew'
      and p_team_id is not null
      and p_team_id = public.current_sicatat_team_id()
    );
$$;

revoke all on function public.can_follow_up_temperature_alert(uuid, uuid) from public, anon;
grant execute on function public.can_follow_up_temperature_alert(uuid, uuid) to authenticated;

drop policy if exists temperature_alert_read on public.temperature_alert;
create policy temperature_alert_read on public.temperature_alert
  for select to authenticated
  using (public.can_follow_up_temperature_alert(site_id, team_id));

drop policy if exists audit_log_read_temperature_alert on public.audit_log;
create policy audit_log_read_temperature_alert on public.audit_log
  for select to authenticated
  using (
    entity_type = 'temperature_alert'
    and exists (
      select 1 from public.temperature_alert a
      where a.id = audit_log.entity_id
        and public.can_follow_up_temperature_alert(a.site_id, a.team_id)
    )
  );

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
      and public.can_follow_up_temperature_alert(a.site_id, a.team_id)
  );
$$;

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
  reviewer boolean;
begin
  select * into alert from public.temperature_alert where id = p_id for update;
  if not found then
    raise exception 'Peringatan suhu tidak ditemukan.';
  end if;
  if actor is null or not public.can_follow_up_temperature_alert(alert.site_id, alert.team_id) then
    raise exception 'Anda tidak berwenang menindaklanjuti peringatan ini.';
  end if;
  reviewer := public.can_review_daily_check(alert.site_id, alert.team_id);
  if p_status not in ('open', 'in_progress', 'closed') then
    raise exception 'Status tindak lanjut tidak dikenal.';
  end if;
  if not reviewer and (p_status = 'closed' or alert.followup_status = 'closed') then
    raise exception 'Peringatan ditutup atau dibuka kembali oleh foreman.';
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
