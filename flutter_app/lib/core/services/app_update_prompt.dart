import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_update_service.dart';

/// Offers the newest Android APK: automatically once per app launch (on the
/// login screen before NIK/PIN, or on Beranda when the session is restored)
/// and on demand from Profil → Periksa pembaruan.
abstract final class AppUpdatePrompt {
  static bool _offeredThisLaunch = false;

  /// Shows the offer only when a newer APK exists, at most once per launch.
  /// Failures stay silent: the crew can always sign in with the current app.
  static Future<void> offerOnce(BuildContext context) async {
    if (kIsWeb || _offeredThisLaunch) return;
    _offeredThisLaunch = true;
    try {
      final update = await AppUpdateService().checkForUpdate();
      final release = update.release;
      if (!update.isUpdateAvailable || release == null || !context.mounted) {
        return;
      }
      await _offer(context, release, update.currentVersion);
    } on Object {
      // No network or no release: nothing to offer.
    }
  }

  /// Profil → Periksa pembaruan: always answers, also when up to date.
  static Future<void> checkManually(BuildContext context) async {
    try {
      final update = await AppUpdateService().checkForUpdate();
      if (!context.mounted) return;
      final release = update.release;
      if (release == null) {
        await _message(
          context,
          title: 'Pembaruan belum tersedia',
          message: 'Belum ada rilis Android pada kanal pembaruan ini.',
          icon: Icons.cloud_off_rounded,
        );
        return;
      }
      if (!update.isUpdateAvailable) {
        await _message(
          context,
          title: 'SICATAT sudah versi terbaru',
          message:
              'Anda menggunakan versi ${update.currentVersion}, versi terbaru yang tersedia.',
          icon: Icons.verified_rounded,
        );
        return;
      }
      await _offer(context, release, update.currentVersion);
    } on Object catch (error) {
      if (context.mounted) {
        await _message(
          context,
          title: 'Pembaruan tidak dapat diperiksa',
          message: '$error',
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  static Future<void> _offer(
    BuildContext context,
    AppRelease release,
    String currentVersion,
  ) async {
    final bool? install = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: <Widget>[
            Icon(Icons.system_update_rounded, color: AppColors.green),
            SizedBox(width: 10),
            Expanded(child: Text('Versi baru tersedia')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'SICATAT ${release.versionName} sudah tersedia. Versi di HP ini '
                '$currentVersion. Perbarui sekarang?',
              ),
              if (release.releaseNotes.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.greenSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Yang baru',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(release.releaseNotes),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const Text(
                'Android akan meminta persetujuan pemasangan. Data dan sesi '
                'masuk SICATAT tetap tersimpan.',
                style: TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Nanti saja'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.system_update_alt_rounded),
            label: const Text('Perbarui sekarang'),
          ),
        ],
      ),
    );
    if (install == true && context.mounted) {
      await _downloadAndInstall(context, release);
    }
  }

  static Future<void> _downloadAndInstall(
    BuildContext context,
    AppRelease release,
  ) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(width: 18),
            Expanded(child: Text('Mengunduh pembaruan…')),
          ],
        ),
      ),
    );
    try {
      final result = await AppUpdateService().downloadAndInstall(release);
      navigator.pop();
      if (result == AppInstallerResult.permissionRequired && context.mounted) {
        await _message(
          context,
          title: 'Izinkan pemasangan aplikasi',
          message:
              'Android membuka halaman izin. Izinkan pemasangan dari SICATAT, '
              'lalu kembali dan pilih Perbarui sekarang lagi (Profil → '
              'Periksa pembaruan).',
          icon: Icons.security_rounded,
        );
      }
    } on Object catch (error) {
      navigator.pop();
      if (context.mounted) {
        await _message(
          context,
          title: 'Unduhan pembaruan gagal',
          message: '$error',
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  static Future<void> _message(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
  }) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(
        children: <Widget>[
          Icon(icon, color: AppColors.green),
          const SizedBox(width: 10),
          Expanded(child: Text(title)),
        ],
      ),
      content: Text(message),
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Oke'),
        ),
      ],
    ),
  );
}
