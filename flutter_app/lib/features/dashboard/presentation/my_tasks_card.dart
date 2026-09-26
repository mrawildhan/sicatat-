import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/sicatat_types.dart';
import '../../warehouse/warehouse_data.dart';

/// One thing waiting for the signed-in user.
class MyTask {
  const MyTask({
    required this.icon,
    required this.text,
    required this.count,
    required this.route,
    this.urgent = false,
  });

  final IconData icon;
  final String text;
  final int count;
  final String route;
  final bool urgent;
}

/// Beranda → Tugas saya (owner request 2026-09-26): what is waiting for this
/// user across the menus, so nobody has to open each menu to find out.
/// Every source is optional; one that the role may not read is skipped.
Future<List<MyTask>> loadMyTasks(SupabaseClient client, AppUser user) async {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  String date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
  final String name = user.name.trim();
  final List<MyTask> tasks = <MyTask>[];

  Future<List<Object?>> rows(Future<Object?> query) async {
    try {
      final Object? result = await query;
      return result is List ? result : const <Object?>[];
    } on Object {
      return const <Object?>[];
    }
  }

  // Own crew's PM due within a week (or already past its plan).
  final Future<List<Object?>> pmRows = () async {
    if (user.teamId == null) return const <Object?>[];
    final List<Object?> team = await rows(
      client.from('team').select('code').eq('id', user.teamId!).limit(1),
    );
    final String? code = team.isEmpty
        ? null
        : requireJsonMap(team.first).optionalString('code');
    if (code == null) return const <Object?>[];
    return rows(
      client
          .from('preventive_maintenance_work_order')
          .select('crew_code,planned_start_on')
          .eq('crew_code', code)
          .lte('planned_start_on', date(today.add(const Duration(days: 7))))
          .limit(1000),
    );
  }();

  final List<List<Object?>> results = await Future.wait(<Future<List<Object?>>>[
    pmRows,
    // Goods ordered for this user that have not arrived.
    name.isEmpty
        ? Future<List<Object?>>.value(const <Object?>[])
        : rows(
            client
                .from('warehouse_outstanding_po')
                .select('po_no')
                .ilike('requestor', name)
                .limit(1000),
          ),
    // Goods for this user received in the last 7 days (warehouse roles).
    name.isEmpty
        ? Future<List<Object?>>.value(const <Object?>[])
        : rows(
            client
                .from('warehouse_receipt')
                .select('po_number')
                .ilike('requested_by', name)
                .gte(
                  'received_on',
                  date(today.subtract(const Duration(days: 7))),
                )
                .limit(500),
          ),
    // Reviewers: critical temperatures not closed, sheets to approve.
    user.role.canReviewTemperature
        ? rows(
            client
                .from('temperature_alert')
                .select('id')
                .neq('followup_status', 'closed')
                .limit(1000),
          )
        : Future<List<Object?>>.value(const <Object?>[]),
    user.role.canReviewTemperature
        ? rows(
            client
                .from('daily_check_sheet')
                .select('id')
                .eq('status', 'submitted')
                .isFilter('approved_at', null)
                .limit(1000),
          )
        : Future<List<Object?>>.value(const <Object?>[]),
    // Warehouse roles: tools not returned after the allowed days.
    user.role.canManageWarehouse
        ? rows(
            client
                .from('warehouse_tool_loan_item')
                .select('loan:loan_id(loaned_on)')
                .isFilter('returned_at', null)
                .limit(1000),
          )
        : Future<List<Object?>>.value(const <Object?>[]),
    user.role.canManageWarehouse
        ? rows(
            client
                .from('warehouse_list_order_loan')
                .select('loaned_on')
                .eq('returned', false)
                .limit(1000),
          )
        : Future<List<Object?>>.value(const <Object?>[]),
  ]);

  final List<Object?> pm = results[0];
  if (pm.isNotEmpty) {
    final int overdue = pm.where((Object? row) {
      final DateTime? planned = DateTime.tryParse(
        requireJsonMap(row).optionalString('planned_start_on') ?? '',
      );
      return planned != null && planned.isBefore(today);
    }).length;
    tasks.add(
      MyTask(
        icon: Icons.pending_actions_outlined,
        text:
            'PM crew Anda jatuh tempo ≤ 7 hari'
            '${overdue > 0 ? ' ($overdue lewat rencana)' : ''}',
        count: pm.length,
        route: '/outstanding-maintenance',
        urgent: overdue > 0,
      ),
    );
  }
  if (results[3].isNotEmpty) {
    tasks.add(
      MyTask(
        icon: Icons.thermostat_rounded,
        text: 'Suhu kritis belum ditutup',
        count: results[3].length,
        route: '/temperature-alerts',
        urgent: true,
      ),
    );
  }
  if (results[4].isNotEmpty) {
    tasks.add(
      MyTask(
        icon: Icons.fact_check_outlined,
        text: 'Lembar menunggu persetujuan',
        count: results[4].length,
        route: '/monitoring',
      ),
    );
  }
  if (results[2].isNotEmpty) {
    tasks.add(
      MyTask(
        icon: Icons.local_shipping_outlined,
        text: 'Barang pesanan Anda datang (7 hari terakhir)',
        count: results[2].length,
        route: '/warehouse/receipts',
      ),
    );
  }
  if (results[1].isNotEmpty) {
    tasks.add(
      MyTask(
        icon: Icons.shopping_cart_outlined,
        text: 'Barang pesanan Anda belum datang',
        count: results[1].length,
        route:
            '/warehouse/purchase-orders?requestor=${Uri.encodeQueryComponent(name)}',
      ),
    );
  }
  int lateLoans = 0;
  for (final Object? row in results[5]) {
    final Object? loan = requireJsonMap(row)['loan'];
    final DateTime? on = loan is Map
        ? DateTime.tryParse('${loan['loaned_on']}')
        : null;
    if (on != null && warehouseLoanAgeDays(on) > warehouseLoanOverdueDays) {
      lateLoans++;
    }
  }
  for (final Object? row in results[6]) {
    final DateTime? on = DateTime.tryParse(
      requireJsonMap(row).optionalString('loaned_on') ?? '',
    );
    if (on != null && warehouseLoanAgeDays(on) > warehouseLoanOverdueDays) {
      lateLoans++;
    }
  }
  if (lateLoans > 0) {
    tasks.add(
      MyTask(
        icon: Icons.handyman_outlined,
        text: 'Alat terlambat kembali (> $warehouseLoanOverdueDays hari)',
        count: lateLoans,
        route: '/warehouse/tool-loans',
        urgent: true,
      ),
    );
  }
  return tasks;
}

