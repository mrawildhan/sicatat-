import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/purchase_requisition_models.dart';
import '../models/sicatat_types.dart';

class PurchaseRequisitionService {
  const PurchaseRequisitionService(this._client);

  final SupabaseClient _client;

  static const String _fields =
      'id,no_pr,no_po,description,equip_ref,closed_date,release_date,status';

  Future<void> synchronize() async {
    late final FunctionResponse response;
    try {
      response = await _client.functions.invoke('sync-purchase-requisitions');
    } on FunctionException catch (error) {
      final Object? details = error.details;
      if (details is Map<Object?, Object?> && details['error'] != null) {
        throw FormatException(details['error'].toString());
      }
      rethrow;
    }
    final JsonMap data = requireJsonMap(
      response.data,
      source: 'Sinkron data PR',
    );
    if (data['ok'] != true) {
      throw FormatException(
        data.optionalString('error') ?? 'Data PR tidak dapat diperbarui.',
      );
    }
  }

  Future<PurchaseRequisitionSnapshot?> loadSnapshot() async {
    final Object response = await _client
        .from('purchase_requisition_sync_log')
        .select('snapshot_rows,completed_at')
        .eq('status', 'completed')
        .order('completed_at', ascending: false)
        .limit(1);
    if (response is! List || response.isEmpty) return null;
    return PurchaseRequisitionSnapshot.fromJson(
      requireJsonMap(response.first, source: 'Status data PR'),
    );
  }

  Future<List<PurchaseRequisition>> search(
    String query, {
    PurchaseRequisitionSort sort = PurchaseRequisitionSort.arrivalNewest,
  }) async {
    final String value = _safeSearch(query);
    final Object response;
    if (value.isEmpty) {
      response = await _client
          .from('purchase_requisition')
          .select(_fields)
          .order('closed_date', ascending: sort.ascending, nullsFirst: false)
          .order('release_date', ascending: sort.ascending, nullsFirst: false)
          .limit(60);
    } else {
      response = await _client
          .from('purchase_requisition')
          .select(_fields)
          .or(
            'no_pr.ilike.%$value%,no_po.ilike.%$value%,'
            'description.ilike.%$value%,equip_ref.ilike.%$value%',
          )
          .order('closed_date', ascending: sort.ascending, nullsFirst: false)
          .order('release_date', ascending: sort.ascending, nullsFirst: false)
          .limit(60);
    }
    if (response is! List) {
      throw const FormatException('Data PR mengembalikan format tidak valid.');
    }
    return response
        .cast<Object?>()
        .map(
          (Object? item) => PurchaseRequisition.fromJson(
            requireJsonMap(item, source: 'Data PR'),
          ),
        )
        .toList(growable: false);
  }

  String _safeSearch(String value) => value
      .trim()
      .replaceAll(RegExp(r'[%(),.]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}
