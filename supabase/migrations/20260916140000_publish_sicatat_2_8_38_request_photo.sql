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
      and name = 'arm64-v8a/app-arm64-v8a-2.8.38-release.apk'
  ) then
    raise exception 'Upload APK arm64-v8a SICATAT 2.8.38 sebelum mengaktifkan rilis.';
  end if;

  update public.app_release
  set is_active = false
  where platform = 'android' and abi = 'arm64-v8a';

  insert into public.app_release (
    platform, abi, version_name, version_code, apk_path, release_notes, is_active, created_by
  ) values (
    'android',
    'arm64-v8a',
    '2.8.38',
    14318,
    'arm64-v8a/app-arm64-v8a-2.8.38-release.apk',
    E'• Permintaan Barang: area pekerjaan bertambah COP.\n• Permintaan Barang: bisa melampirkan link produk (boleh diawali www.) dan satu foto barang, keduanya opsional. Foto dikompres otomatis.\n• Planner melihat foto dan alamat link lengkap sebelum membukanya.\n• Panduan pengguna ditulis ulang menjadi 10 kelompok mengikuti menu aplikasi.\n• Pusat Dokumen menolak pertanyaan di luar dokumen kerja dan menjawab lebih cepat.\n• Foto pada Pengingat dan Notulen dikompres otomatis sebelum diunggah.\n• Perbaikan lain: tombol Bagikan PDF sheet, catatan nilai tidak wajar di CSV, judul laporan periode, pencarian dan urutan Data PR, serta peringatan bila pengiriman email bermasalah.',
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
