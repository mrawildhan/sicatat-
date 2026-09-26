import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/export/xlsx_export.dart';
import '../../../core/pdf/pdf_fonts.dart';
import '../../../core/pdf/report_pdf.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../core/widgets/info_tag.dart';
import '../../../data/models/app_user.dart';
import '../../auth/application/current_user_provider.dart';
import '../alert_follow_up.dart';

enum _AlertRange {
  unclosed('Belum ditutup'),
  days30('30 hari'),
  days90('90 hari');

  const _AlertRange(this.label);

  final String label;
}

/// Suhu → Tindak lanjut suhu kritis: every critical reading with what was
/// done about it, for reviewers and auditors (owner request 2026-09-26).
class TemperatureAlertsScreen extends ConsumerStatefulWidget {
  const TemperatureAlertsScreen({super.key});

  @override
  ConsumerState<TemperatureAlertsScreen> createState() =>
      _TemperatureAlertsScreenState();
}

class _TemperatureAlertsScreenState
    extends ConsumerState<TemperatureAlertsScreen> {
  final AlertFollowUpService _service = AlertFollowUpService(
    Supabase.instance.client,
  );
  _AlertRange _range = _AlertRange.unclosed;
  List<TemperatureAlertRecord> _alerts = const <TemperatureAlertRecord>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final DateTime now = DateTime.now();
      final List<TemperatureAlertRecord> alerts = switch (_range) {
        _AlertRange.unclosed => await _service.loadUnclosed(),
        _AlertRange.days30 => await _service.load(
          from: now.subtract(const Duration(days: 30)),
          to: now.add(const Duration(days: 1)),
        ),
        _AlertRange.days90 => await _service.load(
          from: now.subtract(const Duration(days: 90)),
          to: now.add(const Duration(days: 1)),
        ),
      };
      if (mounted) setState(() => _alerts = alerts);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _open(TemperatureAlertRecord alert) async {
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FollowUpSheet(
        alert: alert,
        service: _service,
        // Crew record the handling; the foreman (or above) closes it.
        canClose:
            ref.read(currentUserProvider)?.role.canReviewTemperature == true,
      ),
    );
    if (saved == true) {
      _toast('Tindak lanjut disimpan.');
      await _load();
    }
  }

  String get _periodLabel => switch (_range) {
    _AlertRange.unclosed => 'Semua yang belum ditutup',
    _AlertRange.days30 => '30 hari terakhir',
    _AlertRange.days90 => '90 hari terakhir',
  };

  Future<void> _exportExcel() async {
    final DateTime now = DateTime.now();
    final Uint8List bytes = buildXlsx(
      sheetName: 'Suhu kritis',
      title: 'Tindak lanjut suhu kritis · $_periodLabel',
      columns: const <XlsxColumn>[
        XlsxColumn('Waktu', width: 18),
        XlsxColumn('Lembar', width: 30),
        XlsxColumn('Titik ukur', width: 40),
        XlsxColumn('Nilai °C', width: 10),
        XlsxColumn('Batas °C', width: 10),
        XlsxColumn('Regu', width: 12),
        XlsxColumn('Shift', width: 14),
        XlsxColumn('Status', width: 12),
        XlsxColumn('Tindakan', width: 50),
        XlsxColumn('No. WO', width: 14),
        XlsxColumn('Ditangani oleh', width: 22),
        XlsxColumn('Ditutup', width: 18),
        XlsxColumn('Umur/durasi (hari)', width: 12),
      ],
      rows: <List<Object?>>[
        for (final TemperatureAlertRecord a in _alerts)
          <Object?>[
            DateFormat('dd/MM/yyyy HH.mm').format(a.occurredAt),
            a.formLabel,
            a.pointLabel,
            a.value,
            a.limitValue,
            a.teamName,
            a.shiftLabel,
            a.status.label,
            a.action,
            a.workOrder,
            a.handlerName,
            a.closedAt == null
                ? null
                : DateFormat('dd/MM/yyyy HH.mm').format(a.closedAt!),
            a.ageDays(now),
          ],
      ],
    );
    await saveExportFile(
      bytes,
      fileName: 'Suhu kritis ${DateFormat('dd-MM-yyyy').format(now)}.xlsx',
    );
  }

  Future<void> _exportPdf() async {
    try {
      final Uint8List bytes = await buildAlertFollowUpPdf(
        _alerts,
        periodLabel: _periodLabel,
        theme: await loadPdfTheme(),
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'Tindak lanjut suhu kritis ${DateFormat('dd-MM-yyyy').format(DateTime.now())}.pdf',
      );
    } on Object catch (error) {
      _toast('PDF gagal dibuat: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    int count(AlertFollowUpStatus status) =>
        _alerts.where((a) => a.status == status).length;
    final List<TemperatureAlertRecord> closed = _alerts
        .where((a) => a.isClosed)
        .toList(growable: false);
    final double? meanClose = closed.isEmpty
        ? null
        : closed
                  .map((a) => a.closedAt!.difference(a.occurredAt).inMinutes)
                  .reduce((a, b) => a + b) /
              closed.length /
              60;
    return AppBackScope(
      fallbackRoute: '/temperature-forms',
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallbackRoute: '/temperature-forms'),
          title: const Text('Tindak lanjut suhu kritis'),
          actions: <Widget>[
            IconButton(
              tooltip: 'Ekspor Excel',
              onPressed: _loading || _alerts.isEmpty ? null : _exportExcel,
              icon: const Icon(Icons.table_view_outlined),
            ),
            IconButton(
              tooltip: 'Ekspor PDF',
              onPressed: _loading || _alerts.isEmpty ? null : _exportPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
            children: <Widget>[
              const Text(
                'Setiap pembacaan di atas batas kritis perlu dicatat '
                'tindakannya sampai ditutup. Riwayat perubahan tersimpan '
                'untuk audit.',
                style: AppTextStyles.supporting,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final _AlertRange range in _AlertRange.values)
                    ChoiceChip(
                      label: Text(range.label),
                      selected: _range == range,
                      onSelected: (_) {
                        setState(() => _range = range);
                        _load();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FigureTile(
                      label: 'Terbuka',
                      value: '${count(AlertFollowUpStatus.open)}',
                      color: AppColors.danger,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FigureTile(
                      label: 'Ditangani',
                      value: '${count(AlertFollowUpStatus.inProgress)}',
                      color: AppColors.orange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FigureTile(
                      label: 'Ditutup',
                      value: '${count(AlertFollowUpStatus.closed)}',
                      color: AppColors.green,
                    ),
                  ),
                ],
              ),
              if (meanClose != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  'Rata-rata waktu sampai ditutup: '
                  '${meanClose < 24 ? '${meanClose.toStringAsFixed(1)} jam' : '${(meanClose / 24).toStringAsFixed(1)} hari'}',
                  style: AppTextStyles.supporting,
                ),
              ],
              const SizedBox(height: 14),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _Message(
                  icon: Icons.cloud_off_rounded,
                  text: 'Data belum dapat dimuat. $_error',
                  onRetry: _load,
                )
              else if (_alerts.isEmpty)
                _Message(
                  icon: Icons.verified_outlined,
                  text: _range == _AlertRange.unclosed
                      ? 'Semua peringatan suhu kritis sudah ditutup.'
                      : 'Tidak ada suhu kritis pada periode ini.',
                )
              else
                for (final TemperatureAlertRecord alert in _alerts) ...<Widget>[
                  _AlertCard(alert: alert, now: now, onTap: () => _open(alert)),
                  const SizedBox(height: 8),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.onRetry});

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: <Widget>[
          Icon(icon, color: AppColors.green, size: 32),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center),
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: 10),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Coba lagi'),
            ),
          ],
        ],
      ),
    ),
  );
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.alert,
    required this.now,
    required this.onTap,
  });

  final TemperatureAlertRecord alert;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final int age = alert.ageDays(now);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: alert.status == AlertFollowUpStatus.open && age >= 1
            ? const BorderSide(color: AppColors.danger, width: 1.2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    '${_number(alert.value)} °C',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.danger,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'batas ${_number(alert.limitValue)} °C',
                      style: AppTextStyles.supporting,
                    ),
                  ),
                  InfoTag(alert.status.label, color: alert.status.color),
                ],
              ),
              const SizedBox(height: 4),
              Text(alert.pointLabel, style: AppTextStyles.cardTitle),
              Text(
                <String?>[
                  alert.formLabel,
                  alert.teamName,
                  alert.shiftLabel,
                ].whereType<String>().join(' · '),
                style: AppTextStyles.supporting,
              ),
              const SizedBox(height: 4),
              Text(
                '${DateFormat('EEE, d MMM yyyy HH.mm', 'id_ID').format(alert.occurredAt)}'
                ' · ${alert.isClosed ? 'ditutup dalam $age hari' : '$age hari terbuka'}',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              if (alert.action != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  'Tindakan: ${alert.action}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (alert.handlerName != null)
                Text(
                  'Oleh ${alert.handlerName}'
                  '${alert.workOrder == null ? '' : ' · WO ${alert.workOrder}'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FollowUpSheet extends StatefulWidget {
  const _FollowUpSheet({
    required this.alert,
    required this.service,
    required this.canClose,
  });

  final TemperatureAlertRecord alert;
  final AlertFollowUpService service;
  final bool canClose;

  @override
  State<_FollowUpSheet> createState() => _FollowUpSheetState();
}

class _FollowUpSheetState extends State<_FollowUpSheet> {
  late AlertFollowUpStatus _status;
  late final TextEditingController _action;
  late final TextEditingController _workOrder;
  String? _photoPath;
  Uint8List? _photo;
  bool _busy = false;
  List<AlertFollowUpEntry>? _history;

  @override
  void initState() {
    super.initState();
    final TemperatureAlertRecord alert = widget.alert;
    // A new follow-up usually starts handling the alert.
    _status = alert.status == AlertFollowUpStatus.open
        ? AlertFollowUpStatus.inProgress
        : alert.status;
    _action = TextEditingController(text: alert.action ?? '');
    _workOrder = TextEditingController(text: alert.workOrder ?? '');
    _photoPath = alert.photoPath;
    _loadExtras();
  }

  @override
  void dispose() {
    _action.dispose();
    _workOrder.dispose();
    super.dispose();
  }

  Future<void> _loadExtras() async {
    try {
      final List<AlertFollowUpEntry> history = await widget.service.history(
        widget.alert.id,
      );
      if (mounted) setState(() => _history = history);
    } on Object {
      if (mounted) setState(() => _history = const <AlertFollowUpEntry>[]);
    }
    final String? path = _photoPath;
    if (path != null) {
      try {
        final Uint8List bytes = await widget.service.downloadPhoto(path);
        if (mounted) setState(() => _photo = bytes);
      } on Object {
        // The path stays; only the preview is missing.
      }
    }
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _pickPhoto() async {
    final FilePickerResult? picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['jpg', 'jpeg', 'png'],
      withData: true,
    );
    final PlatformFile? file = picked?.files.single;
    final Uint8List? bytes = file?.bytes;
    if (file == null || bytes == null) return;
    setState(() => _busy = true);
    try {
      final String path = await widget.service.uploadPhoto(
        alertId: widget.alert.id,
        bytes: bytes,
        fileName: file.name,
      );
      final String? previous = _photoPath;
      // Only a photo not yet saved on the alert may be removed right away.
      if (previous != null && previous != widget.alert.photoPath) {
        await widget.service.removePhoto(previous).catchError((Object _) {});
      }
      final Uint8List preview = await widget.service.downloadPhoto(path);
      if (mounted) {
        setState(() {
          _photoPath = path;
          _photo = preview;
        });
      }
    } on Object catch (error) {
      _toast('Foto belum dapat diunggah. $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_status == AlertFollowUpStatus.closed && _action.text.trim().isEmpty) {
      _toast('Tuliskan tindakan yang dilakukan sebelum menutup.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.service.save(
        alertId: widget.alert.id,
        status: _status,
        action: _action.text,
        workOrder: _workOrder.text,
        photoPath: _photoPath,
      );
      final String? old = widget.alert.photoPath;
      if (old != null && old != _photoPath) {
        await widget.service.removePhoto(old).catchError((Object _) {});
      }
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      final String message = error is PostgrestException
          ? error.message
          : '$error';
      _toast('Belum tersimpan. $message');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TemperatureAlertRecord alert = widget.alert;
    // A closed alert is reopened only by the foreman or above.
    final bool locked = alert.isClosed && !widget.canClose;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .9,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: <Widget>[
              Text(
                '${_number(alert.value)} °C · ${alert.pointLabel}',
                style: AppTextStyles.sectionTitle,
              ),
              const SizedBox(height: 2),
              Text(
                <String?>[
                  alert.formLabel,
                  alert.teamName,
                  alert.shiftLabel,
                  DateFormat(
                    'd MMM yyyy HH.mm',
                    'id_ID',
                  ).format(alert.occurredAt),
                ].whereType<String>().join(' · '),
                style: AppTextStyles.supporting,
              ),
              const SizedBox(height: 16),
              SegmentedButton<AlertFollowUpStatus>(
                segments: <ButtonSegment<AlertFollowUpStatus>>[
                  for (final AlertFollowUpStatus status
                      in AlertFollowUpStatus.values)
                    ButtonSegment<AlertFollowUpStatus>(
                      value: status,
                      label: Text(status.label),
                      enabled:
                          status != AlertFollowUpStatus.closed ||
                          widget.canClose,
                    ),
                ],
                selected: <AlertFollowUpStatus>{_status},
                onSelectionChanged: _busy || locked
                    ? null
                    : (Set<AlertFollowUpStatus> value) =>
                          setState(() => _status = value.first),
              ),
              if (!widget.canClose) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  locked
                      ? 'Sudah ditutup. Hanya foreman yang dapat membukanya kembali.'
                      : 'Catat penanganan Anda; foreman yang menutup peringatan.',
                  style: AppTextStyles.supporting,
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _action,
                readOnly: locked,
                minLines: 3,
                maxLines: 6,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Tindakan yang dilakukan',
                  hintText:
                      'Contoh: cek oli gearbox, level rendah, ditambah 5 L; '
                      'suhu turun ke 58 °C',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _workOrder,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: 'No. WO / CM (bila ada)',
                ),
              ),
              const SizedBox(height: 8),
              if (_photo != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(_photo!, height: 180, fit: BoxFit.cover),
                ),
              Row(
                children: <Widget>[
                  TextButton.icon(
                    onPressed: _busy || locked ? null : _pickPhoto,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text(
                      _photoPath == null ? 'Tambah foto' : 'Ganti foto',
                    ),
                  ),
                  if (_photoPath != null)
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _photoPath = null;
                              _photo = null;
                            }),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Hapus foto'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy || locked ? null : _save,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Simpan tindak lanjut'),
              ),
              const SizedBox(height: 18),
              const Text('Riwayat', style: AppTextStyles.cardTitle),
              const SizedBox(height: 6),
              if (_history == null)
                const LinearProgressIndicator()
              else if (_history!.isEmpty)
                const Text(
                  'Belum ada tindak lanjut.',
                  style: AppTextStyles.supporting,
                )
              else
                for (final AlertFollowUpEntry entry in _history!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(Icons.circle, size: 10, color: entry.status.color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${DateFormat('d MMM yyyy HH.mm', 'id_ID').format(entry.at)}'
                            ' · ${entry.status.label}'
                            '${entry.byName == null ? '' : ' · ${entry.byName}'}'
                            '${entry.action == null ? '' : '\n${entry.action}'}'
                            '${entry.workOrder == null ? '' : '\nWO ${entry.workOrder}'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

/// The follow-up list as an A4 landscape PDF.
Future<Uint8List> buildAlertFollowUpPdf(
  List<TemperatureAlertRecord> alerts, {
  required String periodLabel,
  required pw.ThemeData theme,
  DateTime? now,
}) {
  final DateTime today = now ?? DateTime.now();
  const String title = 'Tindak Lanjut Suhu Kritis';
  int count(AlertFollowUpStatus status) =>
      alerts.where((a) => a.status == status).length;
  final pw.Document document = pw.Document(theme: theme, title: title);
  document.addPage(
    reportPage(
      title: title,
      format: PdfPageFormat.a4.landscape,
      build: (pw.Context context) => <pw.Widget>[
        ...reportHeading(title, 'Asam-Asam · $periodLabel'),
        reportFigures(<ReportFigure>[
          ReportFigure('Suhu kritis', '${alerts.length}'),
          ReportFigure(
            'Terbuka',
            '${count(AlertFollowUpStatus.open)}',
            color: reportDanger,
          ),
          ReportFigure(
            'Ditangani',
            '${count(AlertFollowUpStatus.inProgress)}',
            color: reportOrange,
          ),
          ReportFigure(
            'Ditutup',
            '${count(AlertFollowUpStatus.closed)}',
            color: reportGreen,
          ),
        ]),
        pw.SizedBox(height: 10),
        reportTable(
          headers: const <String>[
            'No',
            'Waktu',
            'Lembar · titik ukur',
            '°C',
            'Regu · shift',
            'Status',
            'Tindakan',
            'WO',
            'Oleh',
            'Hari',
          ],
          widths: const <int, pw.TableColumnWidth>{
            0: pw.FixedColumnWidth(20),
            1: pw.FixedColumnWidth(62),
            2: pw.FlexColumnWidth(2.2),
            3: pw.FixedColumnWidth(26),
            4: pw.FixedColumnWidth(70),
            5: pw.FixedColumnWidth(46),
            6: pw.FlexColumnWidth(2.6),
            7: pw.FixedColumnWidth(46),
            8: pw.FixedColumnWidth(70),
            9: pw.FixedColumnWidth(24),
          },
          centered: const <int>{0, 3, 5, 9},
          bold: const <int>{3},
          rows: <List<String>>[
            for (int i = 0; i < alerts.length; i++)
              <String>[
                '${i + 1}',
                DateFormat('d/M/yy HH.mm').format(alerts[i].occurredAt),
                '${alerts[i].formLabel}\n${alerts[i].pointLabel}',
                _number(alerts[i].value),
                <String?>[
                  alerts[i].teamName,
                  alerts[i].shiftLabel,
                ].whereType<String>().join(' · '),
                alerts[i].status.label,
                alerts[i].action ?? '-',
                alerts[i].workOrder ?? '-',
                alerts[i].handlerName ?? '-',
                '${alerts[i].ageDays(today)}',
              ],
          ],
          cellColor: (int row, int column) => switch (column) {
            3 => reportDanger,
            5 => switch (alerts[row].status) {
              AlertFollowUpStatus.open => reportDanger,
              AlertFollowUpStatus.inProgress => reportOrange,
              AlertFollowUpStatus.closed => reportGreen,
            },
            _ => null,
          },
        ),
      ],
    ),
  );
  return document.save();
}
