do $$
declare
  release_creator uuid;
begin
  select id into release_creator from public.app_user
  where role = 'admin' and is_active = true order by created_at limit 1;
  if release_creator is null then
    raise exception 'Tidak ditemukan admin aktif untuk menerbitkan rilis Android.';
  end if;
  update public.app_release set is_active = false
  where platform = 'android' and abi = 'arm64-v8a';
  insert into public.app_release (
    platform, abi, version_name, version_code, apk_path, release_notes, is_active, created_by
  ) values (
    'android', 'arm64-v8a', '2.8.28', 12308,
    'arm64-v8a/app-arm64-v8a-2.8.28-release.apk',
    E'• Tampilan Anggaran Operasional lebih padat dan konsisten di satu halaman.\n• Angka USD memakai pemisah ribuan Indonesia.\n• Realisasi bulanan dibuka pada halaman rincian tersendiri.',
    true, release_creator
  );
end $$;
