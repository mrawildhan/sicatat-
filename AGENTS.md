# SICATAT — Codex Handoff

**How to read this file:** sections below dated `— 2026-MM-DD` are a historical changelog, accurate only as of that date — don't treat an old dated entry (e.g. "Canonical source remains worktree `42e3`") as still true just because it isn't explicitly retracted. Only "Current continuation baseline" and "Current product and non-negotiable rules" are meant to describe *today's* state, and even those can drift between edits — re-verify against `git log -1` and `flutter_app/pubspec.yaml` before trusting a version/commit claim here.

## Rilis Android 2.8.42 — 2026-09-25

- Pemilik meminta update Android. Versi `2.8.42+12322`, `AppConfig.appVersion` `2.8.42`, cache suffix web `2.8.42-android-release`. Hanya `arm64-v8a` (version code 14322, 28.675.868 byte) diunggah ke `app-releases` dan diaktifkan lewat `20260925110000_publish_sicatat_2_8_42_gudang_upload.sql`; `aapt2` menunjukkan 2.8.42/14322 dan sertifikat SHA-256 `b1d69e78…dc574584` (keystore debug mesin ini, sama dengan rilis sebelumnya).
- CLI Supabase 2.117 menolak `storage cp` dengan path sumber absolut Windows ("LegacyStorageUnsupportedOperationError … copy between local directories"). Jalankan dari folder APK dengan nama file relatif, plus `--experimental --linked --content-type application/vnd.android.package-archive --workdir <repo>`.
- APK 2.8.40 dan 2.8.41 masih di bucket; 2.8.40 belum dihapus (hapus data produksi hanya setelah pemilik setuju).
- Isi rilis: Gudang di Operasional (Cari barang, Barang dipesan + filter pemesan, Pengambilan, Peminjaman Alat), kartu "Terakhir diperbarui", Anggaran setahun penuh, Cost Code lengkap, MOM beberapa rencana per temuan, Unggah data dan Data master yang dirapikan. Belum diuji di HP fisik.

## Unggah data: file Excel langsung ke SICATAT, Anggaran setahun penuh — 2026-09-25

- Pemilik (satu-satunya yang meng-update spreadsheet) memilih **upload langsung** daripada OneDrive (akun kantor arutmin.com biasanya melarang link "siapa saja", Graph API butuh admin IT) dan daripada link publik Google Drive (data PR/anggaran/PO terbuka untuk siapa pun yang punya link).
- Admin: Data master → **Unggah data** (`/admin/data-upload`, `features/admin/presentation/data_upload_screen.dart`). Bagian (part): `pr`, `pm_cpp`, `pm_port`, `cm`, `budget`, `actual_cpp`, `actual_port`, `gudang_inventory`, `gudang_list_order`, `gudang_outstanding_po`.
- Alur: app mengunggah ke Storage privat `data-source-uploads/incoming/<part>` (RLS admin), lalu memanggil fungsi sync-nya dengan `{"upload": {"part", "file_name", "size"}}` (Gudang juga `source`). Fungsi mengimpor bersama part lain; **hanya bila berhasil** file dipindah ke `current/<part>` dan dicatat di `data_source_upload`; bila gagal `incoming` dihapus dan data lama tetap. Selama `current/<part>` ada, link Drive part itu diabaikan; "Kembali ke Google Drive" menghapusnya. Helper bersama: `supabase/functions/_shared/source_files.ts`; migrasi `20260925100000_data_source_uploads.sql`. Kartu "Terakhir diperbarui" memakai waktu unggah untuk part yang diunggah.
- Yang disimpan hanya file terbaru per part (~8 MB di Storage 1 GB); database tetap snapshot yang ditimpa (spreadsheet ±22 MB dari 46 MB DB pada 2026-09-25).
- Anggaran kini **Jan–Des 2026** (budget setahun penuh, pilihan pemilik; aktual mengisi sendiri saat `cpp asm`/`port asm` di-update). Migrasi `20260925090000` melebarkan check `period_start` sampai Desember; `importVersion` di sidik jari memaksa impor ulang.
- Temuan: ekspor CSV Google (gviz) mengosongkan sel rumus `=300000000/D5` (CPP 00220 CONTRACTOR-GENERAL, Jun 2026), jadi budget CPP dari Drive kurang US$18.182. File Excel yang diunggah membaca nilai tersimpan Excel dengan benar (total budget US$685.952). Budget sudah diunggah sebagai sumber pada 2026-09-25; Data PR diuji lalu dikembalikan ke Drive.

## Kartu pembaruan: dua baris, tanggal "Date modified" Drive — 2026-09-24

- Permintaan pemilik: kartu pembaruan di Data PR, PM & CM, Anggaran, Cari barang, Barang dipesan, dan tab List Order cukup dua baris: judul + "Terakhir diperbarui d/M/yy HH.mm" (24 jam), memakai **tanggal modifikasi file di Drive** (seperti kolom "Date modified"), bukan waktu SICATAT mendeteksi perubahan. `SourceUpdateCard(title, updatedAt, checking, error, onRefresh)`; baris kedua berganti "Memeriksa pembaruan…" atau "Gagal memeriksa: …".
- Sumber tanggal: header `Last-Modified` dari `drive.usercontent.google.com/download?id=…` (HEAD, tanpa API key). `_shared/drive_modified.ts` `recordDriveModified()` dipanggil tiap fungsi sinkron (PR v9, PM v5, CM v7, anggaran v6 verify_jwt false) dan disimpan di tabel baru `data_source_status` (migrasi `20260924110000_data_source_status.sql`; key `purchase_requisition`, `preventive_maintenance`, `corrective_maintenance`, `operational_budget`); `sync-warehouse-drive` (v2) menyimpan `warehouse_drive_source.modified_at` per file. Aplikasi membaca lewat `loadSourceModified()`; kartu yang menggabungkan beberapa file menampilkan yang terbaru.
- Diuji live: PR 24/9 14.13 (cocok dengan Drive 2:13 PM), PM & CM 9/9 15.17 (file CM "Weekly Meeting.xlsm"), anggaran 10/9 09.38, Gudang 24/9 14.56. Untuk file Gudang, Drive UI sempat menampilkan 14.54/14.55 sedangkan header 14.56, jadi selisih 1–2 menit mungkin terjadi pada file yang baru diunggah.
## Gudang dari folder Drive: Warehouse Inventory, LIST ORDER, Outstanding PO — 2026-09-24

- Sumber baru: folder Drive publik "Gudang" (`1VlT_EfkGY_M1-shqwJndmZ3beO2fAmTg`). Edge function `sync-warehouse-drive` (verify_jwt true, pengguna aktif mana pun) membaca daftar folder lewat `drive.google.com/embeddedfolderview`, memilih file menurut **awal nama** (`Warehouse_inventory…`, `Outstanding_Purchase_Order…`, `LIST ORDER…`; simpan satu file per jenis), dan mengimpor **satu sumber per panggilan** (`{"source": "inventory"|"list_order"|"outstanding_po"}`), dipanggil paralel dari aplikasi saat Cari barang / Barang dipesan / Peminjaman Alat dibuka. File yang sidik SHA-256-nya sama hanya ditandai diperiksa. Status per sumber di `warehouse_drive_source` (changed_at, checked_at, report_at, error).
- SheetJS butuh ~1,6 s CPU untuk inventory 21 ribu baris (batas Edge ~2 s); pakai `_shared/lean_xlsx.ts` (fflate + pindai XML) ~0,4 s. Laporan Ellipse AIJ17W/AIJOPO menyimpan angka sebagai teks; tanggal run inventory = serial Excel WITA.
- **Warehouse Inventory = sumber stok utama Cari barang** (keputusan pemilik): upsert ke `warehouse_stock` (`stock_source='inventory'`, part no, kelas stok, kategori, terakhir diterima/dikeluarkan, nilai), kode SC dinormalisasi tanpa nol depan (`000004675` = `4675`), site_label per gudang Ellipse (AMWH/AFS1 Asamasam, KMWH/KMIN/KFS1 Kintap, MAIN/CSWH/CMWH/NCH1/NFS1 NPLCT, SNOS/SNKN/SNFS Senakin, STOS/SAWH/SAFS Satui, BLWH Batulicin, BPPN Balikpapan). `sync-warehouse-data` (SCALLSITE harian, v18, verify_jwt false) **tidak lagi menimpa** baris inventory, hanya mengisi kode/gudang yang tidak ada di laporan, dan melewati baris `TOTAL`; label MAIN kini "NPLCT". Alasan: TANGGAL UPDATE SCALLSITE tidak bisa dipercaya (25/9 saat hari ini 24/9).
- LIST ORDER: 13 sheet crew/departemen → `warehouse_issue_history` (26 ribu baris; tanggal kosong = ikut baris atas, tanggal mustahil = null); sheet "PEMINJAMAN & OUTSTANDING TOOLS" → `warehouse_list_order_loan` (kondisi akhir kosong = belum kembali). Outstanding PO → `warehouse_outstanding_po`. Tabel diganti per batch (sidik) lalu batch lama dihapus.
- Aplikasi: Cari barang punya kartu pembaruan (inventory + LIST ORDER), filter site Asamasam/Kintap/NPLCT/Senakin/Satui, cari part no, kode SC persis di atas; detail barang menampilkan "Sedang dipesan" (PO untuk SC itu) dan "5 pengambilan terakhir" (LIST ORDER + pengambilan SICATAT bila pengelola). Kartu menu baru **Barang dipesan** (`/warehouse/purchase-orders`, semua pengguna; pesanan terbaru di atas, filter lewat jatuh tempo). Peminjaman Alat punya tab **List Order** (hanya baca, belum kembali + 50 terakhir sudah kembali; RLS pengelola).
- Barang dipesan menampilkan "Pemesan: <nama>" per kartu dan dropdown filter **Pemesan** (jumlah per nama). Di laporan Ellipse, baris tanpa Requestor ("null - null") persis baris ber-kode SC (restock gudang), jadi ditampilkan "Stok gudang (restock)" (`WarehouseOutstandingPo.orderedFor`). Pengambilan Barang (barang habis pakai, tidak kembali) dan Peminjaman Alat (alat wajib kembali) sengaja dipisah; pemilik bertanya bedanya 2026-09-24, keduanya dipertahankan.
- Menu Gudang dirampingkan (2026-09-24, pemilik merasa menunya kebanyakan): kartu **Penerimaan Barang dihapus dari menu** dan dipindah ke dalam Barang dipesan. Pengelola gudang melihat tombol "Terima" di tiap kartu PO (buka `/warehouse/receipts/new?po=…&supplier=…`, form terisi dan langsung cek PO) dan ikon riwayat di app bar ke `/warehouse/receipts` (riwayat, cek PO / PR / stok, Penerimaan baru). Rute penerimaan tetap sama; kembali dari sana ke Barang dipesan.
- Migrasi `20260924100000_warehouse_drive_sources.sql`. Uji live: inventory 20.918 barang (report 24/9 13.01 WITA), LIST ORDER 33.391 baris (109 pinjaman terbuka), PO 275.
- Catatan penulisan: here-string PowerShell berkutip ganda membuang backtick dan mengubah "`0" menjadi NUL; tulis catatan ini dengan here-string kutip tunggal atau editor file.

