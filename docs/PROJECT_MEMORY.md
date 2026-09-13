# SICATAT Project Memory

Dokumen ini adalah pegangan singkat bagi pengembang berikutnya. Baca juga
`AGENTS.md`, terutama aturan keamanan dan rilis.

## Handoff terbaru — 13 September 2026

- Sumber terbaru berada di `origin/master`. Commit awal untuk pekerjaan
  berikutnya adalah `519e4f0`; versi aplikasi tetap `2.8.34+12314` / `2.8.34`.
- Website produksi sudah memakai bundle yang sama dengan commit `ff086b3`:
  `https://sicatat-5l5.pages.dev/?versi=2-8-34-mom-english#/dashboard`.
  Deploy terakhir diverifikasi dengan checksum `main.dart.js` lokal dan
  produksi yang sama.
- Pemilik tetap meminta website-first. Jangan build, upload, atau publish APK
  Android kecuali diminta secara eksplisit.
- Meeting Minutes sekarang menggunakan label dan pesan UI bahasa Inggris.
  Due date opsional. Ekspor Excel memakai metadata Inggris, judul 60 pt,
  nomor/foto/date raised/due date/responsible person/progress rata tengah,
  dan maksimal dua foto proporsional sejajar dalam satu baris action plan.
- Foto MOM dikompres otomatis menjadi JPEG, sisi terpanjang maksimal 1280 px,
  target sekitar 600 KB, sebelum masuk bucket privat. Excel menampilkan gambar,
  bukan nama file.
- Data contoh MOM `Contoh MOM - Ban Bocor Kendaraan Ringan - Tindak lanjut`
  sudah memiliki dua issue description dan tiga foto yang dibagi 1 foto pada
  action pertama serta 2 foto pada action kedua.
- Slide satu halaman terbaru berisi 15 menu/section dengan screenshot website
  tanggal 13 September 2026 dan penjelasan singkat. Artefak final:
  `output/ppt/sicatat-semua-menu-terbaru.pptx` (commit `519e4f0`).
- Seluruh 21 Flutter tests dan `flutter analyze` terakhir lulus sebelum deploy
  Meeting Minutes. Finalizer PowerPoint menyatakan package, layout, font Arial,
  dan jumlah satu slide valid.
- Folder lokal `.codex-build/`, `.wrangler/`, `flutter_app/.wrangler/`,
  `flutter_app/android/build/`, `flutter_app/supabase/`, `output/pdf/`, dan
  `outputs/` tidak dilacak. Jangan ikut commit atau hapus tanpa kebutuhan.

## Kondisi produk saat ini

- Aplikasi aktif adalah Flutter di `flutter_app/`; kode JavaScript/Capacitor di
  root adalah arsip dan tidak dipakai.
- Website produksi: `https://sicatat-5l5.pages.dev`.
- Supabase adalah backend utama untuk Auth, data snapshot, dan Edge Function.
  Jangan memasukkan service-role key ke Flutter, APK, dokumentasi, atau Git.
- Release sumber saat dokumen ini ditulis: `2.8.33+12313`. Lihat
  `flutter_app/pubspec.yaml` dan `AppConfig.appVersion` sebelum memulai
  perubahan baru.

## Kebijakan rilis pemilik

- Prioritaskan **website**. Jangan membangun, mengunggah, atau menerbitkan APK
  Android kecuali pemilik secara eksplisit meminta pembaruan Android.
- Kode Flutter tetap satu sumber untuk website dan Android; jangan membuat
  fitur data yang berbeda antarlayanan tanpa persetujuan.
- Setiap pekerjaan selesai harus diverifikasi, di-commit, lalu di-push ke
  `origin/master` agar dapat dilanjutkan dari komputer lain.
- Untuk perubahan website, perbarui suffix cache
  `flutter_app/web/index.html` pada `flutter_bootstrap.js`, build web, lalu
  deploy Cloudflare Pages. Jangan mengubah nomor versi aplikasi hanya untuk
  perapihan tampilan website.

## Sistem tampilan: ikuti Beranda

Beranda adalah acuan visual. Font aplikasi adalah Arial yang ditetapkan secara
global di `AppTheme`; jangan menetapkan `fontFamily` berbeda pada halaman baru.

Gunakan token pada `flutter_app/lib/core/theme/app_theme.dart`:

| Kebutuhan | Token |
| --- | --- |
| Judul halaman | `AppTextStyles.pageTitle` |
| Judul section | `AppTextStyles.sectionTitle` |
| Judul kartu | `AppTextStyles.cardTitle` |
| Isi reguler | `AppTextStyles.body` |
| Keterangan/metadata | `AppTextStyles.supporting` |
| Angka utama | `AppTextStyles.metric` |

- Jangan menambah ukuran font manual untuk judul, kartu, atau teks pendukung
  yang umum. Pengecualian hanya untuk PDF, tabel rapat, badge sangat kecil, dan
  angka yang harus menyesuaikan lebar kartu.
