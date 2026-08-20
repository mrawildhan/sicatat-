# PRD SICATAT v0.5 — Kondisi Implementasi & Acuan Pemulihan

| Informasi | Nilai |
|---|---|
| Produk | SICATAT — Sistem Inspeksi dan Catatan Temperatur |
| Status | Acuan implementasi saat ini / recovery specification |
| Tanggal | 20 Agustus 2026 |
| Versi aplikasi | `2.1.2+212` |
| Menggantikan | PRD-SICATAT-v0.4.md |
| Fokus rilis saat ini | Daily Temperature Check: Gearbox Breaker dan Gearbox Sizer |

> Dokumen ini adalah sumber kebenaran untuk membangun ulang SICATAT bila source code, APK, atau percakapan sebelumnya tidak tersedia. Ia membedakan **fitur yang benar-benar sudah ada**, **aturan bisnis yang wajib dipertahankan**, dan **rencana yang belum dikerjakan**. PRD v0.4 tidak boleh dipakai sebagai fakta implementasi tanpa membandingkannya dengan dokumen ini.

## 1. Ringkasan produk

SICATAT adalah aplikasi Flutter berbasis Supabase untuk mencatat inspeksi temperatur peralatan oleh crew lapangan. Rilis saat ini menangani pemeriksaan harian Gearbox Breaker dan Gearbox Sizer dalam dua round pada setiap shift, menyimpan draft ke server, menghindari duplikasi sheet, memberikan ringkasan kelengkapan, dan menghasilkan laporan PDF/CSV.

Aplikasi bersifat **online-only**. Data penting harus dikirim ke Supabase; SQLite lokal dipakai sebagai cache dan antrian sinkronisasi yang tahan terhadap gangguan singkat, bukan sebagai mode kerja offline yang dijanjikan kepada pengguna. Halaman Sheet Summary memakai matriks empat kartu ringkas (Breaker/Sizer × Round 1/2) agar status utama dan tombol Submit dapat terlihat pada satu layar ponsel normal; detail tetap tersedia saat kartu diketuk.

Tujuan operasionalnya adalah memastikan pembacaan temperatur kritis tidak terlewat, dapat ditelusuri berdasarkan tanggal/shift/crew, serta mudah dibaca oleh supervisor atau boss melalui laporan yang rapi.

## 2. Cara memakai dokumen ini untuk membangun ulang

Simpan dokumen ini bersama repository. Bila proyek perlu dibuat ulang, gunakan instruksi awal berikut kepada pengembang/agen:

```text
Bangun atau pulihkan aplikasi Flutter SICATAT persis sesuai docs/PRD-SICATAT-v0.5.md.
Pertahankan login Supabase, aplikasi online-only, seluruh aturan bisnis, serta fungsi yang
sudah ditandai Implemented. Audit source dan schema dahulu; jangan menghapus data Supabase,
jangan memasukkan service-role key ke aplikasi, dan jangan mengubah aturan satu sheet per
module/tanggal/shift. Setelah implementasi, jalankan analyze, test, dan pengujian alur
end-to-end sampai ekspor PDF.
```

Lokasi penting dalam repository:

| Artefak | Lokasi |
|---|---|
| Aplikasi Flutter | `flutter_app/` |
| Skema awal Supabase | `supabase/schema.sql` |
| Migrasi pencegah sheet duplikat | `supabase/migrations/20260819_prevent_duplicate_shift_sheets.sql` |
| Skema SQLite lokal | `flutter_app/assets/sql/local_schema.sql` |
| Konfigurasi aplikasi | `flutter_app/lib/core/config/app_config.dart` |
| APK Android release terakhir | `flutter_app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` |

Rahasia seperti Supabase URL/anon key boleh disuntik lewat `--dart-define` atau konfigurasi aman yang setara. Jangan menaruh service-role key, password, atau kredensial produksi di PRD, source mobile, atau repository publik.

## 3. Pengguna, peran, dan otorisasi

| Peran | Tanggung jawab dan akses utama |
|---|---|
| Crew | Membuat sheet untuk shift, mengisi atau melanjutkan draft, melihat sheet miliknya, mengirim sheet, dan merevisi sheet yang belum diverifikasi. |
| Foreman | Memantau sheet tim dan melihat laporan temperatur tinggi/lembar belum lengkap. |
| Supervisor | Akses monitoring dan laporan operasional setara atau di atas foreman. |
| Admin | Melihat seluruh sheet, mengelola user, team, shift, roster, equipment, measurement point, threshold, reminder, laporan periode, dan ekspor. |

