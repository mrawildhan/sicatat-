import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';

/// Opens the same operational/reference picker on every screen size.
/// Desktop presents its groups in the sidebar; mobile presents them in the
/// bottom bar. The destinations and permissions must remain identical.
Future<void> openNavigationGroup(
  BuildContext context, {
  required bool operational,
  required bool canTemperature,
  required bool canReminders,
  required bool canWarehouse,
}) async {
  final route = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                operational ? 'Operasional' : 'Referensi',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (operational && canTemperature)
              ListTile(
                leading: const Icon(Icons.thermostat_rounded),
                title: const Text('Suhu'),
                subtitle: const Text('Pencatatan dan pemeriksaan suhu'),
                onTap: () => Navigator.pop(sheetContext, '/sheets'),
              ),
            if (operational && canReminders)
              ListTile(
                leading: const Icon(Icons.notifications_none_rounded),
                title: const Text('Pengingat'),
                subtitle: const Text('Tindak lanjut pekerjaan'),
                onTap: () => Navigator.pop(sheetContext, '/reminders'),
              ),
            if (!operational && canWarehouse)
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Gudang'),
                subtitle: const Text('Cari stok dan lokasi barang'),
                onTap: () => Navigator.pop(sheetContext, '/warehouse'),
              ),
            if (!operational)
              ListTile(
                leading: const Icon(Icons.folder_shared_outlined),
                title: const Text('Pusat Dokumen'),
                subtitle: const Text('Tanya AI dan cari dokumen kerja'),
                onTap: () => Navigator.pop(sheetContext, '/documents'),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );
  if (route != null && context.mounted) context.go(route);
}

/// Shared by the dashboard and all module pages so mobile menus stay identical.
class GroupedBottomNavigation extends StatelessWidget {
  const GroupedBottomNavigation({
    required this.selected,
    required this.canTemperature,
    required this.canReminders,
    required this.canWarehouse,
    this.onHome,
    this.onProfile,
    super.key,
  });

  final String selected;
  final bool canTemperature;
  final bool canReminders;
  final bool canWarehouse;
  final VoidCallback? onHome;
  final VoidCallback? onProfile;

  @override
  Widget build(BuildContext context) {
    final hasOperational = canTemperature || canReminders;
    final groups = [
      'home',
      if (hasOperational) 'operational',
      'reference',
      'profile',
    ];
    final current = switch (selected) {
      'temperature' || 'reminders' => 'operational',
      'warehouse' || 'documents' => 'reference',
      _ => selected,
    };
    final index = groups.indexOf(current);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, bottom: 2),
            child: Text(
              '© 2026 • Versi ${AppConfig.appVersion}',
              style: TextStyle(fontSize: 10, color: AppColors.muted),
            ),
          ),
          NavigationBar(
            selectedIndex: index < 0 ? 0 : index,
            onDestinationSelected: (value) {
              switch (groups[value]) {
                case 'home':
                  (onHome ?? () => context.go('/dashboard'))();
                case 'profile':
                  (onProfile ?? () => context.go('/dashboard?tab=profile'))();
                case 'operational':
                  openNavigationGroup(
                    context,
                    operational: true,
                    canTemperature: canTemperature,
                    canReminders: canReminders,
                    canWarehouse: canWarehouse,
                  );
                case 'reference':
                  openNavigationGroup(
                    context,
                    operational: false,
                    canTemperature: canTemperature,
                    canReminders: canReminders,
                    canWarehouse: canWarehouse,
                  );
              }
            },
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Beranda',
              ),
              if (hasOperational)
                const NavigationDestination(
                  icon: Icon(Icons.fact_check_outlined),
                  selectedIcon: Icon(Icons.fact_check),
                  label: 'Operasional',
                ),
              const NavigationDestination(
                icon: Icon(Icons.folder_copy_outlined),
                selectedIcon: Icon(Icons.folder_copy),
                label: 'Referensi',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Profil',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
