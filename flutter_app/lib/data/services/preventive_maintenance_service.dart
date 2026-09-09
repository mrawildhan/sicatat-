import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/preventive_maintenance_models.dart';
import '../models/sicatat_types.dart';

class PreventiveMaintenanceService {
  const PreventiveMaintenanceService(this._client);

  final SupabaseClient _client;

  Future<PreventiveMaintenanceSyncResult> synchronize() async {
    final FunctionResponse response = await _client.functions.invoke(
      'sync-preventive-maintenance',
    );
    final JsonMap data = requireJsonMap(response.data, source: 'PM sync');
    if (data['ok'] != true) {
      throw FormatException(
        data.optionalString('error') ?? 'Data PM tidak dapat diperbarui.',
      );
    }
    return PreventiveMaintenanceSyncResult(
      changed: data['changed'] == true,
      rows: (data['rows'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.tryParse(data.optionalString('synced_at') ?? ''),
    );
  }

  Future<List<PreventiveMaintenanceWorkOrder>> loadOutstanding() async {
    final Object response = await _client
        .from('preventive_maintenance_work_order')
        .select(
          'work_order,work_order_description,equipment_reference,crew_code,site_code,status_code,raised_on,planned_start_on,assigned_to,assigned_to_description,priority,priority_description',
        )
        .order('site_code')
        .order('crew_code')
        .order('planned_start_on')
        .order('work_order');
    if (response is! List) {
      throw const FormatException(
        'Data PM mengembalikan format yang tidak valid.',
      );
    }
    return response
        .cast<Object?>()
        .map(
          (Object? row) =>
              PreventiveMaintenanceWorkOrder.fromJson(requireJsonMap(row)),
        )
        .toList(growable: false);
  }
}
