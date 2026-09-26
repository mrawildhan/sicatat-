import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import 'grouped_bottom_navigation.dart';
import 'my_tasks_card.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/app_update_prompt.dart';
import '../../../data/models/app_user.dart';
import '../../auth/application/current_user_provider.dart';
import '../../daily_checks/check_reminders.dart';
import '../../daily_checks/critical_alert_watcher.dart';
import '../../daily_checks/presentation/check_schedule_card.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({this.showProfile = false, super.key});

  final bool showProfile;

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _index = 0;
  bool _checkingForUpdate = false;
  late bool _showProfile;

  @override
  void initState() {
    super.initState();
    _showProfile = widget.showProfile;
    // A restored session skips the login screen, so offer a newer APK here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppUpdatePrompt.offerOnce(context);
      // Right after signing in, not only at the next 3-minute tick.
      CriticalAlertWatcher.instance.check();
    });
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showProfile != widget.showProfile) {
      _showProfile = widget.showProfile;
    }
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
    final bool hasTemperatureTab = user?.role.canOpenTemperature == true;
    final bool hasReminderTab = user?.role.canUseReminders == true;
    final bool hasWarehouseTab = user?.role.canUseWarehouse == true;
    final bool hasMajorJob = user?.role.canUseMajorJob == true;
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
        context.go('/temperature-forms');
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
                'Operasional, referensi, dan informasi kerja',
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
                            _desktopSidebarItem(
                              label: 'Operasional',
                              icon: Icons.fact_check_outlined,
                              selectedIcon: Icons.fact_check,
                              selected: false,
                              onTap: () => openNavigationGroup(
                                context,
                                operational: true,
                                canTemperature: hasTemperatureTab,
                                canReminders: hasReminderTab,
                                canWarehouse: hasWarehouseTab,
                                canMajorJob: hasMajorJob,
                              ),
                            ),
                            _desktopSidebarItem(
                              label: 'Referensi',
                              icon: Icons.folder_copy_outlined,
                              selectedIcon: Icons.folder_copy,
                              selected: false,
                              onTap: () => openNavigationGroup(
                                context,
                                operational: false,
                                canTemperature: hasTemperatureTab,
                                canReminders: hasReminderTab,
                                canWarehouse: hasWarehouseTab,
                                canMajorJob: hasMajorJob,
                              ),
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
                          '© 2026 • Versi ${AppConfig.appVersion}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
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
            : GroupedBottomNavigation(
                selected: _showProfile ? 'profile' : 'home',
                canTemperature: hasTemperatureTab,
                canReminders: hasReminderTab,
                canWarehouse: hasWarehouseTab,
                canMajorJob: hasMajorJob,
                onHome: () => selectDestination(0),
                onProfile: () => selectDestination(profileIndex),
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
          'Anda memerlukan NIK dan kata sandi untuk masuk kembali.',
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
    await CheckReminders.cancelAll();
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
        title: const Text('Kata sandi berhasil diubah'),
        content: const Text(
          'Untuk melindungi akun, semua sesi SICATAT akan dikeluarkan. '
          'Silakan masuk kembali dengan kata sandi baru.',
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Masuk kembali'),
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
      await AppUpdatePrompt.checkManually(context);
    } finally {
      if (mounted) setState(() => _checkingForUpdate = false);
    }
  }

  Widget _profile(BuildContext context, AppUser? user) {
    final name = user?.name ?? 'Account';
    final role = user == null ? 'Belum masuk' : user.role.label;
    final phone = user?.phone?.trim();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      children: <Widget>[
        const Text('Profil', style: AppTextStyles.pageTitle),
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
              _profileRow(Icons.badge_outlined, 'NIK', user?.nik ?? '—'),
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
        Card(
          child: ListTile(
            leading: const Icon(Icons.password_rounded, color: AppColors.green),
            title: const Text('Ganti kata sandi'),
            subtitle: const Text(
              'Ubah kata sandi dan keluarkan semua perangkat yang masih masuk',
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
            subtitle: const Text('Panduan penggunaan setiap menu'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.go('/guide'),
          ),
        ),
        const SizedBox(height: 12),
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
    // A label beside its value, not a card title.
    title: Text(label, style: AppTextStyles.body),
    trailing: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 170),
      child: Text(
        value,
        textAlign: TextAlign.end,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.body.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );

  Widget _home(BuildContext context, String crewName, AppUser? user) {
    final bool hasTemperature =
        user?.role.canCreateTemperatureSheet == true ||
        user?.role.canReviewTemperature == true;
    final bool hasReminders = user?.role.canUseReminders == true;
    final bool hasWarehouse = user?.role.canUseWarehouse == true;
    final bool hasMajorJob = user?.role.canUseMajorJob == true;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const CircleAvatar(
                    radius: 23,
                    backgroundColor: AppColors.mint,
                    child: Icon(Icons.person_rounded, color: AppColors.green),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Selamat datang',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          crewName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                          softWrap: true,
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Pilih menu untuk melanjutkan pekerjaan',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (user != null) MyTasksCard(user: user),
        if (user != null &&
            (user.role == UserRole.crew || user.role == UserRole.foreman))
          CheckScheduleCard(user: user),
        const SizedBox(height: 16),
        const Text('Akses cepat', style: AppTextStyles.sectionTitle),
        const SizedBox(height: 4),
        const Text(
          'Pilih kelompok menu untuk melihat fitur di dalamnya.',
          style: AppTextStyles.supporting,
        ),
        const SizedBox(height: 8),
        _homeMenuCard(
          icon: Icons.fact_check_rounded,
          title: 'Operasional',
          subtitle: 'Suhu, gudang, PM & CM, anggaran, dan lainnya',
          onTap: () => openNavigationGroup(
            context,
            operational: true,
            canTemperature: hasTemperature,
            canReminders: hasReminders,
            canWarehouse: hasWarehouse,
            canMajorJob: hasMajorJob,
          ),
        ),
        const SizedBox(height: 8),
        _homeMenuCard(
          icon: Icons.folder_copy_rounded,
          title: 'Referensi',
          subtitle: 'Dokumen, data PR, kode biaya, alat, dan panduan',
          onTap: () => openNavigationGroup(
            context,
            operational: false,
            canTemperature: hasTemperature,
            canReminders: hasReminders,
            canWarehouse: hasWarehouse,
            canMajorJob: hasMajorJob,
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
        height: 78,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.mint,
                child: Icon(icon, color: AppColors.green, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: AppTextStyles.cardTitle),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.supporting,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _homeMoreActions(BuildContext context, AppUser? user) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const Text('Pengaturan & bantuan', style: AppTextStyles.sectionTitle),
      const SizedBox(height: 4),
      const Text(
        'Akses umum aplikasi di luar pekerjaan Suhu.',
        style: AppTextStyles.supporting,
      ),
      if (user?.role.canManageMasterData == true) ...<Widget>[
        const SizedBox(height: 8),
        _homeUtilityCard(
          icon: Icons.manage_accounts_outlined,
          title: 'Data master & pengguna',
          subtitle: 'Kelola pengguna dan data operasional',
          onTap: () => context.go('/admin'),
        ),
      ],
      const SizedBox(height: 8),
      _homeUtilityCard(
        icon: Icons.help_outline_rounded,
        title: 'Panduan pengguna',
        subtitle: 'Pelajari cara menggunakan aplikasi',
        onTap: () => context.go('/guide'),
      ),
    ],
  );

  Widget _homeUtilityCard({
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
        height: 70,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.mint,
                child: Icon(icon, color: AppColors.green, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: AppTextStyles.cardTitle),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.supporting,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
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
              'Kata sandi lama tidak sesuai atau tidak dapat diverifikasi.',
        );
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Kata sandi belum dapat diubah. Periksa koneksi lalu coba lagi.',
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
      return 'Kata sandi baru harus berbeda dari kata sandi lama.';
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
      tooltip: obscure ? 'Tampilkan kata sandi' : 'Sembunyikan kata sandi',
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
              'Ganti kata sandi',
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
                label: 'Kata sandi lama',
                obscure: _obscureCurrent,
                onToggle: () =>
                    setState(() => _obscureCurrent = !_obscureCurrent),
              ),
              validator: (String? value) => (value == null || value.isEmpty)
                  ? 'Masukkan kata sandi lama.'
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
                label: 'Kata sandi baru',
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
                label: 'Ulangi kata sandi baru',
                obscure: _obscureConfirmation,
                onToggle: () => setState(
                  () => _obscureConfirmation = !_obscureConfirmation,
                ),
              ),
              validator: (String? value) => value != _newPassword.text
                  ? 'Kata sandi baru belum sama.'
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
                label: Text(
                  _saving ? 'Menyimpan...' : 'Simpan kata sandi baru',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
