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
      and name = 'arm64-v8a/app-arm64-v8a-2.8.37-release.apk'
  ) then
    raise exception 'Upload APK arm64-v8a SICATAT 2.8.37 sebelum mengaktifkan rilis.';
  end if;

  update public.app_release
  set is_active = false
  where platform = 'android' and abi = 'arm64-v8a';

  insert into public.app_release (
    platform, abi, version_name, version_code, apk_path, release_notes, is_active, created_by
  ) values (
    'android',
    'arm64-v8a',
    '2.8.37',
    14317,
    'arm64-v8a/app-arm64-v8a-2.8.37-release.apk',
    E'• Panduan pengguna ditulis ulang: 10 kelompok mengikuti menu aplikasi, termasuk Laporan, Notulen rapat, Anggaran, Pusat Dokumen, dan panduan admin.\n• Pusat Dokumen menolak pertanyaan di luar dokumen kerja dan menjawab lebih cepat.\n• Foto pada Pengingat dan Notulen dikompres otomatis sebelum diunggah; PDF pengingat maksimal 2 MB.\n• Tombol Bagikan pada PDF sheet tidak lagi menghasilkan berkas kosong, dan halaman kosong di akhir PDF dihapus.\n• Catatan nilai tidak wajar hanya menempel pada pembacaan yang bersangkutan, termasuk di CSV.\n• Judul laporan periode menghitung sheet yang benar-benar berisi data.\n• Data PR: pencarian tidak lagi berhenti diam-diam di 60 baris dan No. PR terbaru diurutkan sebagai angka.\n• Layar Pengingat memperingatkan bila pengiriman email bermasalah.',
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
