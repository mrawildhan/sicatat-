import 'sicatat_types.dart';

class OperationalBudgetMonth {
  const OperationalBudgetMonth({
    required this.site,
    required this.period,
    required this.budgetUsd,
    required this.actualUsd,
    required this.syncedAt,
  });

  factory OperationalBudgetMonth.fromJson(JsonMap json) =>
      OperationalBudgetMonth(
        site: json.requiredString('site_code'),
        period: DateTime.parse(json.requiredString('period_start')),
        budgetUsd: (json['budget_usd'] as num?)?.toDouble() ?? 0,
        actualUsd: (json['actual_usd'] as num?)?.toDouble() ?? 0,
        syncedAt: DateTime.tryParse(json.optionalString('synced_at') ?? ''),
      );

  final String site;
  final DateTime period;
  final double budgetUsd;
  final double actualUsd;
  final DateTime? syncedAt;

  double get remainingUsd => budgetUsd - actualUsd;
}

class OperationalBudgetSummary {
  const OperationalBudgetSummary(this.months);

  final List<OperationalBudgetMonth> months;

  double get budgetUsd =>
      months.fold(0, (total, item) => total + item.budgetUsd);
  double get actualUsd =>
      months.fold(0, (total, item) => total + item.actualUsd);
  double get remainingUsd => budgetUsd - actualUsd;

  DateTime? get syncedAt {
    final List<DateTime> values = months
        .map((item) => item.syncedAt)
        .whereType<DateTime>()
        .toList(growable: false);
    if (values.isEmpty) return null;
    values.sort();
    return values.last;
  }

  List<OperationalBudgetMonth> forSite(String site) =>
      months.where((item) => item.site == site).toList(growable: false)
        ..sort((left, right) => left.period.compareTo(right.period));
}
