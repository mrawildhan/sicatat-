import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/pdf/pdf_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/sicatat_types.dart';
import '../../../data/models/app_user.dart';
import '../../../data/reports/period_report_pdf.dart';
import '../../../data/reports/report_export_service.dart';
import '../../auth/application/current_user_provider.dart';
import '../../daily_checks/daily_check_forms.dart';
import '../../daily_checks/daily_check_pdf.dart';
import '../../daily_checks/daily_check_repository.dart';

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
          .order('code', ascending: true);
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
      _message('Tanggal mulai tidak boleh setelah tanggal akhir.');
      return;
    }
    if (_teamLocked && _teamId == null) {
      _message(
        'Akun foreman Anda perlu ditugaskan ke regu sebelum mengekspor.',
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final ReportExportResult result = await ReportExportService(
        Supabase.instance.client,
      ).load(from: _from, to: _to, teamId: _teamId);
      if (result.rows.isEmpty) {
        _message('Tidak ada data pembacaan pada periode ini.');
        return;
      }
      final String teamName = _teamId == null
          ? 'Semua regu'
          : _teams
                    .where((team) => team.id == _teamId)
                    .map((team) => team.name)
                    .firstOrNull ??
                'Regu terpilih';
      final Uint8List bytes = await PeriodReportPdf.build(
        result: result,
        from: _from,
        to: _to,
        teamName: teamName,
        theme: await loadPdfTheme(),
      );
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat _) async => bytes,
        name: 'sicatat-report-${_date(_from)}_${_date(_to)}.pdf',
      );
    } on Object catch (error) {
      if (mounted) _message('Laporan tidak dapat dibuat: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportCsv() async {
    if (_from.isAfter(_to)) {
      _message('Tanggal mulai tidak boleh setelah tanggal akhir.');
      return;
    }
    if (_teamLocked && _teamId == null) {
      _message(
        'Akun foreman Anda perlu ditugaskan ke regu sebelum mengekspor.',
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
        _message('Tidak ada data pembacaan pada periode ini.');
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
      if (mounted) _message('CSV tidak dapat diekspor: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppBackScope(
    fallbackRoute: '/sheets',
    child: Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/sheets'),
        title: const Text('Laporan Periode'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          const Text(
            'Ekspor semua pembacaan yang sudah tersinkron dalam rentang tanggal tertentu, misalnya 1 sampai 31 Agustus 2026, atau 1 Januari sampai 31 Desember 2026.',
          ),
          const SizedBox(height: 18),
          _dateTile('Tanggal mulai', _from, () => _pick(true)),
          const SizedBox(height: 10),
          _dateTile('Tanggal akhir', _to, () => _pick(false)),
          const SizedBox(height: 10),
          if (_teamLocked)
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Cakupan regu',
                prefixIcon: Icon(Icons.groups_rounded),
              ),
              child: Text(
                _teams
                        .where((team) => team.id == _teamId)
                        .map((team) => team.name)
                        .firstOrNull ??
                    'Regu Anda',
              ),
            )
          else
            DropdownButtonFormField<String>(
              key: const ValueKey<String>('report-team'),
              initialValue: _teamId,
              items: <DropdownMenuItem<String>>[
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('Semua regu'),
                ),
                ..._teams.map(
                  (team) => DropdownMenuItem<String>(
                    value: team.id,
                    child: Text(team.name),
                  ),
                ),
              ],
              onChanged: (String? value) => setState(() => _teamId = value),
              decoration: const InputDecoration(labelText: 'Regu'),
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
              _loading ? 'Menyiapkan ekspor...' : 'Buat dan bagikan PDF',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _loading ? null : _exportCsv,
            icon: const Icon(Icons.table_view_rounded),
            label: const Text('Ekspor CSV untuk Excel'),
          ),
          const SizedBox(height: 26),
          const Text('Lembar harian lain', style: AppTextStyles.sectionTitle),
          const SizedBox(height: 4),
          const Text(
            'Cetak semua lembar pada rentang tanggal di atas dalam satu PDF, '
            'satu halaman per lembar dengan formulir aslinya.',
            style: AppTextStyles.supporting,
          ),
          const SizedBox(height: 10),
          for (final type in DailyCheckFormType.values) ...<Widget>[
            OutlinedButton.icon(
              onPressed: _loading ? null : () => _printDaily(type),
              icon: Icon(type.form.icon),
              label: Text('Cetak ${type.form.title}'),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    ),
  );

  Future<void> _printDaily(DailyCheckFormType type) async {
    if (_from.isAfter(_to)) {
      _message('Tanggal mulai tidak boleh setelah tanggal akhir.');
      return;
    }
    setState(() => _loading = true);
    try {
      final repository = DailyCheckRepository();
      await repository.loadThresholds();
      final sheets = (await repository.listRange(type, _from, _to))
          .where((sheet) => _teamId == null || sheet.teamId == _teamId)
          .toList(growable: false);
      if (sheets.isEmpty) {
        _message('Tidak ada lembar ${type.form.title} pada rentang ini.');
        return;
      }
      await printDailyCheckSheets(type, sheets, _from, _to);
    } on Object catch (error) {
      _message('PDF tidak dapat dibuat: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _dateTile(String title, DateTime date, VoidCallback onTap) => Card(
    child: ListTile(
      onTap: onTap,
      leading: const Icon(Icons.calendar_month_rounded, color: AppColors.green),
      title: Text(title),
      subtitle: Text(_date(date)),
    ),
  );
}
