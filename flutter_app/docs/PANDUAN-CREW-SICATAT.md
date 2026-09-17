# Panduan pengguna SICATAT

Panduan yang selalu terbaru ada di dalam aplikasi: **Beranda → Panduan pengguna**. Dari layar itu juga tersedia tombol **Unduh PDF Bahasa Indonesia**. Berkas ini dibuat otomatis dari isi yang sama; bila berbeda, yang di aplikasi yang benar.

> Catatan untuk pengembang: isi panduan disimpan sekali saja di `lib/features/guide/guide_content.dart`. Setelah mengubahnya, cetak ulang `docs/Panduan-Pengguna-SICATAT.pdf` dengan `dart run tool/generate_guide_pdf.dart` dari folder `flutter_app/`, lalu samakan berkas ini.

## Dasar penggunaan

- **Masuk aplikasi.** Masuk dengan NIK dan kata sandi masing-masing; kata sandi awal berupa PIN dari admin. Jangan berbagi kata sandi. Akun dibuat oleh admin; tidak ada pendaftaran sendiri.
- **Menemukan menu.** Ada empat tab di bawah layar: Beranda, Operasional, Referensi, dan Profil. Operasional berisi pekerjaan harian, Referensi berisi data yang dicari saat dibutuhkan. Menu yang muncul mengikuti peran dan lokasi akun Anda.
- **Harus online.** SICATAT hanya bekerja secara online. Bila data gagal dimuat, periksa koneksi lalu ketuk Muat ulang. Jangan menghapus aplikasi.

## Suhu

- **Membuat lembar.** Buka Operasional lalu Suhu, pilih Daily Temperature Feeder Sizer, pilih Lembar baru, kemudian pilih tanggal inspeksi dan shift yang benar. Satu lembar hanya untuk satu kombinasi tanggal, shift, modul, dan lokasi. Kombinasi yang sama akan ditolak.
- **Ronde 1 dan Ronde 2.** Pilih unit serta sisi Barat atau Timur, lalu simpan setiap sisi. Waktu ronde tercatat otomatis saat data pertama disimpan. Lembar boleh tetap draf dan dilanjutkan sebelum shift berakhir.
- **Kondisi unit.** Pilih Beroperasi untuk mengisi seluruh titik suhu. Bila unit Tidak beroperasi atau Tidak dapat diakses, isi alasannya dan titik suhu dikosongkan.
- **Warna suhu.** Hijau di bawah 60 derajat C. Kuning 60 sampai 69 derajat C dan perlu perhatian. Merah 70 derajat C atau lebih, laporkan segera sesuai prosedur.
- **Nilai tidak wajar.** Nilai di luar -50 sampai 250 derajat C harus dikonfirmasi dan diberi catatan. Catatan itu hanya menempel pada angka yang tidak wajar, bukan pada seluruh ronde.
- **Ringkasan dan kirim.** Buka Ringkasan lembar untuk melihat bagian yang belum lengkap, lalu ketuk kartu merah untuk langsung membuka data yang kurang. Lembar yang sudah dikirim bersifat final; pembuatnya masih dapat membuka kembali untuk revisi, sedangkan lembar lama yang terverifikasi terkunci.

## Hydraulic Feeder dan Coal Valve

- **Tiga pilihan Suhu.** Menu Suhu kini berisi tiga lembar: Daily Temperature Feeder Sizer, Daily Check Sheet Hydraulic Feeder, dan Temperature Coal Valve. Nama menunya berbahasa Inggris sesuai formulir kertas, sedangkan isinya berbahasa Indonesia. Setiap lembar hanya satu per tanggal dan shift.
- **Daily Check Sheet Hydraulic Feeder.** Ada tiga pengecekan per shift: shift pagi pukul 10.00, 14.00, dan 18.00; shift malam pukul 22.00, 02.00, dan 06.00. Isi Feeder 1 lalu Feeder 2: suhu (Ambient temp, Main pump, Hydraulic motor, Flushing valve P1/P2/T, Heat exchanger A/B/C), tekanan (Forward, Charge, Case, Vacuum), dan Feeder speed bila ada. Nama titik ukur mengikuti istilah di formulir kertas. Bila feeder Tidak beroperasi atau Tidak dapat diakses, cukup isi alasannya.
- **Temperature Coal Valve.** Ada empat pembacaan per shift, sama dengan formulir kertas. Setiap pembacaan berisi suhu RV01 sampai RV04 di Sisi Barat, Timur, Utara, dan Selatan. Jam pembacaan tercatat otomatis saat pertama kali disimpan.
- **Menyimpan, mengirim, dan mencetak.** Anggota regu yang sama dapat mengisi lembar yang sama. Kartu merah berarti masih ada nilai kosong. Kirim lembar membuat lembar final; lembar masih dapat dibuka lewat Buka kembali untuk revisi. Ikon PDF mencetak nilai langsung di atas formulir kertas aslinya (termasuk logo), dengan warna oranye untuk 60 sampai 69 derajat C dan merah untuk 70 derajat C ke atas.

## Laporan dan ekspor

- **Ekspor satu lembar.** Dari ringkasan lembar, pilih ikon ekspor untuk melihat pratinjau PDF atau mengunduh CSV. PDF memakai warna suhu; CSV tidak dapat berwarna sehingga memakai kolom Peringatan Suhu.
- **Laporan periode.** Laporan Periode menggabungkan beberapa tanggal sekaligus. Pilih rentang tanggal dan regu, lalu ekspor PDF atau CSV. Judulnya menyebut jumlah lembar yang berisi data beserta jumlah barisnya.
- **Suhu tinggi.** Menampilkan pembacaan 60 derajat C ke atas dari seluruh lembar, supaya yang berisiko ditangani lebih dulu.
- **Lembar belum lengkap.** Daftar lembar yang masih punya isian kosong, agar tidak ada yang tertinggal di akhir shift.