## Anggaran Operasional: keterangan pembaruan spreadsheet — 2026-09-24

- Kartu "Pembaruan data anggaran" (`SourceUpdateCard`) di atas Anggaran: spreadsheet anggaran & realisasi terakhir berubah = `max(operational_budget_month.synced_at)`, terakhir diperiksa = pemeriksaan latar belakang saat layar dibuka, ↻ memeriksa ulang dengan notifikasi. Baris "Sumber lembar kerja, diperbarui …" (dulu waktu sinkron) diganti keterangan sumber saja.
- `sync-operational-budget` (v5, verify_jwt tetap false) melewati penulisan ulang bila sidik 4 CSV sama dengan snapshot, mencatat log "tidak berubah", dan mengembalikan `changed:false`.

## PM & CM Tertunda: keterangan pembaruan spreadsheet — 2026-09-24

- Kartu "Pembaruan data PM & CM" (komponen bersama `core/widgets/source_update_card.dart`, juga dipakai Data PR): per sumber "spreadsheet terakhir berubah" = `max(synced_at)` baris PM/CM + jumlah tertunda, lalu "Terakhir diperiksa" dari pemeriksaan yang berjalan setiap layar dibuka (log PM hanya terbaca admin/SMG/foreman, jadi tidak dipakai). Tombol ↻ di kartu memeriksa ulang dan memberi tahu hasilnya. Kegagalan CM kini tampil (dulu diabaikan diam-diam).
- `sync-corrective-maintenance` (v6) kini melewati penulisan ulang bila sidik file sama dengan baris yang ada, supaya `synced_at` CM berarti waktu perubahan, bukan waktu pemeriksaan. Diuji live: CM tetap 23/9 04:50 UTC setelah pemeriksaan.

## Data PR: keterangan pembaruan spreadsheet — 2026-09-24

- Pemilik bingung apakah edit di PR.xlsx sudah masuk. Layar Data PR kini punya kartu "Pembaruan data PR" (gaya Gudang): **Spreadsheet terakhir berubah** = `max(purchase_requisition.synced_at)` (baris hanya ditulis ulang saat file berubah) + jumlah PR, dan **Terakhir diperiksa** = log `completed` terbaru; bila pemeriksaan terakhir gagal, kartu oranye dengan pesannya.
- Membuka Data PR memeriksa spreadsheet di latar belakang (seperti PM & CM); tombol ↻ memeriksa dan memberi tahu "diperbarui" atau "belum berubah sejak …".
- Edge function `sync-purchase-requisitions` (v8, verify_jwt tetap true) membandingkan SHA-256 file dengan log `completed` terakhir: bila sama, snapshot tidak ditulis ulang, hanya mencatat log "tidak berubah" dan mengembalikan `changed:false`. Sidik file Drive stabil antar-unduhan (diuji live 06:27 → 06:34 UTC).
## Gudang pindah ke Operasional + transaksi gudang — 2026-09-24

- Pemilik meminta Gudang dipindah dari Referensi ke **Operasional** dan fiturnya mengikuti aplikasi Gudang buatan tim warehouse (`D:\Project\Sicatat\Gudang`, HTML + Google Apps Script). Keputusan pemilik: data transaksi di **Supabase SICATAT** (bukan Apps Script); tahap 1 = Pengambilan Barang, Peminjaman Alat, Penerimaan & Cek PO. **DST (stock check acak) dan menu Pengingat aplikasi itu tidak diperlukan** (keputusan pemilik 2026-09-24) — jangan dibangun; migrasi Gudang dari aplikasi teman dianggap selesai. **Semua pengguna aktif boleh mencari stok/alat**; transaksi hanya admin, supervisor SMG, warehouseman (site sendiri) — `UserRoleX.canManageWarehouse` = SQL `can_manage_warehouse_site`.
- Migrasi `20260924090000_warehouse_transactions.sql`: tabel `warehouse_issue(_item)`, `warehouse_tool_loan(_item)` (index unik parsial: satu alat hanya di satu pinjaman terbuka), `warehouse_goods_receipt(_item)`; kolom kondisi SICATAT di `warehouse_tool` (`condition_status/_note/_updated_at/_by`, `created_by`). Tulis hanya lewat RPC SECURITY DEFINER: `warehouse_issue_create`, `warehouse_tool_register`, `warehouse_tool_set_condition`, `warehouse_tool_loan_create`, `warehouse_tool_return`, `warehouse_goods_receipt_create`; `warehouse_tools_on_loan()` memberi status "dipinjam" ke semua pengguna tanpa nama peminjam. `warehouse_receipt` (riwayat PENERIMAAN dari sheet) kini bisa dibaca pengelola untuk Cek PO.
- Sinkron harian `sync-warehouse-data` hanya meng-upsert kolom yang dikirimnya, jadi kondisi SICATAT dan alat registrasi SICATAT (`source_key` `sicatat-tool|<site>|<kode>`) tidak tertimpa. Status alat yang tampil: dipinjam (SICATAT) → kondisi SICATAT → `tool_status` sheet. Transaksi dari aplikasi teman (Apps Script) tidak masuk SICATAT, dan sebaliknya.
- Flutter: `features/warehouse/warehouse_data.dart` (site, lookup SC, format), layar `warehouse_issue_screen.dart`, `warehouse_tool_loan_screen.dart`, `warehouse_receipt_screen.dart`; rute `/warehouse/issues(/new)`, `/warehouse/tool-loans(/new)`, `/warehouse/tools/new`, `/warehouse/receipts(/new)`. Sejak permintaan pemilik berikutnya `/warehouse` adalah menu kartu (`warehouse_hub_screen.dart`, gaya menu Suhu): **Cari barang** (`/warehouse/search`, layar pencarian lama, semua pengguna) lalu, untuk pengelola, Pengambilan Barang, Peminjaman Alat, Penerimaan Barang. Pencarian tidak lagi langsung tampil saat Gudang dibuka. Qty outstanding PO tidak ada karena belum ada sumber baris PO; Cek PO memakai riwayat penerimaan (sheet + SICATAT), Data PR, dan stok.

## Major Job (admin) di Cloudflare D1 + KV — 2026-09-24

