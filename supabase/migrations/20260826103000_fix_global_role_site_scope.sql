-- Global roles must not inherit Asam-Asam from the initial backfill. Their
-- null site_id explicitly means access to every active SICATAT site.
update public.app_user
set site_id = null
where role in ('admin', 'supervisor_smg');
