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

class OperationalBudgetItem {
  const OperationalBudgetItem({
    required this.site,
    required this.accountCode,
    required this.description,
    required this.budgetUsd,
    required this.actualUsd,
    required this.budgetMonths,
    required this.actualMonths,
    required this.peakPeriod,
    required this.peakActualUsd,
    required this.largestTransactionUsd,
    required this.largestTransactionDate,
    required this.largestTransactionNo,
  });

  factory OperationalBudgetItem.fromJson(JsonMap json) => OperationalBudgetItem(
    site: json.requiredString('site_code'),
    accountCode: json.requiredString('account_code'),
    description: json.requiredString('description'),
    budgetUsd: (json['budget_usd'] as num?)?.toDouble() ?? 0,
    actualUsd: (json['actual_usd'] as num?)?.toDouble() ?? 0,
    budgetMonths: _months(json['budget_months']),
    actualMonths: _months(json['actual_months']),
    peakPeriod: json.optionalString('peak_period'),
    peakActualUsd: (json['peak_actual_usd'] as num?)?.toDouble() ?? 0,
    largestTransactionUsd:
        (json['largest_transaction_usd'] as num?)?.toDouble() ?? 0,
    largestTransactionDate: DateTime.tryParse(
      json.optionalString('largest_transaction_date') ?? '',
    ),
    largestTransactionNo: json.optionalString('largest_transaction_no'),
  );

  final String site;
  final String accountCode;
  final String description;
  final double budgetUsd;
  final double actualUsd;
  final Map<String, double> budgetMonths;
  final Map<String, double> actualMonths;
  final String? peakPeriod;
  final double peakActualUsd;
  final double largestTransactionUsd;
  final DateTime? largestTransactionDate;
  final String? largestTransactionNo;

  double get remainingUsd => budgetUsd - actualUsd;
  bool get overBudget => actualUsd > budgetUsd;

  bool matches(String query) {
    final String value = query.trim().toLowerCase();
    return value.isEmpty ||
        accountCode.toLowerCase().contains(value) ||
        description.toLowerCase().contains(value) ||
        site.toLowerCase().contains(value);
  }
}

Map<String, double> _months(Object? value) {
  if (value is! Map) return const <String, double>{};
  return value.map<String, double>(
    (Object? key, Object? raw) => MapEntry(
      key.toString(),
      (raw as num?)?.toDouble() ?? double.tryParse(raw.toString()) ?? 0,
    ),
  );
}
