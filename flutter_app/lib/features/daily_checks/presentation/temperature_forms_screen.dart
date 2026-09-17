import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../daily_check_forms.dart';

/// Suhu opens here first: the Feeder/Sizer temperature sheet and the two
/// daily check sheets that belong with it.
class TemperatureFormsScreen extends StatelessWidget {
  const TemperatureFormsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final choices = <_FormChoice>[
      const _FormChoice(
        icon: Icons.thermostat_rounded,
        title: 'Daily Temperature Feeder Sizer',
        subtitle: 'Gearbox breaker & sizer, 2 ronde per shift',
        route: '/sheets',
      ),
      for (final type in DailyCheckFormType.values)
        _FormChoice(
          icon: type.form.icon,
          title: type.form.title,
          subtitle: type.form.description,
          route: '/daily-checks/${type.storageValue}',
        ),
    ];
    return AppBackScope(
      fallbackRoute: '/dashboard',
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallbackRoute: '/dashboard'),
          title: const Text(
            'Suhu',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: <Widget>[
            const Text(
              'Pilih lembar pemeriksaan',
              style: AppTextStyles.sectionTitle,
            ),
            const SizedBox(height: 4),
            const Text(
              'Setiap lembar diisi satu kali per tanggal dan shift.',
              style: AppTextStyles.supporting,
            ),
            const SizedBox(height: 14),
            for (final choice in choices)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => context.go(choice.route),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                      child: Row(
                        children: <Widget>[
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: AppColors.mint,
                            child: Icon(choice.icon, color: AppColors.green),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  choice.title,
                                  style: AppTextStyles.cardTitle.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  choice.subtitle,
                                  style: AppTextStyles.supporting,
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FormChoice {
  const _FormChoice({
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
