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
                title: const Text('Unduh PDF Bahasa Indonesia'),
                subtitle: const Text(
                  'Simpan panduan untuk dibaca tanpa membuka aplikasi',
                ),
                trailing: const Icon(Icons.download_rounded),
                onTap: _downloadIndonesianPdf,
              ),
            ),
            const SizedBox(height: 12),
            const _GuideGroup(
              title: 'Suhu',
              icon: Icons.thermostat_rounded,
              initiallyExpanded: true,
              sections: <_GuideEntry>[
                _GuideEntry(
                  'Pencatatan',
                  'Buka menu Suhu, lalu pilih Buat sheet. Pilih tanggal inspeksi dan shift yang benar. Satu sheet digunakan untuk satu kombinasi tanggal, shift, modul, dan site.',
                ),
                _GuideEntry(
                  'Round 1 dan Round 2',
                  'Pilih unit serta sisi West atau East, kemudian simpan setiap sisi. Waktu round tercatat otomatis saat data pertama disimpan. Sheet dapat tetap berupa draf dan dilanjutkan sebelum shift berakhir.',
                ),
                _GuideEntry(
                  'Kondisi unit',
                  'Pilih Beroperasi untuk mengisi seluruh titik suhu. Jika unit Tidak beroperasi atau Tidak dapat diakses, isi alasannya.',
                ),
                _GuideEntry(
                  'Warna suhu',
                  'Hijau berarti di bawah 60°C. Oranye berarti 60–69°C dan perlu perhatian. Merah berarti 70°C atau lebih dan harus segera dilaporkan.',
                ),
                _GuideEntry(
                  'Ringkasan dan kirim',
                  'Buka Ringkasan sheet untuk meninjau bagian yang lengkap atau belum lengkap. Ketuk kartu merah untuk membuka data yang masih kurang. Sheet yang diverifikasi akan terkunci.',
                ),
              ],
            ),
            const _GuideGroup(
              title: 'Pengingat',
              icon: Icons.notifications_none_rounded,
              sections: <_GuideEntry>[
                _GuideEntry(
                  'Membuat pengingat',
                  'Pengguna dengan akses Pengingat dapat menambahkan judul, aset, tindakan, PIC, lokasi, jatuh tempo, prioritas, penerima, dan jadwal email.',
                ),
                _GuideEntry(
                  'Menyelesaikan pengingat',
                  'Setelah pekerjaan selesai, ketuk Tandai selesai dan isi catatan bila perlu. Gunakan Buka kembali bila pekerjaan perlu dilanjutkan.',
                ),
              ],
            ),
            const _GuideGroup(
              title: 'Gudang',
              icon: Icons.inventory_2_outlined,
              sections: <_GuideEntry>[
                _GuideEntry(
                  'Mencari stok',
                  'Buka Gudang, lalu ketik minimal dua karakter untuk mencari nama item, kode SC, atau lokasi bin. Gunakan filter gudang bila perlu.',
                ),
                _GuideEntry(
                  'Melihat detail',
                  'Ketuk kartu item untuk melihat kode SC, site, lokasi bin, satuan, stok, harga unit, serta tanggal pembaruan spreadsheet.',
                ),
              ],
            ),
            const _GuideGroup(
              title: 'Profil dan aplikasi',
              icon: Icons.person_outline_rounded,
              sections: <_GuideEntry>[
                _GuideEntry(
                  'Ganti password',
                  'Buka Profil lalu pilih Ganti password. Buat password baru minimal delapan karakter dengan gabungan huruf dan angka.',
                ),
                _GuideEntry(
                  'Memperbarui Android',
                  'Buka Profil, pilih Pembaruan aplikasi, lalu ketuk Periksa pembaruan. Jika ada versi baru, pilih Unduh dan pasang.',
                ),
                _GuideEntry(
                  'Akses dan koneksi',
                  'SICATAT digunakan saat online. Jika data tidak dapat dimuat, periksa internet lalu ketuk Muat ulang.',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideEntry {
  const _GuideEntry(this.title, this.description);

  final String title;
  final String description;
}

class _GuideGroup extends StatelessWidget {
  const _GuideGroup({
    required this.title,
    required this.icon,
    required this.sections,
    this.initiallyExpanded = false,
  });

  final String title;
  final IconData icon;
  final List<_GuideEntry> sections;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      leading: CircleAvatar(
        backgroundColor: AppColors.mint,
        child: Icon(icon, color: AppColors.green),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text(
        '${sections.length} panduan',
        style: const TextStyle(color: AppColors.muted, fontSize: 12),
      ),
      children: <Widget>[
        const Divider(height: 1),
        for (final _GuideEntry section in sections)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  section.title,
                  style: const TextStyle(
                    color: AppColors.greenDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  section.description,
                  style: const TextStyle(color: AppColors.muted, height: 1.4),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
      ],
    ),
  );
}
