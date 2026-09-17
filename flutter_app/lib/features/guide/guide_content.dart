import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// One topic inside a guide group.
class GuideEntry {
  const GuideEntry(this.title, this.description);

  final String title;
  final String description;
}

/// A menu-sized group of topics.
class GuideGroupContent {
  const GuideGroupContent({required this.title, required this.entries});

  final String title;
  final List<GuideEntry> entries;
}

const List<GuideGroupContent> guideGroups = <GuideGroupContent>[
  GuideGroupContent(
    title: 'Dasar penggunaan',
    entries: <GuideEntry>[
      GuideEntry(
        'Masuk aplikasi',
        'Masuk dengan NIK dan kata sandi masing-masing; kata sandi awal berupa PIN dari admin. Jangan berbagi kata sandi. Akun dibuat oleh admin; tidak ada pendaftaran sendiri.',
      ),
      GuideEntry(
        'Menemukan menu',
        'Ada empat tab di bawah layar: Beranda, Operasional, Referensi, dan Profil. Operasional berisi pekerjaan harian, Referensi berisi data yang dicari saat dibutuhkan. Menu yang muncul mengikuti peran dan lokasi akun Anda.',
      ),
      GuideEntry(
        'Harus online',
        'SICATAT hanya bekerja secara online. Bila data gagal dimuat, periksa koneksi lalu ketuk Muat ulang. Jangan menghapus aplikasi.',
      ),
    ],
  ),
  GuideGroupContent(
    title: 'Suhu',
    entries: <GuideEntry>[
      GuideEntry(
        'Membuat lembar',
        'Buka Operasional lalu Suhu, pilih Daily Temperature Feeder Sizer, pilih Lembar baru, kemudian pilih tanggal inspeksi dan shift yang benar. Satu lembar hanya untuk satu kombinasi tanggal, shift, modul, dan lokasi. Kombinasi yang sama akan ditolak.',
      ),
      GuideEntry(
        'Ronde 1 dan Ronde 2',
        'Pilih unit serta sisi Barat atau Timur, lalu simpan setiap sisi. Waktu ronde tercatat otomatis saat data pertama disimpan. Lembar boleh tetap draf dan dilanjutkan sebelum shift berakhir.',
      ),
      GuideEntry(
        'Kondisi unit',
        'Pilih Beroperasi untuk mengisi seluruh titik suhu. Bila unit Tidak beroperasi atau Tidak dapat diakses, isi alasannya dan titik suhu dikosongkan.',
      ),
      GuideEntry(
        'Warna suhu',
        'Hijau di bawah 60 derajat C. Kuning 60 sampai 69 derajat C dan perlu perhatian. Merah 70 derajat C atau lebih, laporkan segera sesuai prosedur.',
      ),
      GuideEntry(
        'Nilai tidak wajar',
        'Nilai di luar -50 sampai 250 derajat C harus dikonfirmasi dan diberi catatan. Catatan itu hanya menempel pada angka yang tidak wajar, bukan pada seluruh ronde.',
      ),
      GuideEntry(
        'Ringkasan dan kirim',
        'Buka Ringkasan lembar untuk melihat bagian yang belum lengkap, lalu ketuk kartu merah untuk langsung membuka data yang kurang. Lembar yang sudah dikirim bersifat final; pembuatnya masih dapat membuka kembali untuk revisi, sedangkan lembar lama yang terverifikasi terkunci.',
      ),
    ],
  ),
  GuideGroupContent(
    title: 'Hydraulic Feeder dan Coal Valve',
    entries: <GuideEntry>[
      GuideEntry(
        'Tiga pilihan Suhu',
        'Menu Suhu kini berisi tiga lembar: Daily Temperature Feeder Sizer, Daily Check Sheet Hydraulic Feeder, dan Temperature Coal Valve. Nama menunya berbahasa Inggris sesuai formulir kertas, sedangkan isinya berbahasa Indonesia. Setiap lembar hanya satu per tanggal dan shift.',
      ),
      GuideEntry(
        'Daily Check Sheet Hydraulic Feeder',
        'Ada tiga pengecekan per shift: shift pagi pukul 10.00, 14.00, dan 18.00; shift malam pukul 22.00, 02.00, dan 06.00. Isi Feeder 1 lalu Feeder 2: suhu (ambien, pompa utama, motor hidrolik, katup flushing P1/P2/T, penukar panas A/B/C), tekanan (forward, charge, case, vakum), dan kecepatan feeder bila ada. Bila feeder Tidak beroperasi atau Tidak dapat diakses, cukup isi alasannya.',
      ),
      GuideEntry(
        'Temperature Coal Valve',
        'Ada empat pembacaan per shift, sama dengan formulir kertas. Setiap pembacaan berisi suhu RV01 sampai RV04 di Sisi Barat, Timur, Utara, dan Selatan. Jam pembacaan tercatat otomatis saat pertama kali disimpan.',
      ),
      GuideEntry(
        'Menyimpan, mengirim, dan mencetak',
        'Anggota regu yang sama dapat mengisi lembar yang sama. Kartu merah berarti masih ada nilai kosong. Kirim lembar membuat lembar final; lembar masih dapat dibuka lewat Buka kembali untuk revisi. Ikon PDF mencetak nilai langsung di atas formulir kertas aslinya (termasuk logo), dengan warna oranye untuk 60 sampai 69 derajat C dan merah untuk 70 derajat C ke atas.',
      ),
    ],
  ),
  GuideGroupContent(
    title: 'Laporan dan ekspor',
    entries: <GuideEntry>[
      GuideEntry(
        'Ekspor satu lembar',
        'Dari ringkasan lembar, pilih ikon ekspor untuk melihat pratinjau PDF atau mengunduh CSV. PDF memakai warna suhu; CSV tidak dapat berwarna sehingga memakai kolom Peringatan Suhu.',
      ),
      GuideEntry(
        'Laporan periode',
        'Laporan Periode menggabungkan beberapa tanggal sekaligus. Pilih rentang tanggal dan regu, lalu ekspor PDF atau CSV. Judulnya menyebut jumlah lembar yang berisi data beserta jumlah barisnya.',
      ),
      GuideEntry(
        'Suhu tinggi',
        'Menampilkan pembacaan 60 derajat C ke atas dari seluruh lembar, supaya yang berisiko ditangani lebih dulu.',
      ),
      GuideEntry(
        'Lembar belum lengkap',
        'Daftar lembar yang masih punya isian kosong, agar tidak ada yang tertinggal di akhir shift.',
      ),
    ],
  ),
  GuideGroupContent(
    title: 'Pengingat',
    entries: <GuideEntry>[
      GuideEntry(
        'Membuat pengingat',
        'Isi judul, kategori, aset, nomor dokumen, instansi, tindakan, penanggung jawab, lokasi, prioritas, dan tanggal berakhir. Pengingat adalah menu admin.',
      ),
      GuideEntry(
        'Jadwal email',
        'Pilih mingguan, bulanan, atau jumlah hari sendiri sebelum jatuh tempo. Email dikirim tepat pada hari itu saja, bukan setiap hari, dan hanya untuk pengingat yang belum lewat jatuh tempo.',
      ),
      GuideEntry(
        'Lampiran dokumen',
        'Lampirkan PDF, JPG, JPEG, atau PNG. Foto dikompres otomatis supaya hemat penyimpanan; PDF maksimal 2 MB, kecilkan dulu bila lebih besar.',
      ),
      GuideEntry(
        'Menyelesaikan pengingat',
        'Ketuk Tandai selesai, isi catatan bila perlu, lalu unggah minimal satu bukti. Gunakan Buka kembali bila pekerjaan ternyata belum tuntas.',
      ),
      GuideEntry(
        'Pengingat berulang',
        'Bila pengingat diatur berulang, siklus berikutnya dibuat otomatis setelah yang sekarang ditandai selesai.',
      ),
      GuideEntry(
        'Peringatan email',
        'Server memeriksa izin pengiriman email setiap hari. Bila kotak merah muncul di layar Pengingat, email tidak akan terkirim sampai izin Gmail diperbarui admin.',
      ),
    ],
  ),
  GuideGroupContent(
    title: 'Notulen rapat',
    entries: <GuideEntry>[
      GuideEntry(
        'Membuat notulen',
        'Isi judul, tanggal, jam, lokasi, peserta, dan pembahasan. Notulen dapat disimpan sebagai draf dulu sebelum dilengkapi.',
      ),
      GuideEntry(
        'Rencana tindakan',
        'Tambahkan rencana tindakan beserta penanggung jawab dan tenggatnya. Setiap rencana dapat diberi maksimal dua foto, dan fotonya dikompres otomatis sebelum diunggah.',
      ),
      GuideEntry(
        'Tindak lanjut',
        'Gunakan Tindak lanjut untuk membuat notulen lanjutan yang membawa rencana tindakan yang belum selesai.',
      ),
      GuideEntry(
        'Ekspor Excel',
        'Ikon di kanan atas mengunduh notulen dalam format Excel, lengkap dengan foto rencana tindakan.',
      ),
    ],
  ),
  GuideGroupContent(
    title: 'Anggaran dan pekerjaan',
    entries: <GuideEntry>[
      GuideEntry(
        'Anggaran Operasional',
        'Menampilkan anggaran dan realisasi per elemen biaya beserta sisanya. Angkanya mengikuti lembar kerja sumber dan hanya dapat dibaca.',
      ),
      GuideEntry(
        'PM & CM Tertunda',
        'Daftar pekerjaan preventif dan korektif yang belum selesai, dipisah per kru dan lokasi.',
      ),
      GuideEntry(
        'Data PR',
        'Cari Purchase Requisition dan PO berdasarkan nomor atau uraian. Urutan No. PR terbaru memakai angka, bukan abjad. Bila hasilnya lebih dari 60 baris, daftar diakhiri catatan supaya kata kunci dipersempit.',
      ),
      GuideEntry(
        'Permintaan Barang',
        'Mengajukan kebutuhan barang untuk LV, COP, dan Drilling, boleh dilengkapi link produk dan foto barang. Permintaan yang sudah dibuat tidak dapat dihapus, jadi periksa dulu sebelum menyimpan.',
      ),
    ],
  ),
  GuideGroupContent(
    title: 'Gudang',
    entries: <GuideEntry>[
      GuideEntry(
        'Mencari stok',
        'Ketik minimal dua karakter untuk mencari nama item, kode SC, atau lokasi bin. Daftar memang kosong sebelum ada pencarian.',
      ),
      GuideEntry(
        'Melihat detail',
        'Ketuk kartu item untuk melihat kode SC, lokasi, lokasi bin, satuan, stok, harga unit, serta tanggal pembaruan lembar kerja.',
      ),
      GuideEntry(
        'Stok dan alat',
        'Tab Stok & harga untuk barang, tab Alat untuk peralatan. Filter lokasi mempersempit hasil.',
      ),
      GuideEntry(
        'Hasil terlalu banyak',
        'Hanya 100 item pertama yang ditampilkan. Bila catatan itu muncul di akhir daftar, persempit kata kunci atau pilih gudang tertentu.',
      ),
    ],
  ),
  GuideGroupContent(
    title: 'Pusat Dokumen dan referensi',
    entries: <GuideEntry>[
      GuideEntry(
        'Bertanya ke Pusat Dokumen',
        'Tulis pertanyaan memakai kata yang dipakai di dokumen, misalnya nama pekerjaan, nomor SOP, atau nama unit. Jawaban hanya diambil dari berkas di folder dokumen, bukan dari internet.',
      ),
      GuideEntry(
        'Membaca jawaban',
        'Di bawah jawaban selalu ada daftar sumber. Buka berkas aslinya sebelum dipakai sebagai dasar pekerjaan. Jawaban biasanya butuh 10 sampai 25 detik karena dokumennya dibaca lebih dulu.',
      ),
      GuideEntry(
        'Kode Biaya',
        'Mencari struktur dan elemen biaya beserta referensinya.',
      ),
      GuideEntry('Referensi Alat', 'Mencari data unit Asamasam dan Kintap.'),
    ],
  ),
  GuideGroupContent(
    title: 'Profil dan aplikasi',
    entries: <GuideEntry>[
      GuideEntry(
        'Ganti kata sandi',
        'Buka Profil lalu Ganti kata sandi. Kata sandi baru minimal delapan karakter, gabungan huruf dan angka. Setelah berhasil, semua perangkat lain ikut keluar dan harus masuk lagi.',
      ),
      GuideEntry(
        'Memperbarui Android',
        'Buka Profil, pilih Pembaruan aplikasi, ketuk Periksa pembaruan, lalu Unduh dan pasang bila tersedia. Izinkan pemasangan saat Android meminta. Tidak perlu menghapus aplikasi lama.',
      ),
      GuideEntry(
        'Versi web',
        'Versi web tidak perlu diperbarui manual. Bila tampilan terasa tertinggal, muat ulang halaman.',
      ),
    ],
  ),
  GuideGroupContent(
    title: 'Untuk admin',
    entries: <GuideEntry>[
      GuideEntry(
        'Data master',
        'Kelola lokasi, shift, regu, rotasi regu, peralatan, titik ukur, dan templat formulir. Data master tidak dapat dihapus, hanya dinonaktifkan, supaya riwayat lama tetap terbaca.',
      ),
      GuideEntry(
        'Batas suhu',
        'Atur batas peringatan dan alarm per titik ukur. Angkanya wajib valid, batas peringatan harus lebih kecil dari alarm, dan sumber acuan wajib diisi.',
      ),
      GuideEntry(
        'Pengguna',
        'Tambah pengguna baru lewat Data master & pengguna. Pembuatan akun membutuhkan PIN awal dan hanya dapat dilakukan admin aktif.',
      ),
    ],
  ),
];