- Menu baru **Operasional → Major Job** (`/major-job`, `/major-job/new?date=`, `/major-job/job/:id`), hanya untuk `admin` (`UserRoleX.canUseMajorJob`, permintaan pemilik). Menggantikan skrip Python/Word pemilik untuk laporan foto pekerjaan mingguan: pekerjaan (tanggal + deskripsi + maks. 8 foto) dikelompokkan per minggu **Selasa–Senin yang bersambung terus lintas bulan** (…, 22–28 Sep, 29 Sep–05 Okt, 06–12 Okt, …; ubah 2026-09-24, sebelumnya dipotong di akhir bulan). Minggu masuk bulan tempat ia **berakhir**: Weekly Oktober dimulai 29 Sep ("Weekly Job 29 September - 12 Oktober 2026"). **Major Job bulanan tetap kalender** (01–30 Sep) dengan minggu yang dipotong ke bulan itu, jadi foto 29–30 Sep ikut di Major Job September (subjudul "29 – 30 September 2026") dan juga di Weekly Oktober. Layar bulan menampilkan 29–30 Sep sebagai bagian ekor berketerangan. Worker `/jobs` menerima `from`/`to` (maks. 62 hari) selain `month`.
- **Data sengaja tidak di Supabase.** Worker `cloudflare/major-job` (`https://sicatat-major-job.sicatat.workers.dev`) menyimpan baris di D1 `sicatat-major-job` dan byte foto di KV `sicatat-major-job-photos` (R2 belum aktif karena butuh kartu; pemilik memilih KV gratis 1 GB). Supabase hanya dipakai untuk login: Worker memverifikasi token akses lewat JWKS publik (ES256) dan RPC `is_active_sicatat_admin` dengan token pemanggil sendiri; tidak ada secret Supabase di Worker. Lihat `cloudflare/major-job/README.md`.
- Foto dikompres di aplikasi lewat `MeetingMinutePhotoCompressor.compress(maxDimension: 1200, targetBytes: 200 KB)`; layar menampilkan pemakaian KV terhadap 1 GB.
- PDF (`features/major_job/major_job_pdf.dart`, font aplikasi): judul **WEEKLY JOB REPORT** / **MAJOR JOB REPORT**, "COP | 01 – 10 Agustus 2026", garis, lalu per periode (halaman baru) tabel **No | Photo | Job Description** berheader abu-abu yang berulang. Setiap foto landscape dipotong tepat 5,4 × 3,6 cm, portrait 2,4 × 3,6 cm (tengah foto dipertahankan, tanpa bingkai) — keputusan pemilik setelah mencoba versi tanpa potong dan berbingkai. Laporan mingguan kumulatif sejak awal minggu pertama bulan itu sampai akhir minggu yang dipilih; bulanan mengikuti kalender. Nama file tetap gaya pemilik: `Weekly Job 01 - 10 Agustus 2026.pdf`, `Mayor Job 01 - 31 Agustus 2026.pdf`. Pekerjaan tanpa foto tidak ikut di PDF (diberi tanda di daftar).
- Layar edit menampilkan foto dengan potongan yang sama seperti PDF, urutan bisa digeser kiri/kanan (urutan = urutan di PDF). Sejak 2026-09-24 (permintaan pemilik) "Pekerjaan baru" langsung punya bagian Foto di bawah deskripsi: foto dikompres dan disimpan di perangkat, lalu diunggah setelah pekerjaan dibuat ("Simpan pekerjaan & N foto"); bila ada yang gagal, layar pindah ke halaman pekerjaan agar bisa ditambah ulang. Foto bisa diketuk untuk dibuka layar penuh tanpa potongan (geser/zoom, `showMajorJobPhotoViewer`). Tes: `test/major_job_photo_viewer_test.dart`.
- Tes: `flutter test test/major_job_test.dart`, `node --test cloudflare/major-job/test.mjs`.

## Font diganti ke Roboto — 2026-09-23

- Setelah melihat daftar font terpopuler, pemilik memilih Roboto untuk aplikasi dan semua PDF (menggantikan Figtree). File dari rilis resmi `googlefonts/roboto-3-classic` v3.016 (unhinted, SIL OFL), dipangkas dengan `pyftsubset` ke Latin/Latin Extended/Vietnam + tanda baca, mata uang, panah, simbol matematika, dan bentuk umum (U+0000-024F, 1E00-1EFF, 2000-22FF, 25A0-26FF, ...) sehingga tiap file ~165 KB, bukan ~400 KB. Hanya Regular/Medium/Bold; w600 tampil Bold. Excel notulen tetap menulis "Aptos". Bagian Figtree dan Poppins di bawah hanya riwayat.

## Font diganti ke Figtree, Excel ke Aptos — 2026-09-23

- Pemilik menilai Poppins jelek dan meminta Aptos. Lisensi Aptos (Microsoft, font cloud Office) hanya mengizinkan pemakaian di dalam produk Microsoft, jadi file Aptos tidak boleh dibundel ke website/APK/PDF. Pemilik memilih Figtree (SIL OFL, file statis Regular/Medium/SemiBold/Bold dari repo resmi `erikdkennedy/figtree`) untuk aplikasi dan semua PDF. Excel notulen menulis "Aptos" (tanpa file font); perkiraan tinggi baris Excel kembali ke angka Arial karena lebar Aptos setara Arial. Bagian Poppins di bawah hanya riwayat.

## Font diganti ke Poppins — 2026-09-23

- Pemilik menilai Liberation Sans "gepeng" dan meminta Poppins. Poppins Regular/Medium/SemiBold/Bold (Google Fonts, SIL OFL; `assets/fonts/` + `OFL.txt`) kini dipakai aplikasi, semua PDF (disematkan), dan Excel notulen (atas pilihan pemilik, walau komputer tanpa Poppins memakai font pengganti). ExtraBold tidak dibundel agar judul w800/w900 tetap setebal Bold seperti saat Arial. Perkiraan tinggi baris Excel disesuaikan (~12% lebih sedikit karakter per baris). Panduan PDF dibuat ulang; layar Beranda, Suhu, PM & CM, Lembar belum selesai, dan form Hydraulic dicek di ukuran HP tanpa teks meluber.

## Audit database, fitur, ekspor, dan font — 2026-09-23

- **Font satu untuk semua:** "Arial" di `AppTheme` tidak pernah dibundel, jadi web/Android sebenarnya menampilkan Roboto, sedangkan PDF memakai Helvetica. Kini Liberation Sans 2.1.5 (metrik Arial, SIL OFL 1.1; `flutter_app/assets/fonts/` + `OFL.txt`, lisensi terdaftar di halaman lisensi) dipakai aplikasi (`appFontFamily`) dan disematkan di semua PDF (`core/pdf/pdf_fonts.dart` `loadPdfTheme()`, `core/pdf/pdf_theme.dart` untuk tool non-Flutter). Excel MOM tetap "Arial". Panduan kini menulis "°C" dan `flutter_app/docs/Panduan-Pengguna-SICATAT.pdf` dibuat ulang.
- **PDF:** pembuat Ekspor lembar (`data/reports/sheet_export_pdf.dart`) dan Laporan periode (`data/reports/period_report_pdf.dart`) dipisah dari layar; `test/export_pdf_font_test.dart` memastikan PDF lembar, periode, panduan hanya memakai LiberationSans (PDF Hydraulic/Coal Valve di `daily_check_pdf_test.dart`). Tanggal PDF dd/mm/yyyy (`shownReportDate`), "Attention 60-69°C" → "Waspada 60-69°C", kolom Status lembar di PDF periode kini "Terkirim/Draf/..." (CSV tetap nilai asli).
- **Bug sinkronisasi diperbaiki:** hanya kepala lembar Feeder Sizer yang ditarik ke perangkat, jadi draf yang dilanjutkan di HP/browser lain tampil kosong, membuat ronde lokal duplikat yang ditolak server (409 unique sheet+section+round) selamanya, dan pembacaan di ronde itu tidak pernah terkirim. `SyncService.pullSheetDetail` + `LocalDatabase.mergeRemoteSheetDetail` menarik ronde/status unit/pembacaan saat form dan ringkasan dibuka; baris lokal duplikat mengambil id server dan antreannya ditulis ulang; 23505 pada insert ronde/status unit memicu tarik otomatis. Terbukti live: antrean 409 di browser audit pulih (200) tanpa mengubah draf crew 24/08.
- **Database:** migrasi sinkron; semua tabel RLS (warehouse_receipt dan technical_document_index sengaja tanpa policy, hanya edge function); tidak ada fungsi SECURITY DEFINER tanpa search_path; bucket privat; storage 55 MB; tidak ada file/baris foto yatim; cron 0 gagal 7 hari; sinkron gudang/PM/anggaran/PR completed. Migrasi `20260923090000_index_growing_foreign_keys.sql` menambah index FK untuk tabel yang tumbuh.
- **Fitur:** 33 rute dibuka live tanpa error konsol atau request gagal (selain 409 di atas).
- Catatan: lembar contoh 31/12/2034 (dulu disimpan sebagai sampel) sudah tidak ada di server dan tidak ada jejaknya di audit_log.

## Uji menyeluruh fitur Suhu & kartu Aktivitas bersama — 2026-09-23