Login menggunakan NIK dan PIN melalui Supabase Auth/data pengguna aplikasi. Sesi dipulihkan ketika aplikasi dibuka kembali. Profil menampilkan nama, NIK/crew ID, peran, team, telepon bila ada, serta tombol logout; profil tidak boleh menjadi halaman kosong.

Visibilitas sheet wajib dipertahankan:

- Crew hanya melihat sheet yang dibuatnya.
- Foreman melihat data monitoring untuk team yang menjadi tanggung jawabnya.
- Admin melihat seluruh sheet yang tersedia di server.

## 4. Aturan bisnis yang wajib dipertahankan

### 4.1 Tanggal dan shift

- Tanggal inspeksi dipilih manual saat **New sheet**. Tanggal lampau diperbolehkan untuk kasus lupa input; rentang UI saat ini 2024–2035.
- Shift Pagi adalah 07:00–19:00 dan Shift Malam adalah 19:00–07:00. Master shift dapat dikelola admin, tetapi arti operasional dua shift ini wajib dipertahankan kecuali ada keputusan bisnis baru.
- Satu team menggunakan satu sheet untuk sebuah tanggal dan shift. Namun mekanisme aplikasi saat ini lebih ketat: untuk kombinasi **module + tanggal + shift hanya boleh ada satu sheet secara global**, agar crew lain tidak membuat data ganda.
- Pencegahan duplikasi dilakukan dua lapis: preflight di Flutter dan trigger PostgreSQL `prevent_duplicate_shift_sheet()` dengan migrasi `20260819_prevent_duplicate_shift_sheets.sql`. Jangan menghapus trigger ini. Konflik database harus ditampilkan sebagai pesan yang jelas, bukan error teknis mentah.

### 4.2 Round, draft, dan waktu

Alur modul temperatur saat ini memiliki empat langkah tetap:

1. Gearbox Breaker — Round 1 (B R1)
2. Gearbox Sizer — Round 1 (S R1)
3. Gearbox Breaker — Round 2 (B R2)
4. Gearbox Sizer — Round 2 (S R2)

- Waktu setiap round **otomatis memakai jam saat pertama kali round disimpan/diisi**. Pengguna tidak memilih waktu round secara manual.
- Waktu round berlaku untuk sisi West dan East pada round tersebut.
- Tanggal sheet tetap tanggal yang dipilih saat New sheet; ia tidak berubah karena jam input aktual.
- Input boleh dilewati sementara. Tombol Next harus tetap menyimpan draft dan maju ke langkah berikutnya, bukan memaksa semua temperatur terisi.
- Draft dapat dibuka lagi, termasuk setelah crew mengisi Round 1 pagi hari lalu melanjutkan Round 2 sebelum pulang.
- Semua perubahan draft harus disimpan lokal lalu diantrikan untuk sinkronisasi ke Supabase secara idempoten menggunakan UUID klien.

### 4.3 Kelengkapan, submit, dan revisi

- Halaman Sheet Summary menampilkan semua empat bagian dan statusnya: terisi/operating atau belum terisi.
- Item belum lengkap memiliki tombol merah/tegas yang dapat diketuk dan mengarahkan pengguna tepat ke langkah/input yang belum lengkap.
- Bila ada input yang belum lengkap, submit normal tidak boleh menyatakan sheet lengkap. Ringkasan harus menjelaskan bagian yang masih tertinggal.
- Admin/role berwenang dapat melakukan override submit incomplete bila diperlukan. Status harus jelas sebagai `submitted_incomplete`, bukan tersamarkan sebagai data lengkap.
- Status sheet yang digunakan: `draft`, `submitted`, `submitted_incomplete`, `verified`, dan `returned`.
- Pembuat sheet dapat membuka kembali `submitted` atau `submitted_incomplete` untuk koreksi sebelum verifikasi. Aksi ini mengembalikan sheet ke draft dan mengosongkan `submitted_at`.
- Foreman, supervisor, atau admin dapat memilih **Verify** atau **Return** pada sheet yang telah dikirim. Return wajib beralasan dan dicatat dalam audit trail.
- Sheet `verified` terkunci bagi crew dan di tingkat database. Perubahan setelah verifikasi harus melalui proses return/revision yang berjejak audit, bukan mengubah data diam-diam.

