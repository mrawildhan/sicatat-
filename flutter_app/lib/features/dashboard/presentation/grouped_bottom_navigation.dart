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
  final List<_NavigationGroupOption> options = <_NavigationGroupOption>[
    if (operational && canTemperature)
      const _NavigationGroupOption(
        icon: Icons.thermostat_rounded,
        title: 'Suhu',
        subtitle: 'Pencatatan dan pemeriksaan suhu',
        route: '/sheets',
      ),
    if (operational && canReminders)
      const _NavigationGroupOption(
        icon: Icons.notifications_none_rounded,
        title: 'Pengingat',
        subtitle: 'Tindak lanjut pekerjaan',
        route: '/reminders',
      ),
    if (operational)
      const _NavigationGroupOption(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Anggaran Operasional',
        subtitle: 'Pantau anggaran dan aktual',
        route: '/budget',
      ),
    if (operational)
      const _NavigationGroupOption(
        icon: Icons.handyman_outlined,
        title: 'Permintaan Barang',
        subtitle: 'Order kebutuhan LV dan Drilling',
        route: '/material-requests',
      ),
    if (operational)
      const _NavigationGroupOption(
        icon: Icons.request_quote_outlined,
        title: 'Data PR',
        subtitle: 'Cari Purchase Requisition dan PO',
        route: '/purchase-requisitions',
      ),
    if (operational)
      const _NavigationGroupOption(
        icon: Icons.pending_actions_outlined,
        title: 'Outstanding PM & CM',
        subtitle: 'Pantau pekerjaan yang belum selesai',
        route: '/outstanding-maintenance',
      ),
    if (operational)
      const _NavigationGroupOption(
        icon: Icons.assignment_outlined,
        title: 'Notulen Rapat',
        subtitle: 'Buat dan lanjutkan draf MOM',
        route: '/meeting-minutes',
      ),
    if (!operational && canWarehouse)
      const _NavigationGroupOption(
        icon: Icons.inventory_2_outlined,
        title: 'Gudang',
        subtitle: 'Cari stok dan lokasi barang',
        route: '/warehouse',
      ),
    if (!operational)
      const _NavigationGroupOption(
        icon: Icons.folder_shared_outlined,
        title: 'Pusat Dokumen',
        subtitle: 'Cari SOP, manual, dan drawing',
        route: '/documents',
      ),
  ];
  final route = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) {
      final bool tablet = MediaQuery.sizeOf(sheetContext).width >= 600;
      final bool compactOperationalGrid = operational && !tablet;
      return SafeArea(
        top: false,
        child: SizedBox(
          height:
              MediaQuery.sizeOf(sheetContext).height *
              (tablet
                  ? 0.5
                  : operational
                  ? options.length > 6
                        ? 0.76
                        : 0.5
                  : 0.4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  operational ? 'Operasional' : 'Referensi',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: tablet || compactOperationalGrid ? 3 : 2,
                    mainAxisSpacing: compactOperationalGrid ? 8 : 12,
                    crossAxisSpacing: compactOperationalGrid ? 8 : 12,
                    childAspectRatio: tablet ? 1.7 : 1.08,
                  ),
                  itemCount: options.length,
                  physics: const NeverScrollableScrollPhysics(),
                  itemBuilder: (_, index) => _NavigationGroupCard(
                    option: options[index],
                    compact: compactOperationalGrid,
                    onTap: () =>
                        Navigator.pop(sheetContext, options[index].route),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (route != null && context.mounted) context.go(route);
}

class _NavigationGroupOption {
  const _NavigationGroupOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
}

class _NavigationGroupCard extends StatelessWidget {
  const _NavigationGroupCard({
    required this.option,
    required this.compact,
    required this.onTap,
  });

  final _NavigationGroupOption option;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: option.title,
    child: Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              CircleAvatar(
                radius: compact ? 15 : 16,
                backgroundColor: AppColors.mint,
                child: Icon(
                  option.icon,
                  color: AppColors.green,
                  size: compact ? 17 : 18,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                option.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: compact ? 12 : 13,
                  height: 1.15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
    const hasOperational = true;
    final groups = [
      'home',
      if (hasOperational) 'operational',
      'reference',
      'profile',
    ];
    final current = switch (selected) {
      'temperature' ||
      'reminders' ||
      'budget' ||
      'materialRequests' ||
      'purchaseRequisitions' ||
      'outstandingMaintenance' ||
      'meetingMinutes' => 'operational',
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
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Beranda',
              ),
              if (hasOperational)
                NavigationDestination(
                  icon: Icon(Icons.fact_check_outlined),
                  selectedIcon: Icon(Icons.fact_check),
                  label: 'Operasional',
                ),
              NavigationDestination(
                icon: Icon(Icons.folder_copy_outlined),
                selectedIcon: Icon(Icons.folder_copy),
                label: 'Referensi',
              ),
              NavigationDestination(
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
