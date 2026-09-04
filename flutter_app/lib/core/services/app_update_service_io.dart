import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppRelease {
  const AppRelease({
    required this.abi,
    required this.versionName,
    required this.versionCode,
    required this.apkPath,
    required this.releaseNotes,
  });

  final String abi;
  final String versionName;
  final int versionCode;
  final String apkPath;
  final String releaseNotes;

  factory AppRelease.fromJson(Map<String, dynamic> json) => AppRelease(
    abi: json['abi'] as String,
    versionName: json['version_name'] as String,
    versionCode: (json['version_code'] as num).toInt(),
    apkPath: json['apk_path'] as String,
    releaseNotes: (json['release_notes'] as String? ?? '').trim(),
  );
}

class AppUpdateCheck {
  const AppUpdateCheck({
    required this.currentVersion,
    required this.release,
    required this.isUpdateAvailable,
  });

  final String currentVersion;
  final AppRelease? release;
  final bool isUpdateAvailable;
}

enum AppInstallerResult { installerOpened, permissionRequired }

class AppUpdateService {
  AppUpdateService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static const MethodChannel _installerChannel = MethodChannel(
    'id.sicatat.sicatat_flutter/app_update',
  );

  final SupabaseClient _client;

  Future<AppUpdateCheck> checkForUpdate() async {
    final PackageInfo package = await PackageInfo.fromPlatform();
    final String currentVersion = package.version;
    if (!Platform.isAndroid) {
      return AppUpdateCheck(
        currentVersion: currentVersion,
        release: null,
        isUpdateAvailable: false,
      );
    }
    final String abi = await _androidAbi();
    final dynamic response = await _client
        .from('app_release')
        .select('abi,version_name,version_code,apk_path,release_notes')
        .eq('platform', 'android')
        .eq('abi', abi)
        .eq('is_active', true)
        .order('version_code', ascending: false)
        .limit(1)
        .maybeSingle();
    if (response == null) {
      return AppUpdateCheck(
        currentVersion: currentVersion,
        release: null,
        isUpdateAvailable: false,
      );
    }
    final AppRelease release = AppRelease.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
    return AppUpdateCheck(
      currentVersion: currentVersion,
      release: release,
      isUpdateAvailable: _isVersionNewer(release.versionName, currentVersion),
    );
  }

  Future<AppInstallerResult> downloadAndInstall(AppRelease release) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('In-app updates are available on Android.');
    }
    final String signedUrl = await _client.storage
        .from('app-releases')
        .createSignedUrl(release.apkPath, 300);
    final http.Response response = await http.get(Uri.parse(signedUrl));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Unable to download the update (HTTP ${response.statusCode}).',
      );
    }
    if (response.bodyBytes.length < 1024 ||
        response.bodyBytes[0] != 0x50 ||
        response.bodyBytes[1] != 0x4b) {
      throw const FormatException('The downloaded update is not a valid APK.');
    }
    final Directory cache = await getTemporaryDirectory();
    final File apk = File(
      '${cache.path}${Platform.pathSeparator}sicatat-${release.versionName}.apk',
    );
    await apk.writeAsBytes(response.bodyBytes, flush: true);
    final String? result = await _installerChannel.invokeMethod<String>(
      'installApk',
      <String, String>{'path': apk.path},
    );
    return result == 'permission_required'
        ? AppInstallerResult.permissionRequired
        : AppInstallerResult.installerOpened;
  }

  static bool _isVersionNewer(String candidate, String current) {
    final List<int> candidateParts = _versionParts(candidate);
    final List<int> currentParts = _versionParts(current);
    for (int index = 0; index < 3; index += 1) {
      if (candidateParts[index] != currentParts[index]) {
        return candidateParts[index] > currentParts[index];
      }
    }
    return false;
  }

  static List<int> _versionParts(String value) {
    final List<int> parts = value
        .split('.')
        .take(3)
        .map((String part) => int.tryParse(part) ?? 0)
        .toList(growable: true);
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts;
  }

  Future<String> _androidAbi() async {
    final List<dynamic>? rawAbis = await _installerChannel
        .invokeListMethod<dynamic>('supportedAbis');
    const Set<String> supported = <String>{
      'arm64-v8a',
      'armeabi-v7a',
      'x86_64',
    };
    for (final dynamic rawAbi in rawAbis ?? const <dynamic>[]) {
      final String abi = rawAbi.toString();
      if (supported.contains(abi)) return abi;
    }
    throw UnsupportedError(
      'This Android device architecture is not supported.',
    );
  }
}
