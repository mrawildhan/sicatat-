import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<void> main() async {
  final document = pw.Document();
  final sections = <(String, List<String>)>[
    (
      'Sebelum mulai',
      <String>[
        'Pastikan baterai cukup dan perangkat pernah terhubung internet untuk memuat data awal.',
        'Masuk menggunakan NIK dan PIN sendiri. Jangan berbagi PIN.',
        'Buat lembar sesuai tanggal dan shift bertugas.',
      ],
    ),
    (
      'Mengisi pemeriksaan',
      <String>[
        'Ikuti urutan: Breaker Ronde 1, Sizer Ronde 1, Breaker Ronde 2, Sizer Ronde 2.',
        'Pada setiap ronde isi sisi Barat dan Timur.',
        'Beroperasi: isi empat suhu gearbox. Tidak operasi atau tidak akses: isi alasan.',
        'Periksa waktu inspeksi sebelum menyimpan sisi.',
        'Setiap sisi yang disimpan langsung dicoba dikirim agar draft dan progres dapat dilihat foreman/admin.',
      ],
    ),
    (
      'Batas perhatian suhu',
      <String>[
        'Hijau: di bawah 60 derajat C.',
        'Kuning: 60 sampai 69,9 derajat C.',
        'Merah: 70 derajat C atau lebih. Laporkan sesuai prosedur operasi setempat.',
      ],
    ),
    (
      'Kirim dan sinkronisasi',
      <String>[
        'Kirim dari Ringkasan setelah seluruh delapan sisi terjawab.',
        'Status Not synced berarti data tetap tersimpan di perangkat dan perlu disinkronkan saat koneksi tersedia.',
        'Jangan hapus aplikasi sebelum status menjadi Synced.',
        'Status Conflict harus dilaporkan ke foreman atau admin.',
      ],
    ),
  ];
  document.addPage(
    pw.MultiPage(
      pageTheme: const pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(40),
      ),
      build: (context) => <pw.Widget>[
        // ignore: prefer_const_constructors
        pw.Text(
          'PANDUAN CREW LAPANGAN',
          style: const pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromInt(0xFF0B3D2E),
          ),
        ),
        // ignore: prefer_const_constructors
        pw.SizedBox(height: 4),
        pw.Text(
          'SICATAT — Daily Temperature Check CPP Asam-Asam',
          style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
        ),
        // ignore: prefer_const_constructors
        pw.SizedBox(height: 22),
        ...sections.expand(
          (section) => <pw.Widget>[
            // ignore: prefer_const_constructors
            pw.Text(
              section.$1,
              style: const pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromInt(0xFF176B4D),
              ),
            ),
            // ignore: prefer_const_constructors
            pw.SizedBox(height: 6),
            ...section.$2.map(
              (item) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 5),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Text('•  '),
                    pw.Expanded(
                      child: pw.Text(
                        item,
                        style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ignore: prefer_const_constructors
            pw.SizedBox(height: 14),
          ],
        ),
      ],
    ),
  );
  final output = File('docs/Panduan-Crew-SICATAT.pdf');
  await output.parent.create(recursive: true);
  await output.writeAsBytes(await document.save());
  stdout.writeln('Panduan dibuat: ${output.path}');
}