### 4.4 Status unit dan pembacaan temperatur

Setiap sisi gearbox memiliki status unit:

- Operating
- Not operating
- Not accessible

UI status harus menggunakan tombol penuh/vertikal dengan teks yang tidak terpotong pada layar Android kecil. Jika Operating dipilih, pembacaan temperatur terkait wajib untuk dianggap lengkap. Jika Not operating atau Not accessible dipilih, alasan/keterangan wajib disediakan sesuai konfigurasi formulir.

Tidak boleh ada nilai temperatur kritis yang tersamar. Laporan menggunakan warna berikut:

| Nilai temperatur | Warna laporan |
|---|---|
| Di bawah 60°C | Hijau |
| 60–69°C | Oranye/peringatan |
| 70°C atau lebih | Merah/kritis |

Master threshold kini dibaca per measurement point pada form. Nilai warning, critical, atau di luar rentang fisik `-50` sampai `250°C` memerlukan konfirmasi dan catatan anomali sebelum disimpan. Batas fallback tetap 60°C (warning) dan 70°C (critical) untuk point yang belum memiliki threshold aktif.

## 5. Bentuk formulir temperatur saat ini

### 5.1 Gearbox Breaker

Setiap Round Gearbox Breaker memuat kelompok berikut.

| Equipment | Pembacaan/field utama |
|---|---|
| Feeder Breaker | Motor DE, Motor NDE, Drum East, Drum West, Oil Level (OK/Low), Gear Box, Remark opsional |
| Hydraulic Pump 1 | Motor DE, Motor NDE, Chain Head, Chain Tail, Remark opsional |
| Hydraulic Pump 2 | Motor DE, Motor NDE, Chain Head, Chain Tail, Remark opsional |
| Heat Exchanger | Motor DE, Motor NDE, Remark opsional |

Bagian Temperature Gearbox Breaker memiliki tab West dan East, pemilihan status unit, serta empat point: Low speed, Intermediate, High speed, dan Input shaft.

### 5.2 Gearbox Sizer

Setiap Round Gearbox Sizer memuat kelompok berikut.

| Equipment | Pembacaan/field utama |
|---|---|
| Motor | Motor DE, Motor NDE, Oil Level (OK/Low), Remark opsional |
| Bearing | Motor DE, Motor NDE, Remark opsional |
| Timing | Motor DE, Motor NDE, Remark opsional |

Bagian Temperature Gearbox Sizer juga memiliki West/East, status unit, dan empat point: Low speed, Intermediate, High speed, dan Input shaft.

Catatan penting: equipment dan measurement point aktif dibaca dinamis dari master data; admin juga dapat mengatur urutan round 1–2 lewat Temperature Form Template. Penambahan section/modul temperature baru yang memiliki perilaku berbeda masih memerlukan pengembangan form builder generik. Lihat roadmap bagian 12.

## 6. Pengalaman pengguna dan navigasi

Semua halaman inti wajib memiliki jalur kembali yang masuk akal ke halaman aplikasi sebelumnya/utama. Tombol Back Android tidak boleh menutup aplikasi atau langsung kembali ke home screen saat pengguna masih berada dalam alur SICATAT.

Rute utama yang telah ada:

| Rute | Fungsi | Akses |
|---|---|---|
| `/login` | Login NIK/PIN | Publik |
| `/dashboard` | Beranda aplikasi | Semua user login |
| `/sheets` | My sheets / daftar sheet | Semua user login, terfilter per peran |
| `/sheets/new` | Buat sheet baru | Crew dan user berwenang |
| `/temperature` | Input empat langkah temperature | User dengan sheet aktif |
| `/summary` | Ringkasan, kelengkapan, submit/revisi | Pembuat/role berwenang |
| `/monitoring` | Monitoring sheet | Foreman, supervisor, admin |
| `/incomplete` | Lembar belum lengkap | Foreman, supervisor, admin |
| `/high-temperature` | Laporan temperatur tinggi | Foreman, supervisor, admin |
| `/sheet-export` | Ekspor sheet PDF/CSV | Semua user sesuai hak sheet |
| `/reports` | Laporan periode PDF/CSV | Admin |
| `/admin` dan sub-rute | Master data dan administrasi | Admin |
| `/reminders` | Pengingat admin | Admin |
| `/users` | Kelola user | Admin |

