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
    '2.8.22',
    12302,
    'arm64-v8a/app-arm64-v8a-2.8.22-release.apk',
    E'• Anggaran Operasional Asam-Asam kini menampilkan budget, aktual, dan sisa dalam USD untuk Januari–Juni 2026.\n• Ringkasan CPP dan PORT serta realisasi bulanan diambil dari spreadsheet yang disetujui.',
    true,
    release_creator
  );
end $$;
