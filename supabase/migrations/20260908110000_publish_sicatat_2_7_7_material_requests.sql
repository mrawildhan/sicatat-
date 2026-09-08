-- Publish only after the three matching APK artifacts are available.
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

  if (select count(*) from storage.objects where bucket_id = 'app-releases' and name in (
    'arm64-v8a/app-arm64-v8a-2.7.7-release.apk',
    'armeabi-v7a/app-armeabi-v7a-2.7.7-release.apk',
    'x86_64/app-x86_64-2.7.7-release.apk')) <> 3 then
    raise exception 'Upload all three 2.7.7 APKs before activating this release.';
  end if;

  update public.app_release
  set is_active = false
  where platform = 'android';

  insert into public.app_release (
    platform, abi, version_name, version_code, apk_path, release_notes, is_active, created_by
  ) values
    ('android', 'arm64-v8a', '2.7.7', 12277, 'arm64-v8a/app-arm64-v8a-2.7.7-release.apk', E'• Beranda diringkas menjadi grup Operasional dan Referensi agar lebih rapi.\n• Crew dapat mengirim pengajuan barang LV atau Drilling: nama, jumlah, satuan, kondisi kebutuhan, dan alasan.\n• Planner dapat melihat seluruh pengajuan serta menyimpan status Diproses atau Ditolak dengan catatan.', true, release_creator),
    ('android', 'armeabi-v7a', '2.7.7', 11277, 'armeabi-v7a/app-armeabi-v7a-2.7.7-release.apk', E'• Beranda diringkas menjadi grup Operasional dan Referensi agar lebih rapi.\n• Crew dapat mengirim pengajuan barang LV atau Drilling: nama, jumlah, satuan, kondisi kebutuhan, dan alasan.\n• Planner dapat melihat seluruh pengajuan serta menyimpan status Diproses atau Ditolak dengan catatan.', true, release_creator),
    ('android', 'x86_64', '2.7.7', 14277, 'x86_64/app-x86_64-2.7.7-release.apk', E'• Beranda diringkas menjadi grup Operasional dan Referensi agar lebih rapi.\n• Crew dapat mengirim pengajuan barang LV atau Drilling: nama, jumlah, satuan, kondisi kebutuhan, dan alasan.\n• Planner dapat melihat seluruh pengajuan serta menyimpan status Diproses atau Ditolak dengan catatan.', true, release_creator)
  on conflict (platform, abi, version_code) do update
  set version_name = excluded.version_name,
      apk_path = excluded.apk_path,
      release_notes = excluded.release_notes,
      is_active = excluded.is_active,
      created_by = excluded.created_by,
      published_at = now();
end $$;