/// Builds the downloadable guide.
///
/// Deliberately free of Flutter imports so `dart run tool/generate_guide_pdf.dart`
/// can regenerate `docs/Panduan-Pengguna-SICATAT.pdf` from the same content the
/// app shows. Text avoids characters outside the built-in font, which is why
/// the temperature entries read "derajat C".
Future<Uint8List> buildGuidePdfBytes() async {
  final pw.Document document = pw.Document();
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(42),
      build: (_) => <pw.Widget>[
        pw.Text(
          'Panduan pengguna SICATAT',
          style: const pw.TextStyle(
            fontSize: 22,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Disusun per menu aplikasi, mengikuti urutan pada layar Panduan pengguna.',
          style: const pw.TextStyle(fontSize: 11),
        ),
        pw.SizedBox(height: 18),
        ...guideGroups.expand(
          (GuideGroupContent group) => <pw.Widget>[
            pw.Text(
              group.title,
              style: const pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 6),
            ...group.entries.expand(
              (GuideEntry entry) => <pw.Widget>[
                pw.Text(
                  entry.title,
                  style: const pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  entry.description,
                  style: const pw.TextStyle(fontSize: 10.5),
                ),
                pw.SizedBox(height: 8),
              ],
            ),
            pw.SizedBox(height: 8),
          ],
        ),
      ],
    ),
  );
  return document.save();
}
