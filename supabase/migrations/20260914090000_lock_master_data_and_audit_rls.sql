-- Security audit 2026-09-14: eleven legacy tables from schema.sql never had
-- RLS enabled, so the public anon key could read, change, or delete master
-- data, forge or delete audit history, and raise app_version.min_version to
-- lock every Android install. Writers below mirror the RoleGuard on the
-- /admin/* routes in flutter_app/lib/app.dart (admin, supervisor_smg).

create or replace function public.can_manage_sicatat_master_data()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_sicatat_role() in ('admin', 'supervisor_smg'), false);
$$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'module', 'form_template', 'equipment', 'measurement_point', 'threshold',
    'shift', 'roster', 'roster_anchor'
  ]
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke insert, update, delete on public.%I from anon', t);
    execute format('drop policy if exists %I on public.%I', t || '_read_active_users', t);
    execute format('drop policy if exists %I on public.%I', t || '_manage_master_data', t);
    execute format(
      'create policy %I on public.%I for select to authenticated using (public.current_sicatat_user_id() is not null)',
      t || '_read_active_users', t
    );
    execute format(
      'create policy %I on public.%I for all to authenticated using (public.can_manage_sicatat_master_data()) with check (public.can_manage_sicatat_master_data())',
      t || '_manage_master_data', t
    );
  end loop;
end;
$$;

-- The Android app reads the version policy before sign-in, so reads stay public.
alter table public.app_version enable row level security;
revoke insert, update, delete on public.app_version from anon;
drop policy if exists app_version_read_public on public.app_version;
drop policy if exists app_version_manage_admin on public.app_version;
create policy app_version_read_public on public.app_version
  for select to anon, authenticated using (true);
create policy app_version_manage_admin on public.app_version
  for all to authenticated
  using (public.current_sicatat_role() = 'admin')
  with check (public.current_sicatat_role() = 'admin');

alter table public.attachment enable row level security;
revoke insert, update, delete on public.attachment from anon;
drop policy if exists attachment_read_scoped on public.attachment;
drop policy if exists attachment_manage_master_data on public.attachment;
create policy attachment_read_scoped on public.attachment
  for select to authenticated
  using (
    public.can_manage_sicatat_master_data()
    or exists (
      select 1 from public.sheet s
      where s.id = attachment.sheet_id
        and public.can_read_sicatat_sheet(s.site_id, s.team_id, s.created_by)
    )
  );
create policy attachment_manage_master_data on public.attachment
  for all to authenticated
  using (public.can_manage_sicatat_master_data())
  with check (public.can_manage_sicatat_master_data());

-- audit_log is append-only. Clients upsert on id so retried syncs stay
-- idempotent; the trigger lets an identical re-send through but rejects edits.
create or replace function public.prevent_audit_log_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Audit history cannot be deleted.' using errcode = '42501';
  end if;
  if new is distinct from old then
    raise exception 'Audit history cannot be changed.' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists audit_log_append_only on public.audit_log;
create trigger audit_log_append_only
  before update or delete on public.audit_log
  for each row execute function public.prevent_audit_log_mutation();

alter table public.audit_log enable row level security;
revoke insert, update, delete on public.audit_log from anon;
revoke delete on public.audit_log from authenticated;
drop policy if exists audit_log_read_scoped on public.audit_log;
drop policy if exists audit_log_insert_own on public.audit_log;
drop policy if exists audit_log_resend_own on public.audit_log;
create policy audit_log_read_scoped on public.audit_log
  for select to authenticated
  using (
    public.can_manage_sicatat_master_data()
    or (
      entity_type = 'sheet'
      and exists (
        select 1 from public.sheet s
        where s.id = audit_log.entity_id
          and public.can_read_sicatat_sheet(s.site_id, s.team_id, s.created_by)
      )
    )
  );
create policy audit_log_insert_own on public.audit_log
  for insert to authenticated
  with check (changed_by = public.current_sicatat_user_id());
create policy audit_log_resend_own on public.audit_log
  for update to authenticated
  using (changed_by = public.current_sicatat_user_id())
  with check (changed_by = public.current_sicatat_user_id());

-- Anonymous callers passed the role check (NULL NOT IN (...) is NULL) and
-- could list occupied shifts for any site and date.
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
  if public.current_sicatat_user_id() is null then
    raise exception 'No active SICATAT user.' using errcode = '42501';
  end if;
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

-- Public sign-up is enabled on the project, so "authenticated" alone does not
-- mean a SICATAT account. Release metadata and APKs require an active user.
drop policy if exists app_release_read_active on public.app_release;
create policy app_release_read_active on public.app_release
  for select to authenticated
  using (is_active = true and public.current_sicatat_user_id() is not null);

drop policy if exists app_release_object_read_authenticated on storage.objects;
create policy app_release_object_read_authenticated on storage.objects
  for select to authenticated
  using (bucket_id = 'app-releases' and public.current_sicatat_user_id() is not null);
