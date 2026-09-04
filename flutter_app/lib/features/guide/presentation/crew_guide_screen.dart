import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';

class CrewGuideScreen extends StatelessWidget {
  const CrewGuideScreen({super.key});

  Future<void> _downloadIndonesianPdf() async {
    final pw.Document document = pw.Document();
    const List<({String title, String body})> sections =
        <({String title, String body})>[
          (
            title: 'A. Pencatatan temperatur',
            body: 'Buka menu Temperature lalu pilih New sheet. Pilih tanggal inspeksi dan shift yang benar. Satu sheet hanya digunakan untuk satu kombinasi tanggal, shift, modul, dan site.',
          ),
          (
            title: 'B. Round 1 dan Round 2',
            body: 'Pilih unit serta sisi West atau East, kemudian simpan setiap sisi. Waktu round tercatat otomatis saat data pertama disimpan. Sheet dapat tetap berupa draft dan dilanjutkan sebelum shift berakhir.',
          ),
          (
            title: 'C. Kondisi unit',
            body: 'Pilih Operating untuk mengisi seluruh titik temperatur. Jika unit Not operating atau Not accessible, isi alasannya. Jangan mengganti alasan wajib dengan nilai temperatur.',
          ),
          (
            title: 'D. Warna temperatur',
            body: 'Hijau berarti di bawah 60 C. Oranye berarti 60 sampai 69 C dan perlu perhatian. Merah berarti 70 C atau lebih dan harus segera dilaporkan sesuai prosedur operasi.',
          ),
          (
            title: 'E. Ringkasan dan submit',
            body: 'Buka Sheet summary untuk meninjau bagian yang lengkap atau belum lengkap. Ketuk kartu merah untuk membuka data yang masih kurang. Kirim data hanya jika sudah siap; sheet yang diverifikasi akan terkunci.',
          ),
          (
            title: 'F. Reminder operasional',
            body: 'Pengguna dengan akses Reminder dapat menambahkan judul, aset, tindakan, PIC, lokasi, tanggal jatuh tempo, prioritas, penerima, dan jadwal email. Pilih weekly, monthly, atau jumlah hari custom sebelum jatuh tempo.',
          ),
          (
            title: 'G. Menyelesaikan reminder',
            body: 'Setelah pekerjaan selesai, ketuk Mark complete, isi catatan bila perlu, dan unggah minimal satu bukti PDF, JPG, JPEG, atau PNG. Jika reminder berulang, siklus berikutnya dibuat otomatis sesuai pengaturan repeat.',
          ),
          (
            title: 'H. Mencari stok Warehouse',
            body: 'Buka menu Warehouse lalu ketik minimal dua karakter pada kolom pencarian, misalnya nama item, kode SC, atau lokasi bin. Data stok tidak ditampilkan sebelum pencarian dilakukan. Gunakan filter warehouse bila perlu, lalu pilih Stock & Price untuk melihat stok atau Tools untuk mencari alat.',
          ),
          (
            title: 'I. Melihat detail item Warehouse',
            body: 'Ketuk nama atau kartu item pada hasil pencarian untuk melihat detail yang tersedia dari Google Sheet: kode SC, site, lokasi bin, satuan, stok, harga unit, tanggal pembaruan sheet, dan waktu sinkronisasi. Gunakan tombol Refresh bila hasil belum sesuai setelah sumber data diperbarui.',
          ),
          (
            title: 'J. Ganti password',
            body: 'Buka Profile lalu pilih Ganti password. Masukkan password lama, kemudian buat password baru minimal delapan karakter dengan gabungan huruf dan angka. Setelah berhasil, semua perangkat yang masih login akan dikeluarkan dan Anda perlu masuk kembali dengan password baru.',
          ),
          (
            title: 'K. Memperbarui aplikasi Android',
            body: 'Buka Profile, pilih App updates, lalu ketuk Check update. Bila versi baru tersedia, pilih Download & install dan izinkan pemasangan aplikasi saat Android meminta persetujuan. Pastikan internet stabil; tidak perlu menghapus aplikasi lama.',
          ),
          (
            title: 'L. Akses dan koneksi',
            body: 'SICATAT hanya dapat digunakan saat online. Menu yang tersedia mengikuti peran dan cakupan site akun. Jika data tidak dapat dimuat, periksa koneksi internet dan ketuk Refresh; jangan menghapus aplikasi.',
          ),
        ];
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(42),
        build: (_) => <pw.Widget>[
          pw.Text(
            'Panduan SICATAT',
            style: const pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Panduan penggunaan aplikasi untuk pencatatan temperatur dan reminder operasional.',
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.SizedBox(height: 20),
          ...sections.expand(
            (({String title, String body}) section) => <pw.Widget>[
              pw.Text(
                section.title,
                style: const pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(section.body, style: const pw.TextStyle(fontSize: 10.5)),
              pw.SizedBox(height: 13),
            ],
          ),
        ],
      ),
    );
    final Uint8List bytes = await document.save();
    await Printing.sharePdf(bytes: bytes, filename: 'Panduan-SICATAT.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return AppBackScope(
      fallbackRoute: '/dashboard',
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallbackRoute: '/dashboard'),
          title: const Text(
            'Panduan pengguna SICATAT',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            Card(
              color: AppColors.mint,
              child: ListTile(
                leading: const Icon(
                  Icons.picture_as_pdf_outlined,
                  color: AppColors.green,
                ),
                title: const Text('Download Indonesian PDF'),
                subtitle: const Text('Panduan aplikasi dalam Bahasa Indonesia'),
                trailing: const Icon(Icons.download_rounded),
                onTap: _downloadIndonesianPdf,
              ),
            ),
            const SizedBox(height: 12),
            const _GuideSection(
              'A. Pencatatan temperatur',
              'Buka menu Temperature, lalu pilih New sheet. Pilih tanggal inspeksi dan shift yang benar. Satu sheet digunakan untuk satu kombinasi tanggal, shift, modul, dan site.',
            ),
            const _GuideSection(
              'B. Round 1 dan Round 2',
              'Pilih unit serta sisi West atau East, kemudian simpan setiap sisi. Waktu round tercatat otomatis saat data pertama disimpan. Sheet dapat tetap berupa draft dan dilanjutkan sebelum shift berakhir.',
            ),
            const _GuideSection(
              'C. Kondisi unit',
              'Pilih Operating untuk mengisi seluruh titik temperatur. Jika unit Not operating atau Not accessible, isi alasannya. Jangan mengganti alasan wajib dengan nilai temperatur.',
            ),
            const _GuideSection(
              'D. Warna temperatur',
              'Hijau berarti di bawah 60°C. Oranye berarti 60–69°C dan perlu perhatian. Merah berarti 70°C atau lebih dan harus segera dilaporkan sesuai prosedur operasi.',
            ),
            const _GuideSection(
              'E. Ringkasan dan submit',
              'Buka Sheet summary untuk meninjau bagian yang lengkap atau belum lengkap. Ketuk kartu merah untuk membuka data yang masih kurang. Kirim data hanya jika sudah siap; sheet yang diverifikasi akan terkunci.',
            ),
            const _GuideSection(
              'F. Reminder operasional',
              'Pengguna dengan akses Reminder dapat menambahkan judul, aset, tindakan, PIC, lokasi, tanggal jatuh tempo, prioritas, penerima, dan jadwal email. Pilih weekly, monthly, atau jumlah hari custom sebelum jatuh tempo.',
            ),
            const _GuideSection(
              'G. Menyelesaikan reminder',
              'Setelah pekerjaan selesai, ketuk Mark complete dan isi catatan bila perlu. Gunakan Reopen jika pekerjaan perlu dibuka kembali. Gunakan ikon riwayat untuk melihat pengiriman email dan perubahan.',
            ),
            const _GuideSection(
              'H. Mencari stok Warehouse',
              'Buka Warehouse, lalu ketik minimal dua karakter untuk mencari nama item, kode SC, atau lokasi bin. Hasil stok baru muncul setelah pencarian. Gunakan filter warehouse bila perlu, lalu pilih Stock & Price atau Tools sesuai kebutuhan.',
            ),
            const _GuideSection(
              'I. Detail item Warehouse',
              'Ketuk nama atau kartu item untuk melihat detail dari Google Sheet: kode SC, site, lokasi bin, satuan, stok, harga unit, tanggal pembaruan sheet, dan waktu sinkronisasi.',
            ),
            const _GuideSection(
              'J. Ganti password',
              'Buka Profile lalu pilih Ganti password. Masukkan password lama, kemudian buat password baru minimal delapan karakter dengan gabungan huruf dan angka. Setelah berhasil, semua perangkat yang masih login akan dikeluarkan dan Anda perlu masuk kembali.',
            ),
            const _GuideSection(
              'K. Memperbarui aplikasi Android',
              'Buka Profile, pilih App updates, lalu ketuk Check update. Jika ada versi baru, pilih Download & install dan izinkan pemasangan saat Android meminta persetujuan. Jangan hapus aplikasi lama.',
            ),
            const _GuideSection(
              'L. Akses dan koneksi',
              'SICATAT hanya dapat digunakan saat online. Menu yang tersedia mengikuti peran dan cakupan site akun. Jika data tidak dapat dimuat, periksa koneksi internet dan ketuk Refresh; jangan menghapus aplikasi.',
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideSection extends StatelessWidget {
  const _GuideSection(this.title, this.description);

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: AppColors.greenDark,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(color: AppColors.muted, height: 1.45),
          ),
        ],
      ),
    ),
  );
}
