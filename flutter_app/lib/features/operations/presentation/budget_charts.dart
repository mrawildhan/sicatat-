import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/operational_budget_models.dart';

/// Budget against actual (owner request 2026-09-26): cumulative spend, a
/// straight-line projection to December, and the cost elements that are
/// already above their budget.
class BudgetAnalysis {
  BudgetAnalysis(this.summary, this.items, {List<String>? sites})
    : sites = sites ?? const <String>['CPP', 'PORT'];

  final OperationalBudgetSummary summary;
  final List<OperationalBudgetItem> items;
  final List<String> sites;

  List<DateTime> get periods {
    final List<DateTime> values =
        summary.months
            .map(
              (OperationalBudgetMonth m) =>
                  DateTime(m.period.year, m.period.month),
            )
            .toSet()
            .toList()
          ..sort();
    return values;
  }

  double budgetOf(DateTime period) => summary.months
      .where(
        (m) => m.period.year == period.year && m.period.month == period.month,
      )
      .fold<double>(
        0,
        (double sum, OperationalBudgetMonth m) => sum + m.budgetUsd,
      );

  double actualOf(DateTime period) => summary.months
      .where(
        (m) => m.period.year == period.year && m.period.month == period.month,
      )
      .fold<double>(
        0,
        (double sum, OperationalBudgetMonth m) => sum + m.actualUsd,
      );

  /// The last month with any actual cost recorded.
  DateTime? get lastActual {
    DateTime? last;
    for (final DateTime period in periods) {
      if (actualOf(period) > 0) last = period;
    }
    return last;
  }

  List<DateTime> get _toDate {
    final DateTime? last = lastActual;
    return last == null
        ? const <DateTime>[]
        : periods.where((DateTime p) => !p.isAfter(last)).toList();
  }

  double get budgetToDate =>
      _toDate.fold<double>(0, (double sum, DateTime p) => sum + budgetOf(p));

  double get actualToDate =>
      _toDate.fold<double>(0, (double sum, DateTime p) => sum + actualOf(p));

  double get budgetYear =>
      periods.fold<double>(0, (double sum, DateTime p) => sum + budgetOf(p));

  /// Average actual per month so far, times the months of the year.
  double get projectedYear {
    final int months = _toDate.length;
    if (months == 0) return 0;
    return actualToDate / months * periods.length;
  }

  /// Cost elements whose actual up to [lastActual] is above their budget
  /// for the same months, largest overspend first.
  List<(OperationalBudgetItem item, double budget, double actual)>
  get overspent {
    final Set<String> keys = <String>{
      for (final DateTime p in _toDate)
        '${p.year}${p.month.toString().padLeft(2, '0')}',
    };
    final List<(OperationalBudgetItem, double, double)> result =
        <(OperationalBudgetItem, double, double)>[];
    for (final OperationalBudgetItem item in items) {
      double budget = 0;
      double actual = 0;
      for (final String key in keys) {
        budget += item.budgetMonths[key] ?? 0;
        actual += item.actualMonths[key] ?? 0;
      }
      if (actual > budget && actual > 0) result.add((item, budget, actual));
    }
    result.sort((a, b) => (b.$3 - b.$2).compareTo(a.$3 - a.$2));
    return result;
  }
}

String budgetUsd(double value) =>
    'US\$${NumberFormat.decimalPattern('id_ID').format(value.round())}';

String _compact(double value) => value >= 1000
    ? '${NumberFormat.decimalPattern('id_ID').format((value / 1000).round())}rb'
    : value.round().toString();

class BudgetCharts extends StatelessWidget {
  const BudgetCharts({
    required this.summary,
    required this.items,
    required this.onOpenItem,
    super.key,
  });

  final OperationalBudgetSummary summary;
  final List<OperationalBudgetItem> items;
  final ValueChanged<OperationalBudgetItem> onOpenItem;

