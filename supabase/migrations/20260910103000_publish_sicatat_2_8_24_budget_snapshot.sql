-- Publish the arm64 Android build that matches the 2.8.24 web budget view.

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

  update public.app_release
  set is_active = false
  where platform = 'android' and abi = 'arm64-v8a';

  insert into public.app_release (
    platform, abi, version_name, version_code, apk_path, release_notes, is_active, created_by
  ) values (
    'android',
    'arm64-v8a',
    '2.8.24',
    12304,
    'arm64-v8a/app-arm64-v8a-2.8.24-release.apk',
    E'• Anggaran Operasional Asam-Asam menampilkan snapshot budget dan aktual USD CPP/PORT Januari–Juni 2026.\n• Pembukaan halaman membaca data tersimpan agar cepat dan hemat pemakaian.',
    true,
    release_creator
  );
end $$;