## Pengingat

- **Membuat pengingat.** Isi judul, kategori, aset, nomor dokumen, instansi, tindakan, penanggung jawab, lokasi, prioritas, dan tanggal berakhir. Pengingat adalah menu admin.
- **Jadwal email.** Pilih mingguan, bulanan, atau jumlah hari sendiri sebelum jatuh tempo. Email dikirim tepat pada hari itu saja, bukan setiap hari, dan hanya untuk pengingat yang belum lewat jatuh tempo.
- **Lampiran dokumen.** Lampirkan PDF, JPG, JPEG, atau PNG. Foto dikompres otomatis supaya hemat penyimpanan; PDF maksimal 2 MB, kecilkan dulu bila lebih besar.
- **Menyelesaikan pengingat.** Ketuk Tandai selesai, isi catatan bila perlu, lalu unggah minimal satu bukti. Gunakan Buka kembali bila pekerjaan ternyata belum tuntas.
- **Pengingat berulang.** Bila pengingat diatur berulang, siklus berikutnya dibuat otomatis setelah yang sekarang ditandai selesai.
- **Peringatan email.** Server memeriksa izin pengiriman email setiap hari. Bila kotak merah muncul di layar Pengingat, email tidak akan terkirim sampai izin Gmail diperbarui admin.

## Notulen rapat

- **Membuat notulen.** Isi judul, tanggal, jam, lokasi, peserta, dan pembahasan. Notulen dapat disimpan sebagai draf dulu sebelum dilengkapi.
- **Rencana tindakan.** Tambahkan rencana tindakan beserta penanggung jawab dan tenggatnya. Setiap rencana dapat diberi maksimal dua foto, dan fotonya dikompres otomatis sebelum diunggah.
- **Tindak lanjut.** Gunakan Tindak lanjut untuk membuat notulen lanjutan yang membawa rencana tindakan yang belum selesai.
- **Ekspor Excel.** Ikon di kanan atas mengunduh notulen dalam format Excel, lengkap dengan foto rencana tindakan.

## Anggaran dan pekerjaan

- **Anggaran Operasional.** Menampilkan anggaran dan realisasi per elemen biaya beserta sisanya. Angkanya mengikuti lembar kerja sumber dan hanya dapat dibaca.
- **PM & CM Tertunda.** Daftar pekerjaan preventif dan korektif yang belum selesai, dipisah per kru dan lokasi.
- **Data PR.** Cari Purchase Requisition dan PO berdasarkan nomor atau uraian. Urutan No. PR terbaru memakai angka, bukan abjad. Bila hasilnya lebih dari 60 baris, daftar diakhiri catatan supaya kata kunci dipersempit.
- **Permintaan Barang.** Mengajukan kebutuhan barang untuk LV, COP, dan Drilling, boleh dilengkapi link produk dan foto barang. Permintaan yang sudah dibuat tidak dapat dihapus, jadi periksa dulu sebelum menyimpan.

## Gudang

- **Mencari stok.** Ketik minimal dua karakter untuk mencari nama item, kode SC, atau lokasi bin. Daftar memang kosong sebelum ada pencarian.
- **Melihat detail.** Ketuk kartu item untuk melihat kode SC, lokasi, lokasi bin, satuan, stok, harga unit, serta tanggal pembaruan lembar kerja.
- **Stok dan alat.** Tab Stok & harga untuk barang, tab Alat untuk peralatan. Filter lokasi mempersempit hasil.
- **Hasil terlalu banyak.** Hanya 100 item pertama yang ditampilkan. Bila catatan itu muncul di akhir daftar, persempit kata kunci atau pilih gudang tertentu.

## Pusat Dokumen dan referensi

- **Bertanya ke Pusat Dokumen.** Tulis pertanyaan memakai kata yang dipakai di dokumen, misalnya nama pekerjaan, nomor SOP, atau nama unit. Jawaban hanya diambil dari berkas di folder dokumen, bukan dari internet.
- **Membaca jawaban.** Di bawah jawaban selalu ada daftar sumber. Buka berkas aslinya sebelum dipakai sebagai dasar pekerjaan. Jawaban biasanya butuh 10 sampai 25 detik karena dokumennya dibaca lebih dulu.
- **Kode Biaya.** Mencari struktur dan elemen biaya beserta referensinya.
- **Referensi Alat.** Mencari data unit Asamasam dan Kintap.

## Profil dan aplikasi

- **Ganti kata sandi.** Buka Profil lalu Ganti kata sandi. Kata sandi baru minimal delapan karakter, gabungan huruf dan angka. Setelah berhasil, semua perangkat lain ikut keluar dan harus masuk lagi.
- **Memperbarui Android.** Buka Profil, pilih Pembaruan aplikasi, ketuk Periksa pembaruan, lalu Unduh dan pasang bila tersedia. Izinkan pemasangan saat Android meminta. Tidak perlu menghapus aplikasi lama.
- **Versi web.** Versi web tidak perlu diperbarui manual. Bila tampilan terasa tertinggal, muat ulang halaman.

## Untuk admin

- **Data master.** Kelola lokasi, shift, regu, rotasi regu, peralatan, titik ukur, dan templat formulir. Data master tidak dapat dihapus, hanya dinonaktifkan, supaya riwayat lama tetap terbaca.
- **Batas suhu.** Atur batas peringatan dan alarm per titik ukur. Angkanya wajib valid, batas peringatan harus lebih kecil dari alarm, dan sumber acuan wajib diisi.
- **Pengguna.** Tambah pengguna baru lewat Data master & pengguna. Pembuatan akun membutuhkan PIN awal dan hanya dapat dilakukan admin aktif.
