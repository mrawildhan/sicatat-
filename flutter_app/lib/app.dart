import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'core/widgets/online_only_gate.dart';
import 'core/widgets/role_guard.dart';
import 'data/models/app_user.dart';
import 'data/version/app_version_service.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/admin/presentation/basic_master_screens.dart';
import 'features/admin/presentation/equipment_management_screen.dart';
import 'features/admin/presentation/form_template_management_screen.dart';
import 'features/admin/presentation/master_data_hub_screen.dart';
import 'features/admin/presentation/threshold_management_screen.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';
import 'features/guide/presentation/crew_guide_screen.dart';
import 'features/reminders/presentation/reminder_screen.dart';
import 'features/reports/presentation/report_screen.dart';
import 'features/reports/presentation/sheet_export_screen.dart';
import 'features/reports/presentation/high_temperature_report_screen.dart';
import 'features/users/presentation/user_management_screen.dart';
import 'features/sheets/presentation/new_sheet_screen.dart';
import 'features/sheets/presentation/sheet_list_screen.dart';
import 'features/sheets/presentation/sheet_monitoring_screen.dart';
import 'features/sheets/presentation/incomplete_sheet_screen.dart';
import 'features/sheets/presentation/sheet_summary_screen.dart';
import 'features/temperature/presentation/temperature_form_screen.dart';

final _router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
    GoRoute(
      path: '/admin',
      builder: (_, __) => const RoleGuard(
        allowed: <UserRole>{UserRole.admin},
        child: MasterDataHubScreen(),
      ),
    ),
    GoRoute(
      path: '/admin/shifts',
      builder: (_, __) => const RoleGuard(
        allowed: <UserRole>{UserRole.admin},
        child: ShiftManagementScreen(),
      ),
    ),
    GoRoute(
      path: '/admin/teams',
      builder: (_, __) => const RoleGuard(
        allowed: <UserRole>{UserRole.admin},
        child: TeamManagementScreen(),
      ),
    ),
    GoRoute(
      path: '/admin/roster',
      builder: (_, __) => const RoleGuard(
        allowed: <UserRole>{UserRole.admin},
        child: RosterManagementScreen(),
      ),
    ),
    GoRoute(
      path: '/admin/equipment',
      builder: (_, __) => const RoleGuard(
        allowed: <UserRole>{UserRole.admin},
        child: EquipmentManagementScreen(),
      ),
    ),
    GoRoute(
      path: '/admin/thresholds',
      builder: (_, __) => const RoleGuard(
        allowed: <UserRole>{UserRole.admin},
        child: ThresholdManagementScreen(),
      ),
    ),
    GoRoute(
      path: '/admin/form-template',
      builder: (_, __) => const RoleGuard(
        allowed: <UserRole>{UserRole.admin},
        child: FormTemplateManagementScreen(),
      ),
    ),
    GoRoute(
      path: '/admin/measurement-points',
      builder: (_, state) => RoleGuard(
        allowed: const <UserRole>{UserRole.admin},
        child: MeasurementPointManagementScreen(
          equipmentId: state.uri.queryParameters['equipmentId'],
          equipmentName:
              state.uri.queryParameters['equipmentName'] ??
              'Measurement points',
        ),
      ),
    ),
    GoRoute(path: '/sheets', builder: (_, __) => const SheetListScreen()),
    GoRoute(path: '/sheets/new', builder: (_, __) => const NewSheetScreen()),
    GoRoute(
      path: '/monitoring',
      builder: (_, __) => const RoleGuard(
        allowed: <UserRole>{
          UserRole.foreman,
          UserRole.supervisor,
          UserRole.admin,
        },
        child: SheetMonitoringScreen(),
      ),
    ),
    GoRoute(
      path: '/temperature',
      builder: (_, state) => TemperatureFormScreen(
        sheetId: state.uri.queryParameters['sheetId'],
        initialSection: state.uri.queryParameters['section'],
        initialRound: state.uri.queryParameters['round'],
        initialSide: state.uri.queryParameters['side'],
        initialEntry: state.uri.queryParameters['entry'],
      ),
    ),
    GoRoute(
      path: '/summary',
      builder: (_, state) =>
          SheetSummaryScreen(sheetId: state.uri.queryParameters['sheetId']),
    ),
    GoRoute(path: '/guide', builder: (_, __) => const CrewGuideScreen()),
    GoRoute(
      path: '/reminders',
      builder: (_, __) => const RoleGuard(
        allowed: <UserRole>{UserRole.admin},
        child: ReminderScreen(),
      ),
    ),
    GoRoute(
      path: '/reports',
      builder: (_, __) => const RoleGuard(
        allowed: <UserRole>{UserRole.admin},
        child: ReportScreen(),
      ),
    ),
    GoRoute(
      path: '/sheet-export',
      builder: (_, state) => RoleGuard(
        allowed: const <UserRole>{
          UserRole.crew,
          UserRole.foreman,
          UserRole.supervisor,
          UserRole.admin,
        },
        child: SheetExportScreen(sheetId: state.uri.queryParameters['sheetId']),
      ),
    ),
    GoRoute(
      path: '/high-temperature',
      builder: (_, __) => const RoleGuard(
        allowed: <UserRole>{
          UserRole.foreman,
          UserRole.supervisor,
          UserRole.admin,
        },
        child: HighTemperatureReportScreen(),
      ),
    ),
    GoRoute(
      path: '/incomplete',
      builder: (_, __) => const RoleGuard(
        allowed: <UserRole>{
          UserRole.foreman,
          UserRole.supervisor,
          UserRole.admin,
        },
        child: IncompleteSheetScreen(),
      ),
    ),
    GoRoute(
      path: '/users',
      builder: (_, __) => const RoleGuard(
        allowed: <UserRole>{UserRole.admin},
        child: UserManagementScreen(),
      ),
    ),
  ],
);

