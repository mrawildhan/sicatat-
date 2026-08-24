import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/section_title.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/dashboard_activity.dart';
import '../../../data/local/local_database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../auth/application/current_user_provider.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _index = 0;
  DashboardActivity? _activity;
  Timer? _activityRefreshTimer;

  @override
  void initState() {
    super.initState();
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

  Future<void> _loadActivity() async {
    try {
      final user = ref.read(currentUserProvider);
      final DashboardActivity activity = await LocalDatabase.instance
          .getDashboardActivity(
            DateTime.now(),
            createdBy:
                user?.role == UserRole.admin ||
                    user?.role == UserRole.supervisor
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

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final crewName = user?.name ?? 'Crew';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _index != 0) {
          setState(() => _index = 0);
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
              tooltip: 'Refresh activity',
            ),
            IconButton(
              onPressed: _signOut,
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Logout',
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: IndexedStack(
            index: _index,
            children: [
              _home(context, crewName, user),
              const SizedBox(),
              _profile(context, user),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) {
              if (value == 1) {
                context.go('/sheets');
                return;
              }
              setState(() => _index = value);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.description_outlined),
                selectedIcon: Icon(Icons.description_rounded),
                label: 'Sheets',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Profile',
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
        title: const Text('Log out?'),
        content: const Text(
          'You will need your Crew ID and PIN to sign in again.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (shouldLogOut != true) return;
    await Supabase.instance.client.auth.signOut();
    ref.read(currentUserProvider.notifier).state = null;
    if (mounted) context.go('/login');
  }

  Widget _profile(BuildContext context, AppUser? user) {
    final name = user?.name ?? 'Account';
    final role = user == null
        ? 'Not signed in'
        : '${user.role.name[0].toUpperCase()}${user.role.name.substring(1)}';
    final phone = user?.phone?.trim();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      children: <Widget>[
        const Text(
          'Profile',
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
          'Account details',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: <Widget>[
              _profileRow(Icons.badge_outlined, 'Crew ID', user?.nik ?? '—'),
              const Divider(height: 1),
              _profileRow(Icons.admin_panel_settings_outlined, 'Role', role),
              const Divider(height: 1),
              _profileRow(
                Icons.groups_outlined,
                'Team assignment',
                user?.teamId == null ? 'Not assigned' : 'Assigned',
              ),
              const Divider(height: 1),
              _profileRow(
                Icons.phone_outlined,
                'Phone',
                phone?.isNotEmpty == true ? phone! : 'Not provided',
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        OutlinedButton.icon(
          onPressed: _signOut,
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Log out from this device'),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Row(
          children: [
            const CircleAvatar(
              radius: 25,
              backgroundColor: AppColors.mint,
              child: Icon(Icons.person_rounded, color: AppColors.green),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hello, $crewName',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    'Choose the operational task you want to manage.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            SyncChip(_syncState),
          ],
        ),
        const SizedBox(height: 22),
        const Text(
          'Operations hub',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        _primaryAction(
          icon: Icons.thermostat_rounded,
          title: 'Temperature inspections',
          subtitle: 'Record Feeder Breaker and Sizer readings. More temperature modules can be added here.',
          actionLabel: 'Open inspections',
          onTap: () => context.go('/sheets/new'),
        ),
        const SizedBox(height: 12),
        _primaryAction(
          icon: Icons.notifications_active_rounded,
          title: 'Operational reminders',
          subtitle: user?.role == UserRole.admin
              ? 'Manage due dates for servicing, documents, and other operational follow-ups.'
              : 'Reminder schedules are currently managed by the administrator.',
          actionLabel: user?.role == UserRole.admin
              ? 'Open reminders'
              : 'Admin-managed',
          enabled: user?.role == UserRole.admin,
          onTap: () => context.go('/reminders'),
        ),
        const SizedBox(height: 28),
        SectionTitle(
          'Today’s activity',
          action: TextButton(
            onPressed: () => context.go('/sheets'),
            child: const Text('View all'),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _stat(
              'Draft',
              _activity?.draftCount.toString() ?? '—',
              AppColors.warning,
              Icons.edit_note_rounded,
            ),
            const SizedBox(width: 10),
            _stat(
              'Synced',
              _activity?.syncedCount.toString() ?? '—',
              AppColors.green,
              Icons.cloud_done_rounded,
            ),
            const SizedBox(width: 10),
            _stat(
              'High temp',
              _activity?.highTemperatureCount.toString() ?? '—',
              AppColors.danger,
              Icons.device_thermostat_rounded,
            ),
          ],
        ),
        const SizedBox(height: 28),
        const SectionTitle('Quick access'),
        const SizedBox(height: 12),
        _quickAction(
          Icons.description_rounded,
          'My sheets',
          'View and continue field entries',
          () => context.go('/sheets'),
        ),
        const SizedBox(height: 10),
        _quickAction(
          Icons.sync_rounded,
          'Sync data',
          'Send data queued on this device to the server',
          () async {
            await ref.read(sicatatRepositoryProvider).syncPending();
            await _loadActivity();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sync queue checked.')),
              );
            }
          },
        ),
        const SizedBox(height: 10),
        if (user != null && user.role != UserRole.crew) ...<Widget>[
          _quickAction(
            Icons.assignment_late_outlined,
            'Incomplete sheets',
            user.role == UserRole.foreman
                ? 'Review incomplete sheets for your team'
                : 'Review incomplete sheets across teams',
            () => context.go('/incomplete'),
          ),
          const SizedBox(height: 10),
          _quickAction(
            Icons.monitor_heart_outlined,
            user.role == UserRole.foreman ? 'Team sheets' : 'Sheet monitoring',
            'View synced crew sheets and drafts',
            () => context.go('/monitoring'),
          ),
          const SizedBox(height: 10),
          _quickAction(
            Icons.thermostat_auto_rounded,
            'High temperature report',
            'Review all temperatures at or above 60°C',
            () => context.go('/high-temperature'),
          ),
          const SizedBox(height: 10),
          _quickAction(
            Icons.picture_as_pdf_outlined,
            'Period reports',
            user.role == UserRole.foreman
                ? 'Export readings for your team by date range'
                : 'Export readings and PDF reports by date range',
            () => context.go('/reports'),
          ),
          const SizedBox(height: 10),
        ],
        if (user?.role == UserRole.admin) ...<Widget>[
          _quickAction(
            Icons.manage_accounts_outlined,
            'Master data & users',
            'Manage equipment, roster, teams, users, and exports',
            () => context.go('/admin'),
          ),
          const SizedBox(height: 10),
        ],
        _quickAction(
          Icons.help_outline_rounded,
          'Crew guide',
          'How to complete a field sheet',
          () => context.go('/guide'),
        ),
      ],
    );
  }

  Widget _stat(String title, String value, Color color, IconData icon) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 21),
              const SizedBox(height: 9),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                title,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
      );

  Widget _primaryAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onTap,
    bool enabled = true,
  }) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: enabled
          ? const LinearGradient(colors: [AppColors.greenDark, AppColors.green])
          : null,
      color: enabled ? null : AppColors.mint,
      borderRadius: BorderRadius.circular(24),
      border: enabled ? null : Border.all(color: AppColors.line),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: enabled ? Colors.white.withValues(alpha: .16) : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: enabled ? Colors.white : AppColors.green),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  color: enabled ? Colors.white : AppColors.greenDark,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  color: enabled ? Colors.white70 : AppColors.muted,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: enabled ? onTap : null,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.greenDark,
                  disabledBackgroundColor: Colors.white,
                  disabledForegroundColor: AppColors.muted,
                ),
                icon: Icon(
                  enabled
                      ? Icons.arrow_forward_rounded
                      : Icons.admin_panel_settings_outlined,
                ),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _quickAction(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) => Card(
    child: ListTile(
      onTap: onTap,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.mint,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: AppColors.green),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
    ),
  );
}