- Aktivitas suhu kini kartu baris `MenuChoiceCard`/`MenuChoiceList` (`core/widgets/menu_choice_card.dart`, sama dengan menu Suhu) di Feeder Sizer, Hydraulic Feeder, dan Coal Valve (pilihan pemilik). Hydraulic/Coal Valve: Cetak lembar, Tren suhu, dan untuk reviewer Belum lengkap, Pemantauan & persetujuan, Laporan suhu tinggi (tanpa Sinkronisasi karena langsung online).
- `/temperature-trend?form=feeder_sizer|hydraulic_feeder|coal_valve` membuka tren lembar itu. Grafik tidak menggambar nilai di luar -50..250 °C (dummy 6363 dulu membuat skala 6.4K) dan menyebut jumlahnya; titik gearbox tanpa peralatan diberi label "Gearbox · …".
- Bug diperbaiki: halaman lembar dan daftar Hydraulic/Coal Valve adalah rute induk, jadi GoRouter mengembalikan state lama setelah form isian menyimpan (jumlah kosong, suhu maks, dan PDF cetak memakai data lama). Mixin `ReloadOnReturn` (`daily_check_widgets.dart`) memuat ulang saat lokasi kembali ke halaman itu; dijaga `test/reload_on_return_test.dart`.
- Teks: "1 person(s)" → "1 orang"; kartu admin "Override incomplete sheet" → "Kirim walau belum lengkap (Admin)"; kepala PDF laporan periode kini "Periode … s.d. … - Regu … lembar berisi data, … baris"; tanggal di Laporan suhu tinggi dd/mm/yyyy.
- Diuji live (lembar uji dihapus setelahnya): buat Feeder Sizer 31/12/2039, ambang 45/62/71, dialog anomali, status unit, ringkasan kartu merah, duplikat ditolak di UI dan server (409), sinkronisasi, hapus; Hydraulic & Coal Valve 01/01/2025: buat, isi, kirim tidak lengkap, edit ditolak server, persetujuan + PDF (penyetuju tercetak), batalkan, buka kembali, hapus; approved_by tidak bisa dipalsukan; Belum lengkap, Pemantauan, Laporan suhu tinggi, Laporan periode (CSV 163 baris/8 lembar, PDF 7 halaman), cetak rentang.
- PENTING untuk uji berikutnya: nilai ≥70 °C di data uji langsung memicu `temperature_alert` (cron 5 menit) dan notifikasi HP reviewer Android. Pakai nilai <70, atau hapus lembar dan alert segera.

## Perapian UI: "Crew", kartu lembar belum selesai, label Suhu — 2026-09-23

- Semua teks UI "kru"/"Kru"/"KRU" menjadi "crew"/"Crew"/"CREW" (permintaan pemilik); label PDF lembar "KRU / SIF" menjadi "CREW / SHIFT". Nilai database tidak berubah.
- `/incomplete`: status tidak lagi berupa chip di kanan (di HP teks terjepit satu huruf per baris); kini badge di bawah teks, tanggal "24 Agustus 2026", dan "n/8 terisi".
- Kartu aktivitas Suhu (`sheet_list_screen.dart`) memakai huruf biasa, bukan tebal. Kartu CM kini berjudul "CPP"/"PORT" di bawah "CM per lokasi" (dengan "CM PORT" hurufnya mengecil karena kartu setengah lebar; pemilik menilainya tidak rapi).
- Catatan cache: `{{flutter_service_worker_version}}` kini selalu `121553952` (service worker Flutter deprecated), jadi `main.dart.js?v=` tidak berubah antar deploy. Pengguna tetap mendapat versi baru karena `_headers` memberi `Cache-Control: no-cache` (revalidasi ETag). Setelah deploy, tunggu beberapa detik sebelum memuat ulang; pane sempat memuat versi lama saat edge belum terbarui.

## Notulen: satu temuan, banyak rencana tindakan — 2026-09-23

- Tanpa perubahan database: baris `meeting_minute_action` berurutan dengan uraian temuan dan tanggal temuan yang sama dianggap satu temuan (`groupMeetingMinuteFindings` di `meeting_minute_models.dart`). Notulen contoh "Ban Bocor" sudah memakai pola ini.
- Form: "Temuan N" (uraian + tanggal diisi sekali) berisi "Rencana tindakan N.k", tombol "Tambah rencana tindakan untuk temuan N" menyisipkan tepat di bawah temuannya; uraian/tanggal disalin ke semua rencananya saat simpan. Menghapus rencana pertama memindahkan temuan ke rencana berikutnya.
- Excel: No., Uraian Temuan, dan Tanggal Temuan di-merge per temuan; rencana diberi nomor 1., 2., …; rencana tanpa foto bertanda "–" (bukan "Tanpa foto", permintaan pemilik); bagian DETAIL RAPAT berbingkai dengan label tebal; judul DETAIL RAPAT/RENCANA TINDAKAN rata tengah; Catatan jadi baris berlabel; cetak A4 landscape, muat 1 halaman lebar. Baris mulai 16 (header 15).
- Bug diperbaiki: setelah menyimpan notulen yang sudah ada, layar tidak mengambil id rencana baru sehingga foto tidak bisa ditambah sebelum halaman dimuat ulang; tambah/hapus foto juga tidak lagi membuang ketikan yang belum disimpan.
- Diuji live (cache suffix `2.8.41-mom-findings`): notulen dummy kini temuan 1 = 3 rencana, temuan 2 = 5 rencana (11 baris, 8 foto); ekspor ulang berisi merge A16:A18 dan A19:A23.

## Notulen (MOM) sepenuhnya berbahasa Indonesia — 2026-09-23

- Ekspor Excel notulen: label Lokasi, Peserta, Berhalangan hadir, Notulis, RENCANA TINDAKAN, Uraian Temuan, Rencana Tindakan, Foto, Tenggat, Penanggung Jawab, Progres / Catatan, CATATAN. Tanggal kosong dicetak "–" (dulu "Belum diisi").
- Form notulen: "Rencana tindakan N", "Foto rencana tindakan (n/2)", pesan validasi berbahasa Indonesia; pemilih tanggal rapat/temuan/tenggat tidak lagi memaksa `Locale('en')`.
- Website saja (cache suffix `2.8.41-mom-id`, versi tetap). Diverifikasi live: ekspor ulang notulen contoh "DATA DUMMY - Inspeksi Area CPP (Review Output MOM)" (5 temuan, 7 foto) berisi label baru dan 7 gambar.

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
- Laporan periode 15–24 Agustus 2026 (semua regu): CSV 163 baris = 142 pembacaan + 21 status unit, 30 HIGH dan 5 CRITICAL sesuai DB, tanpa alert salah. PDF 7 halaman: sel nilai <60 putih (94), 60–69 `#ffb74d` (30), ≥70 `#e53935` (5). Di web mobile, `Printing.layoutPdf` membuka PDF lewat anchor `target=_blank` (bukan dialog cetak), jadi hook harus menangkap anchor tanpa atribut `download`. Header dulu menulis "8 sheet(s), 163 reading(s)"; jumlah 8 sudah benar (dua sheet tanpa pembacaan tetap punya baris status unit), tetapi 163 termasuk status unit. Kini "8 sheet(s) with data, 163 row(s)", dihitung dari kombinasi tanggal+regu+shift di baris laporan — regu wajib ikut karena data lama punya dua regu pada tanggal dan shift yang sama (19/08/2026 Night Crew A dan Crew C).
- Nilai 5757/6060/6161/6262/6363 pada 19/08/2026 Night Crew A adalah data dummy (dikonfirmasi pemilik 2026-09-15), bukan salah ketik crew.

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

## Logo baru, pengalihan ke sicatat.com, dan cache browser — 2026-09-17