`AppBackScope` dan `AppBackButton` dipakai agar perilaku Back konsisten. Setiap halaman baru yang ditambahkan wajib memakai pola yang sama dan dites menggunakan tombol Back Android fisik/sistem.

## 7. Arsitektur teknis

| Lapisan | Implementasi |
|---|---|
| Client | Flutter/Dart, Material 3, Riverpod, go_router |
| Backend | Supabase: Auth dan PostgreSQL |
| Penyimpanan lokal | SQLite untuk cache dan antrian sync |
| Konektivitas | `connectivity_plus` dan probe backend Supabase |
| PDF dan share | Paket `pdf`, `printing`, `share_plus` |
| Android | Application ID `id.sicatat.app`, minimum SDK 24 (Android 7) |
| iOS | Target Flutter tersedia, tetapi distribusi IPA/TestFlight produksi belum disiapkan |

### 7.1 Online-only yang tidak mengganggu

`OnlineOnlyGate` berada pada level aplikasi. Ia memeriksa status jaringan dan keterjangkauan backend. Saat jaringan benar-benar tidak tersedia, layar menjelaskan bahwa SICATAT membutuhkan internet dan menyediakan tombol Try again.

Agar tidak mengganggu pengguna yang sebenarnya tersambung, pemeriksaan latar belakang dilakukan sekitar satu menit sekali dan overlay baru muncul setelah tiga kegagalan berturut-turut. Jangan mengubah kembali menjadi notifikasi error berulang setiap beberapa detik.

SQLite tetap menyimpan perubahan yang baru dibuat dan antrian sync untuk kegagalan singkat, tetapi UI/produk tidak boleh menjanjikan workflow offline penuh. Setelah koneksi kembali, `SyncCoordinator` mengirim perubahan yang tertunda.

### 7.2 Struktur data

Master data di Supabase mencakup `module`, `form_template`, `equipment`, `measurement_point`, `threshold`, `shift`, `team`, `roster_anchor`, `app_version`, dan `app_user`.

Data transaksi mencakup `sheet`, `sheet_contributor`, `round`, `unit_status`, `reading`, `attachment`, dan `audit_log`. Tidak semua tabel yang telah tersedia sudah memiliki UI penuh—attachment dan audit log khususnya merupakan fondasi untuk tahap berikutnya.

Prinsip sinkronisasi:

- Setiap object yang dibuat client memiliki `client_uuid` agar pengiriman ulang tidak menciptakan duplikat.
- Database lokal menyimpan cache sheet, round, unit status, reading, master data, dan `sync_queue`.
- Urutan sinkronisasi harus menghormati relasi sheet → round/status → reading.
- Admin melakukan cache header sheet seluruh server untuk tampilan My sheets; crew hanya menerima/melihat sheet miliknya sesuai kebijakan akses.

### 7.3 Keamanan dan operasional

- Gunakan anon key publik hanya dari aplikasi; jangan pernah memakai service-role key di APK.
- RLS/policy Supabase, otorisasi peran, dan akses antar-team harus diaudit sebelum rollout produksi besar. Jangan menganggap schema saja sudah otomatis aman.
- Backup berkala database Supabase dan simpan release keystore Android secara aman. Kehilangan keystore menghambat update APK dengan package yang sama.
- `app_version` dipakai untuk menampilkan pemberitahuan atau memblokir aplikasi versi lama. Proses rilis wajib memperbarui metadata ini secara terkendali.

## 8. Laporan dan ekspor

### 8.1 Ekspor sheet

Pengguna dapat mengekspor sheet sesuai hak akses sebagai PDF atau CSV. PDF sheet terbaru didesain sebagai laporan ringkas satu halaman yang layak dibaca manajemen:

- header identitas sheet (tanggal, shift, crew, status),
- metrik jumlah pembacaan, nilai maksimum, jumlah warning, dan jumlah critical,
- indikator distribusi temperatur,
- tabel pembacaan ringkas,
- warna hijau/oranye/merah untuk temperatur sesuai bagian 4.4.

