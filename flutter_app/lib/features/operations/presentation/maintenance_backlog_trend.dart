import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/sicatat_types.dart';

/// One day of `maintenance_backlog_snapshot` (recorded daily at 23:30 WITA
/// since 2026-09-26, owner request: is the backlog shrinking?).
class BacklogPoint {
  BacklogPoint(this.day);

  final DateTime day;
  int pm = 0;
  int pmOverdue = 0;
  int cm = 0;
  int cmOld = 0;

  /// "A CPP" → PM count.
  final Map<String, int> pmByCrewSite = <String, int>{};
  final Map<String, int> cmBySite = <String, int>{};
}

Future<List<BacklogPoint>> loadBacklogHistory(
  SupabaseClient client, {
  int days = 120,
}) async {
  final DateTime since = DateTime.now().subtract(Duration(days: days));
  final Object rows = await client
      .from('maintenance_backlog_snapshot')
      .select('taken_on,kind,crew_code,site_code,outstanding,overdue')
      .gte('taken_on', DateFormat('yyyy-MM-dd').format(since))
      .order('taken_on', ascending: true)
      .limit(5000);
  final Map<String, BacklogPoint> byDay = <String, BacklogPoint>{};
  if (rows is List) {
    for (final Object? raw in rows) {
      final JsonMap row = requireJsonMap(raw, source: 'backlog snapshot');
      final String day = row.requiredString('taken_on');
      final BacklogPoint point = byDay.putIfAbsent(
        day,
        () => BacklogPoint(DateTime.parse(day)),
      );
      final int count = (row['outstanding'] as num?)?.toInt() ?? 0;
      final int overdue = (row['overdue'] as num?)?.toInt() ?? 0;
      final String site = row.optionalString('site_code') ?? '';
      if (row['kind'] == 'pm') {
        point.pm += count;
        point.pmOverdue += overdue;
        final String key = '${row.optionalString('crew_code') ?? ''} $site';
        point.pmByCrewSite[key] = (point.pmByCrewSite[key] ?? 0) + count;
      } else {
        point.cm += count;
        point.cmOld += overdue;
        point.cmBySite[site] = (point.cmBySite[site] ?? 0) + count;
      }
    }
  }
  return byDay.values.toList(growable: false);
}

/// The newest point at least [days] before the last one.
BacklogPoint? backlogPointBefore(List<BacklogPoint> points, int days) {
  if (points.isEmpty) return null;
  final DateTime limit = points.last.day.subtract(Duration(days: days));
  BacklogPoint? found;
  for (final BacklogPoint point in points) {
    if (!point.day.isAfter(limit)) found = point;
  }
  return found;
}

class MaintenanceBacklogTrend extends StatefulWidget {
  const MaintenanceBacklogTrend({super.key});

  @override
  State<MaintenanceBacklogTrend> createState() =>
      _MaintenanceBacklogTrendState();
}

class _MaintenanceBacklogTrendState extends State<MaintenanceBacklogTrend> {
  List<BacklogPoint>? _points;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<BacklogPoint> points = await loadBacklogHistory(
        Supabase.instance.client,
      );
      if (mounted) setState(() => _points = points);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<BacklogPoint>? points = _points;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Tren backlog PM & CM', style: AppTextStyles.cardTitle),
            const SizedBox(height: 2),
            const Text(
              'Jumlah tertunda tercatat setiap hari pukul 23.30 WITA.',
              style: AppTextStyles.supporting,
            ),
            const SizedBox(height: 10),
            if (_error != null)
              Text('Riwayat belum dapat dimuat. $_error')
            else if (points == null)
              const LinearProgressIndicator()
            else if (points.isEmpty)
              const Text('Belum ada riwayat.', style: AppTextStyles.supporting)
            else ...<Widget>[
              _comparison(points),
              const SizedBox(height: 12),
              if (points.length < 2)
                Text(
                  'Riwayat dimulai ${DateFormat('d MMMM yyyy', 'id_ID').format(points.first.day)}; '
                  'garis tren muncul setelah dua hari data.',
                  style: AppTextStyles.supporting,
                )
              else
                _chart(points),
              const SizedBox(height: 8),
              const Wrap(
                spacing: 12,
                children: <Widget>[
                  _Legend('PM tertunda', AppColors.green),
                  _Legend('PM lewat rencana', AppColors.orange),
                  _Legend('CM tertunda', AppColors.danger),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _comparison(List<BacklogPoint> points) {
    final BacklogPoint now = points.last;
    final BacklogPoint? week = backlogPointBefore(points, 7);
    final BacklogPoint? month = backlogPointBefore(points, 30);
    Widget delta(int current, int? before) {
      if (before == null) {
        return const Text('-', style: AppTextStyles.supporting);
      }
      final int change = current - before;
      final Color color = change > 0
          ? AppColors.danger
          : change < 0
          ? AppColors.green
          : AppColors.muted;
      return Text(
        change == 0 ? '±0' : (change > 0 ? '+$change' : '$change'),
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      );
    }

    TableRow row(String label, int current, int? w, int? m) => TableRow(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(label),
        ),
        Text(
          '$current',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        Center(child: delta(current, w)),
        Center(child: delta(current, m)),
      ],
    );

    return Table(
      columnWidths: const <int, TableColumnWidth>{0: FlexColumnWidth(2)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: <TableRow>[
        const TableRow(
          children: <Widget>[
            SizedBox(),
            Text(
              'Sekarang',
              textAlign: TextAlign.center,
              style: AppTextStyles.supporting,
            ),
            Text(
              'vs 7 hari',
              textAlign: TextAlign.center,
              style: AppTextStyles.supporting,
            ),
            Text(
              'vs 30 hari',
              textAlign: TextAlign.center,
              style: AppTextStyles.supporting,
            ),
          ],
        ),
        row('PM tertunda', now.pm, week?.pm, month?.pm),
        row(
          'PM lewat rencana',
          now.pmOverdue,
          week?.pmOverdue,
          month?.pmOverdue,
        ),
        row('CM tertunda', now.cm, week?.cm, month?.cm),
      ],
    );
  }

  Widget _chart(List<BacklogPoint> points) {
    final DateTime first = points.first.day;
    double x(BacklogPoint p) => p.day.difference(first).inDays.toDouble();
    final double maxX = x(points.last);
    final int top = points
        .map((BacklogPoint p) => p.pm > p.cm ? p.pm : p.cm)
        .reduce((int a, int b) => a > b ? a : b);
    LineChartBarData line(int Function(BacklogPoint) value, Color color) =>
        LineChartBarData(
          spots: <FlSpot>[
            for (final BacklogPoint p in points)
              FlSpot(x(p), value(p).toDouble()),
          ],
          color: color,
          barWidth: 2.5,
          dotData: FlDotData(show: points.length <= 20),
        );
    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX == 0 ? 1 : maxX,
          minY: 0,
          maxY: (top * 1.15).ceilToDouble() + 1,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: AppColors.line, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 32),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: maxX <= 7 ? 1 : (maxX / 5).ceilToDouble(),
                getTitlesWidget: (double value, TitleMeta meta) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    DateFormat('d/M')
                        .format(first.add(Duration(days: value.round()))),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
          lineBarsData: <LineChartBarData>[
            line((BacklogPoint p) => p.pm, AppColors.green),
            line((BacklogPoint p) => p.pmOverdue, AppColors.orange),
            line((BacklogPoint p) => p.cm, AppColors.danger),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Container(width: 12, height: 3, color: color),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}
