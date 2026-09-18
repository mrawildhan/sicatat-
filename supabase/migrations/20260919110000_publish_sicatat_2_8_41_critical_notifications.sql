do $$
declare
  release_creator uuid;
begin
  select id into release_creator
  from public.app_user
  where role = 'admin' and is_active = true
  order by created_at
  limit 1;

  if release_creator is null then
    raise exception 'Tidak ditemukan admin aktif untuk menerbitkan rilis Android.';
  end if;

  if not exists (
    select 1
    from storage.objects
    where bucket_id = 'app-releases'
      and name = 'arm64-v8a/app-arm64-v8a-2.8.41-release.apk'
  ) then
    raise exception 'Upload APK arm64-v8a SICATAT 2.8.41 sebelum mengaktifkan rilis.';
  end if;

  update public.app_release
  set is_active = false
  where platform = 'android' and abi = 'arm64-v8a';

  insert into public.app_release (
    platform, abi, version_name, version_code, apk_path, release_notes, is_active, created_by
  ) values (
    'android',
    'arm64-v8a',
    '2.8.41',
    14321,
    'arm64-v8a/app-arm64-v8a-2.8.41-release.apk',
    E'• Foreman dan supervisor mendapat notifikasi di HP saat ada suhu kritis di regu atau lokasinya, tanpa perlu email. Notifikasi muncul selama SICATAT terbuka atau begitu aplikasi dibuka lagi.\n• Pembaruan aplikasi ditawarkan langsung di layar masuk sebelum mengisi NIK dan PIN.',
    true,
    release_creator
  ) on conflict (platform, abi, version_code) do update
  set version_name = excluded.version_name,
      apk_path = excluded.apk_path,
      release_notes = excluded.release_notes,
      is_active = true,
      created_by = excluded.created_by,
      published_at = now();
end $$;
