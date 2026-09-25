import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/preventive_maintenance_models.dart';
import '../maintenance_report.dart';

/// PM per crew and the age of all outstanding PM & CM, shown above the
/// PM & CM cards (owner request 2026-09-25).
class MaintenanceCharts extends StatelessWidget {
  const MaintenanceCharts({
    required this.pm,
    required this.cm,
    required this.today,
    super.key,
  });

  final List<PreventiveMaintenanceWorkOrder> pm;
  final List<CorrectiveMaintenanceWorkOrder> cm;
  final DateTime today;

  int _pm(String crew, String site) =>
      pm.where((item) => item.crew == crew && item.site == site).length;

  @override
  Widget build(BuildContext context) {
    final List<int> pmAges = maintenanceAgeCounts(
      pm.map((item) => item.raisedOn),
      today,
    );
    final List<int> cmAges = maintenanceAgeCounts(
      cm.map((item) => item.raisedOn),
      today,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ChartCard(
          title: 'PM tertunda per crew',
          legend: const <(String, Color)>[
            ('CPP', AppColors.green),
            ('PORT', AppColors.orange),
          ],
          // One labelled bar per crew and site: Crew A CPP, Crew A PORT, ...
          groups: <String>[
            for (final String crew in maintenanceCrews)
              for (final String site in maintenanceSites) 'Crew $crew\n$site',
          ],
          series: <List<int>>[
            <int>[
              for (final String crew in maintenanceCrews)
                for (final String site in maintenanceSites) _pm(crew, site),
            ],
          ],
          colors: const <Color>[AppColors.green],
          groupColors: <Color>[
            for (final String _ in maintenanceCrews) ...const <Color>[
              AppColors.green,
              AppColors.orange,
            ],
          ],
        ),
        const SizedBox(height: 10),
        _ChartCard(
          title: 'Umur pekerjaan sejak dibuat',
          legend: const <(String, Color)>[
            ('PM', AppColors.green),
            ('CM', AppColors.orange),
          ],
          groups: <String>[
            for (final MaintenanceAgeBucket bucket in maintenanceAgeBuckets)
              bucket.label,
          ],
          series: <List<int>>[pmAges, cmAges],
          colors: const <Color>[AppColors.green, AppColors.orange],
        ),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.legend,
    required this.groups,
    required this.series,
    required this.colors,
    this.groupColors,
  });

  final String title;
  final List<(String, Color)> legend;
  final List<String> groups;
  final List<List<int>> series;
  final List<Color> colors;

  /// Colour per group for a single-series chart (overrides [colors]).
  final List<Color>? groupColors;

  @override
  Widget build(BuildContext context) {
    final int maxValue = series
        .expand((List<int> values) => values)
        .fold(0, (int a, int b) => a > b ? a : b);
    // Room above the tallest bar for its value label.
    final double maxY = maxValue == 0 ? 1 : (maxValue * 1.25).ceilToDouble();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(title, style: AppTextStyles.cardTitle)),
                for (final (String name, Color color) in legend) ...<Widget>[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(name, style: AppTextStyles.supporting),
                  const SizedBox(width: 10),
                ],
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  alignment: BarChartAlignment.spaceAround,
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        const FlLine(color: AppColors.line, strokeWidth: 1),
                  ),
                  barTouchData: BarTouchData(
                    enabled: false,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => Colors.transparent,
                      tooltipPadding: EdgeInsets.zero,
                      tooltipMargin: 2,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                          BarTooltipItem(
                            rod.toY.toInt().toString(),
                            const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: groups.any((g) => g.contains('\n'))
                            ? 38
                            : 24,
                        getTitlesWidget: (double value, TitleMeta meta) {
                          final int index = value.toInt();
                          if (index < 0 || index >= groups.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              groups[index],
                              textAlign: TextAlign.center,
                              style: AppTextStyles.supporting.copyWith(
                                fontSize: 11,
                                height: 1.2,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: <BarChartGroupData>[
                    for (int g = 0; g < groups.length; g++)
                      BarChartGroupData(
                        x: g,
                        barsSpace: 4,
                        // Value labels always visible above each bar.
                        showingTooltipIndicators: <int>[
                          for (int s = 0; s < series.length; s++) s,
                        ],
                        barRods: <BarChartRodData>[
                          for (int s = 0; s < series.length; s++)
                            BarChartRodData(
                              toY: series[s][g].toDouble(),
                              color: groupColors?[g] ?? colors[s],
                              width: 14,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
