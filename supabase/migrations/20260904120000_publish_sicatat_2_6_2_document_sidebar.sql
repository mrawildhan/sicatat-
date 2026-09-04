-- Publish SICATAT 2.6.2 after the matching APKs are uploaded to app-releases.
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
    raise exception 'An active admin is required to publish an app release.';
  end if;

  insert into public.app_release (
    platform, abi, version_name, version_code, apk_path, release_notes, is_active, created_by
  ) values
    ('android', 'arm64-v8a', '2.6.2', 12262, 'arm64-v8a/app-arm64-v8a-2.6.2-release.apk', E'• Pusat Dokumen sekarang tersedia pada sidebar website.\n• Menu bawah aplikasi tetap ringkas; Gudang tidak dihapus.', true, release_creator),
    ('android', 'armeabi-v7a', '2.6.2', 11262, 'armeabi-v7a/app-armeabi-v7a-2.6.2-release.apk', E'• Pusat Dokumen sekarang tersedia pada sidebar website.\n• Menu bawah aplikasi tetap ringkas; Gudang tidak dihapus.', true, release_creator),
    ('android', 'x86_64', '2.6.2', 14262, 'x86_64/app-x86_64-2.6.2-release.apk', E'• Pusat Dokumen sekarang tersedia pada sidebar website.\n• Menu bawah aplikasi tetap ringkas; Gudang tidak dihapus.', true, release_creator)
  on conflict (platform, abi, version_code) do update
  set version_name = excluded.version_name,
      apk_path = excluded.apk_path,
      release_notes = excluded.release_notes,
      is_active = excluded.is_active,
      created_by = excluded.created_by,
      published_at = now();
end $$;
