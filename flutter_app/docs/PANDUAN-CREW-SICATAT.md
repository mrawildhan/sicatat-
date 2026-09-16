# Panduan pengguna SICATAT

Panduan yang selalu terbaru ada di dalam aplikasi: **Beranda → Panduan pengguna**. Dari layar itu juga tersedia tombol **Unduh PDF Bahasa Indonesia**. Isi berkas ini mengikuti kelompok yang sama; bila berbeda, yang di aplikasi yang benar.

> Catatan untuk pengembang: isi panduan disimpan sekali saja di `lib/features/guide/presentation/crew_guide_screen.dart` (`_guideGroups`), dipakai bersama oleh layar dan PDF. Perbarui daftar itu, lalu samakan berkas ini. `Panduan-Crew-SICATAT.pdf` di folder ini adalah cetakan lama; pakai unduhan dari aplikasi.

## Dasar penggunaan

- **Masuk aplikasi.** Masuk dengan NIK dan PIN masing-masing. Jangan berbagi PIN. Akun dibuat oleh admin; tidak ada pendaftaran sendiri.
- **Menemukan menu.** Ada empat tab di bawah layar: Beranda, Operasional, Referensi, dan Profil. Menu yang muncul mengikuti peran dan site akun.
- **Harus online.** SICATAT hanya bekerja saat ada internet. Bila data gagal dimuat, periksa koneksi lalu ketuk Muat ulang. Jangan menghapus aplikasi.

## Suhu

- **Membuat sheet.** Operasional → Suhu → Buat sheet. Pilih tanggal inspeksi dan shift yang benar. Satu sheet hanya untuk satu kombinasi tanggal, shift, modul, dan site; kombinasi yang sama akan ditolak.
- **Ronde 1 dan Ronde 2.** Pilih unit serta sisi Barat atau Timur, lalu simpan setiap sisi. Waktu ronde tercatat otomatis saat data pertama disimpan. Sheet boleh tetap draf dan dilanjutkan sebelum shift berakhir.
- **Kondisi unit.** Pilih Beroperasi untuk mengisi seluruh titik suhu. Bila Tidak beroperasi atau Tidak dapat diakses, isi alasannya dan titik suhu dikosongkan.
- **Warna suhu.** Hijau di bawah 60 °C. Kuning 60 sampai 69 °C dan perlu perhatian. Merah 70 °C atau lebih, laporkan segera sesuai prosedur.
- **Nilai tidak wajar.** Nilai di luar −50 sampai 250 °C harus dikonfirmasi dan diberi catatan. Catatan hanya menempel pada angka yang tidak wajar, bukan pada seluruh ronde.
- **Ringkasan dan kirim.** Ringkasan sheet menandai bagian yang belum lengkap; ketuk kartu merah untuk membukanya. Sheet yang sudah dikirim bersifat final, pembuatnya masih dapat membuka kembali untuk revisi, sedangkan sheet lama yang terverifikasi terkunci.

## Laporan dan ekspor

- **Ekspor satu sheet.** Dari ringkasan sheet, ikon ekspor membuka pratinjau PDF atau mengunduh CSV. PDF memakai warna suhu; CSV memakai kolom `Temperature Alert`.
- **Laporan periode.** Menu Laporan menggabungkan beberapa tanggal. Pilih rentang tanggal dan regu, lalu ekspor PDF atau CSV.
- **Suhu tinggi.** Menampilkan pembacaan 60 °C ke atas dari seluruh sheet.
- **Sheet belum lengkap.** Daftar sheet yang masih punya isian kosong.

## Pengingat

- **Membuat pengingat.** Isi judul, kategori, aset, nomor dokumen, instansi, tindakan, penanggung jawab, lokasi, prioritas, dan tanggal berakhir. Pengingat adalah menu admin.
- **Jadwal email.** Mingguan, bulanan, atau jumlah hari sendiri sebelum jatuh tempo. Email dikirim tepat pada hari itu saja, dan hanya untuk pengingat yang belum lewat jatuh tempo.
- **Lampiran dokumen.** PDF, JPG, JPEG, atau PNG. Foto dikompres otomatis; PDF maksimal 2 MB.
- **Menyelesaikan pengingat.** Tandai selesai, isi catatan bila perlu, unggah minimal satu bukti. Gunakan Buka kembali bila pekerjaan belum tuntas.
- **Pengingat berulang.** Siklus berikutnya dibuat otomatis setelah yang sekarang ditandai selesai.
- **Peringatan email.** Server memeriksa izin pengiriman email setiap hari. Kotak merah di layar Pengingat berarti email tidak akan terkirim sampai izin Gmail diperbarui admin.

