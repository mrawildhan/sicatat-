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
    '2.8.33',
    12313,
    'arm64-v8a/app-arm64-v8a-2.8.33-release.apk',
    E'• Filter periode rilis PR diperbaiki: pilih tahun saja atau bulan dan tahun.\n• Kartu PR dirapikan dengan judul PR dan PO dalam satu baris.\n• Informasi sumber PR yang tidak diperlukan dihapus.',
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
    and version_code <> 12313;
end $$;
