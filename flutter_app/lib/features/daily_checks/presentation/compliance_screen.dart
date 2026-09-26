import 'dart:typed_data';

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
import '../compliance.dart';

/// Suhu → Kepatuhan pengisian: a month calendar of the three check sheets
/// per shift, with the rate per crew (owner request 2026-09-26).
class ComplianceScreen extends ConsumerStatefulWidget {
  const ComplianceScreen({super.key});

  @override
  ConsumerState<ComplianceScreen> createState() => _ComplianceScreenState();
}

class _ComplianceScreenState extends ConsumerState<ComplianceScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  ComplianceMonth? _data;
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
      final AppUser? user = ref.read(currentUserProvider);
      final ComplianceMonth data = await loadComplianceMonth(
        Supabase.instance.client,
        _month,
        onlyTeamId: user?.role.isTeamScopedTemperature == true
            ? user?.teamId
            : null,
      );
      if (mounted) setState(() => _data = data);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  String get _monthLabel => DateFormat('MMMM yyyy', 'id_ID').format(_month);

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _exportPdf() async {
    final ComplianceMonth? data = _data;
    if (data == null) return;
    try {
      final Uint8List bytes = await buildCompliancePdf(
        data,
        theme: await loadPdfTheme(),
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'Kepatuhan pengisian $_monthLabel.pdf',
      );
    } on Object catch (error) {
      _toast('PDF gagal dibuat: $error');
    }
  }

  Future<void> _exportExcel() async {
    final ComplianceMonth? data = _data;
    if (data == null) return;
    await saveExportFile(
      buildXlsx(
        sheetName: 'Kepatuhan',
        title: 'Kepatuhan pengisian lembar · $_monthLabel',
        columns: const <XlsxColumn>[
          XlsxColumn('Tanggal', width: 12),
          XlsxColumn('Shift', width: 12),
          XlsxColumn('Crew', width: 8),
          XlsxColumn('Lembar', width: 34),
          XlsxColumn('Status', width: 16),
          XlsxColumn('Dikirim', width: 18),
          XlsxColumn('Disetujui', width: 18),
        ],
        rows: <List<Object?>>[
          for (final ComplianceCell cell in data.cells)
            if (cell.status != ComplianceStatus.upcoming)
              <Object?>[
                cell.date,
                complianceShiftLabel(cell.shiftCode),
                cell.teamCode,
                cell.form.title,
                cell.status.label,
                cell.sheet?.submittedAt == null
                    ? null
                    : DateFormat('dd/MM/yyyy HH.mm')
                          .format(cell.sheet!.submittedAt!),
                cell.sheet?.approvedAt == null
                    ? null
                    : DateFormat('dd/MM/yyyy HH.mm')
                          .format(cell.sheet!.approvedAt!),
              ],
        ],
      ),
      fileName: 'Kepatuhan pengisian $_monthLabel.xlsx',
    );
  }

  void _openDay(DateTime date) {
    final ComplianceMonth? data = _data;
    if (data == null) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: <Widget>[
            Text(
              DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(date),
              style: AppTextStyles.sectionTitle,
            ),
            for (final String shift in complianceShifts) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                '${complianceShiftLabel(shift)} · Crew '
                '${data.cellsOf(date, shift).firstOrNull?.teamCode ?? '-'}',
                style: AppTextStyles.cardTitle,
              ),
              for (final ComplianceCell cell in data.cellsOf(date, shift))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.circle,
                    size: 12,
                    color: cell.status.color,
                  ),
                  title: Text(cell.form.title),
                  subtitle: cell.sheet?.submittedAt == null
                      ? null
                      : Text(
                          'Dikirim ${DateFormat('d MMM HH.mm', 'id_ID').format(cell.sheet!.submittedAt!)}'
                          '${cell.sheet!.waitingApproval ? ' · belum disetujui' : ''}',
                        ),
                  trailing: InfoTag(
                    cell.status.label,
                    color: _tagColor(cell.status),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ComplianceMonth? data = _data;
    return AppBackScope(
      fallbackRoute: '/temperature-forms',
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallbackRoute: '/temperature-forms'),
          title: const Text('Kepatuhan pengisian'),
          actions: <Widget>[
            IconButton(
              tooltip: 'Ekspor Excel',
              onPressed: data == null || _loading ? null : _exportExcel,
              icon: const Icon(Icons.table_view_outlined),
            ),
            IconButton(
              tooltip: 'Ekspor PDF',
              onPressed: data == null || _loading ? null : _exportPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
            children: <Widget>[
              Row(
                children: <Widget>[
                  IconButton(
                    tooltip: 'Bulan sebelumnya',
                    onPressed: _loading ? null : () => _shiftMonth(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Text(
                      _monthLabel,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.sectionTitle,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Bulan berikutnya',
                    onPressed:
                        _loading ||
                            !_month.isBefore(
                              DateTime(
                                DateTime.now().year,
                                DateTime.now().month,
                              ),
                            )
                        ? null
                        : () => _shiftMonth(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              const Text(
                'Tiga lembar per shift: Feeder Sizer, Hydraulic, dan Coal '
                'Valve. Tepat waktu berarti dikirim paling lambat 2 jam '
                'setelah shift berakhir. Crew mengikuti jadwal regu 3-3-3.',
                style: AppTextStyles.supporting,
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: <Widget>[
                        Text('Data belum dapat dimuat. $_error'),
                        const SizedBox(height: 8),
                        FilledButton.tonal(
                          onPressed: _load,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (data != null)
                ..._content(data),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(ComplianceMonth data) => <Widget>[
    Row(
      children: <Widget>[
        Expanded(
          child: FigureTile(
            label: 'Terisi',
            value: _percent(data.filledRate),
            color: _rateColor(data.filledRate),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FigureTile(
            label: 'Tepat waktu',
            value: _percent(data.onTimeRate),
            color: _rateColor(data.onTimeRate),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FigureTile(
            label: 'Tidak ada',
            value: '${data.count(ComplianceStatus.missing)}',
            color: AppColors.danger,
          ),
        ),
      ],
    ),
    const SizedBox(height: 8),
    Text(
      '${data.due.length} lembar jatuh tempo · '
      '${data.count(ComplianceStatus.late)} terlambat · '
      '${data.count(ComplianceStatus.incomplete)} belum lengkap · '
      '${data.waitingApproval.length} belum disetujui',
      style: AppTextStyles.supporting,
    ),
    const SizedBox(height: 16),
    const Text('Per crew', style: AppTextStyles.sectionTitle),
    const SizedBox(height: 6),
    if (data.crews.isEmpty)
      const Text(
        'Belum ada shift yang berakhir.',
        style: AppTextStyles.supporting,
      )
    else
      for (final ComplianceCrewSummary crew in data.crews)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      'Crew ${crew.teamCode}',
                      style: AppTextStyles.cardTitle,
                    ),
                    const Spacer(),
                    Text(
                      'Terisi ${_percent(crew.filledRate)} · '
                      'tepat waktu ${_percent(crew.onTimeRate)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _rateColor(crew.filledRate),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: crew.filledRate,
                    minHeight: 8,
                    color: _rateColor(crew.filledRate),
                    backgroundColor: AppColors.line,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${crew.due} lembar · ${crew.onTime} tepat waktu · '
                  '${crew.late} terlambat · ${crew.incomplete} belum lengkap '
                  '· ${crew.missing} tidak ada',
                  style: AppTextStyles.supporting,
                ),
              ],
            ),
          ),
        ),
    const SizedBox(height: 8),
    const Text('Per lembar', style: AppTextStyles.sectionTitle),
    const SizedBox(height: 6),
    for (final MapEntry<ComplianceForm, double> entry
        in data.filledRateByForm.entries)
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: <Widget>[
            SizedBox(width: 110, child: Text(entry.key.shortLabel)),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: entry.value,
                  minHeight: 8,
                  color: _rateColor(entry.value),
                  backgroundColor: AppColors.line,
                ),
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                _percent(entry.value),
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    const SizedBox(height: 12),
    const Text('Kalender', style: AppTextStyles.sectionTitle),
    const SizedBox(height: 4),
    const Text(
      'Warna hari mengikuti lembar terburuk. Ketuk hari untuk rinciannya.',
      style: AppTextStyles.supporting,
    ),
    const SizedBox(height: 8),
    _Calendar(month: data.month, data: data, onTap: _openDay),
    const SizedBox(height: 8),
    Wrap(
      spacing: 10,
      runSpacing: 4,
      children: <Widget>[
        for (final ComplianceStatus status in ComplianceStatus.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.square_rounded, size: 14, color: status.color),
              const SizedBox(width: 3),
              Text(status.label, style: const TextStyle(fontSize: 12)),
            ],
          ),
      ],
    ),
    if (data.waitingApproval.isNotEmpty) ...<Widget>[
      const SizedBox(height: 16),
      Text(
        'Belum disetujui (${data.waitingApproval.length})',
        style: AppTextStyles.sectionTitle,
      ),
      const SizedBox(height: 6),
      for (final ComplianceSheet sheet in data.waitingApproval)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(
            Icons.hourglass_top_rounded,
            color: AppColors.orange,
          ),
          title: Text(sheet.form.title),
          subtitle: Text(
            '${DateFormat('d MMM yyyy', 'id_ID').format(sheet.date)} · '
            '${complianceShiftLabel(sheet.shiftCode)}'
            '${sheet.teamCode == null ? '' : ' · Crew ${sheet.teamCode}'}',
          ),
        ),
    ],
  ];
}

class _Calendar extends StatelessWidget {
  const _Calendar({
    required this.month,
    required this.data,
    required this.onTap,
  });

  final DateTime month;
  final ComplianceMonth data;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final int days = DateTime(month.year, month.month + 1, 0).day;
    final int lead = DateTime(month.year, month.month).weekday - 1;
    const List<String> names = <String>[
      'Sen',
      'Sel',
      'Rab',
      'Kam',
      'Jum',
      'Sab',
      'Min',
    ];
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            for (final String name in names)
              Expanded(
                child: Center(
                  child: Text(name, style: AppTextStyles.supporting),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: <Widget>[
            for (int i = 0; i < lead; i++) const SizedBox(),
            for (int d = 1; d <= days; d++)
              () {
                final DateTime date = DateTime(month.year, month.month, d);
                final ComplianceStatus status = data.dayStatus(date);
                // Amber and the pale "not yet" need dark text.
                final bool light =
                    status == ComplianceStatus.upcoming ||
                    status == ComplianceStatus.late;
                return Material(
                  color: status.color.withValues(
                    alpha: status == ComplianceStatus.upcoming ? .5 : .9,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: status == ComplianceStatus.upcoming
                        ? null
                        : () => onTap(date),
                    child: Center(
                      child: Text(
                        '$d',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: light ? AppColors.ink : Colors.white,
                        ),
                      ),
                    ),
                  ),
                );
              }(),
          ],
        ),
      ],
    );
  }
}

Color _tagColor(ComplianceStatus status) => switch (status) {
  ComplianceStatus.late => const Color(0xFFB7791F),
  ComplianceStatus.upcoming => AppColors.muted,
  _ => status.color,
};

String _percent(double rate) => '${(rate * 100).round()}%';

Color _rateColor(double rate) => rate >= .95
    ? AppColors.green
    : rate >= .8
    ? AppColors.orange
    : AppColors.danger;

/// The month as a PDF: summary, crews, and one line per day.
Future<Uint8List> buildCompliancePdf(
  ComplianceMonth data, {
  required pw.ThemeData theme,
}) {
  final String month = DateFormat('MMMM yyyy', 'id_ID').format(data.month);
  const String title = 'Kepatuhan Pengisian Lembar';
  PdfColor colorOf(ComplianceStatus status) => switch (status) {
    ComplianceStatus.onTime => reportGreen,
    ComplianceStatus.late => PdfColor.fromHex('#B7791F'),
    ComplianceStatus.incomplete => reportOrange,
    ComplianceStatus.missing => reportDanger,
    _ => reportMuted,
  };
  String short(ComplianceStatus status) => switch (status) {
    ComplianceStatus.onTime => 'OK',
    ComplianceStatus.late => 'Telat',
    ComplianceStatus.incomplete => 'Kurang',
    ComplianceStatus.missing => 'Tidak ada',
    ComplianceStatus.running => 'Berjalan',
    ComplianceStatus.upcoming => '-',
  };
  final int days = DateTime(data.month.year, data.month.month + 1, 0).day;
  final List<List<ComplianceCell>> lines =
      <List<ComplianceCell>>[
            for (int d = 1; d <= days; d++)
              <ComplianceCell>[
                for (final String shift in complianceShifts)
                  ...data.cellsOf(
                    DateTime(data.month.year, data.month.month, d),
                    shift,
                  ),
              ],
          ]
          .where(
            (List<ComplianceCell> line) =>
                line.isNotEmpty &&
                line.any(
                  (ComplianceCell c) => c.status != ComplianceStatus.upcoming,
                ),
          )
          .toList();
  final pw.Document document = pw.Document(theme: theme, title: title);
  document.addPage(
    reportPage(
      title: '$title · $month',
      build: (pw.Context context) => <pw.Widget>[
        ...reportHeading(
          title,
          'Asam-Asam · $month · Feeder Sizer, Hydraulic, Coal Valve · '
          'tepat waktu = dikirim paling lambat 2 jam setelah shift',
        ),
        reportFigures(<ReportFigure>[
          ReportFigure('Lembar jatuh tempo', '${data.due.length}'),
          ReportFigure('Terisi', _percent(data.filledRate)),
          ReportFigure('Tepat waktu', _percent(data.onTimeRate)),
          ReportFigure(
            'Tidak ada',
            '${data.count(ComplianceStatus.missing)}',
            color: reportDanger,
          ),
          ReportFigure(
            'Belum disetujui',
            '${data.waitingApproval.length}',
            color: reportOrange,
          ),
        ]),
        reportSectionTitle('Per crew'),
        reportTable(
          headers: const <String>[
            'Crew',
            'Jatuh tempo',
            'Tepat waktu',
            'Terlambat',
            'Belum lengkap',
            'Tidak ada',
            'Terisi',
            'Tepat waktu %',
          ],
          centered: const <int>{0, 1, 2, 3, 4, 5, 6, 7},
          bold: const <int>{0},
          rows: <List<String>>[
            for (final ComplianceCrewSummary crew in data.crews)
              <String>[
                crew.teamCode,
                '${crew.due}',
                '${crew.onTime}',
                '${crew.late}',
                '${crew.incomplete}',
                '${crew.missing}',
                _percent(crew.filledRate),
                _percent(crew.onTimeRate),
              ],
          ],
        ),
        reportSectionTitle('Per hari'),
        reportTable(
          headers: const <String>[
            'Tanggal',
            'Pagi',
            'Feeder Sizer',
            'Hydraulic',
            'Coal Valve',
            'Malam',
            'Feeder Sizer',
            'Hydraulic',
            'Coal Valve',
          ],
          centered: const <int>{0, 1, 2, 3, 4, 5, 6, 7, 8},
          bold: const <int>{1, 5},
          fontSize: 7,
          rows: <List<String>>[
            for (final List<ComplianceCell> line in lines)
              <String>[
                DateFormat('EEE d/M', 'id_ID').format(line.first.date),
                for (final String shift in complianceShifts) ...<String>[
                  line
                          .where((ComplianceCell c) => c.shiftCode == shift)
                          .firstOrNull
                          ?.teamCode ??
                      '-',
                  for (final ComplianceCell cell in line.where(
                    (ComplianceCell c) => c.shiftCode == shift,
                  ))
                    short(cell.status),
                ],
              ],
          ],
          cellColor: (int row, int column) {
            if (column == 0 || column == 1 || column == 5) return null;
            final List<ComplianceCell> line = lines[row];
            final String shift = column < 5 ? 'PAGI' : 'MALAM';
            final int index = column < 5 ? column - 2 : column - 6;
            final List<ComplianceCell> cells = line
                .where((ComplianceCell c) => c.shiftCode == shift)
                .toList();
            return index < cells.length ? colorOf(cells[index].status) : null;
          },
        ),
        if (data.waitingApproval.isNotEmpty) ...<pw.Widget>[
          reportSectionTitle('Belum disetujui'),
          reportTable(
            headers: const <String>[
              'Tanggal',
              'Shift',
              'Crew',
              'Lembar',
              'Dikirim',
            ],
            centered: const <int>{0, 1, 2},
            rows: <List<String>>[
              for (final ComplianceSheet sheet in data.waitingApproval)
                <String>[
                  reportDate(sheet.date),
                  complianceShiftLabel(sheet.shiftCode),
                  sheet.teamCode ?? '-',
                  sheet.form.title,
                  reportDateTime(sheet.submittedAt),
                ],
            ],
          ),
        ],
      ],
    ),
  );
  return document.save();
}