- **Logo digambar ulang** karena tagline lama "Aplikasi Pencatatan Lapangan" tidak lagi sesuai. Logo lama berupa gambar raster dengan latar bertekstur dan sudut hitam di versi ikon. Yang baru: lencana hijau tua (`AppColors.greenDark`) berisi gir (operasional) dan centang oranye (pekerjaan tuntas), wordmark "SICATAT" (Arial Black), tagline "OPERASIONAL • REFERENSI • INFORMASI KERJA", latar transparan. Dibuat dengan `flutter_app/tool/make_logo.py` (Pillow); ikon Android/iOS/web diperbarui lewat `dart run flutter_launcher_icons`. Ikon Android baru ikut rilis APK berikutnya.
- Layar masuk: "Aplikasi operasional dan referensi kerja"; pemilik meminta **"online"** menggantikan "daring" (dan "offline" menggantikan "luring") — pilihan pemilik mengalahkan istilah KBBI di sini.
- **Pengalihan**: `web/_worker.js` (Pages advanced mode) mengalihkan setiap host selain `sicatat.com` — `sicatat-5l5.pages.dev`, URL pratinjau per deploy, `www.sicatat.com` — dengan **302** (bukan 301, supaya tidak tersimpan permanen di browser bila domain suatu saat bermasalah). `web/_routes.json` membatasi worker hanya pada `/` dan `/index.html`, sehingga aset statis tidak menghabiskan kuota request Workers gratis. Worker menambahkan header keamanan sendiri karena `_headers` tidak berlaku untuk respons worker. Fragmen `#/rute` ikut terbawa. Konsekuensi: URL pratinjau per deploy tidak bisa lagi dipakai untuk memeriksa build; periksa lewat `https://sicatat.com`.
- **Cache browser 4 jam di sicatat.com**: zona baru memakai *Browser Cache TTL* bawaan 4 jam yang **menimpa** `Cache-Control` dari Pages (`pages.dev` memakai `max-age=0`). Akibatnya `main.dart.js?v=2.8.39` dan gambar lama bertahan sampai 4 jam setelah deploy — logo baru sempat tidak tampil. `_headers` kini memberi `Cache-Control: no-cache`, tetapi baru berlaku setelah pemilik mengubah **Caching → Configuration → Browser Cache TTL → Respect Existing Headers** (token wrangler tidak punya izin pengaturan zona). Periksa dengan `curl -sI https://sicatat.com/main.dart.js`: harus `no-cache`, bukan `max-age=14400`.

## Domain sicatat.com — 2026-09-17

- Pemilik membeli `sicatat.com` di Cloudflare Registrar (akun yang sama dengan proyek Pages). Domain `sicatat.com` dan `www.sicatat.com` ditambahkan ke proyek Pages `sicatat` lewat API; catatan DNS CNAME `@` dan `www` → `sicatat-5l5.pages.dev` (proxied) dibuat pemilik di dashboard karena token wrangler tidak punya izin DNS.
- Hasil cek: kedua alamat HTTP 200 dengan sertifikat valid, header keamanan ikut aktif, `main.dart.js` identik dengan build lokal, dan halaman masuk di `https://sicatat.com` berhasil memanggil Supabase (`app_version` 200) tanpa galat konsol. Tidak ada perubahan kode: alamat website tidak tertulis di aplikasi maupun email, dan login NIK/kata sandi tidak memakai redirect URL.
- Deploy berikutnya tetap sama (`wrangler pages deploy ... --branch=main`); domain baru otomatis ikut. Sesi masuk tersimpan per alamat, jadi pengguna perlu masuk sekali lagi saat pertama membuka `sicatat.com`.

## Anggaran: jangan dipaksa memanjang — 2026-09-17

- Percobaan membuat Anggaran mengisi seluruh tinggi layar (kartu lokasi dan pintasan ikut memanjang lewat `fillViewport` + `IntrinsicHeight`) **ditolak pemilik** karena terlihat dipaksa. Sudah dikembalikan ke tata letak ringkas bertinggi alami; ruang kosong di bawah halaman pendek itu wajar. Jangan diulangi.
- Yang dipertahankan: angka US$ memakai `cardTitle` bobot 900 (15 px), bukan `metric` 20 px, karena nominal sepuluh karakter di ukuran metric terasa jauh lebih berat daripada label di sekitarnya.

## Tata letak ponsel & aplikasi penuh berbahasa Indonesia — 2026-09-17

Laporan pemilik dari iPhone (Safari), lima poin:

1. **Menu Operasional terpotong.** Lembar bawah memakai tinggi tetap 76% layar dengan `NeverScrollableScrollPhysics`, sehingga baris ketiga (Notulen Rapat) tertutup toolbar Safari. Kini `isScrollControlled`, tinggi mengikuti isi (maks 85%), grid `shrinkWrap` yang boleh digulir, dan padding bawah ikut safe area. Kartu dipendekkan (rasio 1.22).
2. **Kartu Suhu terlalu besar.** Enam aksi kini 3 kolom dengan ikon di tengah dan judul saja (subjudul jadi tooltip), sehingga muat satu layar.
3. **Kembali dari "Semua lembar" ke Beranda.** `sheet_list_screen` kini kembali ke `/sheets` saat `showList`; Pemantauan, Belum lengkap, Laporan periode, dan Suhu tinggi juga kembali ke `/sheets`. Aman karena peran di rute-rute itu adalah himpunan bagian dari peran `/sheets`.
4. **Bahasa Inggris tersisa.** Sapuan penuh (±360 teks di 40 berkas) memakai istilah KBBI: *lembar* (sheet), *shift* (dulu *sif*, diganti 2026-09-17), *kru* (crew), *kata sandi* (password), *pemantauan*, *pratinjau*, *templat*, *daring/luring*, *lembar kerja* (spreadsheet), *PM & CM Tertunda*, *Referensi Alat*, *Kode Biaya*, nama bulan Indonesia di Notulen. PDF dan CSV ikut diterjemahkan, termasuk kolom `Peringatan Suhu` dengan nilai `TINGGI 60-69°C` / `KRITIS >=70°C` / `PERLU DITINJAU` (CLAUDE.md sudah disesuaikan).
   - **Sengaja tidak diterjemahkan:** nilai yang disimpan di database (kategori pengingat `Other`, `Vehicle document`, dll., yang dipetakan ke label Indonesia saat ditampilkan), pesan trigger duplikat `A sheet already exists` yang dicocokkan `sync_service.dart`, nama akun cost code perusahaan, nama peralatan/titik ukur (Gearbox Breaker, Low Speed, …), nama produk (Google Sheet, Excel, Drive), singkatan (PM, CM, PR, PO, SOP, SC), peran (Foreman, Supervisor, Admin), dan kata *email* serta *filter* (yang terakhir ada di KBBI).
   - Dua jebakan yang tertangkap saat pemeriksaan: penggantian massal sempat mengubah nilai kategori `'Other'` dan string pencocokan trigger — keduanya dikembalikan. Setiap pengalihan kata tunggal harus dicek apakah dipakai di `==`, `switch`, `contains`, atau daftar nilai tersimpan.
5. **Anggaran tidak muat satu layar.** Ikon kartu metrik di tengah, dua pintasan (Realisasi per bulan, Rincian anggaran) berdampingan sebagai kartu kecil, sumber data jadi satu baris, jarak dirapatkan, dan `_OperationalSectionPage` hanya memberi ruang bawah 120 px bila halamannya punya FAB.

Diperiksa live pada viewport 375×690 (perkiraan iPhone dengan toolbar Safari): menu Operasional menampilkan ketujuh item, Suhu memuat enam aksi, Kembali dari Semua lembar mendarat di `#/sheets`, kedua layar laporan berbahasa Indonesia, dan Anggaran muat tanpa digulir dengan ruang sisa.

Isi panduan (`guide_content.dart`) ikut diselaraskan; `docs/PANDUAN-CREW-SICATAT.md` kini **dibangkitkan** dari isi itu (lihat skrip di catatan sesi) dan PDF-nya dicetak ulang. Belum dirilis ke Android.

## Kartu ringkasan seragam, Notulen berbahasa Indonesia, rilis 2.8.39 — 2026-09-16

- Temuan pemilik: kotak ringkasan Notulen terlihat lebih besar dari layar lain. Benar — ada **tiga implementasi berbeda** untuk hal yang sama: Suhu (tinggi 108, angka 22), Pengingat (tinggi 60, angka 18), Notulen/Permintaan Barang (tanpa tinggi tetap, angka 22, dibungkus Card lagi).
- Semuanya kini memakai satu widget `core/widgets/summary_filter_card.dart` (`SummaryFilterCard` + `SummaryFilterGap`): tinggi 76, ikon 18, angka `AppTextStyles.metric`, label `badge` berwarna muted, dengan keadaan terpilih (latar dan garis berwarna). `_RequestStatusCard`, `_StatusDivider`, `_summaryTile`, dan `_temperatureSummaryTile` dihapus.
- Catatan tinggi: isi kartu berukuran ±69 px, jadi tinggi 76 dengan padding vertikal 6. Percobaan pertama memakai 68 dan widget test langsung menangkap `RenderFlex overflowed by 7.0 pixels` — jangan turunkan tanpa mengecilkan isinya.
- Efek sampingan yang bagus: kartu Suhu dan Pengingat sekarang menunjukkan penyaring yang sedang aktif, yang sebelumnya tidak terlihat.
- **Notulen Rapat diterjemahkan penuh** (daftar dan editor): judul menu, "Buat notulen", "Detail rapat", "Peserta dan distribusi", "Temuan dan rencana tindakan", "Simpan sebagai draf", "Selesaikan notulen", "Terakhir disimpan ...", badge "Draf"/"Selesai", sampai kolom Excel "Tindak lanjut dari". `MeetingMinuteStatus.storageValue` tidak diubah, jadi data lama tetap terbaca. Tiga tes ikut diperbarui.
- **Rilis 2.8.39** (versionCode 14319, migrasi `20260916150000`) membawa terjemahan, kartu seragam, skala teks, dan tombol mengambang ke Android. APK 2.8.37 dihapus sesuai pola dua versi.