  @override
  Widget build(BuildContext context) {
    final BudgetAnalysis analysis = BudgetAnalysis(summary, items);
    final DateTime? last = analysis.lastActual;
    final List<DateTime> periods = analysis.periods;
    if (periods.isEmpty) return const SizedBox.shrink();
    final String lastLabel = last == null
        ? '-'
        : DateFormat('MMMM', 'id_ID').format(last);
    final double rate = analysis.budgetToDate == 0
        ? 0
        : analysis.actualToDate / analysis.budgetToDate;
    final bool overYear = analysis.projectedYear > analysis.budgetYear;
    final List<(OperationalBudgetItem, double, double)> over =
        analysis.overspent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Grafik anggaran vs aktual',
          style: AppTextStyles.sectionTitle,
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('Per bulan', style: AppTextStyles.cardTitle),
                const SizedBox(height: 10),
                SizedBox(height: 170, child: _monthly(analysis, periods)),
                const SizedBox(height: 6),
                const Wrap(
                  spacing: 12,
                  children: <Widget>[
                    _Legend('Anggaran', AppColors.line),
                    _Legend('Aktual', AppColors.green),
                    _Legend('Aktual di atas anggaran', AppColors.danger),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Kumulatif & proyeksi',
                  style: AppTextStyles.cardTitle,
                ),
                const SizedBox(height: 4),
                Text(
                  last == null
                      ? 'Aktual belum diunggah.'
                      : 'Aktual s.d. $lastLabel ${budgetUsd(analysis.actualToDate)} '
                            'dari anggaran s.d. $lastLabel '
                            '${budgetUsd(analysis.budgetToDate)} '
                            '(${(rate * 100).round()}%).',
                  style: AppTextStyles.supporting,
                ),
                if (last != null)
                  Text(
                    'Proyeksi akhir tahun ${budgetUsd(analysis.projectedYear)} '
                    'vs anggaran setahun ${budgetUsd(analysis.budgetYear)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: overYear ? AppColors.danger : AppColors.green,
                    ),
                  ),
                const SizedBox(height: 10),
                SizedBox(height: 170, child: _cumulative(analysis, periods)),
                const SizedBox(height: 6),
                const Wrap(
                  spacing: 12,
                  children: <Widget>[
                    _Legend('Anggaran kumulatif', AppColors.muted),
                    _Legend('Aktual kumulatif', AppColors.green),
                    _Legend('Proyeksi', AppColors.orange),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Proyeksi = rata-rata aktual per bulan dikali 12.',
                  style: AppTextStyles.supporting,
                ),
              ],
            ),
          ),
        ),
        if (last != null) ...<Widget>[
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Melebihi anggaran s.d. $lastLabel (${over.length})',
                    style: AppTextStyles.cardTitle,
                  ),
                  const SizedBox(height: 4),
                  if (over.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Tidak ada elemen biaya di atas anggaran.',
                        style: AppTextStyles.supporting,
                      ),
                    )
                  else
                    for (final (
                          OperationalBudgetItem item,
                          double budget,
                          double actual,
                        )
                        in over.take(8))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${item.site} · ${item.description}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          'Aktual ${budgetUsd(actual)} · anggaran ${budgetUsd(budget)}',
                        ),
                        trailing: Text(
                          '+${budgetUsd(actual - budget)}',
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        onTap: () => onOpenItem(item),
                      ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _monthly(BudgetAnalysis analysis, List<DateTime> periods) {
    double top = 1;
    for (final DateTime p in periods) {
      top = <double>[
        top,
        analysis.budgetOf(p),
        analysis.actualOf(p),
      ].reduce((double a, double b) => a > b ? a : b);
    }
    return BarChart(
      BarChartData(
        maxY: top * 1.1,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.line, strokeWidth: 1),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
              '${rodIndex == 0 ? 'Anggaran' : 'Aktual'} ${budgetUsd(rod.toY)}',
              const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (double value, TitleMeta meta) => Text(
                _compact(value),
                style: const TextStyle(fontSize: 9, color: AppColors.muted),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 18,
              getTitlesWidget: (double value, TitleMeta meta) {
                final int i = value.toInt();
                if (i < 0 || i >= periods.length) return const SizedBox();
                return Text(
                  DateFormat('MMM', 'id_ID').format(periods[i]).substring(0, 3),
                  style: const TextStyle(fontSize: 10, color: AppColors.muted),
                );
              },
            ),
          ),
        ),
        barGroups: <BarChartGroupData>[
          for (int i = 0; i < periods.length; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 1,
              barRods: <BarChartRodData>[
                BarChartRodData(
                  toY: analysis.budgetOf(periods[i]),
                  color: AppColors.line,
                  width: 7,
                ),
                BarChartRodData(
                  toY: analysis.actualOf(periods[i]),
                  color:
                      analysis.actualOf(periods[i]) >
                          analysis.budgetOf(periods[i])
                      ? AppColors.danger
                      : AppColors.green,
                  width: 7,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cumulative(BudgetAnalysis analysis, List<DateTime> periods) {
    final DateTime? last = analysis.lastActual;
    final List<FlSpot> budget = <FlSpot>[];
    final List<FlSpot> actual = <FlSpot>[];
    final List<FlSpot> projection = <FlSpot>[];
    double b = 0;
    double a = 0;
    final int months = last == null
        ? 0
        : periods.where((DateTime p) => !p.isAfter(last)).length;
    final double perMonth = months == 0 ? 0 : analysis.actualToDate / months;
    for (int i = 0; i < periods.length; i++) {
      b += analysis.budgetOf(periods[i]);
      budget.add(FlSpot(i.toDouble(), b));
      if (last != null && !periods[i].isAfter(last)) {
        a += analysis.actualOf(periods[i]);
        actual.add(FlSpot(i.toDouble(), a));
        if (i == months - 1) projection.add(FlSpot(i.toDouble(), a));
      } else if (months > 0) {
        projection.add(
          FlSpot(
            i.toDouble(),
            analysis.actualToDate + perMonth * (i + 1 - months),
          ),
        );
      }
    }
    final double top = <double>[
      b,
      if (projection.isNotEmpty) projection.last.y,
      a,
    ].reduce((double x, double y) => x > y ? x : y);
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: top * 1.1 + 1,
        minX: 0,
        maxX: (periods.length - 1).toDouble(),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.line, strokeWidth: 1),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (List<LineBarSpot> spots) => <LineTooltipItem>[
              for (final LineBarSpot spot in spots)
                LineTooltipItem(
                  budgetUsd(spot.y),
                  TextStyle(color: spot.bar.color, fontSize: 11),
                ),
            ],
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (double value, TitleMeta meta) => Text(
                _compact(value),
                style: const TextStyle(fontSize: 9, color: AppColors.muted),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 18,
              interval: 1,
              getTitlesWidget: (double value, TitleMeta meta) {
                final int i = value.toInt();
                if (i < 0 || i >= periods.length || i.isOdd) {
                  return const SizedBox();
                }
                return Text(
                  DateFormat('MMM', 'id_ID').format(periods[i]).substring(0, 3),
                  style: const TextStyle(fontSize: 10, color: AppColors.muted),
                );
              },
            ),
          ),
        ),
        lineBarsData: <LineChartBarData>[
          LineChartBarData(
            spots: budget,
            color: AppColors.muted,
            barWidth: 2,
            dashArray: const <int>[5, 4],
            dotData: const FlDotData(show: false),
          ),
          if (actual.isNotEmpty)
            LineChartBarData(
              spots: actual,
              color: AppColors.green,
              barWidth: 3,
              dotData: const FlDotData(show: true),
            ),
          if (projection.length > 1)
            LineChartBarData(
              spots: projection,
              color: AppColors.orange,
              barWidth: 2,
              dashArray: const <int>[3, 3],
              dotData: const FlDotData(show: false),
            ),
        ],
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
      Container(width: 12, height: 8, color: color),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}
