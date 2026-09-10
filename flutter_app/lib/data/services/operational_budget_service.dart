import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/operational_budget_models.dart';
import '../models/sicatat_types.dart';

class OperationalBudgetService {
  const OperationalBudgetService(this._client);

  final SupabaseClient _client;

  Future<void> synchronize() async {
    final FunctionResponse response = await _client.functions.invoke(
      'sync-operational-budget',
    );
    final JsonMap data = requireJsonMap(
      response.data,
      source: 'Sinkron anggaran',
    );
    if (data['ok'] != true) {
      throw FormatException(
        data.optionalString('error') ?? 'Data anggaran tidak dapat diperbarui.',
      );
    }
  }

  Future<OperationalBudgetSummary> loadSummary() async {
    final Object response = await _client
        .from('operational_budget_month')
        .select('site_code,period_start,budget_usd,actual_usd,synced_at')
        .inFilter('site_code', const <String>['CPP', 'PORT'])
        .gte('period_start', '2026-01-01')
        .lte('period_start', '2026-06-01')
        .order('period_start')
        .order('site_code');
    if (response is! List) {
      throw const FormatException(
        'Data anggaran mengembalikan format tidak valid.',
      );
    }
    return OperationalBudgetSummary(
      response
          .cast<Object?>()
          .map(
            (Object? row) =>
                OperationalBudgetMonth.fromJson(requireJsonMap(row)),
          )
          .toList(growable: false),
    );
  }
}
