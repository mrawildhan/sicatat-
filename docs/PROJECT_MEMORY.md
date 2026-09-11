# SICATAT Project Memory

Dokumen ini adalah pegangan singkat bagi pengembang berikutnya. Baca juga
`AGENTS.md`, terutama aturan keamanan dan rilis.

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

1. Periksa `git status` dan versi aplikasi; jangan menyentuh perubahan atau
   folder lokal milik pengguna.
2. Gunakan `AppTextStyles` untuk UI baru dan pertahankan alur navigasi serta
   role/RLS yang ada.
3. Jalankan `flutter analyze` dan `flutter test` dari `flutter_app/`.
4. Untuk perubahan website: `flutter build web --release`, pastikan build
   selesai, deploy dengan Wrangler ke project `sicatat`, lalu cek website.
5. Jalankan `git diff --check`, commit perubahan yang relevan, dan push ke
   `origin/master`.
