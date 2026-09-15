# SICATAT — Codex Handoff

**How to read this file:** sections below dated `— 2026-MM-DD` are a historical changelog, accurate only as of that date — don't treat an old dated entry (e.g. "Canonical source remains worktree `42e3`") as still true just because it isn't explicitly retracted. Only "Current continuation baseline" and "Current product and non-negotiable rules" are meant to describe *today's* state, and even those can drift between edits — re-verify against `git log -1` and `flutter_app/pubspec.yaml` before trusting a version/commit claim here.

## Urutan data Supabase & uji live Data master — 2026-09-14

- `postgrest-dart` mengurutkan **menurun** bila `ascending` tidak ditulis (berbeda dengan SQL dan postgrest-js; tertulis di dokumentasi paketnya). 34 pemanggilan `.order(...)` tanpa arah membuat Lokasi kerja, regu, pengguna, dan email tampil Z→A; Pengingat menampilkan jatuh tempo terjauh paling atas (yang terlambat di bawah); Gudang memakai `.order(...).limit(100)` sehingga tanpa kata kunci yang tampil justru 100 baris terakhir menurut abjad. Semua kini `ascending: true`. `test/order_direction_test.dart` gagal bila ada `.order('kolom')` baru tanpa arah. Form suhu, Anggaran, dan PM/CM tidak terdampak karena mengurutkan ulang di aplikasi.
- Data master: semua layar hanya punya tambah/ubah/aktif-nonaktif, tanpa hapus. Uji live Lokasi kerja lolos (buat `UJI-WEB` → ubah nama → nonaktifkan). Jangan menambah peralatan, titik ukur, atau shift di produksi untuk uji (langsung muncul di form crew), dan jangan membuat pengguna uji (form butuh PIN).
- Shift dan Jadwal regu tidak pernah bisa disimpan dari website: validasi di `basic_master_screens.dart` memakai raw string dengan backslash ganda (`r'^([01]\\d|2[0-3]):[0-5]\\d$'`, `r'^\\d{4}-\\d{2}-\\d{2}$'`). Di raw string Dart itu berarti karakter backslash + "d", sehingga "07:00" dan "2026-09-14" selalu ditolak (dibuktikan dengan menjalankan byte persis dari file). Kini backslash tunggal; `test/raw_regex_escape_test.dart` memindai `lib` untuk pola serupa dan menguji nilai valid. Catatan uji: heredoc di Git Bash bisa menciutkan backslash, jadi bukti regex harus memakai byte dari file asli.
- Verifikasi live setelah deploy `2.8.35-regex-fix`: Night shift dikoreksi lewat form dari 19:00–19:00 menjadi 19:00–07:00 (PATCH 204), Rotasi regu disimpan ulang tanpa perubahan (PATCH 204, tetap 1 anchor aktif 2026-08-01 A,B,C), Lokasi kerja tampil A→Z, dan regu contoh `UJI` ("Contoh Regu Uji Website", Asamasam) dibuat langsung tidak aktif sehingga tidak muncul di pilihan crew.
- Urutan kolom form suhu dibakukan (disetujui pemilik 2026-09-14) lewat `20260914130000_measurement_point_canonical_order.sql`. Sebelumnya semua titik ukur Breaker dan gearbox ber-`sort_order = 0`, sehingga urutan kolom acak (Hydraulic Pump 1 dan 2 berbeda, Remark kadang di tengah). Urutan baku per kode: Motor DE → Motor NDE → Gear box → Drum East → Drum West → Chain Head → Chain Tail → Oil Level → Remark; gearbox: Low Speed → Intermediate → High Speed → Input Shaft. Titik ukur baru wajib diberi `sort_order` sesuai pola kelipatan 10 ini.
- Uji live Data master selesai (deploy `2.8.35-threshold-validation` dan sesudahnya): Regu contoh `UJI` diubah nama (PATCH 204); Peralatan dan Titik ukur disimpan ulang tanpa perubahan (PATCH 204) dan urutan baku tampil di admin; Template formulir disimpan ulang (PATCH 204, `schema_json` kini berisi `steps` 2 ronde di samping `flow` dan `validation` lama — form crew membaca `steps`, bawaan tetap 2 ronde); Pengguna crew 968 disimpan ulang tanpa perubahan (PATCH 204). Form pengguna mengirim `site_id = null` untuk crew, tetapi trigger `trg_set_app_user_site_from_team` mengisi lokasi dari regu, jadi lokasi crew tidak hilang.
- Batas suhu diperbaiki: angka tidak valid dulu tersimpan diam-diam sebagai kosong, sumber kosong menutup dialog dan membuang isian, pilihan titik ikut memuat Oil Level/Remark tanpa nama peralatan dan urutannya acak, daftar menampilkan "Warning 60-". Kini validasi berjalan di dialog (`validateThresholdInput`, diuji di `test/threshold_input_validation_test.dart`: angka, koma desimal, minimal satu batas, min ≤ max, warning < alarm termasuk bawaan 60/70, delta > 0, sumber wajib), hanya titik `numeric` aktif urut seperti form crew, dan daftar menampilkan "Feeder Breaker · Motor DE — Warning ≥60°C · Alarm ≥70°C". Contoh batas suhu tidak aktif (Feeder Breaker · Motor DE 60/70, sumber "Contoh uji website (tidak aktif)") sengaja disimpan; aplikasi hanya membaca batas yang aktif.
- Label "Code" di form Regu, Shift, Peralatan, dan Titik ukur kini "Kode"; teks Rotasi regu kini berbahasa Indonesia.
- Pencarian Gudang dulu berhenti diam-diam di 100 baris ("bolt" punya 201 hasil). Kini diminta 101 baris; bila lebih dari 100, daftar diakhiri catatan agar kata kunci dipersempit. Respons pencarian lama yang datang terlambat tidak lagi menimpa hasil pencarian terbaru.
- Rilis 2.8.36 (Android arm64 versionCode 14316 + website `2.8.36-android-release`) membawa semua perbaikan website sejak 2.8.35. APK diperiksa dengan `aapt2 dump badging`, diunggah dengan `--content-type application/vnd.android.package-archive` (tanpa itu CLI mengirim `application/zip` dan bucket menjawab 415), lalu diaktifkan lewat `20260914140000_publish_sicatat_2_8_36_master_data_fixes.sql`. APK 2.8.34 dihapus dari storage sesuai pola dua versi.
- Data PR juga berhenti di 60 baris ("bearing" punya 89 hasil) dan badge "60+ hasil" muncul walau hasil tepat 60. Kini service meminta 61 baris (`PurchaseRequisitionService.pageSize`), badge 60+ hanya bila memang lebih, dan akhir daftar memberi catatan untuk mempersempit kata kunci atau periode rilis.
- Uji langsung menu baca-saja (2.8.36): Anggaran cocok dengan DB (US$354.360 / 298.679, CPP melebihi 34.436, PORT sisa 90.117); Outstanding PM & CM cocok (CPP A/B/C 25/27/25, PORT 18/18/18, CM 33/20); pencarian Cost code "maintenance" → 2 referensi; Pusat Dokumen menjawab "Minimal 3 (tiga) orang" untuk sandblasting dengan sumber ASM-COP-160 dan ASM-COP-171 (~23 detik); unduh APK 2.8.36 lewat signed URL berhasil (file ZIP). Catatan uji: Browser pane yang tersembunyi membuat Flutter berhenti menggambar (screenshot timeout) — tampilkan pane dulu.
- Urutan "No. PR terbaru" dulu mengurutkan `no_pr` sebagai teks ("9876" di atas "25557"), sehingga PR terbaru bisa terpotong batas 60 baris. Migrasi `20260914150000_purchase_requisition_numeric_sort.sql` menambah kolom generated `no_pr_number` (deret angka pertama dari `no_pr`, NULL untuk baris seperti "No Pr") beserta indeks; service mengurutkan `no_pr_number` lalu `no_pr`. Sinkron `sync-purchase-requisitions` tetap aman karena upsert memakai kolom eksplisit. Catatan data sumber: baris teratas kini "P34361", kemungkinan No. PO yang tertulis di kolom NO PR. APK 2.8.36 masih memakai urutan teks lama sampai rilis Android berikutnya.

