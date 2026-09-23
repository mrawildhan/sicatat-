import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/reports/report_export_service.dart';
import '../../../data/reports/sheet_export_pdf.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../core/pdf/pdf_fonts.dart';

class SheetExportScreen extends StatefulWidget {
  const SheetExportScreen({required this.sheetId, super.key});
  final String? sheetId;
  @override
  State<SheetExportScreen> createState() => _SheetExportScreenState();
}

class _SheetExportScreenState extends State<SheetExportScreen> {
  bool _loading = false;
  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<ReportExportResult?> _load() async {
    final String? sheetId = widget.sheetId;
    if (sheetId == null || sheetId.isEmpty) {
      _message('ID lembar tidak ada.');
      return null;
    }
    setState(() => _loading = true);
    try {
      final ReportExportResult result = await ReportExportService(
        Supabase.instance.client,
      ).load(sheetId: sheetId);
      if (result.rows.isEmpty) {
        _message('Belum ada data pembacaan pada lembar ini.');
        return null;
      }
      return result;
    } on Object catch (error) {
      if (mounted) _message('Ekspor tidak dapat disiapkan: $error');
      return null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pdf() async {
    final ReportExportResult? result = await _load();
    if (result == null) return;
    final Uint8List bytes = await SheetExportPdf.build(
      result,
      theme: await loadPdfTheme(),
    );
    final ReportRow first = result.rows.first;
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _SheetPdfPreview(
          bytes: bytes,
          filename: 'sicatat-sheet-${first.date}.pdf',
        ),
      ),
    );
  }

  Future<void> _csv() async {
    final ReportExportResult? result = await _load();
    if (result == null) return;
    final String date = result.rows.first.date;
    final ReportExportService service = ReportExportService(
      Supabase.instance.client,
    );
    await Share.shareXFiles(<XFile>[
      XFile.fromData(
        utf8.encode(service.toCsv(result)),
        mimeType: 'text/csv',
        name: 'sicatat-sheet-$date.csv',
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) => AppBackScope(
    fallbackRoute: '/sheets',
    child: Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/sheets'),
        title: const Text('Ekspor lembar ini'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Buat ekspor PDF atau CSV berisi semua pembacaan tersimpan di lembar ini.',
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loading ? null : _pdf,
              icon: _loading
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf_rounded),
              label: const Text('Buat dan bagikan PDF'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _loading ? null : _csv,
              icon: const Icon(Icons.table_view_rounded),
              label: const Text('Ekspor CSV untuk Excel'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SheetPdfPreview extends StatelessWidget {
  const _SheetPdfPreview({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;

  @override
  Widget build(BuildContext context) => AppBackScope(
    fallbackRoute: '/sheets',
    child: Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/sheets'),
        title: const Text('Pratinjau PDF'),
      ),
      body: PdfPreview(
        // pdf.js takes ownership of the buffer it rasterizes, which left the
        // Share button with an empty (0-byte) file on the web. Hand every
        // caller its own copy.
        build: (PdfPageFormat _) async => Uint8List.fromList(bytes),
        initialPageFormat: PdfPageFormat.a4.landscape,
        canChangePageFormat: false,
        canChangeOrientation: false,
        pdfFileName: filename,
      ),
    ),
  );
}