Halaman harus terisi proporsional dan tidak menyisakan area kosong besar. Jika data terlalu panjang, prioritasnya adalah keterbacaan: ringkas tabel, gunakan section/metric/chart kecil yang bermakna, lalu tambah halaman hanya bila benar-benar diperlukan.

### 8.2 Laporan administrasi

- Admin memiliki laporan periode dalam PDF/CSV.
- Foreman/supervisor/admin memiliki laporan temperatur tinggi dan daftar sheet belum lengkap.
- PDF harus menampilkan data apa adanya. Validasi angka abnormal sebelum submit penting karena laporan dapat memperlihatkan angka salah ketik, misalnya `6363`, dengan benar tetapi tetap keliru secara operasional.

## 9. Yang sudah dikerjakan

### Implemented dan harus dipertahankan

- [x] Login Supabase NIK/PIN, session restore, dan role user.
- [x] Aplikasi online-only dengan gate koneksi, tombol retry, manifest Android `INTERNET` serta `ACCESS_NETWORK_STATE`.
- [x] Peredaman false alarm koneksi: cek berkala dan tiga kegagalan berturut-turut sebelum gate muncul.
- [x] Dashboard, profile yang berisi informasi user, dan logout.
- [x] Navigasi Back aplikasi untuk halaman inti, termasuk penggunaan tombol Back Android.
- [x] My sheets dengan visibilitas crew sendiri dan admin seluruh sheet.
- [x] New sheet dengan tanggal lampau, Shift Pagi/Malam, dan crew dari akun login.
- [x] Pencegahan sheet duplikat secara aplikasi dan trigger Supabase untuk module/tanggal/shift.
- [x] Empat langkah temperatur: Breaker R1, Sizer R1, Breaker R2, Sizer R2.
- [x] Waktu round otomatis saat pertama pengisian, tanpa input jam manual.
- [x] Draft/lanjutkan entry, penyimpanan lokal, sync queue, dan sinkronisasi Supabase.
- [x] Input terpisah untuk equipment dan gearbox West/East dengan Operating, Not operating, Not accessible.
- [x] Next tetap dapat dipakai untuk draft yang belum lengkap.
- [x] Sheet Summary ringkas: empat kartu Breaker/Sizer × Round 1/2, status lengkap/belum lengkap, kartu merah menuju input yang tertinggal, detail per bagian saat diketuk, submit normal, dan override incomplete untuk role berwenang.
- [x] Revisi oleh pembuat sebelum sheet verified.
- [x] Aksi Verify/Return untuk foreman, supervisor, dan admin; return beralasan serta audit trail lokal/server.
- [x] Penguncian database untuk sheet verified melalui migrasi `20260820_verified_sheet_lock.sql`.
- [x] Validasi temperatur per point dari master threshold, konfirmasi nilai warning/critical/tidak masuk akal, serta flag/note anomali pada reading dan CSV.
- [x] Form membaca equipment/measurement point aktif tanpa whitelist kode; admin dapat mengatur urutan round 1–2 lewat Temperature form template.
- [x] Master data admin: user, team, shift, roster, equipment, measurement point, dan threshold.
- [x] Reminder sementara khusus admin.
- [x] Monitoring, incomplete sheets, high-temperature report, serta laporan admin periode.
- [x] Ekspor sheet PDF/CSV dan laporan PDF/CSV.
- [x] Desain PDF satu halaman dengan penanda suhu 60°C+ dan 70°C+ pada ekspor sheet maupun laporan periode; CSV memuat kolom `Temperature Alert` karena format CSV tidak menyimpan warna sel.
- [x] Pemeriksaan versi aplikasi dari Supabase.
- [x] Branding icon SICATAT dan build APK Android release per ABI.
- [x] `flutter analyze` bersih dan `flutter test` lulus pada rilis `2.1.2+212`.

### Ada fondasi, tetapi belum selesai sebagai produk penuh

- [~] Form saat ini dinamis untuk equipment/point dan urutan Round 1–2 pada dua section Breaker/Sizer. Penambahan section atau module dengan perilaku yang berbeda masih memerlukan pengembangan form builder generik.
- [~] PDF memakai warna fallback 60/70°C; pewarnaan PDF per point sepenuhnya dari master threshold belum diselesaikan.
- [~] Reminder admin tersedia sebagai konfigurasi/pengarah email, belum berupa scheduler/push notification terjamin.
- [~] Tabel `attachment` dan `audit_log` tersedia di schema, tetapi alur upload foto dan penelusuran audit UI belum lengkap.
- [~] Target iOS Flutter tersedia, tetapi belum ada signing, IPA, TestFlight, dan uji perangkat iOS produksi.

