-- Publish SICATAT 2.6.0 after the three matching APKs are uploaded to the
-- private app-releases bucket. The in-app updater selects the matching ABI.
do $$
declare
  release_creator uuid;
begin
  select id
    into release_creator
  from public.app_user
  where role = 'admin'
    and is_active = true
  order by created_at
  limit 1;

  if release_creator is null then
    raise exception 'An active admin is required to publish an app release.';
  end if;

  insert into public.app_release (
    platform,
    abi,
    version_name,
    version_code,
    apk_path,
    release_notes,
    is_active,
    created_by
  )
  values
    (
      'android',
      'arm64-v8a',
      '2.6.0',
      12260,
      'arm64-v8a/app-arm64-v8a-2.6.0-release.apk',
      E'• Pusat Dokumen baru untuk mencari SOP, izin kerja, JSEA, manual book, dan drawing dari folder Google Drive resmi.\n• Jawaban AI dibatasi pada file sumber dan menampilkan dokumen rujukan.\n• Seluruh pesan pembaruan aplikasi telah diterjemahkan ke Bahasa Indonesia.',
      true,
      release_creator
    ),
    (
      'android',
      'armeabi-v7a',
      '2.6.0',
      11260,
      'armeabi-v7a/app-armeabi-v7a-2.6.0-release.apk',
      E'• Pusat Dokumen baru untuk mencari SOP, izin kerja, JSEA, manual book, dan drawing dari folder Google Drive resmi.\n• Jawaban AI dibatasi pada file sumber dan menampilkan dokumen rujukan.\n• Seluruh pesan pembaruan aplikasi telah diterjemahkan ke Bahasa Indonesia.',
      true,
      release_creator
    ),
    (
      'android',
      'x86_64',
      '2.6.0',
      14260,
      'x86_64/app-x86_64-2.6.0-release.apk',
      E'• Pusat Dokumen baru untuk mencari SOP, izin kerja, JSEA, manual book, dan drawing dari folder Google Drive resmi.\n• Jawaban AI dibatasi pada file sumber dan menampilkan dokumen rujukan.\n• Seluruh pesan pembaruan aplikasi telah diterjemahkan ke Bahasa Indonesia.',
      true,
      release_creator
    )
  on conflict (platform, abi, version_code) do update
  set version_name = excluded.version_name,
      apk_path = excluded.apk_path,
      release_notes = excluded.release_notes,
      is_active = excluded.is_active,
      created_by = excluded.created_by,
      published_at = now();
end $$;
