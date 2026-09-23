-- Audit 2026-09-23: 43 foreign keys had no index.  The tables are small today,
-- so only the ones that grow with every shift (and are joined or checked by
-- RLS) get one; lookup tables such as shift or site stay as they are.

create index if not exists reading_unit_status_id_idx on public.reading (unit_status_id);
create index if not exists reading_recorded_by_idx on public.reading (recorded_by);
create index if not exists unit_status_equipment_id_idx on public.unit_status (equipment_id);
create index if not exists sheet_team_id_idx on public.sheet (team_id);
create index if not exists sheet_shift_id_idx on public.sheet (shift_id);
create index if not exists sheet_created_by_idx on public.sheet (created_by);
create index if not exists sheet_contributor_user_id_idx on public.sheet_contributor (user_id);
create index if not exists attachment_sheet_id_idx on public.attachment (sheet_id);
create index if not exists attachment_reading_id_idx on public.attachment (reading_id);
create index if not exists audit_log_changed_by_idx on public.audit_log (changed_by);
create index if not exists daily_check_sheet_team_id_idx on public.daily_check_sheet (team_id);
create index if not exists daily_check_sheet_shift_id_idx on public.daily_check_sheet (shift_id);
create index if not exists temperature_alert_team_id_idx on public.temperature_alert (team_id);
create index if not exists operational_reminder_activity_actor_id_idx on public.operational_reminder_activity (actor_id);
