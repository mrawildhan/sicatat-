import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/sicatat_types.dart';
import '../../../data/models/app_user.dart';
import '../../../data/reports/report_export_service.dart';
import '../../auth/application/current_user_provider.dart';

class _TeamOption {
  const _TeamOption({required this.id, required this.name});
  final String id;
  final String name;
  factory _TeamOption.fromJson(JsonMap json) => _TeamOption(
    id: json.requiredString('id'),
    name: json.requiredString('name'),
  );
}

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});
  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  late DateTime _from;
  late DateTime _to;
  List<_TeamOption> _teams = const <_TeamOption>[];
  String? _teamId;
  bool _loading = false;
  bool get _teamLocked =>
      ref.read(currentUserProvider)?.role.isTeamScopedTemperature == true;
  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = now;
    if (_teamLocked) _teamId = ref.read(currentUserProvider)?.teamId;
    _loadTeams();
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  Future<void> _loadTeams() async {
    try {
      final Object response = await Supabase.instance.client
          .from('team')
          .select('id,name')
          .order('code');
      if (response is! List) return;
      final List<_TeamOption> teams = response
          .map(
            (Object? row) =>
                _TeamOption.fromJson(requireJsonMap(row, source: 'team')),
          )
          .toList(growable: false);
      if (mounted) setState(() => _teams = teams);
    } on Object catch (_) {}
  }

  Future<void> _pick(bool from) async {
    final DateTime? selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2040),
      initialDate: from ? _from : _to,
    );
    if (selected != null) {
      setState(() {
        if (from) {
          _from = selected;
        } else {
          _to = selected;
        }
      });
    }
  }

  void _message(String value) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
  Future<void> _export() async {
    if (_from.isAfter(_to)) {
      _message('Start date cannot be after end date.');
      return;
    }
    if (_teamLocked && _teamId == null) {
      _message(
        'Your foreman account needs a team assignment before exporting.',
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final ReportExportResult result = await ReportExportService(
        Supabase.instance.client,
      ).load(from: _from, to: _to, teamId: _teamId);
      if (result.rows.isEmpty) {
        _message('No reading data was found for this period.');
        return;
      }
      final pw.Document pdf = pw.Document();
      final String teamName = _teamId == null
          ? 'All teams'
          : _teams
                    .where((team) => team.id == _teamId)
                    .map((team) => team.name)
                    .firstOrNull ??
                'Selected team';
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(22),
          header: (pw.Context context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(
                'SICATAT FIELD TEMPERATURE REPORT',
                style: const pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Period: ${_date(_from)} to ${_date(_to)} - Team: $teamName - ${result.sheetCount} sheet(s), ${result.rows.length} reading(s)',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.SizedBox(height: 8),
            ],
          ),
          footer: (pw.Context context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
          build: (pw.Context context) => <pw.Widget>[_reportTable(result.rows)],
        ),
      );
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat _) async => pdf.save(),
        name: 'sicatat-report-${_date(_from)}_${_date(_to)}.pdf',
      );
    } on Object catch (error) {
      if (mounted) _message('Unable to create report: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  pw.Widget _reportTable(List<ReportRow> rows) => pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey400, width: .35),
    columnWidths: const <int, pw.TableColumnWidth>{
      0: pw.FixedColumnWidth(48),
      1: pw.FixedColumnWidth(68),
      2: pw.FixedColumnWidth(88),
      3: pw.FixedColumnWidth(62),
      4: pw.FlexColumnWidth(1.4),
      5: pw.FixedColumnWidth(62),
      6: pw.FixedColumnWidth(70),
      7: pw.FixedColumnWidth(62),
    },
    children: <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.green700),
        children: <pw.Widget>[
          _reportCell('Date', header: true),
          _reportCell('Team / shift', header: true),
          _reportCell('Section / round / time', header: true),
          _reportCell('Side / status', header: true),
          _reportCell('Equipment / point', header: true),
          _reportCell('Value / alert', header: true),
          _reportCell('Recorded by', header: true),
          _reportCell('Sheet status', header: true),
        ],
      ),
      ...rows.map(
        (ReportRow row) => pw.TableRow(
          children: <pw.Widget>[
            _reportCell(row.date),
            _reportCell('${row.team}\n${row.shift}'),
            _reportCell('${row.section}\nRound ${row.round} - ${row.time}'),
            _reportCell('${row.side}\n${row.unitStatus}'),
            _reportCell(
              '${row.equipment.isEmpty ? '' : '${row.equipment} - '}${row.point}',
            ),
            _reportCell(
              '${row.value} ${row.unit}${row.alertLabel.isEmpty ? '' : '\n${row.alertLabel}'}',
              alert: row.alertLabel,
            ),
            _reportCell(row.recordedBy),
            _reportCell(row.sheetStatus),
          ],
        ),
      ),
    ],
  );

  pw.Widget _reportCell(
    String value, {
    bool header = false,
    String alert = '',
  }) {
    final bool critical = alert.startsWith('CRITICAL');
    final bool high = alert.startsWith('HIGH');
    final bool review = alert.isNotEmpty && !critical && !high;
    final PdfColor background = header
        ? PdfColors.green700
        : critical
        ? PdfColors.red600
        : high
        ? PdfColors.orange300
        : review
        ? PdfColors.amber100
        : PdfColors.white;
    final PdfColor foreground = header || critical
        ? PdfColors.white
        : PdfColors.black;
    return pw.Container(
      color: background,
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: header ? 7 : 6,
          color: foreground,
          fontWeight: header || alert.isNotEmpty
              ? pw.FontWeight.bold
              : pw.FontWeight.normal,
        ),
      ),
    );
  }

  Future<void> _exportCsv() async {
    if (_from.isAfter(_to)) {
      _message('Start date cannot be after end date.');
      return;
    }
    if (_teamLocked && _teamId == null) {
      _message(
        'Your foreman account needs a team assignment before exporting.',
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final ReportExportService service = ReportExportService(
        Supabase.instance.client,
      );
      final ReportExportResult result = await service.load(
        from: _from,
        to: _to,
        teamId: _teamId,
      );
      if (result.rows.isEmpty) {
        _message('No reading data was found for this period.');
        return;
      }
      await Share.shareXFiles(<XFile>[
        XFile.fromData(
          utf8.encode(service.toCsv(result)),
          mimeType: 'text/csv',
          name: 'sicatat-export-${_date(_from)}_${_date(_to)}.csv',
        ),
      ]);
    } on Object catch (error) {
      if (mounted) _message('Unable to export CSV: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppBackScope(
    fallbackRoute: '/dashboard',
    child: Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/dashboard'),
        title: const Text('Period report'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          const Text(
            'Export every synced reading for a selected date range. For example, select 1 August 2026 through 31 August 2026, or 1 January through 31 December 2026.',
          ),
          const SizedBox(height: 18),
          _dateTile('From date', _from, () => _pick(true)),
          const SizedBox(height: 10),
          _dateTile('To date', _to, () => _pick(false)),
          const SizedBox(height: 10),
          if (_teamLocked)
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Team scope',
                prefixIcon: Icon(Icons.groups_rounded),
              ),
              child: Text(
                _teams
                        .where((team) => team.id == _teamId)
                        .map((team) => team.name)
                        .firstOrNull ??
                    'Your assigned team',
              ),
            )
          else
            DropdownButtonFormField<String>(
              key: const ValueKey<String>('report-team'),
              initialValue: _teamId,
              items: <DropdownMenuItem<String>>[
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('All teams'),
                ),
                ..._teams.map(
                  (team) => DropdownMenuItem<String>(
                    value: team.id,
                    child: Text(team.name),
                  ),
                ),
              ],
              onChanged: (String? value) => setState(() => _teamId = value),
              decoration: const InputDecoration(labelText: 'Team'),
            ),
          const SizedBox(height: 22),
          ElevatedButton.icon(
            onPressed: _loading ? null : _export,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.picture_as_pdf_rounded),
            label: Text(
              _loading ? 'Creating export...' : 'Create and share PDF',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _loading ? null : _exportCsv,
            icon: const Icon(Icons.table_view_rounded),
            label: const Text('Export CSV for Excel'),
          ),
        ],
      ),
    ),
  );
  Widget _dateTile(String title, DateTime date, VoidCallback onTap) => Card(
    child: ListTile(
      onTap: onTap,
      leading: const Icon(Icons.calendar_month_rounded, color: AppColors.green),
      title: Text(title),
      subtitle: Text(_date(date)),
    ),
  );
}
