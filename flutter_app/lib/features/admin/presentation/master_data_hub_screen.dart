import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/app_user.dart';
import '../../auth/application/current_user_provider.dart';

typedef _HubItem = (IconData icon, String title, String subtitle, String route);

/// Items in alphabetical order, as the owner asked (2026-09-25).
List<_HubItem> _sorted(List<_HubItem> items) => items.toList()
  ..sort(
    (_HubItem a, _HubItem b) =>
        a.$2.toLowerCase().compareTo(b.$2.toLowerCase()),
  );

class MasterDataHubScreen extends ConsumerWidget {
  const MasterDataHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final canManageUsers = user?.role.canManageUsers == true;
    return _HubPage(
      title: 'Data master & administrasi',
      intro: 'Kelola data master yang digunakan oleh aplikasi SICATAT.',
      fallbackRoute: '/dashboard',
      items: _sorted(<_HubItem>[
        (
          Icons.location_city_rounded,
          'Lokasi kerja',
          'Lokasi operasional seperti Asam-Asam dan Kintap',
          '/admin/sites',
        ),
        // The four temperature settings share one card so the list stays
        // short (owner request 2026-09-25).
        (
          Icons.thermostat_rounded,
          'Pengaturan suhu',
          'Batas suhu, peringatan kritis, template formulir, dan titik ukur',
          '/admin/temperature',
        ),
        (
          Icons.schedule_rounded,
          'Shift',
          'Nama, kode, dan jam shift siang/malam',
          '/admin/shifts',
        ),
        (
          Icons.groups_rounded,
          'Regu',
          'Regu crew dan status aktifnya',
          '/admin/teams',
        ),
        (
          Icons.calendar_month_rounded,
          'Jadwal regu',
          'Acuan rotasi tiga hari dan urutan regu',
          '/admin/roster',
        ),
        if (canManageUsers)
          (
            Icons.upload_file_rounded,
            'Unggah data',
            'File Excel PR, PM & CM, anggaran, dan gudang',
            '/admin/data-upload',
          ),
        if (canManageUsers)
          (
            Icons.manage_accounts_outlined,
            'Pengguna',
            'NIK, peran, regu, dan status akun crew',
            '/users',
          ),
        (
          Icons.file_download_outlined,
          'Ekspor rentang tanggal',
          'Ekspor PDF dan data seluruh regu',
          '/reports',
        ),
      ]),
    );
  }
}

/// Pengaturan suhu: the temperature limits, alerts, form template, and
/// measurement points, grouped under one Data master card.
class TemperatureSettingsHubScreen extends StatelessWidget {
  const TemperatureSettingsHubScreen({super.key});

  @override
  Widget build(BuildContext context) => _HubPage(
    title: 'Pengaturan suhu',
    intro: 'Pengaturan untuk lembar suhu dan daily check sheet.',
    fallbackRoute: '/admin',
    items: _sorted(const <_HubItem>[
      (
        Icons.precision_manufacturing_outlined,
        'Peralatan & titik ukur',
        'Peralatan, bagian, titik ukur, dan status aktif',
        '/admin/equipment',
      ),
      (
        Icons.tune_rounded,
        'Batas suhu',
        'Batas peringatan, alarm, dan perubahan suhu Feeder/Sizer',
        '/admin/thresholds',
      ),
      (
        Icons.notifications_active_outlined,
        'Batas & peringatan suhu',
        'Batas suhu Hydraulic/Coal Valve dan email peringatan kritis',
        '/admin/daily-check-settings',
      ),
      (
        Icons.account_tree_outlined,
        'Template formulir suhu',
        'Urutan dan jumlah ronde setiap shift',
        '/admin/form-template',
      ),
    ]),
  );
}

class _HubPage extends StatelessWidget {
  const _HubPage({
    required this.title,
    required this.intro,
    required this.fallbackRoute,
    required this.items,
  });

  final String title;
  final String intro;
  final String fallbackRoute;
  final List<_HubItem> items;

  @override
  Widget build(BuildContext context) => AppBackScope(
    fallbackRoute: fallbackRoute,
    child: Scaffold(
      appBar: AppBar(
        leading: AppBackButton(fallbackRoute: fallbackRoute),
        title: Text(title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(intro, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 16),
          for (final (IconData icon, String name, String subtitle, String route)
              in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  onTap: () => context.go(route),
                  leading: Icon(icon),
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(subtitle),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
