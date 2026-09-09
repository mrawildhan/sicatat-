do $$
declare release_creator uuid;
begin
  select id into release_creator from public.app_user where role = 'admin' and is_active = true order by created_at limit 1;
  if release_creator is null then raise exception 'An active admin is required to publish an app release.'; end if;
  if not exists (select 1 from storage.objects where bucket_id = 'app-releases' and name = 'arm64-v8a/app-arm64-v8a-2.8.13-release.apk') then raise exception 'Upload the arm64-v8a 2.8.13 APK before activating this release.'; end if;
  update public.app_release set is_active = false where platform = 'android' and abi = 'arm64-v8a';
  insert into public.app_release (platform,abi,version_name,version_code,apk_path,release_notes,is_active,created_by) values
    ('android','arm64-v8a','2.8.13',12293,'arm64-v8a/app-arm64-v8a-2.8.13-release.apk',E'• Outstanding PM dibuat lebih ringkas per CPP dan PORT.\n• CM CPP dan PORT menampilkan daftar work order serta progres terakhir dari spreadsheet.',true,release_creator)
  on conflict (platform,abi,version_code) do update set version_name=excluded.version_name,apk_path=excluded.apk_path,release_notes=excluded.release_notes,is_active=excluded.is_active,created_by=excluded.created_by,published_at=now();
end $$;