## Uji export, unggah file, dan penyelesaian pengingat di website — 2026-09-15

- Cara uji di Browser pane tanpa file sungguhan: pasang hook JS di halaman (simpan Blob dari `URL.createObjectURL`, cegat `HTMLAnchorElement.prototype.click` dan `navigator.share`, dan ganti `HTMLInputElement.prototype.click` untuk input `type=file` agar menerima PNG buatan kanvas). PDF dibaca dengan pdf.js yang dimuat plugin printing, lalu warna sel diambil dari hasil render kanvas. File .xlsx dibaca dengan unzip `DecompressionStream('deflate-raw')`. Pane harus terlihat; bila tersembunyi Flutter berhenti menggambar dan animasi halaman macet.
- Bug diperbaiki (`8267895`): tombol Share di pratinjau PDF sheet menghasilkan PDF 0 byte di website, dan pratinjau gagal saat digambar ulang ("ArrayBuffer is already detached"), karena `PdfPreview` memberi buffer yang sama ke pdf.js (yang memindahkannya ke worker) dan ke Share. Kini setiap `build` mendapat salinan. Panel perhatian kosong beserta spasi penutupnya dihapus sehingga sheet contoh 31/12/2034 tidak lagi punya halaman 2 kosong.
- Warna PDF sheet 19/08/2026 Night Crew A terverifikasi: <60 `#e8f5e9` (41 sel, termasuk 58), 60–69 `#ffb74d` (28 sel, termasuk tepat 60), ≥70 `#e53935` (5 sel). Kelima nilai ≥70 adalah 5757, 6060, 6161, 6262, 6363 — tampaknya salah ketik crew (angka dobel); data asli tidak diubah.
- Bug diperbaiki (`b022048`): catatan konfirmasi anomali tersalin ke semua pembacaan di ronde yang sama, sehingga CSV menampilkan catatan di 13 baris normal. Form kini hanya menyimpan catatan pada pembacaan anomali dan CSV hanya mencetaknya untuk anomali; header "Titik Ukur" menjadi "Measurement Point".
- CSV sheet contoh: 80 baris, 66 nilai suhu, semua `Temperature Alert` sesuai ambang (62 → HIGH, 71 → CRITICAL).
- MOM contoh: export Excel berisi seluruh detail dan action plan; setelah unggah gambar uji lewat "Add photo" (storage 200, baris foto 201, JPEG 14 KB) Excel memuat `xl/media/image1.jpg`.
- Pengingat contoh "Contoh Pengingat Uji Website" diselesaikan dengan bukti gambar uji: storage 200, RPC `complete_operational_reminder` 200, status `completed`, bukti `completion_proof` tercatat. Menyelesaikan pengingat tidak mengirim email (trigger hanya mencatat aktivitas).

## Email pengingat & perbaikan hasil uji live — 2026-09-14

- **Selesai 2026-09-14:** pemilik mem-publish OAuth app "SICATAT Reminder" (project `sicatat-reminder`) ke *In production* setelah menghapus logo dan mengisi home page `https://sicatat-5l5.pages.dev`, privacy policy `https://sicatat-5l5.pages.dev/privacy` (`flutter_app/web/privacy.html`; Cloudflare Pages mengalihkan `.html` ke path tanpa ekstensi), dan authorized domain `sicatat-5l5.pages.dev`. Token Gmail diperbarui lewat `node scripts/renew-gmail-refresh-token.mjs` (secret `GMAIL_*` 11:17 UTC). Uji kirim manual ke mailbox uji berstatus `sent` (Gmail provider id `1a09fa4490a3391d`). `RESEND_API_KEY` masih tidak valid, jadi fallback Resend tidak berfungsi; tidak dibutuhkan selama Gmail aktif.