## Notulen: kartu ringkasan yang bisa disaring — 2026-09-16

- Chip statis "Draft 1 / Completed 1" diganti kartu ringkasan tiga kolom seperti di Permintaan Barang (`_RequestStatusCard` + `_StatusDivider` dipakai ulang), dan ditambah kategori **Tindak lanjut** (`followUpOf != null`).
- Penting: ketiganya adalah **penyaring, bukan pembagian**. Sebuah notulen tindak lanjut tetap berstatus draft atau selesai, jadi jumlahnya sengaja tumpang tindih dan tidak dijumlahkan menjadi total. Ini ditulis sebagai komentar di kode supaya tidak "diperbaiki" jadi saling eksklusif.
- Menekan kartu yang sedang aktif akan melepas penyaringnya (`_toggleFilter`), sama seperti Permintaan Barang; ada tombol "Semua" di samping judul daftar dan keadaan kosong menawarkan "Tampilkan semua".
- Label layar daftar Notulen ikut diterjemahkan supaya tidak campur setelah kartu baru berbahasa Indonesia: FAB "Buat notulen", "Notulen belum dapat dimuat", "Coba lagi", "Notulen tanpa judul", "N rencana tindakan", "Tindak lanjut dari ...". **Layar editornya masih berbahasa Inggris** — belum dikerjakan.
- `_MeetingStatusChip` dihapus karena tidak terpakai lagi. Tes widget MOM diperbarui: label kartu, dan "Buat notulen" kini muncul dua kali (FAB dan tombol keadaan kosong).

## Aksi utama jadi tombol mengambang — 2026-09-16

- Permintaan pemilik: bagian atas layar terasa penuh. Tombol utama dipindahkan ke `FloatingActionButton.extended` mengikuti pola "Sheet baru" yang sudah ada di layar Suhu, dan penjelasan yang hanya mengulang judul halaman dihapus.
- **Pengingat**: judul "Tindak lanjut operasional", kalimat penjelasannya, dan tombol selebar layar "Tambah pengingat" dihapus dari badan daftar; sekarang langsung kartu ringkasan. Tombol jadi FAB, dan padding bawah daftar dinaikkan ke 110 + safe area supaya kartu terakhir tidak tertutup.
- **Permintaan Barang**: tombol "Ajukan kebutuhan barang" selebar layar dihapus; FAB "Ajukan barang" ditambahkan lewat parameter baru `floatingActionButton` pada `_OperationalSectionPage` (dipakai bersama Anggaran, PM & CM, dll). FAB sengaja tetap tampil walau belum ada pengguna masuk, hanya nonaktif, supaya aksinya tetap terlihat — ini juga yang diuji widget test.
- **Meeting Minutes**: sudah punya FAB; yang dihapus hanya judul "Inspection and field meeting minutes" beserta kalimat penjelasannya yang mengulang judul app bar.
- Yang **tidak** dihapus: kalimat yang mengajarkan interaksi, misalnya "Tekan status untuk melihat pengajuan yang sesuai" dan "Pilih pengajuan untuk memperbarui prosesnya". Hanya deskripsi yang mengulang judul yang dibuang.
- Diperiksa live di 375 px: Pengingat dan Permintaan Barang. `test/operational_sections_screen_test.dart` diperbarui ke label baru dan memastikan FAB-nya ada.

## Skala teks dibakukan — 2026-09-16

- Temuan pemilik: teks di layar Pengingat terasa besar. Penelusuran menunjukkan masalahnya bukan Pengingat, melainkan **19 ukuran berbeda** di 117 tempat: judul halaman 22 di Pengingat tetapi **26** di Sheet saya, Pemantauan, dan Belum lengkap; teks pendukung berkeliaran antara 9 dan 13; judul kartu 13/15/16.
- Skala tunggal kini didokumentasikan di `AppTextStyles`: **22 / 20 / 18 / 15 / 14 / 12 / 11**. `pageTitle` turun 24 → 22, dan token baru `badge` (11) untuk chip, label mikro di bawah angka, serta footer versi.
- 39 ukuran di 16 berkas dinormalkan ke tangga itu. Yang sengaja dikecualikan: wordmark "sicatat" (40 di layar masuk, 27 di sidebar) karena itu logo, judul kartu grid menu mode compact (`compact ? 13 : 15`) yang harus muat 3 kolom, dan seluruh `pw.TextStyle` milik ekspor PDF.
- Efek yang terlihat: angka ringkasan Pengingat 23 → 20 dan label di bawahnya 9 → 11 (lebih terbaca), judul tiga layar Suhu 26 → 22. Diperiksa langsung di lebar 375 px pada Beranda, Pengingat, Suhu, dan Pemantauan — tidak ada teks terpotong.
- Aturan ke depan tetap seperti di `docs/PROJECT_MEMORY.md`: pakai token, jangan menulis `fontSize` baru di luar tangga ini.

## Foto barang, link tanpa skema, rilis 2.8.38, dan pembersihan data uji — 2026-09-16

- Link produk kini boleh ditulis tanpa skema. `MaterialRequestProductLink.normalize()` menambahkan `https://` bila belum ada, menolak kata polos tanpa titik (mis. "kacamata") dan skema selain http/https. Kolom database tetap hanya menerima alamat http(s) penuh, jadi normalisasi terjadi di aplikasi. Diuji: `www.tokopedia.com/search?q=...` tersimpan sebagai `https://www.tokopedia.com/search?q=...`.
- Foto barang opsional: bucket privat `material-request-photos` (migrasi `20260916130000`, maks 2 MB, hanya jpeg/png) plus kolom `photo_path`/`photo_mime`. Baris pengajuan belum ada saat form dikirim, jadi objek disimpan di bawah id `app_user` pengunggah — itu pula yang diperiksa policy insert. Policy read: pemilik atau `can_manage_material_request()`.
- Foto dikompres lewat `MeetingMinutePhotoCompressor` (aturan kompresi unggahan). Uji live: PNG 4.380.523 byte → tersimpan 363.274 byte JPEG, dan panel planner menampilkannya lewat signed URL.
- Foto yang diunggah lalu formnya ditinggalkan akan dihapus di `dispose()`, dan mengganti foto menghapus yang lama — supaya tidak ada berkas yatim di storage.
- **Rilis 2.8.38** (versionCode 14318, migrasi `20260916140000`). APK 2.8.36 dihapus sesuai pola dua versi; storage app-releases kembali 2 berkas / 53 MB.
- **Pembersihan data uji atas permintaan pemilik (2026-09-16)**, memakai SQL karena `material_request` tidak punya policy DELETE: 4 permintaan barang uji, 1 notulen "Contoh MOM Uji Website", 12 pengingat `[DEMO]`, 1 batas suhu contoh, 1 regu "Contoh Regu Uji Web" (nonaktif, tanpa referensi), dan 1 sheet bertanggal 2034-12-31. **Pasangan "Contoh MOM - Ban Bocor Kendaraan Ringan" sengaja dipertahankan** sebagai contoh pengisian.
- Menghapus baris induk lewat SQL **tidak** ikut menghapus berkas di Storage (aplikasi yang biasanya melakukannya). Satu foto notulen menjadi yatim dan dihapus manual; setelah itu 0 berkas yatim di `meeting-minute-photos` dan `reminder-evidence`. Periksa hal ini setiap kali menghapus baris yang punya lampiran.

## Permintaan Barang: area COP & link produk — 2026-09-16

- Migrasi `20260916120000_material_request_cop_and_product_url.sql`: check `request_area` kini menerima `lv`, `cop`, `drilling`; kolom baru `product_url text` dengan check `null atau ^https?://[^[:space:]]+$` supaya string kosong tidak lolos dan kolomnya benar-benar berisi alamat.
- `MaterialRequestArea` bertambah `cop` (label "COP", urutan dropdown LV → COP → Drilling). `MaterialRequest.productUrl` bernilai null bila kolomnya kosong atau hanya spasi.
- Form pengajuan punya kolom "Link produk (opsional)" dengan validasi di aplikasi (harus http/https, tanpa spasi) supaya salah ketik tertangkap sebelum insert ditolak Postgres. Di panel planner, link tampil sebagai alamat penuh yang bisa diketuk (`_MaterialRequestProductLink`, `launchUrl` mode eksternal) — sengaja menampilkan URL aslinya agar tujuan yang tidak diharapkan terlihat sebelum dibuka.
- Diuji live: dropdown menampilkan LV/COP/Drilling; link "toko.example/kacamata" ditolak dengan pesan "Link harus diawali http:// atau https://." dan form tidak terkirim; setelah diperbaiki, pengajuan tersimpan `request_area='cop'` dengan `product_url` utuh dan panel planner menampilkan baris "Link produk". Tes unit di `test/material_request_product_url_test.dart`.

## Uji live Permintaan Barang — 2026-09-16

