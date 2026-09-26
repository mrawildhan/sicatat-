import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/pdf/pdf_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/app_user.dart';
import '../../auth/application/current_user_provider.dart';
import '../../daily_checks/alert_follow_up.dart';
import '../../daily_checks/compliance.dart';
import '../monthly_report.dart';

/// Operasional → Laporan Bulanan: pick a month, see the headline figures,
/// share one PDF (owner request 2026-09-26).
class MonthlyReportScreen extends ConsumerStatefulWidget {
  const MonthlyReportScreen({super.key});

  @override
  ConsumerState<MonthlyReportScreen> createState() =>
      _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends ConsumerState<MonthlyReportScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  MonthlyReportData? _data;
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final AppUser? user = ref.read(currentUserProvider);
    final MonthlyReportData data = await loadMonthlyReport(
      Supabase.instance.client,
      _month,
      onlyTeamId: user?.role.isTeamScopedTemperature == true
          ? user?.teamId
          : null,
    );
    if (mounted) {
      setState(() {
        _data = data;
        _loading = false;
      });
    }
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  Future<void> _export() async {
    final MonthlyReportData? data = _data;
    if (data == null) return;
    setState(() => _exporting = true);
    try {
      final Uint8List bytes = await buildMonthlyReportPdf(
        data,
        theme: await loadPdfTheme(),
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'Laporan Bulanan SICATAT ${data.label}.pdf',
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('PDF gagal dibuat: $error')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final MonthlyReportData? data = _data;
    final DateTime current = DateTime(
      DateTime.now().year,
      DateTime.now().month,
    );
    return AppBackScope(
      fallbackRoute: '/dashboard',
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallbackRoute: '/dashboard'),
          title: const Text('Laporan Bulanan'),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _loading || _exporting ? null : _export,
          icon: _exporting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Buat PDF'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
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
                    DateFormat('MMMM yyyy', 'id_ID').format(_month),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.sectionTitle,
                  ),
                ),
                IconButton(
                  tooltip: 'Bulan berikutnya',
                  onPressed: _loading || !_month.isBefore(current)
                      ? null
                      : () => _shiftMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const Text(
              'Satu PDF berisi pemeriksaan suhu & kepatuhan, suhu kritis dan '
              'tindak lanjutnya, PM & CM, anggaran, PR, dan gudang. PM & CM, '
              'PO, dan pinjaman memakai posisi saat laporan dibuat.',
              style: AppTextStyles.supporting,
            ),
            const SizedBox(height: 12),
            if (_loading || data == null)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              ..._summary(data),
          ],
        ),
      ),
    );
  }

  List<Widget> _summary(MonthlyReportData data) {
    final ComplianceMonth? compliance = data.compliance;
    final List<TemperatureAlertRecord>? alerts = data.alerts;
    String percent(double rate) => '${(rate * 100).round()}%';
    Widget line(IconData icon, String title, String value) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.green),
      title: Text(title),
      trailing: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
      ),
    );
    return <Widget>[
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: <Widget>[
              if (compliance != null) ...<Widget>[
                line(
                  Icons.fact_check_outlined,
                  'Lembar terisi',
                  percent(compliance.filledRate),
                ),
                line(
                  Icons.timer_outlined,
                  'Lembar tepat waktu',
                  percent(compliance.onTimeRate),
                ),
              ],
              if (alerts != null)
                line(
                  Icons.thermostat_rounded,
                  'Suhu kritis (belum ditutup)',
                  '${alerts.length} (${alerts.where((a) => !a.isClosed).length})',
                ),
              if (data.pm != null)
                line(
                  Icons.pending_actions_outlined,
                  'PM tertunda',
                  '${data.pm!.length}',
                ),
              if (data.cm != null)
                line(
                  Icons.build_circle_outlined,
                  'CM tertunda',
                  '${data.cm!.length}',
                ),
              if (data.budget != null && data.budget!.lastActual != null)
                line(
                  Icons.account_balance_wallet_outlined,
                  'Aktual vs anggaran s.d. '
                  '${DateFormat('MMM', 'id_ID').format(data.budget!.lastActual!)}',
                  data.budget!.budgetToDate == 0
                      ? '-'
                      : percent(
                          data.budget!.actualToDate / data.budget!.budgetToDate,
                        ),
                ),
              if (data.prReleased != null)
                line(
                  Icons.request_quote_outlined,
                  'PR dirilis bulan ini',
                  '${data.prReleased!.length}',
                ),
              if (data.outstandingPo != null)
                line(
                  Icons.shopping_cart_outlined,
                  'PO belum datang (lewat jatuh tempo)',
                  '${data.outstandingPo} (${data.outstandingPoOverdue})',
                ),
              if (data.lateLoans != null)
                line(
                  Icons.handyman_outlined,
                  'Alat terlambat kembali',
                  '${data.lateLoans}',
                ),
            ],
          ),
        ),
      ),
      if (data.unavailable.isNotEmpty) ...<Widget>[
        const SizedBox(height: 8),
        Text(
          'Tidak termasuk untuk peran Anda: ${data.unavailable.join(', ')}.',
          style: AppTextStyles.supporting,
        ),
      ],
    ];
  }
}
