import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import 'grouped_bottom_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_user.dart';
import '../../auth/application/current_user_provider.dart';

enum MainNavigationTab {
  home,
  operational,
  reference,
  temperature,
  reminders,
  budget,
  materialRequests,
  purchaseRequisitions,
  outstandingMaintenance,
  meetingMinutes,
  warehouse,
  documents,
  costCodes,
  equipmentReference,
  profile,
}

class MainNavigationScaffold extends ConsumerWidget {
  const MainNavigationScaffold({
    required this.selectedTab,
    required this.child,
    super.key,
  });

  final MainNavigationTab selectedTab;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final canTemperature = user?.role.canCreateTemperatureSheet == true;
    final canReminders = user?.role.canUseReminders == true;
    final canWarehouse = user?.role.canUseWarehouse == true;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useNavigationRail = kIsWeb && constraints.maxWidth >= 920;
        // Desktop and mobile share the exact same navigation groups.
        final desktopItems = <_NavigationItem>[
          const _NavigationItem(
            tab: MainNavigationTab.home,
            label: 'Beranda',
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
          ),
          const _NavigationItem(
            tab: MainNavigationTab.operational,
            label: 'Operasional',
            icon: Icons.fact_check_outlined,
            selectedIcon: Icons.fact_check,
          ),
          const _NavigationItem(
            tab: MainNavigationTab.reference,
            label: 'Referensi',
            icon: Icons.folder_copy_outlined,
            selectedIcon: Icons.folder_copy,
          ),
          const _NavigationItem(
            tab: MainNavigationTab.profile,
            label: 'Profil',
            icon: Icons.person_outline_rounded,
            selectedIcon: Icons.person_rounded,
          ),
        ];
        final selectedGroup = switch (selectedTab) {
          MainNavigationTab.temperature ||
          MainNavigationTab.reminders ||
          MainNavigationTab.budget ||
          MainNavigationTab.materialRequests ||
          MainNavigationTab.purchaseRequisitions ||
          MainNavigationTab.outstandingMaintenance ||
          MainNavigationTab.meetingMinutes => MainNavigationTab.operational,
          MainNavigationTab.warehouse ||
          MainNavigationTab.documents ||
          MainNavigationTab.costCodes ||
          MainNavigationTab.equipmentReference => MainNavigationTab.reference,
          _ => selectedTab,
        };
        final items = desktopItems;
        final selectedIndex = items.indexWhere(
          (item) => item.tab == selectedGroup,
        );
        final safeSelectedIndex = selectedIndex < 0 ? 0 : selectedIndex;

        void selectDestination(int index) {
          switch (items[index].tab) {
            case MainNavigationTab.home:
              context.go('/dashboard');
              return;
            case MainNavigationTab.operational:
              openNavigationGroup(
                context,
                operational: true,
                canTemperature: canTemperature,
                canReminders: canReminders,
                canWarehouse: canWarehouse,
              );
              return;
            case MainNavigationTab.reference:
              openNavigationGroup(
                context,
                operational: false,
                canTemperature: canTemperature,
                canReminders: canReminders,
                canWarehouse: canWarehouse,
              );
              return;
            case MainNavigationTab.temperature:
              context.go('/sheets');
              return;
            case MainNavigationTab.reminders:
              context.go('/reminders');
              return;
            case MainNavigationTab.budget:
              context.go('/budget');
              return;
            case MainNavigationTab.materialRequests:
              context.go('/material-requests');
              return;
            case MainNavigationTab.purchaseRequisitions:
              context.go('/purchase-requisitions');
              return;
            case MainNavigationTab.outstandingMaintenance:
              context.go('/outstanding-maintenance');
              return;
            case MainNavigationTab.meetingMinutes:
              context.go('/meeting-minutes');
              return;
            case MainNavigationTab.warehouse:
              context.go('/warehouse');
              return;
            case MainNavigationTab.documents:
              context.go('/documents');
              return;
            case MainNavigationTab.costCodes:
              context.go('/cost-codes');
              return;
            case MainNavigationTab.equipmentReference:
              context.go('/equipment-reference');
              return;
            case MainNavigationTab.profile:
              context.go('/dashboard?tab=profile');
              return;
          }
        }

        Future<void> signOut() async {
          final bool? confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Keluar dari akun?'),
              content: const Text(
                'Anda memerlukan ID Crew dan password untuk masuk kembali.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Keluar'),
                ),
              ],
            ),
          );
          if (confirmed != true || !context.mounted) return;
          await Supabase.instance.client.auth.signOut();
          ref.read(currentUserProvider.notifier).state = null;
          if (context.mounted) context.go('/login');
        }

        return Scaffold(
          appBar: useNavigationRail
              ? AppBar(
                  toolbarHeight: 68,
                  title: const Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'sicatat',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Operasional, referensi, dan informasi kerja',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF92B6A6),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  actions: <Widget>[
                    IconButton(
                      tooltip: 'Keluar',
                      onPressed: signOut,
                      icon: const Icon(Icons.logout_rounded),
                    ),
                    const SizedBox(width: 8),
                  ],
                )
              : null,
          body: Row(
            children: <Widget>[
              if (useNavigationRail) ...<Widget>[
                SizedBox(
                  width: 206,
                  child: Column(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                        child: Image.asset(
                          'assets/images/logo-full.png',
                          height: 42,
                          fit: BoxFit.contain,
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                _DesktopSidebarItem(
                                  label: item.label,
                                  icon: index == safeSelectedIndex
                                      ? item.selectedIcon
                                      : item.icon,
                                  selected: index == safeSelectedIndex,
                                  onTap: () => selectDestination(index),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 18),
                        child: Text(
                          '© 2026 • Versi ${AppConfig.appVersion}',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 9, color: AppColors.muted),
                        ),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
              ],
              Expanded(child: child),
            ],
          ),
          bottomNavigationBar: useNavigationRail
              ? null
              : GroupedBottomNavigation(
                  selected: selectedTab.name,
                  canTemperature: user?.role.canCreateTemperatureSheet == true,
                  canReminders: user?.role.canUseReminders == true,
                  canWarehouse: user?.role.canUseWarehouse == true,
                ),
        );
      },
    );
  }
}

class _NavigationItem {
  const _NavigationItem({
    required this.tab,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final MainNavigationTab tab;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _DesktopSidebarItem extends StatelessWidget {
  const _DesktopSidebarItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.mint : Colors.transparent,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: SizedBox(
        height: 54,
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 58,
              child: Icon(
                icon,
                color: selected ? AppColors.green : AppColors.ink,
              ),
            ),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  color: selected ? AppColors.green : AppColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    ),
  );
}