- Fitur terakhir yang belum pernah diuji langsung (selain buat pengguna) kini sudah: pengajuan dibuat lewat form website (`UJI WEBSITE 16/09 - Filter oli hidrolik`, 2 pcs, LV, penggantian barang rusak) → tersimpan `status='submitted'`, lalu diproses menjadi `status='rejected'` dengan `planner_note` terisi. Validasi "penolakan wajib beralasan" terbukti: begitu Status dipilih Ditolak, kolom berubah menjadi "Alasan penolakan *" bergaris merah dan tombol Simpan status **mati** sampai alasannya diisi.
- Sisa data uji di produksi: 2 baris `material_request` (`Contoh Barang Uji Website` 14/09 berstatus processed, dan baris 16/09 berstatus rejected). Tabel ini tidak punya policy DELETE, jadi hanya bisa dihapus lewat SQL/service role — tanyakan pemilik dulu.
- Catatan uji Browser pane: jangan menghitung koordinat dari screenshot ber-skala kecil untuk elemen setinggi tombol. Beberapa klik meleset ke kolom teks di atasnya karena estimasi dari gambar 0,5x. Ambil satu screenshot `scale: 1` (frame = piksel perangkat) sebelum menekan tombol yang posisinya kritis.
- Catatan uji kedua: `ctrl+a` **tidak** menyeleksi isi kolom teks Flutter web lewat tool ini, dan `Backspace` juga tidak sampai — akibatnya isian menumpuk ("unitpcspcs"). Cara yang berhasil: klik kolomnya, lalu lewat JS `document.activeElement.setSelectionRange(0, value.length)` pada input tersembunyi milik Flutter, baru ketik penggantinya.

## Perbaikan dari sudut pandang pengguna (v2.8.40) — 2026-09-18

Pemilik meminta semua saran dikerjakan: (1) menu Suhu untuk Foreman/Supervisor COP; (2) APK 2.8.40; (3) kartu jadwal pengecekan di Beranda + notifikasi Android 10 menit sebelum jadwal Hydraulic sesuai rotasi 3-3-3; (4) nilai pengecekan sebelumnya di bawah kolom, lonjakan ≥15 ditandai; (5) tekanan dalam bar (tanpa batas normal karena belum ada data OEM); (6) Hydraulic/Coal Valve masuk Suhu tinggi, Lembar belum selesai, Pemantauan, Laporan periode; (7) email peringatan suhu kritis tiap 5 menit ke penerima yang diatur admin; (8) grafik Tren suhu; (9) persetujuan "Mengetahui" tercetak di PDF; (10) batas suhu per titik; (11) cetak banyak lembar sekaligus. Detail teknis di CLAUDE.md. Uji deteksi peringatan memakai dua lembar DATA DUMMY 01/09/2026 (tercatat `no_recipient`, tidak ada email).

## Suhu: Hydraulic Feeder & Coal Valve, kata "shift" — 2026-09-17

1. **Tiga pilihan Suhu.** Menu Suhu kini membuka `/temperature-forms` berisi Daily Temperature Feeder Sizer (alur lama `/sheets`), Daily Check Sheet Hydraulic Feeder, dan Temperature Coal Valve (dari `Print Daily/*.xlsx`). Dua lembar baru berbahasa Inggris atas permintaan pemilik. Detail teknis ada di CLAUDE.md bagian "Suhu menu".
2. **Database.** Tabel `daily_check_sheet` + RPC `daily_check_save_slot` + `daily_check_occupied_shifts` (migrasi `20260917090000`, `20260917091000`). Lembar submitted dikunci trigger; diuji langsung (update ditolak dengan pesan "Reopen it before editing"). Data uji dibuat dan dihapus lagi lewat UI; tabel kosong.
3. **PDF.** Ikon PDF di ringkasan lembar mencetak tata letak formulir kertas satu halaman (Hydraulic A4 lanskap, Coal Valve A4 potret) dengan oranye 60–69 °C dan merah ≥70 °C. `test/daily_check_pdf_test.dart` menulis contoh PDF bila `DAILY_CHECK_PDF_DIR` diisi.
4. **"sif" → "shift".** Pemilik merasa "sif" aneh; seluruh teks UI, panduan, dan tes memakai "shift" (misalnya "Shift Pagi"). Istilah KBBI lain tetap.
5. **Revisi pemilik (hari yang sama).** Hanya tiga nama menu Suhu yang berbahasa Inggris; isi lembar kini berbahasa Indonesia. PDF memakai formulir kosong hasil ekspor Excel (`assets/forms/`) sebagai latar agar sama persis, dan Coal Valve menjadi 4 blok waktu seperti formulirnya. Pesan galat database juga diterjemahkan (migrasi `20260917100000`).
6. **Belum di Android.** Perubahan ini baru di website; APK 2.8.39 belum memuatnya.

## Penolakan pertanyaan di luar topik & rilis 2.8.37 — 2026-09-16

- Pemilihan dokumen di `ask-technical-documents` dulu memakai `haystack.includes(term)`, sehingga potongan kata ikut cocok: "nasi" ada di dalam "kombinasi". Pertanyaan seperti "apa resep membuat nasi goreng" bisa menarik SOP sungguhan lalu model dimintai jawaban sambil memegang dokumen kerja. Kini `mentionsTerm()` mencocokkan kata utuh.
- Catatan implementasi: pola regex-nya dibangun dengan `String.raw`. Di template literal biasa `\p` menciut menjadi `p`, sehingga `[^\p{L}\p{N}]` berubah jadi kelas karakter huruf p/{/L/} dan batas kata tidak berfungsi — persis bug yang sempat lolos saat pengujian pertama. Escaping istilah tidak diperlukan karena `queryTerms` sudah memotong pada semua karakter selain huruf dan angka.
- Bila tidak ada dokumen yang cocok, jawabannya kini menolak secara eksplisit ("Pusat Dokumen hanya menjawab dari SOP, manual, izin kerja, dan drawing milik perusahaan; pertanyaan di luar itu ditolak") dan Gemini tidak dipanggil sama sekali, jadi kuota tidak terpakai. Prompt juga menyuruh model menolak pertanyaan di luar dokumen walau ia tahu jawabannya. Diuji live: "Apa resep membuat nasi goreng?" ditolak dalam 4,5 detik; "Berapa minimal orang untuk pekerjaan sandblasting?" tetap dijawab benar (ASM-COP-160) dalam 8,6 detik.
- Isi panduan dipindahkan ke `lib/features/guide/guide_content.dart` yang **bebas impor Flutter** (ikon per kelompok tinggal di layar). Dengan begitu `dart run tool/generate_guide_pdf.dart` dari `flutter_app/` dapat mencetak ulang `docs/Panduan-Pengguna-SICATAT.pdf` dari isi yang sama persis dengan aplikasi. `docs/Panduan-Crew-SICATAT.pdf` yang lama dihapus atas permintaan pemilik.
- **Rilis 2.8.37** (versionCode 14317, arm64-v8a, migrasi `20260916110000`): membawa seluruh perbaikan sejak 2.8.36 — panduan baru, penolakan pertanyaan di luar topik, kompresi unggahan, perbaikan Share PDF, catatan anomali di CSV, header laporan periode, pencarian dan urutan Data PR, serta peringatan email di layar Pengingat. APK diperiksa dengan `aapt2 dump badging`, unduhan lewat signed URL menghasilkan `PK` dengan content-type APK. APK 2.8.35 dihapus sesuai pola dua versi; storage kembali 2 berkas / 52 MB.
- Catatan CLI: `npx supabase storage rm` **diam-diam tidak menghapus apa pun** tanpa `--yes` — hasilnya `{"deleted":[]}` tanpa pesan galat. Selalu periksa isi `deleted` setelah menjalankannya.

## Pemeriksaan email harian & panduan pengguna baru — 2026-09-16

