-- sync_service.dart upserts audit rows on id. INSERT ... ON CONFLICT DO UPDATE
-- also applies the SELECT policy to the new row, so writers must always see
-- their own audit events, e.g. when the event reaches the server before its
-- sheet or after the sheet was deleted. Edits and deletes stay blocked by the
-- audit_log_append_only trigger and the revoked DELETE grant.
drop policy if exists audit_log_read_scoped on public.audit_log;
create policy audit_log_read_scoped on public.audit_log
  for select to authenticated
  using (
    changed_by = public.current_sicatat_user_id()
    or public.can_manage_sicatat_master_data()
    or (
      entity_type = 'sheet'
      and exists (
        select 1 from public.sheet s
        where s.id = audit_log.entity_id
          and public.can_read_sicatat_sheet(s.site_id, s.team_id, s.created_by)
      )
    )
  );
