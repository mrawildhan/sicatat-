-- Publish SICATAT 2.6.5 after the matching APKs are uploaded to app-releases.
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
    ('android', 'arm64-v8a', '2.6.5', 12265, 'arm64-v8a/app-arm64-v8a-2.6.5-release.apk', E'• Sidebar desktop kini mengelompokkan Operasional, Referensi, dan Akun.\n• Gudang serta Pusat Dokumen tersedia bersama pada kelompok Referensi.', true, release_creator),
    ('android', 'armeabi-v7a', '2.6.5', 11265, 'armeabi-v7a/app-armeabi-v7a-2.6.5-release.apk', E'• Sidebar desktop kini mengelompokkan Operasional, Referensi, dan Akun.\n• Gudang serta Pusat Dokumen tersedia bersama pada kelompok Referensi.', true, release_creator),
    ('android', 'x86_64', '2.6.5', 14265, 'x86_64/app-x86_64-2.6.5-release.apk', E'• Sidebar desktop kini mengelompokkan Operasional, Referensi, dan Akun.\n• Gudang serta Pusat Dokumen tersedia bersama pada kelompok Referensi.', true, release_creator)
  on conflict (platform, abi, version_code) do update
  set version_name = excluded.version_name,
      apk_path = excluded.apk_path,
      release_notes = excluded.release_notes,
      is_active = excluded.is_active,
      created_by = excluded.created_by,
      published_at = now();
end $$;