- `dispatch-reminder-emails` kini memanggil `checkEmailProviders()` (baru di `_shared/reminder_email.ts`) di akhir setiap jalannya dan menyimpan hasilnya ke `public.email_provider_health` (migrasi `20260916100000`). Pemeriksaan hanya menukar refresh token Gmail dan memanggil `GET /domains` milik Resend — tidak ada email yang dikirim. Kegagalan pemeriksaan tidak pernah menggagalkan dispatch.
- Alasannya: cron menjawab `succeeded` walau tidak mengirim apa pun, dan kiriman terjadwal berikutnya baru 24 Desember 2026, sehingga izin Gmail yang mati akan tersembunyi berbulan-bulan.
- `reminder_screen.dart` membaca baris `gmail` dan menampilkan kotak merah bila `ok=false` atau pemeriksaan lebih tua dari 2 hari. RLS: hanya `is_active_sicatat_admin()` yang boleh membacanya; penulisan lewat service role. Kegagalan baca tidak mengganggu layar.
- Hasil pemeriksaan pertama (2026-09-16): `gmail ok=true`, `resend ok=false` ("Resend menolak kunci API (HTTP 400)") — cocok dengan riwayat pengiriman. Banner diuji dengan membalik baris `gmail` ke `ok=false` sebentar (kotak merah muncul), lalu dikembalikan dengan menjalankan pemeriksaan sungguhan, bukan menyunting balik.
- Panduan pengguna ditulis ulang. Isinya sekarang satu sumber (`_guideGroups` di `crew_guide_screen.dart`) yang dipakai layar sekaligus PDF unduhan, karena keduanya sebelumnya punya salinan sendiri yang sudah berbeda (PDF masih menyebut menu "Temperature"). Sepuluh kelompok mengikuti menu aplikasi: Dasar penggunaan, Suhu, Laporan dan ekspor, Pengingat, Notulen rapat, Anggaran dan pekerjaan, Gudang, Pusat Dokumen dan referensi, Profil dan aplikasi, Untuk admin. Diuji live: PDF terbentuk 15.640 byte / 3 halaman dan memuat kesepuluh judul kelompok.
- Teks panduan sengaja memakai "derajat C", bukan simbol derajat, supaya aman di font bawaan PDF. `flutter_app/docs/PANDUAN-CREW-SICATAT.md` disamakan (versi lama masih menjelaskan alur offline/sinkronisasi yang sudah tidak ada dan login "password", bukan PIN). `flutter_app/docs/Panduan-Crew-SICATAT.pdf` adalah cetakan lama yang belum diperbarui.

## Pusat Dokumen: daftar berkas pindah ke Postgres — 2026-09-16

- Masalah: `ask-technical-documents` hanya menyimpan hasil telusur folder Google Drive di memori isolate selama 10 menit, jadi pengguna pertama setelah jeda membayar telusur ulang. Folder ternyata berisi **1.964 berkas**, dan telusurnya mahal.
- Perbaikan: migrasi `20260916090000_technical_document_index.sql` menambah tabel `public.technical_document_index` (`drive_id`, `name`, `folder_path`, `synced_at`) — hanya nama, id Drive, dan jalur folder; isi berkas tetap di Drive. RLS aktif tanpa policy dan hak `anon`/`authenticated` dicabut: hanya edge function dengan service role yang membacanya. Ukuran tabel 520 kB.
- Fungsi membaca tabel; bila umurnya lebih dari 24 jam, jawaban tetap dikirim dari daftar lama dan telusur ulang dijalankan lewat `EdgeRuntime.waitUntil` sesudah respons, jadi tidak ada pengguna yang menunggu Drive. Daftar kosong berarti telusur langsung (sekali saja, saat pertama kali). Hasil telusur kosong tidak pernah menimpa daftar yang baik. Daftar model Gemini juga di-cache satu jam supaya tidak ada bolak-balik tambahan ke Google per pertanyaan.
- Pengukuran live: sebelum 28,0 detik (isolate dingin) dan 22,3 detik (hangat). Sesudah: 50,9 detik sekali saat membangun indeks pertama kali, lalu **9,2 detik** pada isolate dingin (dipaksa dingin dengan deploy ulang) dan 15,8 detik untuk pertanyaan yang sebelumnya 28,0 detik. Jawaban tetap benar dengan sumber yang sama (ASM-COP-160 sandblasting, ASM-OHS-297 kerja ketinggian, ASM-COP-113 pengelasan).
- Catatan kuota: database free plan 500 MB, terpakai 25 MB; tabel indeks ini 520 kB. Storage berkas tidak bertambah sama sekali.

## Uji live menyeluruh website — 2026-09-16

- Kompresi lampiran Pengingat terbukti di website: foto uji 7,94 MB (PNG bising 1800×1350) dipilih lewat dialog "Tambah pengingat" → daftar lampiran menampilkan `uji-kompresi.jpg` 522,4 KB. Dialog ditutup dengan Batal, tidak ada data tersimpan.
- Kompresi foto Notulen diuji sampai ke storage pada MOM contoh (`Contoh MOM Uji Website`): foto 8.328.320 byte tersimpan 534.941 byte `image/jpeg`; PNG datar 200×150 (1.260 byte) tersimpan apa adanya sebagai `image/png` — membuktikan aturan "simpan yang lebih kecil" berjalan di jalur sungguhan. Ekspor Excel MOM berisi `xl/media/image1.jpg` dan `xl/media/image2.png`, jadi jalur PNG baru aman di ekspor. Kedua foto uji dihapus lagi; bucket kembali 6 berkas / 438 kB.
- Gudang: pencarian "bolt" mengirim `limit=101` (2,6 detik) dan diakhiri catatan "Menampilkan 100 item pertama…"; DB memang berisi 201 baris cocok. Sinkron harian terakhir 2026-09-15 22:00 UTC (cron `sicatat-sync-warehouse-daily` succeeded).
- Pusat Dokumen (Gemini): "Apa syarat bekerja di ketinggian?" dijawab dengan sumber ASM-OHS-297 dalam 28,0 detik (indeks Drive dingin); "Berapa minimal orang untuk pekerjaan sandblasting?" dijawab "Minimal 3 (tiga) orang" dengan sumber ASM-COP-160 dan ASM-COP-171 dalam 22,3 detik. Fungsi tetap lambat karena mengunduh sampai 8 dokumen per pertanyaan; indeks folder hanya di-cache 10 menit di dalam isolate.
- 16 rute dibuka berurutan (cost code, referensi alat, anggaran, PM & CM, PR, permintaan barang, notulen, sheets, monitoring, laporan, suhu tinggi, belum lengkap, pengguna, admin, panduan, gudang) dengan pemantau `fetch`: nol permintaan gagal dan nol error konsol.
- Cron sehat: `sicatat-dispatch-operational-reminders` 2026-09-16 00:00 UTC succeeded, `sicatat-sync-warehouse-daily` 2026-09-15 22:00 UTC succeeded.
- Catatan perilaku email pengingat (bukan bug): fungsi hanya mengirim bila **hari ini persis** sama dengan tanggal jatuh tempo dikurangi offset, dan hanya untuk `status='open'` dengan `due_date >= today`. Jadi 96 pengingat yang sudah terlambat tidak pernah dikirimi email, dan bila tanggal kirim terlewat (cron mati atau pengingat dibuat setelah tanggal itu) email tidak pernah menyusul. Saat ini 4 baris seperti itu, semuanya `[DEMO]`. Email berikutnya menunggu tanggal kirim masing-masing; tidak ada yang jatuh pada 15–16 Sep, sehingga tabel `operational_reminder_delivery` memang kosong untuk dua hari itu.
- Catatan uji: koordinat `computer` di Browser pane memakai piksel perangkat (frame screenshot), dibagi `devicePixelRatio` saat dikirim ke halaman. Bila klik tidak direspons sama sekali walau halaman tergambar, kanvas Flutter sudah basi — `resize_window` desktop → mobile lalu `location.reload()` memulihkannya.

## Kompresi unggahan (Supabase free plan) — 2026-09-15

- Pemilik memakai Supabase free plan: setiap unggahan ke Storage wajib dikompres. Foto Notulen sudah lewat `MeetingMinutePhotoCompressor` (JPEG, sisi terpanjang 1280 px, target 600 KB). Pengingat (bukti selesai dan dokumen pendukung) dulu mengunggah file asli hingga 10 MB; kini lewat `ReminderEvidencePreparer`: JPG/PNG dikompres dengan kompresor yang sama dan versi yang lebih kecil yang disimpan (gambar yang sudah ringkas tidak dibesarkan), PDF maksimal 2 MB karena tidak bisa dikompres di aplikasi. Teks petunjuk di dialog sudah diperbarui.
- File gambar rusak dulu memunculkan `RangeError` mentah dari `package:image`; kompresor kini mengubahnya menjadi pesan yang bisa dibaca (berlaku untuk Notulen dan Pengingat). Diuji di `test/reminder_evidence_preparer_test.dart`.
- Fitur unggah baru apa pun harus memakai pola ini dan diverifikasi langsung dengan membandingkan `storage.objects.metadata->>'size'` terhadap file asli.
- 2026-09-16: aturan "simpan yang lebih kecil" dipindahkan ke `MeetingMinutePhotoCompressor` sendiri, jadi Notulen ikut memakainya (dulu foto Notulen selalu dire-encode ke JPEG sehingga PNG kecil justru membengkak). `CompressedMeetingMinutePhoto` kini membawa `mimeType` per foto, dan `meeting_minute_service.dart` memakai nilai itu untuk `contentType` serta kolom `mime_type`; ekspor Excel/PDF memang sudah menangani PNG.
- Pengecualian: foto dengan orientasi EXIF (≠1) selalu dire-encode walau hasilnya lebih besar, karena ekspor menggambar piksel tanpa membaca EXIF. Diuji di `test/meeting_minute_photo_compressor_test.dart` (PNG tidak menyimpan EXIF, jadi tes orientasi memakai sumber JPEG).