## 10. Batasan yang sengaja berlaku sekarang

- SICATAT bukan aplikasi offline-first. Jangan menghapus ketergantungan server atau mengganti perilaku menjadi offline tanpa keputusan bisnis baru.
- APK Android tidak dapat dipasang di iPhone. Untuk iOS diperlukan Mac, Xcode, Apple Developer Program, signing, lalu distribusi lewat TestFlight/App Store atau perangkat terdaftar.
- Modul operasional yang siap pakai baru Daily Temperature Check Gearbox Breaker/Sizer. Fitur lain harus ditambahkan dengan pendekatan template yang aman.
- Tidak ada janji push notification, integrasi IoT, CMMS/ERP, pemindaian QR, atau lampiran foto pada rilis ini.

## 11. Build, deployment, dan pengujian pemulihan

### 11.1 Prasyarat

- Flutter dan Android SDK yang kompatibel dengan proyek.
- Java/Gradle yang disyaratkan Flutter Android saat build.
- Project Supabase yang memiliki schema awal, migration, user, master data, dan RLS/policy yang sudah diuji.
- Perangkat Android fisik dengan internet untuk uji Supabase nyata.

### 11.2 Menyiapkan database baru

1. Buat project Supabase baru dan terapkan `supabase/schema.sql`.
2. Jalankan migrasi `supabase/migrations/20260819_prevent_duplicate_shift_sheets.sql` dan `supabase/migrations/20260820_verified_sheet_lock.sql`.
3. Buat akun admin, team, shift Pagi/Malam, roster, module/template, equipment, measurement point, dan threshold yang diperlukan.
4. Konfigurasikan URL dan anon key aplikasi melalui mekanisme konfigurasi aman.
5. Uji RLS menggunakan akun crew, foreman, dan admin sebelum data lapangan dipakai.

### 11.3 Perintah build utama

