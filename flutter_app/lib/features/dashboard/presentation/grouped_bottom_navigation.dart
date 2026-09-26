import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_user.dart';
import '../../auth/application/current_user_provider.dart';

/// Opens the same operational/reference picker on every screen size.
/// Desktop presents its groups in the sidebar; mobile presents them in the
/// bottom bar. The destinations and permissions must remain identical.
Future<void> openNavigationGroup(
  BuildContext context, {
  required bool operational,
  required bool canTemperature,
  required bool canReminders,
  required bool canWarehouse,
  bool canMajorJob = false,
}) async {
  // Laporan Bulanan is for reviewers (foreman, supervisors, admin); read the
  // role here so every caller of this picker shows the same menu. Widget
  // tests that pump the bar alone have no ProviderScope.
  bool canReports = false;
  try {
    canReports =
        ProviderScope.containerOf(
          context,
          listen: false,
        ).read(currentUserProvider)?.role.canReviewTemperature ==
        true;
  } on StateError {
    canReports = false;
  }
  final List<_NavigationGroupOption> options = <_NavigationGroupOption>[
    if (operational && canTemperature)
      const _NavigationGroupOption(
        icon: Icons.thermostat_rounded,
        title: 'Suhu',
        subtitle: 'Pencatatan dan pemeriksaan suhu',
        route: '/temperature-forms',
      ),
    if (operational && canReminders)
      const _NavigationGroupOption(
        icon: Icons.notifications_none_rounded,
        title: 'Pengingat',
        subtitle: 'Tindak lanjut pekerjaan',
        route: '/reminders',
      ),
    if (operational && canWarehouse)
      const _NavigationGroupOption(
        icon: Icons.inventory_2_outlined,
        title: 'Gudang',
        subtitle: 'Stok, pengambilan, peminjaman alat, dan penerimaan',
        route: '/warehouse',
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
        subtitle: 'Ajukan kebutuhan LV, COP, dan Drilling',
        route: '/material-requests',
      ),
    // Operasional holds at most 9 menus (owner request 2026-09-26); look-up
    // menus (Data PR, Laporan Bulanan, Panduan) live in Referensi.
    if (!operational)
      const _NavigationGroupOption(
        icon: Icons.request_quote_outlined,
        title: 'Data PR',
        subtitle: 'Cari Purchase Requisition dan PO',
        route: '/purchase-requisitions',
      ),
    if (operational)
      const _NavigationGroupOption(
        icon: Icons.pending_actions_outlined,
        title: 'PM & CM Tertunda',
        subtitle: 'Pantau pekerjaan yang belum selesai',
        route: '/outstanding-maintenance',
      ),
    if (operational)
      const _NavigationGroupOption(
        icon: Icons.assignment_outlined,
        title: 'Notulen Rapat',
        subtitle: 'Buat dan lanjutkan draf notulen',
        route: '/meeting-minutes',
      ),
    if (!operational && canReports)
      const _NavigationGroupOption(
        icon: Icons.summarize_outlined,
        title: 'Laporan Bulanan',
        subtitle: 'Satu PDF: suhu, kepatuhan, PM & CM, anggaran, PR, gudang',
        route: '/monthly-report',
      ),
    if (operational && canMajorJob)
      const _NavigationGroupOption(
        icon: Icons.photo_library_outlined,
        title: 'Major Job',
        subtitle: 'Laporan foto pekerjaan mingguan & bulanan',
        route: '/major-job',
      ),
    if (!operational)
      const _NavigationGroupOption(
        icon: Icons.folder_shared_outlined,
        title: 'Pusat Dokumen',
        subtitle: 'Cari SOP, manual, dan drawing',
        route: '/documents',
      ),
    if (!operational)
      const _NavigationGroupOption(
        icon: Icons.account_tree_outlined,
        title: 'Kode Biaya',
        subtitle: 'Cari struktur dan elemen biaya',
        route: '/cost-codes',
      ),
    if (!operational)
      const _NavigationGroupOption(
        icon: Icons.help_outline_rounded,
        title: 'Panduan Pengguna',
        subtitle: 'Cara memakai setiap menu',
        route: '/guide',
      ),
    if (!operational)
      const _NavigationGroupOption(
        icon: Icons.precision_manufacturing_outlined,
        title: 'Referensi Alat',
        subtitle: 'Cari unit Asamasam dan Kintap',
        route: '/equipment-reference',
      ),
  ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  final route = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    // Lets the sheet grow past half the screen when the menu needs it.
    isScrollControlled: true,
    builder: (sheetContext) {
      final bool tablet = MediaQuery.sizeOf(sheetContext).width >= 600;
      final bool compactGrid = !tablet;
      // Size the sheet to its menu instead of a fixed share of the screen.
      // A fixed 76% with scrolling disabled let mobile browsers hide the last
      // row (Notulen Rapat) behind their own toolbar; the grid now scrolls if
      // it ever has to, and keeps clear of the bottom inset.
      final double bottomInset = MediaQuery.paddingOf(sheetContext).bottom;
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                operational ? 'Operasional' : 'Referensi',
                style: AppTextStyles.sectionTitle,
              ),
            ),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.fromLTRB(20, 0, 20, 32 + bottomInset),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: compactGrid ? 8 : 12,
                  crossAxisSpacing: compactGrid ? 8 : 12,
                  childAspectRatio: tablet ? 1.7 : 1.22,
                ),
                itemCount: options.length,
                itemBuilder: (_, index) => _NavigationGroupCard(
                  option: options[index],
                  compact: compactGrid,
                  onTap: () =>
                      Navigator.pop(sheetContext, options[index].route),
                ),
              ),
            ),
          ],
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
              const SizedBox(height: 8),
              Text(
                option.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyles.cardTitle.copyWith(
                  fontSize: compact ? 13 : 15,
                  height: 1.15,
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
    this.canMajorJob = false,
    this.onHome,
    this.onProfile,
    super.key,
  });

  final String selected;
  final bool canTemperature;
  final bool canReminders;
  final bool canWarehouse;
  final bool canMajorJob;
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
      'outstandingMaintenance' ||
      'meetingMinutes' ||
      'majorJob' ||
      'warehouse' => 'operational',
      'documents' ||
      'costCodes' ||
      'equipmentReference' ||
      'purchaseRequisitions' => 'reference',
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
              style: TextStyle(fontSize: 11, color: AppColors.muted),
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
                    canMajorJob: canMajorJob,
                  );
                case 'reference':
                  openNavigationGroup(
                    context,
                    operational: false,
                    canTemperature: canTemperature,
                    canReminders: canReminders,
                    canWarehouse: canWarehouse,
                    canMajorJob: canMajorJob,
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
