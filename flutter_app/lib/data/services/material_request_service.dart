import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/material_request_models.dart';
import '../reports/meeting_minute_photo_compressor.dart';
import '../models/sicatat_types.dart';

class MaterialRequestService {
  MaterialRequestService(this._client);

  final SupabaseClient _client;

  static const String _select =
      'id,request_area,item_name,quantity,unit,need_type,reason,product_url,photo_path,photo_mime,status,planner_note,requested_by,processed_by,processed_at,created_at,requester:requested_by(name)';

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

  static const String photoBucket = 'material-request-photos';

  /// Compresses and uploads the optional item photo.
  ///
  /// The request row does not exist yet when the form is submitted, so the
  /// object lives under the requester's own id, which is also what the storage
  /// policy checks.
  Future<MaterialRequestPhoto> uploadPhoto({
    required String actorId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (bytes.isEmpty) {
      throw const FormatException('Berkas foto kosong.');
    }
    final CompressedMeetingMinutePhoto compressed =
        MeetingMinutePhotoCompressor.compress(bytes: bytes, fileName: fileName);
    final String safeName = compressed.fileName.replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '-',
    );
    final String storagePath =
        '$actorId/${DateTime.now().microsecondsSinceEpoch}-$safeName';
    await _client.storage
        .from(photoBucket)
        .uploadBinary(
          storagePath,
          compressed.bytes,
          fileOptions: FileOptions(
            contentType: compressed.mimeType,
            upsert: false,
          ),
        );
    return MaterialRequestPhoto(
      storagePath: storagePath,
      mimeType: compressed.mimeType,
      sizeBytes: compressed.bytes.lengthInBytes,
    );
  }

  Future<void> removePhoto(String storagePath) =>
      _client.storage.from(photoBucket).remove(<String>[storagePath]);

  Future<String> photoUrl(String storagePath) =>
      _client.storage.from(photoBucket).createSignedUrl(storagePath, 3600);

  Future<MaterialRequest> submit({
    required String actorId,
    required MaterialRequestArea area,
    required String itemName,
    required num quantity,
    required String unit,
    required MaterialNeedType needType,
    required String reason,
    String? productUrl,
    MaterialRequestPhoto? photo,
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
          // A link typed as "www..." is completed here, and anything that is
          // still not an address is stored as nothing rather than as junk.
          'product_url': MaterialRequestProductLink.normalize(productUrl),
          'photo_path': photo?.storagePath,
          'photo_mime': photo?.mimeType,
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

/// An uploaded item photo waiting to be attached to a request.
class MaterialRequestPhoto {
  const MaterialRequestPhoto({
    required this.storagePath,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String storagePath;
  final String mimeType;
  final int sizeBytes;
}
