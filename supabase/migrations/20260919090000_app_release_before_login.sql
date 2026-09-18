-- The Android app offers an update on the login screen, before NIK/PIN are
-- entered, so the signed-out (anon) app must see the active release and
-- download exactly that APK. Nothing else in the bucket or table is exposed;
-- managing releases stays admin-only.

grant select on public.app_release to anon;

drop policy if exists app_release_read_active_anon on public.app_release;
create policy app_release_read_active_anon on public.app_release
  for select to anon
  using (is_active = true);

drop policy if exists app_release_object_read_active_anon on storage.objects;
create policy app_release_object_read_active_anon on storage.objects
  for select to anon
  using (
    bucket_id = 'app-releases'
    and exists (
      select 1
      from public.app_release r
      where r.is_active = true
        and r.apk_path = storage.objects.name
    )
  );
