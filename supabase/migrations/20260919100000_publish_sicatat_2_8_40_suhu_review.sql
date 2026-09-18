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
      and name = 'arm64-v8a/app-arm64-v8a-2.8.40-release.apk'
  ) then
    raise exception 'Upload APK arm64-v8a SICATAT 2.8.40 sebelum mengaktifkan rilis.';
  end if;

  update public.app_release
  set is_active = false
  where platform = 'android' and abi = 'arm64-v8a';

  insert into public.app_release (
    platform, abi, version_name, version_code, apk_path, release_notes, is_active, created_by
  ) values (
    'android',
    'arm64-v8a',
    '2.8.40',
    14320,
    'arm64-v8a/app-arm64-v8a-2.8.40-release.apk',
    E'• Suhu kini berisi Daily Check Sheet Hydraulic Feeder dan Temperature Coal Valve, dicetak di atas formulir kertas aslinya.
• Beranda menampilkan jadwal pengecekan Hydraulic; HP memberi notifikasi 10 menit sebelum jadwal regu yang bertugas.
• Foreman dan supervisor kini bisa membuka Suhu, menyetujui lembar (Mengetahui), dan melihat suhu kritis.
• Tren suhu per titik ukur, nilai pengecekan sebelumnya di bawah kolom, dan cetak banyak lembar sekaligus.
• Pembaruan aplikasi ditawarkan langsung di layar masuk.
• Kata sif diganti shift, kalender dan nama bulan berbahasa Indonesia, regu tampil di daftar lembar.',
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