class MyTasksCard extends StatefulWidget {
  const MyTasksCard({required this.user, super.key});

  final AppUser user;

  @override
  State<MyTasksCard> createState() => _MyTasksCardState();
}

class _MyTasksCardState extends State<MyTasksCard> {
  List<MyTask>? _tasks;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MyTasksCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id) _load();
  }

  Future<void> _load() async {
    try {
      final List<MyTask> tasks = await loadMyTasks(
        Supabase.instance.client,
        widget.user,
      );
      if (mounted) setState(() => _tasks = tasks);
    } on Object {
      if (mounted) setState(() => _tasks = const <MyTask>[]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<MyTask>? tasks = _tasks;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.task_alt_rounded, color: AppColors.green),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Tugas saya', style: AppTextStyles.cardTitle),
                  ),
                  IconButton(
                    tooltip: 'Muat ulang',
                    visualDensity: VisualDensity.compact,
                    onPressed: tasks == null
                        ? null
                        : () {
                            setState(() => _tasks = null);
                            _load();
                          },
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
                ],
              ),
            ),
            if (tasks == null)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: LinearProgressIndicator(),
              )
            else if (tasks.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Text(
                  'Tidak ada tugas yang menunggu Anda.',
                  style: AppTextStyles.supporting,
                ),
              )
            else
              for (final MyTask task in tasks)
                ListTile(
                  dense: true,
                  leading: Icon(
                    task.icon,
                    color: task.urgent ? AppColors.danger : AppColors.green,
                  ),
                  title: Text(task.text),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (task.urgent ? AppColors.danger : AppColors.green)
                                  .withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${task.count}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: task.urgent
                                ? AppColors.danger
                                : AppColors.green,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.muted,
                      ),
                    ],
                  ),
                  onTap: () => context.go(task.route),
                ),
          ],
        ),
      ),
    );
  }
}