class SicatatApp extends StatefulWidget {
  const SicatatApp({super.key});

  @override
  State<SicatatApp> createState() => _SicatatAppState();
}

class _SicatatAppState extends State<SicatatApp> {
  late final Future<AppVersionStatus> _versionStatus;
  bool _noticeDismissed = false;

  @override
  void initState() {
    super.initState();
    _versionStatus = AppVersionService.current().check();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppVersionStatus>(
      future: _versionStatus,
      initialData: const AppVersionStatus.unavailable(),
      builder:
          (BuildContext context, AsyncSnapshot<AppVersionStatus> snapshot) {
            final AppVersionStatus status =
                snapshot.data ?? const AppVersionStatus.unavailable();
            return MaterialApp.router(
              title: 'sicatat',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              routerConfig: _router,
              builder: (BuildContext context, Widget? child) => OnlineOnlyGate(
                child: Stack(
                  children: <Widget>[
                    child ?? const SizedBox.shrink(),
                    if (status.updateAvailable && !_noticeDismissed)
                      _VersionNotice(
                        latestVersion: status.latestVersion ?? '',
                        releaseNotes: status.releaseNotes,
                        onDismiss: () =>
                            setState(() => _noticeDismissed = true),
                      ),
                    if (status.blocked)
                      _VersionBlock(
                        latestVersion: status.latestVersion ?? '',
                        releaseNotes: status.releaseNotes,
                      ),
                  ],
                ),
              ),
            );
          },
    );
  }
}

class _VersionNotice extends StatelessWidget {
  const _VersionNotice({
    required this.latestVersion,
    required this.releaseNotes,
    required this.onDismiss,
  });

  final String latestVersion;
  final String? releaseNotes;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Align(
      alignment: Alignment.topCenter,
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
          decoration: BoxDecoration(
            color: AppColors.mint,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.green.withValues(alpha: .28)),
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.system_update_alt_rounded,
                color: AppColors.green,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Version $latestVersion is available.${releaseNotes == null || releaseNotes!.isEmpty ? '' : ' $releaseNotes'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.greenDark,
                  ),
                ),
              ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Dismiss update notice',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _VersionBlock extends StatelessWidget {
  const _VersionBlock({
    required this.latestVersion,
    required this.releaseNotes,
  });

  final String latestVersion;
  final String? releaseNotes;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.system_update_rounded,
                size: 58,
                color: AppColors.green,
              ),
              const SizedBox(height: 18),
              const Text(
                'Update required',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Text(
                'This app version is no longer supported. Ask your administrator for the latest APK (version $latestVersion) before continuing.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, height: 1.5),
              ),
              if (releaseNotes != null && releaseNotes!.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text(releaseNotes!, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