- Email pengingat gagal terkirim sejak 2026-09-02; sukses terakhir 2026-08-27. `_shared/reminder_email.ts` mencoba Gmail dulu (secret `GMAIL_*` diset 2026-08-25, refresh token kemungkinan kedaluwarsa bila aplikasi OAuth masih mode Testing), lalu Resend, yang menjawab "API key is invalid". Perbaikan kredensial harus dilakukan pemilik: perbarui `GMAIL_REFRESH_TOKEN` atau set `RESEND_API_KEY` yang valid di Supabase → Edge Functions → Secrets. Jangan menaruh kunci di repo.
- Perbaikan kode (sudah deploy `send-reminder-email` v30 verify_jwt=true, `dispatch-reminder-emails` v18 verify_jwt=false): `error_message` pengiriman sekarang memuat alasan Gmail dan Resend sekaligus (termasuk kode OAuth seperti `invalid_grant`); dispatcher tidak lagi memakai `.limit(100)` tanpa urutan yang bisa melewatkan pengingat bila pengingat terbuka mendatang lebih dari 100.
- `net._http_response` untuk cron pukul 00:00 dan 22:00 UTC selalu timeout 5 detik, tetapi fungsi tetap berjalan sampai selesai (log sync gudang 2026-09-13 `completed`). Itu bukan penyebab email gagal.
- Website: daftar Pengingat tidak lagi dimuat dua kali setelah simpan/selesai/hapus (gema realtime diabaikan 1,5 detik setelah muat lokal); form suhu kembali ke atas saat pindah sisi/ronde (sebelumnya terbuka di posisi gulir lama sehingga kolom mudah tertukar); batas tanggal Buat sheet disamakan jadi 2040 dengan filter daftar. Cache suffix `2.8.35-reminder-fixes`.
- Contoh data yang sengaja disimpan: sheet suhu 31/12/2034 Crew C Pagi (submitted) dan pengingat "Contoh Pengingat Uji Website" (UJI-WEB-001, jatuh tempo 2034-12-31). Menandai pengingat selesai mewajibkan file bukti.

## Bug simpan pembacaan suhu di website — 2026-09-14

- Ditemukan saat mengisi sheet suhu secara live di website (sheet uji 31/12/2034 Crew C Pagi): "Simpan draf & lanjutkan" selalu gagal dengan "Data peralatan tidak dapat disimpan. Silakan coba lagi.", tanpa request ke Supabase dan tanpa log console.
- Penyebab: `LocalDatabase` mengirim nilai `bool` Dart (`value_boolean` Oil Level, `is_anomaly`) ke SQLite lokal. Android `sqflite` mengubahnya diam-diam menjadi 0/1, tetapi worker web `sqflite_common_ffi_web` menolak dengan `Invalid sql argument type 'bool': true`, sehingga transaksi pembacaan batal. Kemungkinan terjadi sejak website memakai `sqflite_common_ffi_web` (baseline 2.5.9); pembacaan terakhir di server tercatat 24 Agustus 2026, jadi tidak ada input crew yang terlihat hilang.
- Perbaikan: `LocalDatabase.sqliteValues` menyimpan bool sebagai 0/1 (payload antrean ke Supabase tetap boolean JSON); dijaga oleh `test/local_database_values_test.dart`. Nilai lokal baru WAJIB lewat `_sqliteValues`, jangan menyisipkan `bool` langsung.
- Sekalian: kolom angka di form suhu kini hanya menerima desimal bertanda. Sebelumnya di web huruf bisa diketik ("39Uji…") dan nilai yang tidak bisa di-parse dilewati diam-diam saat simpan.
- Cara menangkap error SQLite web yang ditelan build release: bungkus `window.MessageChannel` di halaman dan catat pesan `port1` (setiap request sqflite web dijawab lewat channel sendiri).
- Bug kedua (semua platform, bukan hanya web), ditemukan setelah perbaikan di atas: pembacaan tersimpan lokal tetapi tidak pernah sampai ke Supabase. Payload antrean `update` (jam ronde di `setRoundTime`, koreksi `unit_status`/`reading`) hanya berisi kolom yang berubah tanpa `sheet_id`/`round_id`, sehingga `getParentSyncStatus` menganggap induknya `missing`. `SyncService` lalu menandai ronde itu `conflict`, menghapusnya dari antrean, dan semua pembacaan di bawahnya ikut `conflict` dan terbuang tanpa pesan. Akibatnya setiap edit data yang sudah tersinkron (termasuk di Android) bisa hilang diam-diam. Terbukti di sheet uji: ronde + 17 pembacaan berstatus `conflict` di SQLite browser, antrean kosong, server 0 pembacaan.
- Perbaikan: `getParentSyncStatus` membaca induk dari baris lokal (via `client_uuid`) bila payload `update` tidak membawanya; dijaga `test/local_database_sync_parent_test.dart` (SQLite ffi, alur sheet → ronde tersinkron → jam ronde → pembacaan → koreksi). Pemulihan sekali jalan `_requeueDroppedChildConflictsIfNeeded` (marker `child_update_conflicts_requeued_v1`) mengantrekan ulang ronde/unit_status/pembacaan `conflict` yang sheet-nya tidak konflik sebagai upsert penuh, jadi data yang tertahan di perangkat crew terkirim saat aplikasi berikutnya dibuka. Cache suffix `2.8.35-web-sync-fix`.

## Rilis Android & website 2.8.35 — 2026-09-14

- Pemilik meminta Android diperbarui agar perbaikan audit (bagian di bawah) juga sampai ke APK. Versi `2.8.35+12315`, `AppConfig.appVersion` `2.8.35`, cache suffix web `2.8.35-android-release`.
- Hanya `arm64-v8a` (version code 14315) yang diunggah ke `app-releases` dan diaktifkan lewat `20260914120000_publish_sicatat_2_8_35_audit_fixes.sql`. APK 2.8.33 dihapus dari bucket untuk menghemat kuota; 2.8.34 disimpan sebagai cadangan.
- APK rilis ditandatangani keystore debug mesin ini (`~/.android/debug.keystore`, SHA-256 `b1d69e78…dc574584`), sama dengan semua rilis sebelumnya. Build dari mesin lain tidak bisa meng-update app di HP crew.
- Verifikasi: `flutter analyze` bersih, 21 test lulus; `main.dart.js` produksi sama dengan build lokal. APK x86_64 2.8.35 di emulator `Medium_Phone` (menimpa 2.5.2, tanda tangan cocok): sesi login pulih, beranda menampilkan "Versi 2.8.35", Outstanding PM & CM terbuka ±4 detik dengan data crew/CM, Android Back tetap di dalam app, panduan menyebut "Kuning" untuk 60–69°C. Pembuatan/hapus sheet dan unduh update di HP fisik arm64 belum diuji.
- Emulator tidak bisa resolve DNS sesudah boot (IP jalan, nama host gagal) sehingga app menampilkan "Internet connection required". Itu masalah emulator, bukan app: jalankan `adb shell settings put global private_dns_mode off` lalu buka ulang app.