## Notulen rapat

- **Membuat notulen.** Isi judul, tanggal, jam, lokasi, peserta, dan pembahasan. Bisa disimpan sebagai draf dulu.
- **Rencana tindakan.** Tambahkan penanggung jawab dan tenggat. Maksimal dua foto per rencana, dikompres otomatis sebelum diunggah.
- **Tindak lanjut.** Membuat notulen lanjutan yang membawa rencana tindakan yang belum selesai.
- **Ekspor Excel.** Ikon di kanan atas mengunduh notulen beserta foto rencana tindakan.

## Anggaran dan pekerjaan

- **Anggaran Operasional.** Anggaran dan realisasi per elemen biaya beserta sisanya, mengikuti spreadsheet sumber, hanya dapat dibaca.
- **Outstanding PM & CM.** Pekerjaan preventif dan korektif yang belum selesai, dipisah per unit dan site.
- **Data PR.** Cari Purchase Requisition dan PO. Urutan No. PR terbaru memakai angka, bukan abjad. Hasil di atas 60 baris diakhiri catatan agar kata kunci dipersempit.
- **Permintaan Barang.** Pengajuan kebutuhan barang LV dan Drilling. Permintaan yang sudah dibuat tidak dapat dihapus.

## Gudang

- **Mencari stok.** Ketik minimal dua karakter: nama item, kode SC, atau lokasi bin. Daftar memang kosong sebelum ada pencarian.
- **Melihat detail.** Ketuk kartu item untuk kode SC, site, lokasi bin, satuan, stok, harga unit, dan tanggal pembaruan spreadsheet.
- **Stok dan alat.** Tab Stok & harga untuk barang, tab Alat untuk peralatan. Filter site mempersempit hasil.
- **Hasil terlalu banyak.** Hanya 100 item pertama ditampilkan; persempit kata kunci atau pilih gudang tertentu.

## Pusat Dokumen dan referensi

- **Bertanya ke Pusat Dokumen.** Gunakan kata yang dipakai di dokumen: nama pekerjaan, nomor SOP, atau nama unit. Jawaban hanya diambil dari berkas di folder dokumen, bukan dari internet.
- **Membaca jawaban.** Selalu ada daftar sumber di bawah jawaban; buka berkas aslinya sebelum dipakai sebagai dasar pekerjaan. Jawaban biasanya butuh 10 sampai 25 detik.
- **Cost Code.** Struktur dan elemen biaya beserta referensinya.
- **Equipment Reference.** Data unit Asamasam dan Kintap.

## Profil dan aplikasi

- **Ganti password.** Profil → Ganti password. Minimal delapan karakter, gabungan huruf dan angka. Setelah berhasil, semua perangkat lain ikut keluar.
- **Memperbarui Android.** Profil → Pembaruan aplikasi → Periksa pembaruan → Unduh dan pasang. Izinkan pemasangan saat Android meminta. Tidak perlu menghapus aplikasi lama.
- **Versi web.** Tidak perlu diperbarui manual; muat ulang halaman bila tampilan terasa tertinggal.

## Untuk admin

- **Data master.** Site, shift, regu, rotasi regu, peralatan, titik ukur, dan template formulir. Data master tidak dapat dihapus, hanya dinonaktifkan.
- **Batas suhu.** Batas peringatan dan alarm per titik ukur. Angka wajib valid, peringatan harus lebih kecil dari alarm, sumber acuan wajib diisi.
- **Pengguna.** Tambah pengguna lewat Data master & pengguna. Pembuatan akun membutuhkan PIN awal dan hanya dapat dilakukan admin aktif.
