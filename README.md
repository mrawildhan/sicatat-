# SICATAT — Repository History & Current Flutter App

> The active application is the Flutter project in [`flutter_app/`](flutter_app/),
> not the legacy Capacitor/vanilla-JS prototype in the repository root. Start
> every new development session by reading [`CLAUDE.md`](CLAUDE.md) and
> [`docs/PRD-SICATAT-v0.5.md`](docs/PRD-SICATAT-v0.5.md). The legacy notes below
> are retained only for historical reference and must not be used as the current
> build or deployment instructions.

## Legacy Capacitor prototype (historical only)

## Ini kode belum pernah dijalankan

Saya menulis seluruh file ini tanpa akses internet, jadi **belum pernah**
di-`npm install`, di-build, atau dites di perangkat/emulator manapun.
Anggap ini draf kuat, bukan kode siap pakai. Langkah pertama Bapak bukan
"pakai", tapi "jalankan dan perbaiki error yang muncul" — itu wajar untuk
kode yang belum pernah dieksekusi sama sekali.

## Langkah setup (di laptop Bapak, yang ada internetnya)

### 1. Install dependency
```bash
cd sicatat
npm install
```

### 2. Buat project Supabase
1. Daftar di https://supabase.com, buat project baru (pilih region Singapore, paling dekat).
2. Buka **SQL Editor** di dashboard, tempel isi `supabase/schema.sql`, jalankan.
3. Buka **Project Settings > API**, salin `Project URL` dan `anon public key`.
4. Tempel keduanya ke `www/js/lib/supabase-client.js` (ganti `GANTI-DENGAN-...`).

### 3. Isi data awal (manual, lewat Supabase Table Editor)
Sebelum aplikasi bisa dipakai, minimal harus ada:
- 1 baris di `module` (code: `temperature_check`)
- 1 baris di `form_template` (module_id merujuk ke atas, version: `v0.4`)
- 4 baris di `equipment` (Feeder Breaker, Hydraulic Pump 1, Hydraulic Pump 2, Heat Exchanger)
- 4 baris di `measurement_point` untuk titik gearbox (`gb_low_speed`, `gb_intermediate`, `gb_high_speed`, `gb_input_shaft`)
- 2 baris di `shift` (Pagi, Malam)
- 3 baris di `team` (A, B, C)
- 1 baris di `roster_anchor`
- Minimal 1 akun di `app_user` dengan role `admin`, supaya ada yang bisa login pertama kali

Ini **belum ada layar admin** untuk mengisi ini lewat aplikasi (lihat "Yang belum dikerjakan" di bawah) — untuk sekarang isi manual lewat Table Editor Supabase.

### 4. Jalankan di browser dulu (paling cepat untuk development)
```bash
npm run dev
```
Buka `http://localhost:5173`. **Catatan:** SQLite lokal (`@capacitor-community/sqlite`) tidak jalan di browser biasa tanpa plugin web-nya — untuk uji coba awal alur UI, kemungkinan perlu mock sementara `db.js`, atau langsung lompat ke langkah 5 (Android).

### 5. Bungkus jadi APK Android
```bash
npx cap add android
npx cap sync android
npx cap open android
```
Ini akan membuka Android Studio. Dari sana, jalankan ke emulator atau HP fisik yang tersambung USB dengan USB debugging aktif.

**Prasyarat yang perlu diinstal dulu (kalau belum ada):** Node.js LTS, Android Studio, Java JDK 17.

## Yang sudah dikerjakan

- Struktur project (Capacitor + vanilla JS, sesuai keputusan hybrid app di PRD Bagian 10)
- Skema database lengkap (`supabase/schema.sql`) — server
- Skema database lokal (`www/js/lib/local-schema.sql`) — SQLite di HP
- Lapisan data offline-first (`db.js`) dengan pola `client_uuid` + `sync_queue` sesuai rancangan
- Sync engine kerangka (`sync-engine.js`) — **belum diuji jaringan sungguhan**
- Router sederhana tanpa framework
- Login (NIK) — **PIN belum diverifikasi sungguhan, lihat komentar TODO di `auth.js`**
- Beranda dengan menu per peran (Crew/Foreman/Supervisor/Admin)
- Menu Temperature
- Daftar Lembar (draft tidak kedaluwarsa)
- Input Gearbox Breaker per sisi, termasuk **logika status "Belum diisi" (FR-26a)** — ini bagian paling saya perhatikan detailnya, karena ini justifikasi utama aplikasi ini dibuat

## Yang BELUM dikerjakan (prioritas mengerjakan berikutnya)

Urutan ini saya susun berdasarkan prioritas P0 di PRD, bukan asal:

1. **Verifikasi PIN sungguhan** (`auth.js`) — saat ini PIN diketik tapi tidak dicek. Ini lubang keamanan, jangan sampai kepakai ke lapangan seperti ini. Sarankan pakai Supabase Auth.
2. **Layar Gearbox Sizer** (ronde × sisi + Motor/Bearing/Timing) — pola kodenya bisa banyak dicontek dari `breakerInput.js`, tapi field-nya beda (lihat wireframe Layar 4/4b).
3. **Layar Ringkasan & Submit** (`findUnansweredSides()` di `db.js` sudah siap dipakai, tinggal dibuatkan UI-nya — lihat wireframe Layar 5)
4. **Layar Nama Crew Pengisi** (wireframe Layar 4c)
5. **Jalur override Foreman/Supervisor** (wireframe Layar 5b) — termasuk logika role-check pakai `requireRole()` di `auth.js`
6. **Layar Monitoring "Belum Lengkap"** dengan filter tim untuk Foreman (wireframe Layar 6)
7. **Layar Admin** untuk kelola master data (equipment, threshold, shift, team, roster, user) — supaya langkah 3 di atas tidak perlu manual lewat Supabase Table Editor terus-terusan
8. **Auto-saran shift & regu dari roster (FR-73)** — saat ini `sheetList.js` masih hardcode `TODO-shift-id-dari-roster`
9. **Pengecekan versi aplikasi (FR-56/57)** — belum ada sama sekali
10. **Ekspor PDF & Excel** (FR-62/63)
11. Uji offline sungguhan: matikan WiFi HP, isi beberapa lembar, nyalakan lagi, pastikan `sync-engine.js` benar-benar mengirim semuanya tanpa duplikat

## Keputusan desain yang perlu diingat saat melanjutkan

- **Jangan pernah tulis langsung ke SQLite/Supabase dari file `screens/*.js`.** Semua lewat `db.js`. Ini yang membuat nanti gampang dites dan gampang diganti kalau ada perubahan skema.
- **Status unit (`unit_status.status`) boleh `null`.** Itu bukan bug — itu representasi "Belum diisi" yang jadi jantung validasi submit (FR-45).
- **client_uuid dibuat di HP, bukan di server.** Jangan pernah biarkan server yang generate ID utama untuk data yang bisa dibuat offline.