```powershell
Set-Location D:\Arutmin\Project\sicatat\flutter_app
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

APK untuk mayoritas perangkat Android modern adalah `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`. Jangan menyerahkan build debug sebagai rilis lapangan kecuali untuk pengujian internal.

### 11.4 Checklist black-box minimum

1. Login dengan crew, foreman, dan admin; cek pembatasan menu masing-masing.
2. Putuskan internet: gate muncul setelah kegagalan yang konsisten; sambungkan kembali: Try again membuka aplikasi tanpa notifikasi berulang.
3. Crew membuat Sheet Pagi pada tanggal hari ini, mengisi sebagian Round 1, keluar/masuk lagi, lalu melanjutkan draft.
4. Pastikan waktu Round 1 tersimpan otomatis dan tidak bisa diedit manual.
5. Lanjutkan ke Round 2 meski field belum lengkap; tombol Next harus bekerja dan summary menandai kekurangan.
6. Ketuk item merah di summary; harus menuju langkah/input yang sesuai.
7. Buat sheet yang sama dari akun lain untuk module/tanggal/shift sama; harus ditolak dengan pesan duplikasi yang jelas.
8. Buat sheet tanggal kemarin untuk Shift Malam; harus diizinkan bila kombinasi belum ada.
9. Submit lengkap, buka kembali sebagai pembuat, revisi sebelum verified; pastikan status kembali draft dan data tersinkron.
10. Pastikan sheet verified tidak dapat diedit crew.
11. Cek My sheets: crew hanya melihat miliknya, admin melihat semua, foreman sesuai team.
12. Uji tombol Back halaman list, new sheet, form, incomplete, users, dan admin memakai tombol Back Android.
13. Isi nilai 59, 60, 69, dan 70°C; ekspor PDF dan periksa warna hijau, oranye, oranye, merah.
14. Periksa PDF di perangkat nyata: header, metrik, tabel, dan penanda warna dapat dibaca serta tidak ada halaman kosong yang tidak perlu.

## 12. Rekomendasi pengembangan berikutnya

### Prioritas 0 — keselamatan data dan kesiapan operasi

1. **Validasi angka abnormal dan alert per point.** Batasi format angka (misalnya tidak menerima `6363` tanpa konfirmasi), definisikan rentang normal per measurement point, wajibkan alasan untuk outlier, dan beri indikator critical sebelum submit.
2. **Workflow verifikasi yang lengkap.** Tambahkan inbox supervisor/admin untuk Verify atau Return, alasan return, siapa/kapan melakukan aksi, serta riwayat audit yang terlihat. Setelah verified, data harus immutable kecuali melalui return terkontrol.
3. **Hardening Supabase.** Audit RLS untuk semua peran, tes akses lintas crew/team, backup terjadwal, pemulihan data, dan pengelolaan keystore/signing rilis.

### Prioritas 1 — perluasan yang paling bernilai

4. **Ubah formulir menjadi template-driven.** Refactor langkah dan field yang sekarang hard-coded menjadi konfigurasi template/module/equipment/measurement point. Ini adalah dasar agar temperature equipment lain dapat ditambahkan tanpa membuat layar baru dari nol, sambil tetap mempertahankan validasi kuat.
5. **Dashboard tren dan tindakan.** Tampilkan tren per point/equipment, top temperature tertinggi, jumlah sheet incomplete, dan daftar tindakan untuk nilai warning/critical. Grafik harus menghasilkan keputusan, bukan sekadar hiasan.
6. **Lampiran bukti.** Tambahkan foto thermal camera/nameplate bila suhu tinggi, dengan kompresi, hak akses, dan retensi data yang jelas.
7. **Notifikasi yang benar-benar terjadwal.** Setelah aturan kepemilikan reminder disepakati, kirim pengingat ke admin terlebih dahulu melalui push/email/scheduler server. Jangan mengandalkan mail composer perangkat sebagai pengingat kritis.

### Prioritas 2 — skala dan integrasi

8. **Dukungan iOS/TestFlight.** Siapkan signing, bundle identifier, privasi, perangkat uji, dan distribusi TestFlight setelah versi Android stabil.
9. **QR code aset dan integrasi CMMS/ERP.** Scan peralatan untuk membuka history, lalu kirim temuan kritis ke work order bila proses maintenance sudah siap.
10. **Integrasi sensor/IoT.** Gunakan sebagai pelengkap, bukan pengganti inspeksi crew, dan pertahankan sumber, waktu, serta kualitas data sensor.

## 13. Keputusan produk yang perlu disepakati sebelum ekspansi

- Apakah satu sheet tetap eksklusif global per module/tanggal/shift, atau kelak perlu kolaborasi multi-crew dalam sheet yang sama? Jangan melonggarkan constraint tanpa desain contributor dan audit yang jelas.
- Siapa yang memiliki otoritas verifikasi: foreman, supervisor, atau admin? Tentukan SLA dan alasan return standar.
- Apa rentang temperatur aman per titik, batas warning/critical, serta tindakan wajib saat nilai tinggi? Nilai ini sebaiknya berasal dari engineering/reliability, bukan asumsi UI.
- Untuk jenis temperature tambahan, apakah layoutnya seragam dengan Breaker/Sizer atau memerlukan template berbeda? Jawaban ini menentukan desain form builder.
- Berapa lama data dan foto disimpan, siapa dapat mengunduh PDF, dan apakah laporan perlu tanda tangan digital?

## 14. Changelog dokumen

### v0.5 — 20 Agustus 2026

- Mengubah PRD menjadi acuan implementasi aktual dan recovery specification.
- Menegaskan aplikasi online-only, bukan offline-first.
- Mendokumentasikan empat round temperature, auto timestamp, draft, sheet summary, revisi, dan constraint sheet duplikat.
- Mendokumentasikan role visibility, navigasi Back, profile, reporting/PDF satu halaman, dan status build Android.
- Memisahkan fitur selesai dari fondasi yang belum menjadi workflow produk penuh.
- Menambahkan checklist build/black-box serta roadmap pengembangan yang diprioritaskan.
- Pembaruan implementasi `2.1.0+210`: validasi anomali, Verify/Return/audit trail, template round, dan database lock verified.
- Pembaruan implementasi `2.1.1+211`: perbaikan Add User, penanda suhu tinggi PDF/CSV, serta Sheet Summary ringkas berbasis empat kartu.
- Pembaruan implementasi `2.1.2+212`: optimasi tinggi halaman Sheet Summary untuk review cepat di perangkat ponsel.
