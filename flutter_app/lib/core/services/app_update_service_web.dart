import 'package:package_info_plus/package_info_plus.dart';

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

/// Browser deployments are refreshed by the website host, not by installing
/// an APK. The current browser page always loads the hosted web release.
class AppUpdateService {
  Future<AppUpdateCheck> checkForUpdate() async {
    final PackageInfo package = await PackageInfo.fromPlatform();
    return AppUpdateCheck(
      currentVersion: package.version,
      release: null,
      isUpdateAvailable: false,
    );
  }

  Future<AppInstallerResult> downloadAndInstall(AppRelease release) =>
      throw UnsupportedError('Browser updates are delivered by the website.');
}
