import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../data/models/sicatat_types.dart';
import 'major_job_models.dart';

class MajorJobApiException implements Exception {
  const MajorJobApiException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Talks to the Cloudflare Worker that stores Major Job data (D1 + KV).
/// Requests carry the signed-in user's Supabase access token; the Worker
/// verifies it and only accepts active admins.
class MajorJobApi {
  MajorJobApi({
    http.Client? client,
    String? baseUrl,
    Future<String?> Function()? accessToken,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.majorJobApiUrl,
       _accessToken = accessToken ?? _supabaseAccessToken;

  final http.Client _client;
  final String _baseUrl;
  final Future<String?> Function() _accessToken;

  /// Photo bytes never change behind an id, so they are kept for the session.
  static final Map<String, Uint8List> _photoCache = <String, Uint8List>{};

  static Future<String?> _supabaseAccessToken() async {
    final GoTrueClient auth = Supabase.instance.client.auth;
    Session? session = auth.currentSession;
    if (session == null) return null;
    if (session.isExpired) {
      session = (await auth.refreshSession()).session;
    }
    return session?.accessToken;
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Object? json,
    Uint8List? bytes,
    String? contentType,
  }) async {
    final String? token = await _accessToken();
    if (token == null) {
      throw const MajorJobApiException(
        'Sesi login berakhir. Silakan masuk kembali.',
        401,
      );
    }
    final http.Request request = http.Request(
      method,
      Uri.parse('$_baseUrl$path'),
    )..headers['authorization'] = 'Bearer $token';
    if (json != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(json);
    } else if (bytes != null) {
      request.headers['content-type'] = contentType ?? 'image/jpeg';
      request.bodyBytes = bytes;
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request));
    } on Object {
      throw const MajorJobApiException(
        'Server Major Job tidak dapat dihubungi. Periksa koneksi internet.',
      );
    }
    if (response.statusCode >= 400) {
      String message = 'Permintaan gagal (${response.statusCode}).';
      try {
        final Object? body = jsonDecode(response.body);
        if (body is Map && body['error'] is String) {
          message = body['error'] as String;
        }
      } on FormatException {
        // Keep the generic message.
      }
      throw MajorJobApiException(message, response.statusCode);
    }
    return response;
  }

  JsonMap _json(http.Response response) =>
      requireJsonMap(jsonDecode(response.body), source: 'Major Job');

  /// Jobs dated [from]..[to] inclusive (a month screen spans its weeks, which
  /// may start in the previous month; see `majorJobMonthRange`).
  Future<List<MajorJob>> listRange(DateTime from, DateTime to) async {
    final JsonMap body = _json(
      await _send(
        'GET',
        '/jobs?from=${majorJobIsoDate(from)}&to=${majorJobIsoDate(to)}',
      ),
    );
    final Object? jobs = body['jobs'];
    if (jobs is! List) return <MajorJob>[];
    return jobs
        .map((Object? item) =>
            MajorJob.fromJson(requireJsonMap(item, source: 'pekerjaan')))
        .toList();
  }

  Future<MajorJob> get(String id) async => MajorJob.fromJson(
    requireJsonMap(
      _json(await _send('GET', '/jobs/${Uri.encodeComponent(id)}'))['job'],
      source: 'pekerjaan',
    ),
  );

  Future<MajorJob> create({
    required DateTime workDate,
    required String description,
  }) async => MajorJob.fromJson(
    requireJsonMap(
      _json(
        await _send(
          'POST',
          '/jobs',
          json: <String, Object?>{
            'work_date': majorJobIsoDate(workDate),
            'description': description,
          },
        ),
      )['job'],
      source: 'pekerjaan',
    ),
  );

  Future<void> update(
    String id, {
    DateTime? workDate,
    String? description,
  }) async {
    await _send(
      'PATCH',
      '/jobs/${Uri.encodeComponent(id)}',
      json: <String, Object?>{
        if (workDate != null) 'work_date': majorJobIsoDate(workDate),
        if (description != null) 'description': description,
      },
    );
  }

  Future<void> delete(String id) async {
    await _send('DELETE', '/jobs/${Uri.encodeComponent(id)}');
  }

  Future<MajorJobPhoto> uploadPhoto(
    String jobId,
    Uint8List bytes,
    String mimeType,
  ) async {
    final MajorJobPhoto photo = MajorJobPhoto.fromJson(
      requireJsonMap(
        _json(
          await _send(
            'POST',
            '/jobs/${Uri.encodeComponent(jobId)}/photos',
            bytes: bytes,
            contentType: mimeType,
          ),
        )['photo'],
        source: 'foto',
      ),
    );
    _photoCache[photo.id] = bytes;
    return photo;
  }

  Future<void> reorderPhotos(String jobId, List<String> ids) async {
    await _send(
      'PUT',
      '/jobs/${Uri.encodeComponent(jobId)}/photo-order',
      json: <String, Object?>{'ids': ids},
    );
  }

  Future<void> deletePhoto(String id) async {
    await _send('DELETE', '/photos/${Uri.encodeComponent(id)}');
    _photoCache.remove(id);
  }

  Future<Uint8List> photoBytes(String id) async {
    final Uint8List? cached = _photoCache[id];
    if (cached != null) return cached;
    final Uint8List bytes = (await _send(
      'GET',
      '/photos/${Uri.encodeComponent(id)}',
    )).bodyBytes;
    return _photoCache[id] = bytes;
  }

  Future<MajorJobUsage> usage() async =>
      MajorJobUsage.fromJson(_json(await _send('GET', '/usage')));
}
