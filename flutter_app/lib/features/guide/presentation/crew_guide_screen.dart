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
            title: 'H. Akses dan koneksi',
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
            'SICATAT field guide',
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
              'A. Temperature recording',
              'Open the Temperature tab, then select New sheet. Choose the inspection date and the correct shift. One sheet is used for one date, shift, and site combination only.',
            ),
            const _GuideSection(
              'B. Complete Round 1 and Round 2',
              'Choose the unit and its West or East side, then save each side. The round time is recorded automatically with the first saved data. A sheet can remain a draft and be continued before the shift ends.',
            ),
            const _GuideSection(
              'C. Select the unit condition',
              'Choose Operating to record every temperature point. If the unit is Not operating or Not accessible, enter the reason. Do not use a temperature value instead of the required reason.',
            ),
            const _GuideSection(
              'D. Check the temperature colours',
              'Green means below 60°C. Orange means 60–69°C and needs attention. Red means 70°C or above and must be reported immediately under the operating procedure.',
            ),
            const _GuideSection(
              'E. Sheet summary and submission',
              'Open Sheet summary to review completed and missing sections. Tap a red card to open the missing data. Submit only when the data is ready; verified sheets are locked.',
            ),
            const _GuideSection(
              'F. Operational reminders',
              'Users with Reminder access can add a title, asset, action, PIC, location, due date, priority, recipients, and email schedule. Select weekly, monthly, or a custom number of days before the due date.',
            ),
            const _GuideSection(
              'G. Completing a reminder',
              'When an action is complete, tap Mark complete and add a note if needed. Use Reopen when the work must be opened again. Use the history icon to view email deliveries and changes.',
            ),
            const _GuideSection(
              'H. Access and connection',
              'SICATAT is online-only. The available menus follow the account role and site scope. If data cannot load, check the internet connection and tap Refresh; do not uninstall the application.',
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
