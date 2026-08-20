import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../models/sicatat_types.dart';

class AppVersionStatus {
  const AppVersionStatus({
    required this.blocked,
    required this.updateAvailable,
    this.latestVersion,
    this.releaseNotes,
  });

  const AppVersionStatus.unavailable()
    : blocked = false,
      updateAvailable = false,
      latestVersion = null,
      releaseNotes = null;

  final bool blocked;
  final bool updateAvailable;
  final String? latestVersion;
  final String? releaseNotes;
}

/// Non-blocking version policy check equivalent to the legacy application.
/// Network or server failures intentionally leave the field app usable.
class AppVersionService {
  const AppVersionService(this._client);

  final SupabaseClient? _client;

  factory AppVersionService.current() {
    try {
      return AppVersionService(Supabase.instance.client);
    } on Object {
      return const AppVersionService(null);
    }
  }

  Future<AppVersionStatus> check() async {
    final SupabaseClient? client = _client;
    if (client == null) return const AppVersionStatus.unavailable();
    try {
      final Object? response = await client
          .from('app_version')
          .select('latest_version,min_version,release_notes')
          .eq('platform', 'android')
          .order('released_at', ascending: false)
          .limit(1)
          .maybeSingle()
          .timeout(const Duration(seconds: 4));
      if (response == null) return const AppVersionStatus.unavailable();
      final JsonMap row = requireJsonMap(response, source: 'app version');
      final String latest = row.requiredString('latest_version');
      final String minimum = row.requiredString('min_version');
      final String? notes = row.optionalString('release_notes');
      final bool blocked = compare(AppConfig.appVersion, minimum) < 0;
      return AppVersionStatus(
        blocked: blocked,
        updateAvailable: !blocked && compare(AppConfig.appVersion, latest) < 0,
        latestVersion: latest,
        releaseNotes: notes,
      );
    } on Object {
      return const AppVersionStatus.unavailable();
    }
  }

  static int compare(String left, String right) {
    final List<int> leftParts = _parts(left);
    final List<int> rightParts = _parts(right);
    final int length = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var index = 0; index < length; index += 1) {
      final int leftPart = index < leftParts.length ? leftParts[index] : 0;
      final int rightPart = index < rightParts.length ? rightParts[index] : 0;
      if (leftPart != rightPart) return leftPart < rightPart ? -1 : 1;
    }
    return 0;
  }

  static List<int> _parts(String version) => version
      .split('.')
      .map((String part) => int.tryParse(part) ?? 0)
      .toList(growable: false);
}
