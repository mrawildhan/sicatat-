import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/material_request_models.dart';
import '../models/sicatat_types.dart';

class MaterialRequestService {
  MaterialRequestService(this._client);

  final SupabaseClient _client;

  static const String _select =
      'id,request_area,item_name,quantity,unit,need_type,reason,status,planner_note,requested_by,processed_by,processed_at,created_at,requester:requested_by(name)';

  Future<List<MaterialRequest>> loadAll() async {
    final Object response = await _client
        .from('material_request')
        .select(_select)
        .order('created_at', ascending: false);
    if (response is! List) {
      throw const FormatException('Data permintaan barang tidak valid.');
    }
    return response
        .map(
          (Object? row) => MaterialRequest.fromJson(
            requireJsonMap(row, source: 'permintaan barang'),
          ),
        )
        .toList(growable: false);
  }

  Future<MaterialRequest> submit({
    required String actorId,
    required MaterialRequestArea area,
    required String itemName,
    required num quantity,
    required String unit,
    required MaterialNeedType needType,
    required String reason,
  }) async {
    final Object response = await _client
        .from('material_request')
        .insert(<String, Object?>{
          'requested_by': actorId,
          'request_area': area.storageValue,
          'item_name': itemName.trim(),
          'quantity': quantity,
          'unit': unit.trim(),
          'need_type': needType.storageValue,
          'reason': reason.trim(),
        })
        .select(_select)
        .single();
    return MaterialRequest.fromJson(
      requireJsonMap(response, source: 'permintaan barang'),
    );
  }

  Future<MaterialRequest> updateStatus({
    required String id,
    required String plannerId,
    required MaterialRequestStatus status,
    required String plannerNote,
  }) async {
    if (status == MaterialRequestStatus.submitted) {
      throw const FormatException('Pilih status diproses atau ditolak.');
    }
    final Object response = await _client
        .from('material_request')
        .update(<String, Object?>{
          'status': status.storageValue,
          'planner_note': plannerNote.trim(),
          'processed_by': plannerId,
        })
        .eq('id', id)
        .select(_select)
        .single();
    return MaterialRequest.fromJson(
      requireJsonMap(response, source: 'permintaan barang'),
    );
  }
}
