import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/operational_budget_models.dart';
import '../models/sicatat_types.dart';

class OperationalBudgetService {
  const OperationalBudgetService(this._client);

  final SupabaseClient _client;

  Future<void> synchronize() async {
    late final FunctionResponse response;
    try {
      response = await _client.functions.invoke('sync-operational-budget');
    } on FunctionException catch (error) {
      final Object? details = error.details;
      if (details is Map<Object?, Object?> && details['error'] != null) {
        throw FormatException(details['error'].toString());
      }
      rethrow;
    }
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

  Future<List<OperationalBudgetItem>> loadItems() async {
    final Object response = await _client
        .from('operational_budget_item')
        .select(
          'site_code,account_code,description,budget_usd,actual_usd,'
          'budget_months,actual_months,peak_period,peak_actual_usd,'
          'largest_transaction_usd,largest_transaction_date,'
          'largest_transaction_no',
        )
        .inFilter('site_code', const <String>['CPP', 'PORT'])
        .order('actual_usd', ascending: false);
    if (response is! List) {
      throw const FormatException(
        'Rincian anggaran mengembalikan format tidak valid.',
      );
    }
    return response
        .cast<Object?>()
        .map(
          (Object? row) => OperationalBudgetItem.fromJson(requireJsonMap(row)),
        )
        .toList(growable: false);
  }
}