## Audit keamanan RLS & header website — 2026-09-14

- Temuan: 11 tabel lama dari `schema.sql` (`module`, `form_template`, `equipment`, `measurement_point`, `threshold`, `shift`, `roster`, `roster_anchor`, `attachment`, `audit_log`, `app_version`) tidak pernah diberi RLS, sehingga anon key publik bisa membaca/mengubah/menghapus master data, memalsukan `audit_log`, dan menaikkan `app_version.min_version` untuk memblokir semua app Android.
- Perbaikan `20260914090000_lock_master_data_and_audit_rls.sql`: master data dibaca user SICATAT aktif, ditulis `admin`/`supervisor_smg` (sama dengan `RoleGuard` `/admin/*`); `app_version` tetap dibaca publik, ditulis admin; `audit_log` append-only (upsert identik diizinkan agar retry sync tidak macet, perubahan/hapus ditolak trigger); `occupied_temperature_shift_ids` menolak anonim; baca `app_release`/APK butuh user SICATAT aktif. Tabel baru WAJIB `enable row level security` + policy di migrasi yang sama.
- Signup publik Supabase dinonaktifkan 2026-09-14 (Authentication → Sign In / Providers → "Allow new users to sign up" off; `/auth/v1/settings` → `disable_signup: true`). `create-crew-user` tetap bisa membuat akun karena memakai admin API. Tetap anggap `authenticated` belum tentu akun SICATAT: policy dan edge function harus mengecek `current_sicatat_user_id()` (`ask-technical-documents` sudah).
- Website: `flutter_app/web/_headers` menambah HSTS, anti-clickjacking (`X-Frame-Options`/`frame-ancestors`), dan Permissions-Policy. CSP `script-src` belum dipasang karena CanvasKit dimuat dari gstatic.
- `audit_log` juga bisa dibaca oleh penulisnya sendiri (`20260914100000_audit_log_read_own_rows.sql`): upsert sync (`sync_service.dart`, on `id`) menerapkan policy SELECT ke baris baru, jadi audit yang tiba sebelum sheet-nya sempat ditolak 42501.
- Bug hapus sheet sejak `20260820_verified_sheet_lock.sql`: trigger `prevent_verified_sheet_mutation` (BEFORE UPDATE OR DELETE) selalu `return new`; untuk DELETE nilainya NULL sehingga Postgres membatalkan penghapusan diam-diam (0 baris, tanpa error). Tombol Delete sheet menghapus salinan lokal, sheet muncul lagi saat sync dan tetap mengunci slot module+tanggal+shift. Diperbaiki di `20260914110000_fix_sheet_delete_trigger.sql`; sheet verified tetap terkunci. Trigger BEFORE DELETE baru WAJIB `return old` untuk DELETE. Tombol Delete sheet (`sheet_summary_screen.dart`) kini memakai `.delete().eq(...).select('id')` dan menampilkan error bila server tidak menghapus apa pun, sehingga salinan lokal tidak ikut terhapus.
- Perbaikan UX hasil audit (website saja, versi tetap 2.8.34, cache suffix `2.8.34-audit-fixes`): pesan kosong di Batas suhu; label "Hari ini di perangkat ini" untuk penghitung Draf/Terkirim; Outstanding PM & CM menampilkan snapshot dulu lalu sync di belakang (sebelumnya menunggu dua sync ±10 detik); `/incomplete` memakai 3 query total, bukan 2 query per sheet; panduan di app menyebut "Kuning" untuk 60–69°C sesuai warna di layar dan `PANDUAN-CREW-SICATAT.md`.

## Rilis foto MOM & ekspor Excel 2.7.2 — 2026-09-07

- Website produksi 2.7.2: https://sicatat-5l5.pages.dev/?versi=2-7-2-mom-foto#/meeting-minutes . Pratinjau deployment: https://65dd237f.sicatat-5l5.pages.dev/?versi=2-7-2-mom-foto#/meeting-minutes .
- Setiap pembahasan/tindak lanjut Notulen Rapat kini dapat memiliki beberapa foto opsional JPG/JPEG/PNG maksimal 8 MB per foto. Pengguna perlu menyimpan draf terlebih dahulu agar tindakan memperoleh identitas, lalu dapat menambah atau menghapus foto. Foto disimpan privat di bucket `meeting-minute-photos` dengan RLS yang mengikuti akses notulen.
- Penyimpanan tindakan tidak lagi menghapus lalu membuat ulang seluruh baris saat MOM diedit, sehingga foto tindakan tetap ada. Excel juga memuat foto pembahasan di bawah tindakan terkait dan menyesuaikan tinggi baris pembahasan panjang. Format metadata dan tabel meniru `260130_MoM_STI Muara Port Electrical Inspection.docx`.
- Server: migrasi `20260907072000_meeting_minute_action_photos.sql` dan rilis Android `20260907073000_publish_sicatat_2_7_2_mom_photos.sql` telah diterapkan di produksi. APK 2.7.2+10272 tiga ABI dibangun, diunggah ke `app-releases`, dan diaktifkan (arm64 code 12272, armeabi-v7a code 11272, x86_64 code 14272). `flutter analyze` bersih dan seluruh test Flutter lulus. Website/preview HTTP 200; pemasangan fisik Android serta demo browser terautentikasi belum diuji.

## Rilis MOM draf & Excel 2.7.1 — 2026-09-07

