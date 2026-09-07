# SICATAT — Codex Handoff

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

## Current product and non-negotiable rules

- Active app: `flutter_app/` (Flutter/Dart). The JavaScript/Capacitor files in the repository root are historical only.
- Kesetaraan platform wajib: setiap pembaruan fitur, menu, label, dan status versi harus tersedia pada website dan Android dari revisi sumber yang sama. Tata letak dapat responsif (sidebar di desktop, navigasi bawah di ponsel), tetapi hierarki menu dan tujuan navigasinya harus setara.
- Backend: Supabase Auth + PostgreSQL. Keep NIK/PIN login and session restore.
- The product is **online-only**. SQLite in `flutter_app/lib/data/local/` is cache/sync queue only; do not turn it into an offline-first product.
- Never put a Supabase service-role key in Flutter/Dart, APK, docs, or Git. Only the server-side edge function may use it.
- Preserve the duplicate-sheet rule: one `module + date + shift` sheet globally, enforced in Flutter and the Supabase trigger.
- Keep Android Back navigation inside the app; use `AppBackScope` / `AppBackButton` for new top-level pages.
- Temperature safety: 60–69°C is warning/orange, >=70°C critical/red. Values outside -50..250°C require explicit anomaly confirmation and note.
- Verified sheets must remain locked; use the Verify/Return/revision workflow and audit trail.

## Source rilis tunggal — wajib untuk setiap chat

- Sumber rilis yang telah diverifikasi adalah `origin/master`, dengan versi `2.6.5+10265` di `flutter_app/pubspec.yaml` dan `2.6.5` di `AppConfig.appVersion` (dirilis 2026-09-04). Worktree `C:\Users\ASUS\.codex\worktrees\42e3\sicatat` adalah checkout yang digunakan untuk rilis ini.
- Sebelum mengubah, membangun, atau menerbitkan apa pun: baca kedua penanda versi tersebut, periksa `git status`, dan bandingkan dengan versi aplikasi Android serta website yang sedang rilis. Pertahankan seluruh perubahan pengguna yang sudah ada.
- Worktree `C:\Users\ASUS\.codex\worktrees\284f\sicatat` dan salinan utama `D:\Arutmin\Project\sicatat` pernah bertanda `2.5.4+10254`; keduanya **dilarang** dipakai untuk build atau deploy sampai telah ditarik dan diverifikasi sama dengan `origin/master`.
- Bila sebuah chat dibuka pada source lama, hentikan proses rilis. Tarik `origin/master` dan verifikasi versi rilis terlebih dahulu; jangan menghapus, menggantikan, atau membangun ulang fitur berdasarkan source lama.
- Jangan pernah menerbitkan website atau Android dari versi yang lebih rendah daripada baseline rilis. Setiap perubahan fungsional harus dikerjakan dari source rilis tunggal, diverifikasi dengan `flutter analyze` dan `flutter test`, lalu diperbarui di website dan Android sesuai prosedur rilis.

## Fast start

```powershell
Set-Location D:\Arutmin\Project\sicatat\flutter_app
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

For this workspace, the latest Android artifact is `flutter_app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (v2.1.2+212). Build output is intentionally ignored by Git.

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
| Database schema/migrations | `supabase/schema.sql`, `supabase/migrations/` |
| Admin account creation edge function | `supabase/functions/create-crew-user/index.ts` |
| Full product/recovery specification | `docs/PRD-SICATAT-v0.5.md` |

## Current UX behavior

- Temperature flow has four default steps: Breaker R1, Sizer R1, Breaker R2, Sizer R2.
- Round time is set automatically at the first saved entry; inspection date is selected only when a sheet is created.
- Incomplete fields can be skipped while drafting. The Sheet Summary card for an incomplete group is red and opens the first missing entry. Complete cards open their per-entry detail in a bottom sheet.
- The default Sheet Summary is deliberately compact: four cards, contributor count, export icon, and sticky Submit. Audit/review/override/delete actions sit in `More options & history`.
- Add User uses a dedicated create-mode state; it calls the `create-crew-user` edge function. If saving a new user fails after deployment, verify that function is deployed and that the signed-in caller is an active `admin`.
- PDF displays 60–69°C orange and >=70°C red. CSV cannot encode colors, so it contains a `Temperature Alert` column with `HIGH 60-69°C` or `CRITICAL >=70°C`.

## Supabase deployment checklist

1. Apply `supabase/schema.sql` to a new project, then every migration in chronological order.
2. Confirm these migrations are present in production: `20260819_prevent_duplicate_shift_sheets.sql` and `20260820_verified_sheet_lock.sql`.
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
5. Submit, reopen before verification, then verify/return as a reviewer.
6. Export values 59, 60, 69, 70°C; inspect PDF colours and CSV `Temperature Alert` values.
7. As admin, open User Management, tap Add User, create a test account, and confirm its login.

## Current limits / next safe work

- New equipment and measurement points are master-data driven, but a wholly new temperature section/module still needs a generic form-builder extension.
- iOS distribution needs macOS, Xcode, an Apple Developer account, signing, and TestFlight; it cannot be built/released from Windows alone.
- Reminders remain admin-only and are not yet a guaranteed push/scheduler workflow.
- Do not commit `tmp/`, `build/`, `.dart_tool/`, APK files, Supabase local state, or machine-local Codex settings.