- Pertahankan warna dari `AppColors`, kartu putih, dan radius kartu yang telah
  ditetapkan tema. Jangan mengubah satu halaman secara terpisah bila token
  global bisa digunakan.
- Saat menambah section, gunakan hierarki yang sama: satu judul halaman,
  judul section, judul kartu, lalu keterangan. Nilai uang boleh memakai
  `AppTextStyles.metric`, tetapi labelnya harus `supporting`.

## Data dan fitur yang sudah tersedia

Data spreadsheet tidak dibaca langsung oleh browser. Edge Function mengambil
sumber, membuat snapshot ringkas di Supabase, dan Flutter membaca snapshot
tersebut agar pencarian cepat.

| Area | Server / snapshot | Catatan penting |
| --- | --- | --- |
| Gudang | `sync-warehouse-data` | Snapshot stok, penerimaan, dan alat. |
| Pusat Dokumen | `ask-technical-documents` | Folder Drive ada di `AppConfig.technicalDocumentsFolderUrl`; tombol buka Drive adalah fallback bila AI bermasalah. |
| PM | `sync-preventive-maintenance` | PM dikelompokkan per crew dan lokasi CPP/PORT; kartu membuka daftar layar penuh. |
| CM | `sync-corrective-maintenance` | CM dikelompokkan CPP/PORT, mempunyai pencarian nama/pekerjaan/aset/lokasi dan progres terakhir. |
| Anggaran | `sync-operational-budget` | Asam-Asam, nilai USD, Januari–Juni 2026; budget CPP sheet `3271 (Mtc)`, PORT `3275 (Mtc)`. Data detail disimpan di `operational_budget_item` dan ringkasan bulan di `operational_budget_month`. |
| Data PR | `sync-purchase-requisitions` | Snapshot `purchase_requisition`. Cari No. PR/PO/deskripsi/equipment reference; filter periode rilis tersedia. Urutan default dan pilihan urut menggunakan **No. PR terbaru/terlama**, bukan Close Date. Close Date tetap dipakai sebagai informasi barang datang. |
| Referensi Equipment | Data Flutter terkompresi | Snapshot dari workbook Drive `Asamasam.xlsx` (121 unit) dan `Kintap.xlsx` (185 unit). Cari equipment reference, deskripsi, status, tipe, atau account code; tombol sumber Drive menjadi fallback saat data perlu diperbarui. |

Sumber URL/ID spreadsheet yang aktif berada di masing-masing Edge Function
`supabase/functions/sync-*`; jangan memindahkan URL ini ke Flutter.

## Penyimpanan Supabase Free

- Free plan memiliki kuota storage ketat. Hindari mengunggah APK multi-ABI atau
  asset duplikat tanpa kebutuhan nyata.
- Bucket foto notulen dan bukti reminder tetap privat/RLS. Jangan menghapus
  file pengguna hanya untuk menghemat ruang tanpa persetujuan.
- Jika dashboard storage tidak langsung turun setelah penghapusan, penggunaan
  dapat dihitung sebagai rata-rata periode penagihan; cek kembali pada siklus
  berikutnya sebelum melakukan tindakan tambahan.

## Checklist perubahan

### Ekspor Excel MOM

- Modul Meeting Minutes menggunakan label/pesan Inggris termasuk metadata
  Excel. Isi bebas pengguna tidak diterjemahkan otomatis.
- Due date opsional saat menyelesaikan MOM; kosong ditampilkan `Not set`.
- Kolom A, D, E, F, G, H rata tengah; B/C rata kiri. Foto dipusatkan
  horizontal dan vertikal dalam tinggi barisnya.

- SpreadsheetML memakai atribut tinggi baris `ht`, bukan `height`. Atribut
  salah diabaikan Excel dan membuat foto melampaui baris.
- Sel harus diserialisasi berurutan A sampai H; urutan pembuatan sel di kode
  dapat berbeda. Urutan XML yang salah membuat nomor/isu tidak terbaca Excel.
- Foto memakai ukuran proporsional dalam kolom D, maksimal dua foto sejajar.
  Baris foto 126 pt, judul 60 pt. Uji regresi memeriksa tinggi dan urutan sel.

1. Periksa `git status` dan versi aplikasi; jangan menyentuh perubahan atau
   folder lokal milik pengguna.
2. Gunakan `AppTextStyles` untuk UI baru dan pertahankan alur navigasi serta
   role/RLS yang ada.
3. Jalankan `flutter analyze` dan `flutter test` dari `flutter_app/`.
4. Untuk perubahan website: `flutter build web --release`, pastikan build
   selesai, deploy dengan Wrangler ke project `sicatat`, lalu cek website.
5. Jalankan `git diff --check`, commit perubahan yang relevan, dan push ke
   `origin/master`.
