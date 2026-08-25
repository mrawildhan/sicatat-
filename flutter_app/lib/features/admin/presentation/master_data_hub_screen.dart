import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/app_user.dart';
import '../../auth/application/current_user_provider.dart';

class MasterDataHubScreen extends ConsumerWidget {
  const MasterDataHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManageUsers =
        ref.watch(currentUserProvider)?.role.canManageUsers == true;
    return AppBackScope(
      fallbackRoute: '/dashboard',
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallbackRoute: '/dashboard'),
          title: const Text('Master data & administration'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            const Text(
              'Manage the same master data as the legacy SICATAT application.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            _item(
              context,
              Icons.location_city_rounded,
              'Sites',
              'Operational locations such as Asam-Asam and Kintap',
              '/admin/sites',
            ),
            _item(
              context,
              Icons.precision_manufacturing_outlined,
              'Equipment & measurement points',
              'Equipment, sections, measurement points, and active status',
              '/admin/equipment',
            ),
            _item(
              context,
              Icons.tune_rounded,
              'Thresholds',
              'Warning, alarm, and temperature change limits',
              '/admin/thresholds',
            ),
            _item(
              context,
              Icons.account_tree_outlined,
              'Temperature form template',
              'Round order and number of rounds per shift',
              '/admin/form-template',
            ),
            _item(
              context,
              Icons.schedule_rounded,
              'Shifts',
              'Day/night shift names, codes, and times',
              '/admin/shifts',
            ),
            _item(
              context,
              Icons.groups_rounded,
              'Teams',
              'Crew teams and their active status',
              '/admin/teams',
            ),
            _item(
              context,
              Icons.calendar_month_rounded,
              'Roster',
              'Three-day rotation reference and crew order',
              '/admin/roster',
            ),
            if (canManageUsers)
              _item(
                context,
                Icons.manage_accounts_outlined,
                'Users',
                'Crew IDs, roles, teams, and account status',
                '/users',
              ),
            _item(
              context,
              Icons.file_download_outlined,
              'Export date range',
              'PDF and data export across all crews',
              '/reports',
            ),
          ],
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
