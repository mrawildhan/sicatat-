import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/app_user.dart';
import '../../auth/application/current_user_provider.dart';
import '../../dashboard/presentation/grouped_bottom_navigation.dart';

class MasterDataHubScreen extends ConsumerWidget {
  const MasterDataHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final canManageUsers = user?.role.canManageUsers == true;
    final canTemperature = user?.role.canCreateTemperatureSheet == true;
    final canReminders = user?.role.canUseReminders == true;
    final canWarehouse = user?.role.canUseWarehouse == true;
    final showSidebar = kIsWeb && MediaQuery.sizeOf(context).width >= 920;
    return AppBackScope(
      fallbackRoute: '/dashboard',
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallbackRoute: '/dashboard'),
          title: const Text('Data master & administrasi'),
        ),
        body: Row(
          children: <Widget>[
            if (showSidebar)
              _Sidebar(
                canTemperature: canTemperature,
                canReminders: canReminders,
                canWarehouse: canWarehouse,
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  const Text(
                    'Kelola data master yang digunakan oleh aplikasi SICATAT.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  _item(
                    context,
                    Icons.location_city_rounded,
                    'Lokasi kerja',
                    'Lokasi operasional seperti Asam-Asam dan Kintap',
                    '/admin/sites',
                  ),
                  _item(
                    context,
                    Icons.precision_manufacturing_outlined,
                    'Peralatan & titik ukur',
                    'Peralatan, bagian, titik ukur, dan status aktif',
                    '/admin/equipment',
                  ),
                  _item(
                    context,
                    Icons.tune_rounded,
                    'Batas suhu',
                    'Batas peringatan, alarm, dan perubahan suhu',
                    '/admin/thresholds',
                  ),
                  _item(
                    context,
                    Icons.account_tree_outlined,
                    'Template formulir suhu',
                    'Urutan dan jumlah ronde setiap shift',
                    '/admin/form-template',
                  ),
                  _item(
                    context,
                    Icons.schedule_rounded,
                    'Shift',
                    'Nama, kode, dan waktu shift siang/malam',
                    '/admin/shifts',
                  ),
                  _item(
                    context,
                    Icons.groups_rounded,
                    'Regu',
                    'Regu crew dan status aktifnya',
                    '/admin/teams',
                  ),
                  _item(
                    context,
                    Icons.calendar_month_rounded,
                    'Jadwal regu',
                    'Acuan rotasi tiga hari dan urutan regu',
                    '/admin/roster',
                  ),
                  if (canManageUsers)
                    _item(
                      context,
                      Icons.manage_accounts_outlined,
                      'Pengguna',
                      'NIK, peran, regu, dan status akun crew',
                      '/users',
                    ),
                  _item(
                    context,
                    Icons.file_download_outlined,
                    'Ekspor rentang tanggal',
                    'Ekspor PDF dan data seluruh regu',
                    '/reports',
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: showSidebar
            ? null
            : GroupedBottomNavigation(
                selected: 'home',
                canTemperature: canTemperature,
                canReminders: canReminders,
                canWarehouse: canWarehouse,
              ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    String route,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Card(
      child: ListTile(
        onTap: () => context.go(route),
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    ),
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.canTemperature,
    required this.canReminders,
    required this.canWarehouse,
  });

  final bool canTemperature;
  final bool canReminders;
  final bool canWarehouse;

  @override
  Widget build(BuildContext context) => Container(
    width: 206,
    decoration: const BoxDecoration(
      border: Border(right: BorderSide(color: Color(0xFFE0E7E2))),
    ),
    child: ListView(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 18),
      children: <Widget>[
        _item(
          context,
          'Beranda',
          Icons.home_outlined,
          () => context.go('/dashboard'),
        ),
        _item(
          context,
          'Operasional',
          Icons.fact_check_outlined,
          () => openNavigationGroup(
            context,
            operational: true,
            canTemperature: canTemperature,
            canReminders: canReminders,
            canWarehouse: canWarehouse,
          ),
        ),
        _item(
          context,
          'Referensi',
          Icons.folder_copy_outlined,
          () => openNavigationGroup(
            context,
            operational: false,
            canTemperature: canTemperature,
            canReminders: canReminders,
            canWarehouse: canWarehouse,
          ),
        ),
        _item(
          context,
          'Profil',
          Icons.person_outline_rounded,
          () => context.go('/dashboard?tab=profile'),
        ),
      ],
    ),
  );

  Widget _item(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onTap,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Icon(icon),
      title: Text(label),
      onTap: onTap,
    ),
  );
}