- Website produksi 2.7.1: https://sicatat-5l5.pages.dev/?versi=2-7-1-mom#/meeting-minutes . Pratinjau deployment: https://5fed7bbe.sicatat-5l5.pages.dev/?versi=2-7-1-mom#/meeting-minutes .
- Notulen Rapat sekarang berfungsi: buat atau edit MOM, simpan draf tanpa mengisi seluruh kolom, kemudian selesaikan setelah judul, tanggal, lokasi, pencatat, dan minimal satu pembahasan tersedia. Setiap tindak lanjut memiliki tanggal item, pembahasan, PIC, serta tenggat.
- Format ekspor `.xlsx` mengikuti contoh `260130_MoM_STI Muara Port Electrical Inspection.docx`: judul, tanggal/waktu, lokasi, peserta, berhalangan hadir, pencatat, distribusi, agenda baru, pengaju, catatan, lalu tabel `Item – Pembahasan – Penanggung Jawab – Tenggat`. Berkas dibuat di aplikasi, tanpa API AI atau layanan berbayar.
- Server: migrasi `20260907070000_meeting_minutes_drafts.sql` telah diterapkan (tabel MOM, tindakan, draf/selesai, RLS pembuat dan pengelola global); cek `supabase db push --dry-run` menyatakan remote up to date.
- APK 2.7.1+10271 tiga ABI dibangun dan diverifikasi (`arm64-v8a` code 12271, `armeabi-v7a` 11271, `x86_64` 14271), diunggah ke `app-releases`, kemudian tiga record aktif dipublikasikan lewat `20260907071000_publish_sicatat_2_7_1_mom_excel.sql`. Validasi query release mengonfirmasi tiga ABI aktif. `flutter analyze` bersih dan 15 Flutter tests lulus. Pemasangan fisik Android belum diuji pada perangkat.

## Rilis tampilan Anggaran & MOM 2.7.0 — 2026-09-07

- Website produksi 2.7.0: https://sicatat-5l5.pages.dev/?versi=2-7-0#/dashboard . Dua section awal tersedia pada kelompok Operasional dan kartu Beranda: `Anggaran Operasional` (`#/budget`) dan `Notulen Rapat` (`#/meeting-minutes`).
- Anggaran baru berupa tampilan read-only: kartu Anggaran, Aktual, dan Sisa Anggaran serta status sumber spreadsheet; belum ada spreadsheet atau nilai nyata yang disambungkan. MOM menunjukkan status Draf/Selesai dan alur kerja draf, tetapi tombol Buat notulen sengaja nonaktif sampai contoh format pengguna diterima.
- APK 2.7.0+10270 tiga ABI dibangun dan diverifikasi (`arm64-v8a` code 12270, `armeabi-v7a` 11270, `x86_64` code 14270), diunggah ke `app-releases`, lalu tiga record aktif dipublikasikan dengan migrasi `20260907060000_publish_sicatat_2_7_0_operational_sections.sql`. Validasi: `flutter analyze` bersih dan 14 Flutter tests lulus. Pemasangan fisik Android serta visual browser otomatis belum diuji.

## Rilis navigasi setara 2.6.9 — 2026-09-07

- Website produksi 2.6.9: https://sicatat-5l5.pages.dev/?versi=2-6-9#/dashboard . Desktop kini memakai sidebar yang sama dengan Android: `Beranda`, `Operasional`, `Referensi`, dan `Profil`; klik Operasional/Referensi membuka submenu identik yang mengikuti hak akses akun. Preview Pages: https://d05fe1d7.sicatat-5l5.pages.dev.
- APK 2.6.9+10269 dibangun serta diperiksa untuk tiga ABI (`arm64-v8a` code 12269, `armeabi-v7a` code 11269, `x86_64` code 14269), diunggah ke `app-releases`, kemudian tiga record aktif `app_release` dipublikasikan melalui migrasi `20260907050000_publish_sicatat_2_6_9_navigation_parity.sql`.
- Validasi: `flutter analyze` bersih, 12 Flutter tests lulus, build web dan APK release berhasil. Cloudflare Pages dan endpoint produksi merespons HTTP 200. Sesi otomasi browser lokal gagal diinisialisasi, dan pemasangan fisik Android belum diuji; jangan mengklaim verifikasi visual/perangkat fisik sampai diuji ulang.

## Rilis Pusat Dokumen rapi 2.6.8 — 2026-09-07

