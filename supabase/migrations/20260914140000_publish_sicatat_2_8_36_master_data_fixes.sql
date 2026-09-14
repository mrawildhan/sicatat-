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
      and name = 'arm64-v8a/app-arm64-v8a-2.8.36-release.apk'
  ) then
    raise exception 'Upload APK arm64-v8a SICATAT 2.8.36 sebelum mengaktifkan rilis.';
  end if;

  update public.app_release
  set is_active = false
  where platform = 'android' and abi = 'arm64-v8a';

  insert into public.app_release (
    platform, abi, version_name, version_code, apk_path, release_notes, is_active, created_by
  ) values (
    'android',
    'arm64-v8a',
    '2.8.36',
    14316,
    'arm64-v8a/app-arm64-v8a-2.8.36-release.apk',
    E'• Kolom suhu hanya menerima angka, dan urutan kolom sama di setiap peralatan (Remark selalu terakhir).\n• Perubahan ronde dan pembacaan yang sudah tersinkron tidak lagi hilang saat diperbarui.\n• Daftar lokasi, regu, pengguna, dan pengingat kini urut dengan benar; pengingat terlambat tampil paling atas dan kategorinya berbahasa Indonesia.\n• Permintaan barang yang ditolak wajib diberi alasan.\n• Admin: Shift dan Rotasi regu bisa disimpan lagi, Batas suhu memeriksa isian sebelum disimpan, dan label data master berbahasa Indonesia.\n• Pencarian Gudang memberi tahu bila hasilnya lebih dari 100.',
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
