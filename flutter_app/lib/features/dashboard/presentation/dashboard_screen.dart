import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/services/app_update_service.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/dashboard_activity.dart';
import '../../../data/local/local_database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../auth/application/current_user_provider.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({this.showProfile = false, super.key});

  final bool showProfile;

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _index = 0;
  DashboardActivity? _activity;
  Timer? _activityRefreshTimer;
  bool _checkingForUpdate = false;
  late bool _showProfile;

  @override
  void initState() {
    super.initState();
    _showProfile = widget.showProfile;
    _loadActivity();
    _activityRefreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _loadActivity(),
    );
  }

  @override
  void dispose() {
    _activityRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showProfile != widget.showProfile) {
      _showProfile = widget.showProfile;
    }
  }

  Future<void> _loadActivity() async {
    try {
      final user = ref.read(currentUserProvider);
      final DashboardActivity activity = await LocalDatabase.instance
          .getDashboardActivity(
            DateTime.now(),
            createdBy: user?.role.isGlobalTemperatureManager == true
                ? null
                : user?.id,
          );
      if (!mounted) return;
      setState(() => _activity = activity);
    } on Object {
      // Keep the activity values unavailable instead of claiming data is synced
      // when the local database cannot be read.
    }
  }

  SyncState get _syncState {
    final DashboardActivity? activity = _activity;
    if (activity == null) return SyncState.pending;
    if (activity.conflictCount > 0) return SyncState.conflict;
    if (activity.pendingSyncCount > 0) {
      return SyncState.pending;
    }
    return SyncState.synced;
  }

  Widget _desktopSidebarItem({
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Material(
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
                  selected ? selectedIcon : icon,
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
    ),
  );

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final crewName = user?.name ?? 'Crew';
    final bool hasTemperatureTab = user?.role.canCreateTemperatureSheet == true;
    final bool hasReminderTab = user?.role.canUseReminders == true;
    final bool hasWarehouseTab = user?.role.canUseWarehouse == true;
    final int? reminderIndex = hasReminderTab
        ? (hasTemperatureTab ? 2 : 1)
        : null;
    final int? warehouseIndex = hasWarehouseTab
        ? 1 + (hasTemperatureTab ? 1 : 0) + (hasReminderTab ? 1 : 0)
        : null;
    final int profileIndex =
        1 +
        (hasTemperatureTab ? 1 : 0) +
        (hasReminderTab ? 1 : 0) +
        (hasWarehouseTab ? 1 : 0);
    final int selectedIndex = _showProfile ? profileIndex : _index;
    final bool useWebNavigationRail =
        kIsWeb && MediaQuery.sizeOf(context).width >= 920;
    void selectDestination(int value) {
      if (hasTemperatureTab && value == 1) {
        context.go('/sheets');
        return;
      }
      if (value == reminderIndex) {
        context.go('/reminders');
        return;
      }
      if (value == warehouseIndex) {
        context.go('/warehouse');
        return;
      }
      setState(() {
        _showProfile = value == profileIndex;
        _index = value;
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selectedIndex != 0) {
          setState(() {
            _showProfile = false;
            _index = 0;
          });
        }
      },
      child: Scaffold(
        extendBody: false,
        extendBodyBehindAppBar: false,
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'sicatat',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
              Text(
                'Operational inspections & reminders',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: _loadActivity,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Muat ulang aktivitas',
            ),
            IconButton(
              onPressed: _signOut,
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Keluar',
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Row(
            children: <Widget>[
              if (useWebNavigationRail) ...<Widget>[
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
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          children: <Widget>[
                            _desktopSidebarItem(
                              label: 'Beranda',
                              icon: Icons.home_outlined,
                              selectedIcon: Icons.home_rounded,
                              selected: selectedIndex == 0,
                              onTap: () => selectDestination(0),
                            ),
                            if (hasTemperatureTab)
                              _desktopSidebarItem(
                                label: 'Suhu',
                                icon: Icons.thermostat_outlined,
                                selectedIcon: Icons.thermostat_rounded,
                                selected: selectedIndex == 1,
                                onTap: () => selectDestination(1),
                              ),
                            if (hasReminderTab)
                              _desktopSidebarItem(
                                label: 'Pengingat',
                                icon: Icons.notifications_none_rounded,
                                selectedIcon:
                                    Icons.notifications_active_rounded,
                                selected: selectedIndex == reminderIndex,
                                onTap: () => selectDestination(reminderIndex!),
                              ),
                            if (hasWarehouseTab)
                              _desktopSidebarItem(
                                label: 'Gudang',
                                icon: Icons.inventory_2_outlined,
                                selectedIcon: Icons.inventory_2_rounded,
                                selected: selectedIndex == warehouseIndex,
                                onTap: () => selectDestination(warehouseIndex!),
                              ),
                            _desktopSidebarItem(
                              label: 'Profil',
                              icon: Icons.person_outline_rounded,
                              selectedIcon: Icons.person_rounded,
                              selected: selectedIndex == profileIndex,
                              onTap: () => selectDestination(profileIndex),
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 18),
                        child: Text(
                          '© 2026 WIL',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 9, color: AppColors.muted),
                        ),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
              ],
              Expanded(
                child: IndexedStack(
                  index: selectedIndex,
                  children: <Widget>[
                    _home(context, crewName, user),
                    if (hasTemperatureTab) const SizedBox(),
                    if (hasReminderTab) const SizedBox(),
                    if (hasWarehouseTab) const SizedBox(),
                    _profile(context, user),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: useWebNavigationRail
            ? null
            : SafeArea(
                top: false,
                child: NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: selectDestination,
                  destinations: <NavigationDestination>[
                    const NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded),
                      label: 'Beranda',
                    ),
                    if (hasTemperatureTab)
                      const NavigationDestination(
                        icon: Icon(Icons.thermostat_outlined),
                        selectedIcon: Icon(Icons.thermostat_rounded),
                        label: 'Suhu',
                      ),
                    if (hasReminderTab)
                      const NavigationDestination(
                        icon: Icon(Icons.notifications_none_rounded),
                        selectedIcon: Icon(Icons.notifications_active_rounded),
                        label: 'Pengingat',
                      ),
                    if (hasWarehouseTab)
                      const NavigationDestination(
                        icon: Icon(Icons.inventory_2_outlined),
                        selectedIcon: Icon(Icons.inventory_2_rounded),
                        label: 'Gudang',
                      ),
                    const NavigationDestination(
                      icon: Icon(Icons.person_outline_rounded),
                      selectedIcon: Icon(Icons.person_rounded),
                      label: 'Profil',
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _signOut() async {
    final shouldLogOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Keluar dari akun?'),
        content: const Text(
          'Anda memerlukan Crew ID dan password untuk masuk kembali.',
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
    if (shouldLogOut != true) return;
    await Supabase.instance.client.auth.signOut();
    ref.read(currentUserProvider.notifier).state = null;
    if (mounted) context.go('/login');
  }

  Future<void> _changePassword(AppUser? user) async {
    final String? nik = user?.nik.trim();
    if (nik == null || nik.isEmpty) return;

    final bool? changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ChangePasswordSheet(email: '$nik@sicatat.local'),
    );
    if (changed != true || !mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Password berhasil diubah'),
        content: const Text(
          'Untuk melindungi akun, semua sesi SICATAT akan dikeluarkan. '
          'Silakan masuk kembali dengan password baru.',
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Login kembali'),
          ),
        ],
      ),
    );
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.global);
    ref.read(currentUserProvider.notifier).state = null;
    if (mounted) context.go('/login');
  }

  Future<void> _checkForUpdates() async {
    if (_checkingForUpdate) return;
    setState(() => _checkingForUpdate = true);
    try {
      final AppUpdateCheck update = await AppUpdateService().checkForUpdate();
      if (!mounted) return;
      final AppRelease? release = update.release;
      if (release == null) {
        await _showUpdateMessage(
          title: 'Updates are not available yet',
          message:
              'No Android release has been published for this update channel.',
          icon: Icons.cloud_off_rounded,
        );
        return;
      }
      if (!update.isUpdateAvailable) {
        await _showUpdateMessage(
          title: 'SICATAT is up to date',
          message:
              'You are using version ${update.currentVersion}, the latest available version.',
          icon: Icons.verified_rounded,
        );
        return;
      }
      final bool? shouldInstall = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Update available'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('SICATAT ${release.versionName} is ready to install.'),
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
                        "What's new",
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
                'Android will ask you to approve the installation. Your SICATAT data and login are kept.',
                style: TextStyle(color: AppColors.muted),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not now'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.system_update_alt_rounded),
              label: const Text('Download update'),
            ),
          ],
        ),
      );
      if (shouldInstall == true && mounted) {
        await _downloadAndInstall(release);
      }
    } on Object catch (error) {
      if (mounted) {
        await _showUpdateMessage(
          title: 'Unable to check for updates',
          message: '$error',
          icon: Icons.error_outline_rounded,
        );
      }
    } finally {
      if (mounted) setState(() => _checkingForUpdate = false);
    }
  }

  Future<void> _downloadAndInstall(AppRelease release) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(width: 18),
            Expanded(child: Text('Downloading the update...')),
          ],
        ),
      ),
    );
    try {
      final AppInstallerResult result = await AppUpdateService()
          .downloadAndInstall(release);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      if (result == AppInstallerResult.permissionRequired) {
        await _showUpdateMessage(
          title: 'Allow app installs first',
          message: 'Android opened its permission page. Allow installations from SICATAT, then return here and tap Check for updates again.',
          icon: Icons.security_rounded,
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await _showUpdateMessage(
        title: 'Update download failed',
        message: '$error',
        icon: Icons.error_outline_rounded,
      );
    }
  }

  Future<void> _showUpdateMessage({
    required String title,
    required String message,
    required IconData icon,
  }) => showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
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
          child: const Text('OK'),
        ),
      ],
    ),
  );

  Widget _profile(BuildContext context, AppUser? user) {
    final name = user?.name ?? 'Account';
    final role = user == null ? 'Not signed in' : user.role.label;
    final phone = user?.phone?.trim();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      children: <Widget>[
        const Text(
          'Profil',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: <Widget>[
                const CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.mint,
                  child: Icon(
                    Icons.person_rounded,
                    size: 32,
                    color: AppColors.green,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        role,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Detail akun',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: <Widget>[
              _profileRow(Icons.badge_outlined, 'ID Crew', user?.nik ?? '—'),
              const Divider(height: 1),
              _profileRow(Icons.admin_panel_settings_outlined, 'Peran', role),
              const Divider(height: 1),
              _profileRow(
                Icons.groups_outlined,
                'Penugasan tim',
                user?.teamId == null ? 'Belum ditugaskan' : 'Sudah ditugaskan',
              ),
              const Divider(height: 1),
              _profileRow(
                Icons.location_on_outlined,
                'Cakupan site',
                user?.siteId == null
                    ? 'Semua site'
                    : (user?.siteName ?? 'Site yang ditugaskan'),
              ),
              const Divider(height: 1),
              _profileRow(
                Icons.phone_outlined,
                'Telepon',
                phone?.isNotEmpty == true ? phone! : 'Belum diisi',
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        if (!kIsWeb) ...<Widget>[
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.system_update_alt_rounded,
                color: AppColors.green,
              ),
              title: const Text('Pembaruan aplikasi'),
              subtitle: const Text('Periksa dan pasang SICATAT versi terbaru'),
              trailing: _checkingForUpdate
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: _checkingForUpdate ? null : _checkForUpdates,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Card(
          child: ListTile(
            leading: const Icon(Icons.password_rounded, color: AppColors.green),
            title: const Text('Ganti password'),
            subtitle: const Text(
              'Ubah password dan keluarkan semua perangkat yang masih login',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _changePassword(user),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.menu_book_outlined,
              color: AppColors.green,
            ),
            title: const Text('Panduan pengguna'),
            subtitle: const Text(
              'Panduan Temperature, Reminder, dan Warehouse',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.go('/guide'),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _signOut,
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Keluar dari perangkat ini'),
        ),
      ],
    );
  }

  Widget _profileRow(IconData icon, String label, String value) => ListTile(
    leading: Icon(icon, color: AppColors.green),
    title: Text(label),
    trailing: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 170),
      child: Text(
        value,
        textAlign: TextAlign.end,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
  );

  Widget _home(BuildContext context, String crewName, AppUser? user) {
    final List<Widget> actions = <Widget>[
      if (user?.role.canCreateTemperatureSheet == true ||
          user?.role.canReviewTemperature == true)
        _homeMenuCard(
          icon: Icons.thermostat_rounded,
          title: 'Suhu',
          subtitle: user?.role.canCreateTemperatureSheet == true
              ? 'Buat atau lanjutkan sheet'
              : 'Tinjau pekerjaan suhu',
          onTap: () => context.go(
            user?.role.canCreateTemperatureSheet == true
                ? '/sheets/new'
                : '/sheets',
          ),
        ),
      if (user?.role.canUseReminders == true)
        _homeMenuCard(
          icon: Icons.notifications_active_rounded,
          title: 'Pengingat',
          subtitle: 'Tindak lanjut pekerjaan',
          onTap: () => context.go('/reminders'),
        ),
      if (user?.role.canUseWarehouse == true)
        _homeMenuCard(
          icon: Icons.inventory_2_rounded,
          title: 'Gudang',
          subtitle: 'Cari stok & lokasi barang',
          onTap: () => context.go('/warehouse'),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: <Widget>[
        Row(
          children: <Widget>[
            const CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.mint,
              child: Icon(Icons.person_rounded, color: AppColors.green),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Selamat datang, $crewName',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    'Pilih menu untuk melanjutkan pekerjaan',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            SyncChip(_syncState),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'Menu utama',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text(
          'Informasi rinci muncul setelah Anda membuka menu.',
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) => Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: actions
                .map(
                  (Widget action) => SizedBox(
                    width: (constraints.maxWidth - 10) / 2,
                    child: action,
                  ),
                )
                .toList(growable: false),
          ),
        ),
        const SizedBox(height: 12),
        _homeMoreActions(context, user),
      ],
    );
  }

  Widget _homeMenuCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 116,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: AppColors.green, size: 25),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _homeMoreActions(BuildContext context, AppUser? user) => Card(
    margin: EdgeInsets.zero,
    child: ExpansionTile(
      leading: const Icon(Icons.bolt_rounded, color: AppColors.green),
      title: const Text(
        'Aksi lainnya',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: const Text('Sheet, sinkronisasi, laporan, dan panduan'),
      children: <Widget>[
        if (user?.role != UserRole.foremanLv)
          ListTile(
            leading: const Icon(Icons.description_rounded),
            title: const Text('Sheet saya'),
            onTap: () => context.go('/sheets'),
          ),
        if (user?.role != UserRole.foremanLv)
          ListTile(
            leading: const Icon(Icons.sync_rounded),
            title: const Text('Periksa sinkronisasi'),
            onTap: () async {
              await ref.read(sicatatRepositoryProvider).syncPending();
              await _loadActivity();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Antrian sinkronisasi diperiksa.'),
                  ),
                );
              }
            },
          ),
        if (user?.role.canReviewTemperature == true) ...<Widget>[
          ListTile(
            leading: const Icon(Icons.assignment_late_outlined),
            title: const Text('Sheet belum lengkap'),
            onTap: () => context.go('/incomplete'),
          ),
          ListTile(
            leading: const Icon(Icons.monitor_heart_outlined),
            title: const Text('Monitoring sheet'),
            onTap: () => context.go('/monitoring'),
          ),
          ListTile(
            leading: const Icon(Icons.thermostat_auto_rounded),
            title: const Text('Laporan suhu tinggi'),
            onTap: () => context.go('/high-temperature'),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Laporan periode'),
            onTap: () => context.go('/reports'),
          ),
        ],
        if (user?.role.canManageMasterData == true)
          ListTile(
            leading: const Icon(Icons.manage_accounts_outlined),
            title: const Text('Data master & pengguna'),
            onTap: () => context.go('/admin'),
          ),
        ListTile(
          leading: const Icon(Icons.help_outline_rounded),
          title: const Text('Panduan pengguna'),
          onTap: () => context.go('/guide'),
        ),
      ],
    ),
  );
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet({required this.email});

  final String email;

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmation = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirmation = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      await client.auth.signInWithPassword(
        email: widget.email,
        password: _currentPassword.text,
      );
      await client.auth.updateUser(UserAttributes(password: _newPassword.text));
      if (mounted) Navigator.pop(context, true);
    } on AuthException {
      if (mounted) {
        setState(
          () => _error =
              'Password lama tidak sesuai atau tidak dapat diverifikasi.',
        );
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Password belum dapat diubah. Periksa koneksi lalu coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _newPasswordError(String? value) {
    final password = value ?? '';
    if (password.length < 8) {
      return 'Gunakan minimal 8 karakter.';
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password)) {
      return 'Gunakan gabungan huruf dan angka.';
    }
    if (password == _currentPassword.text) {
      return 'Password baru harus berbeda dari password lama.';
    }
    return null;
  }

  InputDecoration _decoration({
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
  }) => InputDecoration(
    labelText: label,
    prefixIcon: const Icon(Icons.lock_outline_rounded),
    suffixIcon: IconButton(
      tooltip: obscure ? 'Tampilkan password' : 'Sembunyikan password',
      onPressed: _saving ? null : onToggle,
      icon: Icon(
        obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Ganti password',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'Gunakan minimal 8 karakter dengan gabungan huruf dan angka. '
              'Sesi pada perangkat lain akan dikeluarkan.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _currentPassword,
              obscureText: _obscureCurrent,
              enabled: !_saving,
              autofillHints: const <String>[AutofillHints.password],
              enableSuggestions: false,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: _decoration(
                label: 'Password lama',
                obscure: _obscureCurrent,
                onToggle: () =>
                    setState(() => _obscureCurrent = !_obscureCurrent),
              ),
              validator: (String? value) => (value == null || value.isEmpty)
                  ? 'Masukkan password lama.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _newPassword,
              obscureText: _obscureNew,
              enabled: !_saving,
              autofillHints: const <String>[AutofillHints.newPassword],
              enableSuggestions: false,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: _decoration(
                label: 'Password baru',
                obscure: _obscureNew,
                onToggle: () => setState(() => _obscureNew = !_obscureNew),
              ),
              validator: _newPasswordError,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmation,
              obscureText: _obscureConfirmation,
              enabled: !_saving,
              autofillHints: const <String>[AutofillHints.newPassword],
              enableSuggestions: false,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: _decoration(
                label: 'Ulangi password baru',
                obscure: _obscureConfirmation,
                onToggle: () => setState(
                  () => _obscureConfirmation = !_obscureConfirmation,
                ),
              ),
              validator: (String? value) => value != _newPassword.text
                  ? 'Password baru belum sama.'
                  : null,
            ),
            if (_error case final message?) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                message,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_reset_rounded),
                label: Text(_saving ? 'Menyimpan...' : 'Simpan password baru'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