- Website produksi rilis 2.6.8: https://sicatat-5l5.pages.dev/?versi=2-6-8#/documents . Kartu Jawaban AI memisahkan bagian `Dalam…`/`Untuk…` menjadi langkah visual, membatasi excerpt sumber menjadi empat baris, dan memiliki padding bawah 120px + safe area agar tidak tertutup navigasi bawah.
- Worker `sicatat-document-ai` versi `7c5f0126-abd1-464e-a2ae-a715ff73d586` kini menginstruksikan AI untuk menjawab langsung hanya bagian yang ditanyakan, maksimal lima langkah atau 700 karakter. Jangan menambahkan mode/prosedur yang tidak diminta.
- APK 2.6.8+10268 tiga ABI dibangun dan diverifikasi (arm64 code 12268, armeabi code 11268, x86_64 code 14268), diunggah ke `app-releases`, lalu tiga record aktif 2.6.8 telah diverifikasi di `app_release`. Validasi: `flutter analyze` bersih, 12 Flutter tests lulus, 5 Worker tests lulus, build web dan APK release sukses. Cloudflare Pages production selesai (preview: https://eead6112.sicatat-5l5.pages.dev). Pemasangan fisik Android belum diuji.

## Perbaikan kutipan AI dokumen — 2026-09-07

- Worker `sicatat-document-ai` versi `e2ed523b-0ed9-4a92-931a-c40a7a4aa321` menambahkan fallback kutipan sumber. Jika model tidak menghasilkan sitasi JSON yang valid tetapi isi dokumen yang dipilih memuat istilah pertanyaan, Worker menampilkan cuplikan prosedur asli (maks. 900 karakter) beserta sumbernya. Ia tidak membuat jawaban baru atau menggunakan sumber di luar folder.
- Perbaikan ini menutup kasus VSD: file berhasil diperiksa tetapi jawaban sebelumnya ditolak seluruhnya karena sitasi model tidak valid. Uji Worker 5/5 lulus, termasuk fallback `Prosedur Mode Auto`. Backend berlaku langsung pada website dan Android 2.6.7; tidak ada APK/web bundle baru. Belum ada demo terautentikasi pascadeploy, jadi jangan mengklaim hasil VSD telah terlihat sampai pengguna mengujinya.
- Pembaruan berikutnya memprioritaskan SOP operasional untuk pertanyaan berintensi operasi seperti `Mode Auto`, `manual`, `start/stop`, dan `prosedur`. Duplikat PDF disaring bila Word tersedia, sehingga `ASM-COP-158 Operasional VSD.docx` dipilih sebelum `ASM-COP-157 Penggantian Power Block VSD Siemens.docx` untuk pertanyaan Mode Auto VSD. Fungsi Supabase dan Worker versi `844cf954-063e-44c5-8b0a-56770cacb241` telah dideploy; uji pemilih dan Worker lulus. Tetap belum ada demo terautentikasi pascadeploy.
- Hint retrieval keselamatan menautkan pertanyaan `body harness` ke `ASM-COP-150 Pergantian Roller & Frame Roller`, karena istilah body harness berada di isi SOP dan tidak muncul pada judul file. Uji pemilih `kapan body harness wajib digunakan?` lulus dan fungsi Supabase telah dideploy. Pengujian UI browser terautentikasi dimulai, tetapi sesi otomatis ter-reset sebelum respons akhir dapat dibaca; jangan mengklaim hasil visual sampai diuji kembali.

## Rilis Gudang otomatis 2.6.7 — 2026-09-07

- Website produksi rilis 2.6.7: https://sicatat-5l5.pages.dev/?versi=2-6-7#/warehouse . Gudang menampilkan status `Sinkron otomatis aktif · setiap hari 06.00 WITA`; tombol `Sinkronkan sekarang` tetap cadangan bagi pengelola Gudang.
- Edge Function `sync-warehouse-data` menjalankan pemeriksaan yang sama untuk manual maupun terjadwal. Ia membandingkan SHA-256 gabungan lima CSV Google Sheets; data ditulis hanya bila sidik sumber berubah. Pembaruan manual masih memverifikasi sesi dan peran admin/supervisor SMG/warehouseman. Permintaan terjadwal hanya lolos dengan secret server `WAREHOUSE_SYNC_CRON_SECRET`—jangan pernah menaruhnya di Git, Flutter, atau APK.
- Migrasi `20260907020000_warehouse_automatic_daily_sync.sql` telah diterapkan. Job Supabase Cron aktif: `sicatat-sync-warehouse-daily`, `0 22 * * *` UTC = 06.00 WITA. Nilai secret tersimpan di Supabase Vault sebagai `sicatat_warehouse_sync_cron_secret` dan Edge Function diterapkan dengan `--no-verify-jwt` karena autentikasi dilakukan di dalam fungsi untuk membedakan cron aman vs sesi pengguna.
- Verifikasi produksi backend: pemanggilan terjadwal pertama sukses memperbarui 7.719 stok, 2.161 penerimaan, dan 155 alat. Pemanggilan kedua sukses dengan `changed: false` serta nol penulisan snapshot saat sumber tidak berubah. Jangan mengklaim jadwal telah berjalan sendiri sebelum eksekusi 06.00 WITA berikutnya tercatat.
- APK 2.6.7+10267 tiga ABI sudah dibangun dan diverifikasi (`arm64-v8a` code 12267, `armeabi-v7a` 11267, `x86_64` 14267), diunggah ke `app-releases`, lalu ketiga record aktif 2.6.7 diverifikasi di `app_release`. Website dan APK berasal dari source revision yang sama. Pemasangan fisik Android belum diuji.
- Validasi rilis: `flutter analyze` bersih, seluruh 12 Flutter tests lulus, build web release dan tiga APK release sukses. Cloudflare Pages production selesai pada `main` (preview: https://2f8f3aa3.sicatat-5l5.pages.dev).

## Rilis navigasi 2.6.6 — 2026-09-07

- Website produksi rilis 2.6.6: https://sicatat-5l5.pages.dev/?versi=2-6-6#/dashboard . Tampilan langsung tervalidasi: copyright menjadi `© 2026 • Versi 2.6.6` tanpa WIL.
- Navigasi bawah web/mobile berubah dari menu modul individual menjadi `Beranda`, `Operasional`, `Referensi`, `Profil`. Operasional membuka Suhu/Pengingat sesuai hak akses; Referensi membuka Gudang/Pusat Dokumen. Gunakan `GroupedBottomNavigation` untuk halaman baru agar konsisten.
- APK 2.6.6+10266 tiga ABI sudah dibangun, diunggah ke bucket `app-releases`, dan tiga record aktif 2.6.6 telah diverifikasi di `app_release`: arm64 code 12266, armeabi code 11266, x86_64 code 14266. Update mobile kini dapat terdeteksi oleh aplikasi. Belum diuji pemasangan fisik pada perangkat Android.
- Validasi rilis: `flutter analyze` bersih, 12 Flutter tests lulus (termasuk grouped bottom navigation), build web release dan tiga APK release sukses. Deploy Cloudflare Pages production `main` selesai (preview build URL https://21811392.sicatat-5l5.pages.dev).

## Cloudflare AI integration — 2026-09-07

- Active AI provider is Cloudflare Workers AI via `cloudflare/document-ai/`, not the blocked Gemini project. Supabase function `ask-technical-documents` forwards only server-selected files from the approved Drive root. Worker URL: https://sicatat-document-ai.sicatat.workers.dev . Secrets are configured on both servers; never print them.
- REAL authenticated website demo PASSED on `https://sicatat-5l5.pages.dev/#/documents`: question `berapa minimal orang untuk pekerjaan sandblasting` returned `Minimal 3 (tiga) orang untuk melakukan pekerjaan tersebut`, with source `ASM-COP-160 Sandblasting.docx` and matching excerpt. Three readable files were scanned. No point 3.1 was invented.
- Fixed public Drive listing truncation (standard page first 150 entries) using embedded listing, raised old 240-file crawl ceiling to 3000, excluded common question words from filename matching, added Word reading. The SOP PDF produced empty pages, but its Word counterpart is readable.
- No billing upgrade performed. Limits and unsupported scanned PDFs/drawings remain; see `cloudflare/document-ai/README.md`. Full-content folder indexing and 10-user load testing are NOT completed.
- Backend-only change: shared endpoint now serves both web and existing Android builds; no new Flutter bundle/APK release. Web stays 2.6.5, last confirmed Android publication stays 2.6.4. Physical Android test not performed.
- Verification: Flutter analyze clean, all 10 Flutter tests passed, 4 Worker tests passed, Supabase diagnostics/listing/selection tests passed. Worker and Supabase function deployed. Worker version `eb4caa23-86c0-437e-aa04-ade918abed62`.

## AI live diagnostic — 2026-09-05

- Canonical source remains worktree `42e3`; do not release stale `284f`.
- Deployed backend `ask-technical-documents` now safely classifies Google errors without exposing raw provider responses or secrets. Model candidates are bounded and checked against the model list; Flash-Lite 3.1/3.5 precede legacy 2.5 candidates.
- REAL signed-in website demo of sandblasting question FAILED: legacy 2.5 candidates returned 404; Flash-Lite request returned 403 with Google's project-denied message, displayed as `PROJECT_ACCESS_DENIED`. AI is NOT verified working. Owner must resolve Google project access; do not claim billing or retries fix it. Billing was not enabled.
- Backend applies to both web and Android callers. No Flutter/UI release this diagnostic. Web remains 2.6.5; last confirmed published Android remains 2.6.4 (2.6.5 APK upload had failed). Do not claim mobile 2.6.5 is available.
- Backend regression test: `node supabase/functions/ask-technical-documents/diagnostics.test.mjs` (Node 24).

This is the active handoff file for Codex. Follow it before editing.

## Current continuation baseline — 2026-09-13

This section overrides older release references in this handoff.

- Current shared source is `origin/master`; current app version is
  `2.8.35+12315` / `2.8.35` (Android + website, 2026-09-14). Verify `flutter_app/pubspec.yaml`,
  `AppConfig.appVersion`, `git log -1`, and `git status` before editing —
  this baseline moves roughly daily, don't trust this number without
  re-checking.
- All known local checkouts (`D:\Arutmin\Project\sicatat` and the
  `C:\Users\ASUS\.codex\worktrees\{9261,284f,42e3}\sicatat` worktrees) were
  confirmed fast-forwarded to this exact commit on 2026-09-13, with no
  uncommitted feature work left stashed on any of them (all reviewed and
  dropped). Don't assume any one worktree is "the" canonical source over
  another — `origin/master` on GitHub is canonical; every local checkout
  should just match it.
- The owner currently wants **website-first** delivery. Do not build, upload,
  or publish Android unless the owner explicitly asks for Android. Keep one
  Flutter source and do not intentionally diverge product behavior.
- Read `docs/PROJECT_MEMORY.md` for current data integrations, typography
  rules, Supabase free-storage constraints, and the required commit/push flow.
- Every completed change must be committed and pushed to `origin/master` after
  appropriate verification, so another computer can resume from the same
  state.

## Current product and non-negotiable rules

- Active app: `flutter_app/` (Flutter/Dart). The JavaScript/Capacitor files in the repository root are historical only.
- Kesetaraan platform wajib: setiap pembaruan fitur, menu, label, dan status versi harus tersedia pada website dan Android dari revisi sumber yang sama. Tata letak dapat responsif (sidebar di desktop, navigasi bawah di ponsel), tetapi hierarki menu dan tujuan navigasinya harus setara.
- Backend: Supabase Auth + PostgreSQL. Keep NIK/PIN login and session restore.
- The product is **online-only**. SQLite in `flutter_app/lib/data/local/` is cache/sync queue only; do not turn it into an offline-first product.
- Never put a Supabase service-role key in Flutter/Dart, APK, docs, or Git. Only the server-side edge function may use it.
- Preserve the duplicate-sheet rule: one `module + date + shift` sheet globally, enforced in Flutter and the Supabase trigger.
- Keep Android Back navigation inside the app; use `AppBackScope` / `AppBackButton` for new top-level pages.
- Temperature safety: 60–69°C is warning/orange, >=70°C critical/red. Values outside -50..250°C require explicit anomaly confirmation and note.
- Sheet revision has two distinct, non-conflicting mechanisms — confirmed by reading `flutter_app/lib/data/local/local_database.dart` on 2026-09-13:
  1. **Creator self-service reopen** (`reopenSheetForCorrection`, ~line 1199): the sheet's own creator can reopen their own *submitted-but-not-yet-verified* sheet back to draft, correct it, and resubmit. Blocked once the sheet is verified ("A verified sheet cannot be reopened").
  2. **Reviewer verify/return** (`verifySheet` ~line 1314, `returnSheetForCorrection` ~line 1369): a reviewer (foreman/supervisor/admin) marks a submitted sheet `verified` (locks it permanently, auditable) or `returned` (sends it back with a required reason, distinct from the creator's own self-reopen). Only `draft` or `returned` sheets can have their readings changed.
  Both must keep working; don't collapse this into a single "verify/return" description or a single "creator reopen" description — each covers a different actor and a different point in the lifecycle.

## Sumber rilis tunggal

- `origin/master` di GitHub (`https://github.com/mrawildhan/sicatat-`) adalah satu-satunya sumber kanonis. Jangan menyebut worktree/checkout tertentu sebagai "canonical" secara permanen di file ini — nama worktree yang dulu dianggap paling maju (mis. `42e3`) bisa saja jadi paling tertinggal beberapa hari kemudian (persis yang terjadi 2026-09-07 → 2026-09-13, lihat riwayat rilis di atas).
- Sebelum mengubah, membangun, atau menerbitkan apa pun: jalankan `git fetch origin --prune`, lalu `git log HEAD..origin/master --oneline | wc -l` di checkout yang sedang dipakai. Kalau hasilnya bukan 0, checkout itu tertinggal — jangan build/publish dari sana. Tarik dulu (`git stash push -u` bila ada perubahan tracked, lalu `git merge --ff-only origin/master` atau `git pull --ff-only origin master`).
- Jangan pernah menerbitkan website atau Android dari commit yang lebih lama daripada `origin/master`. Setiap perubahan fungsional harus diverifikasi dengan `flutter analyze` dan `flutter test`, di-commit, lalu di-push ke `origin/master` sebelum diklaim selesai.

## Fast start

```powershell
Set-Location D:\Arutmin\Project\sicatat\flutter_app
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

Android builds are rare under the current website-first policy (see "Current continuation baseline") — don't assume a specific APK artifact/version is sitting in `flutter_app/build/app/outputs/flutter-apk/` without checking; build output is intentionally ignored by Git, so nothing there reflects the checked-in source version.

## Source map

| Area | Primary location |
|---|---|
| App routes and navigation | `flutter_app/lib/app.dart`, `flutter_app/lib/core/widgets/app_navigation.dart` |
| Supabase config | `flutter_app/lib/core/config/app_config.dart` |
| Authentication/current user | `flutter_app/lib/features/auth/` |
| Sheet creation/list/summary | `flutter_app/lib/features/sheets/presentation/` |
| Temperature entry + thresholds | `flutter_app/lib/features/temperature/presentation/temperature_form_screen.dart`, `flutter_app/lib/data/models/master_data_models.dart` |
| Local database/sync queue | `flutter_app/lib/data/local/local_database.dart`, `flutter_app/lib/data/sync/sync_service.dart` |
| Supabase repository | `flutter_app/lib/data/repositories/supabase_sicatat_repository.dart` |
| PDF/CSV exports | `flutter_app/lib/features/reports/presentation/`, `flutter_app/lib/data/reports/report_export_service.dart` |
| Admin user screen | `flutter_app/lib/features/users/presentation/user_management_screen.dart` |
| Document Center / AI Q&A / cost code & equipment reference | `flutter_app/lib/features/documents/presentation/`, `supabase/functions/ask-technical-documents/`, `cloudflare/document-ai/` |
| Warehouse | `flutter_app/lib/features/warehouse/presentation/warehouse_screen.dart`, `supabase/functions/sync-warehouse-data/` |
| Operational budget, purchase requisitions, Meeting Minutes (MOM), maintenance sections | `flutter_app/lib/features/operations/presentation/`, `supabase/functions/sync-operational-budget/`, `supabase/functions/sync-purchase-requisitions/`, `supabase/functions/sync-preventive-maintenance/`, `supabase/functions/sync-corrective-maintenance/` |
| Reminders | `flutter_app/lib/features/reminders/presentation/reminder_screen.dart` |
| Database schema/migrations | `supabase/schema.sql`, `supabase/migrations/` |
| Admin account creation edge function | `supabase/functions/create-crew-user/index.ts` |
| Full product/recovery specification | `docs/PRD-SICATAT-v0.5.md` |
| Day-to-day handoff notes (more current than this table) | `docs/PROJECT_MEMORY.md` |

## Current UX behavior

- Temperature flow has four default steps: Breaker R1, Sizer R1, Breaker R2, Sizer R2.
- Round time is set automatically at the first saved entry; inspection date is selected only when a sheet is created.
- Incomplete fields can be skipped while drafting. The Sheet Summary card for an incomplete group is red and opens the first missing entry. Complete cards open their per-entry detail in a bottom sheet.
- The default Sheet Summary is deliberately compact: four cards, contributor count, export icon, and sticky Submit. Audit/review/override/delete actions sit in `More options & history`.
- Add User uses a dedicated create-mode state; it calls the `create-crew-user` edge function. If saving a new user fails after deployment, verify that function is deployed and that the signed-in caller is an active `admin`.
- PDF displays 60–69°C orange and >=70°C red. CSV cannot encode colors, so it contains a `Temperature Alert` column with `HIGH 60-69°C` or `CRITICAL >=70°C`.

## Supabase deployment checklist

1. Apply `supabase/schema.sql` to a new project, then **every** migration in `supabase/migrations/` in chronological order — there are 90+ as of 2026-09-13, don't assume the two named below are the only ones required.
2. Spot-check these two are present (they enforce the duplicate-sheet and verified-sheet-lock rules from "Current product and non-negotiable rules" above): `20260819_prevent_duplicate_shift_sheets.sql` and `20260820_verified_sheet_lock.sql`.
3. Deploy the user-creation function when needed:

```powershell
supabase functions deploy create-crew-user
```

4. Ensure the caller has an active `app_user` row with `role = 'admin'`.
5. Audit RLS by logging in as crew, foreman, supervisor, and admin before a production rollout.

## Required verification before handoff

Run `flutter analyze` and `flutter test`. For meaningful functional changes, test on Android:

1. Login as crew/admin; use Android Back from sheets, forms, admin, and reports.
2. Create a dated Shift Pagi or Malam sheet; make draft input, reopen it, and fill Round 2.
3. Leave entries missing; confirm red summary card returns to the missing input.
4. Check duplicate date+shift+module creation is rejected from a second account.
5. Submit as the creator; reopen it yourself for correction while it's still unverified and resubmit (creator self-service path); separately, as a reviewer (foreman/supervisor/admin) either verify a submitted sheet (should lock it — reopening afterward must fail) or return it with a reason (distinct from the creator's own reopen).
6. Export values 59, 60, 69, 70°C; inspect PDF colours and CSV `Temperature Alert` values.
7. As admin, open User Management, tap Add User, create a test account, and confirm its login.

## Current limits / next safe work

- New equipment and measurement points are master-data driven, but a wholly new temperature section/module still needs a generic form-builder extension.
- iOS distribution needs macOS, Xcode, an Apple Developer account, signing, and TestFlight; it cannot be built/released from Windows alone.
- Reminders remain admin-only and are not yet a guaranteed push/scheduler workflow.
- Do not commit `tmp/`, `build/`, `.dart_tool/`, APK files, Supabase local state, or machine-local Codex settings.
