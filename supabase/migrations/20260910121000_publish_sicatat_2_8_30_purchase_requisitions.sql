do $$
declare
  release_creator uuid;
begin
  select id into release_creator
  from public.app_user
  where role = 'admin' and is_active
  order by created_at
  limit 1;

  insert into public.app_release (
    platform, abi, version_name, version_code, apk_path, release_notes, is_active, created_by
  ) values (
    'android',
    'arm64-v8a',
    '2.8.30',
    12310,
    'arm64-v8a/app-arm64-v8a-2.8.30-release.apk',
    E'• Menu Data PR tersedia pada kelompok Operasional.\n• Cari No. PR, No. PO, deskripsi, atau referensi alat.\n• Ketuk hasil untuk melihat nomor PO serta tanggal penutupan dan rilis.',
    true,
    release_creator
  ) on conflict (platform, abi, version_code) do update
  set version_name = excluded.version_name,
      apk_path = excluded.apk_path,
      release_notes = excluded.release_notes,
      is_active = true,
      created_by = excluded.created_by;

  update public.app_release
  set is_active = false
  where platform = 'android'
    and abi = 'arm64-v8a'
    and version_code <> 12310;
end $$;
