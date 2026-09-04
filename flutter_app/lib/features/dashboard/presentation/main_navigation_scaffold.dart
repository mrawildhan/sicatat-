import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_user.dart';
import '../../auth/application/current_user_provider.dart';

enum MainNavigationTab { home, temperature, reminders, warehouse, documents, profile }

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
    final mobileItems = <_NavigationItem>[
      const _NavigationItem(
        tab: MainNavigationTab.home,
        label: 'Beranda',
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
      ),
      if (user?.role.canCreateTemperatureSheet == true)
        const _NavigationItem(
          tab: MainNavigationTab.temperature,
          label: 'Suhu',
          icon: Icons.thermostat_outlined,
          selectedIcon: Icons.thermostat_rounded,
        ),
      if (user?.role.canUseReminders == true)
        const _NavigationItem(
          tab: MainNavigationTab.reminders,
          label: 'Pengingat',
          icon: Icons.notifications_none_rounded,
          selectedIcon: Icons.notifications_active_rounded,
        ),
      if (user?.role.canUseWarehouse == true)
        const _NavigationItem(
          tab: MainNavigationTab.warehouse,
          label: 'Gudang',
          icon: Icons.inventory_2_outlined,
          selectedIcon: Icons.inventory_2_rounded,
        ),
      const _NavigationItem(
        tab: MainNavigationTab.profile,
        label: 'Profil',
        icon: Icons.person_outline_rounded,
        selectedIcon: Icons.person_rounded,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final useNavigationRail = kIsWeb && constraints.maxWidth >= 920;
        // Pusat Dokumen lives in the web sidebar so the mobile bottom bar
        // remains compact. On desktop, Gudang and Pusat Dokumen are grouped
        // together as reference tools for quick access.
        final desktopItems = <_NavigationItem>[
          const _NavigationItem(
            tab: MainNavigationTab.home,
            label: 'Beranda',
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
          ),
          if (user?.role.canCreateTemperatureSheet == true)
            const _NavigationItem(
              tab: MainNavigationTab.temperature,
              label: 'Suhu',
              icon: Icons.thermostat_outlined,
              selectedIcon: Icons.thermostat_rounded,
              sectionLabel: 'OPERASIONAL',
            ),
          if (user?.role.canUseReminders == true)
            const _NavigationItem(
              tab: MainNavigationTab.reminders,
              label: 'Pengingat',
              icon: Icons.notifications_none_rounded,
              selectedIcon: Icons.notifications_active_rounded,
            ),
          if (user?.role.canUseWarehouse == true)
            const _NavigationItem(
              tab: MainNavigationTab.warehouse,
              label: 'Gudang',
              icon: Icons.inventory_2_outlined,
              selectedIcon: Icons.inventory_2_rounded,
              sectionLabel: 'REFERENSI',
            ),
          if (user?.role.canUseWarehouse == true)
            const _NavigationItem(
              tab: MainNavigationTab.documents,
              label: 'Pusat Dokumen',
              icon: Icons.folder_shared_outlined,
              selectedIcon: Icons.folder_shared_rounded,
            )
          else
            const _NavigationItem(
              tab: MainNavigationTab.documents,
              label: 'Pusat Dokumen',
              icon: Icons.folder_shared_outlined,
              selectedIcon: Icons.folder_shared_rounded,
              sectionLabel: 'REFERENSI',
            ),
          const _NavigationItem(
            tab: MainNavigationTab.profile,
            label: 'Profil',
            icon: Icons.person_outline_rounded,
            selectedIcon: Icons.person_rounded,
            sectionLabel: 'AKUN',
          ),
        ];
        final items = useNavigationRail ? desktopItems : mobileItems;
        final selectedIndex = items.indexWhere((item) => item.tab == selectedTab);
        final safeSelectedIndex = selectedIndex < 0 ? 0 : selectedIndex;

        void selectDestination(int index) {
          switch (items[index].tab) {
            case MainNavigationTab.home:
              context.go('/dashboard');
              return;
            case MainNavigationTab.temperature:
              context.go('/sheets');
              return;
            case MainNavigationTab.reminders:
              context.go('/reminders');
              return;
            case MainNavigationTab.warehouse:
              context.go('/warehouse');
              return;
            case MainNavigationTab.documents:
              context.go('/documents');
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
                        'Inspeksi operasional dan pengingat',
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
                                if (item.sectionLabel != null)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                                    child: Text(
                                      item.sectionLabel!,
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                  ),
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
                          '© 2026 WIL • Versi ${AppConfig.appVersion}',
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
              : SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Padding(
                        padding: EdgeInsets.only(top: 6, bottom: 2),
                        child: Text(
                          '© 2026 WIL • Versi ${AppConfig.appVersion}',
                          style: TextStyle(fontSize: 10, color: AppColors.muted),
                        ),
                      ),
                      NavigationBar(
                        selectedIndex: safeSelectedIndex,
                        onDestinationSelected: selectDestination,
                        destinations: items
                            .map(
                              (item) => NavigationDestination(
                                icon: Icon(item.icon),
                                selectedIcon: Icon(item.selectedIcon),
                                label: item.label,
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
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
    this.sectionLabel,
  });

  final MainNavigationTab tab;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String? sectionLabel;
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
