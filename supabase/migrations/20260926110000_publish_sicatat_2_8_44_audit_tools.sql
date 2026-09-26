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
      and name = 'arm64-v8a/app-arm64-v8a-2.8.44-release.apk'
  ) then
    raise exception 'Upload APK arm64-v8a SICATAT 2.8.44 sebelum mengaktifkan rilis.';
  end if;

  update public.app_release
  set is_active = false
  where platform = 'android' and abi = 'arm64-v8a';

  insert into public.app_release (
    platform, abi, version_name, version_code, apk_path, release_notes, is_active, created_by
  ) values (
    'android',
    'arm64-v8a',
    '2.8.44',
    14324,
    'arm64-v8a/app-arm64-v8a-2.8.44-release.apk',
    E'• Tugas saya di Beranda: tugas sesuai peran (suhu kritis untuk crew dan foreman, persetujuan lembar untuk foreman, alat terlambat untuk warehouseman) dan pesanan barang Anda.
• Suhu: Tindak lanjut suhu kritis (tindakan, No. WO, foto, riwayat; ditutup oleh foreman) dan Kepatuhan pengisian per crew.
• Laporan Bulanan satu PDF, Riwayat aset per unit, alur PR sampai barang datang, tren backlog PM & CM, dan grafik anggaran vs aktual.
• Ekspor Excel di Barang dipesan, Cari barang, Data PR, Peminjaman Alat, dan laporan suhu. Data PR, Laporan Bulanan, dan Panduan pindah ke Referensi.',
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
