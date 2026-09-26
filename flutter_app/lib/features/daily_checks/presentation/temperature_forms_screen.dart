import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../core/widgets/menu_choice_card.dart';
import '../../../data/models/app_user.dart';
import '../../auth/application/current_user_provider.dart';
import '../daily_check_forms.dart';

/// Suhu opens here first: the Feeder/Sizer temperature sheet and the two
/// daily check sheets that belong with it.
class TemperatureFormsScreen extends ConsumerWidget {
  const TemperatureFormsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canReview =
        ref.watch(currentUserProvider)?.role.canReviewTemperature == true;
    final tools = <_FormChoice>[
      const _FormChoice(
        icon: Icons.show_chart_rounded,
        title: 'Tren suhu',
        subtitle: 'Grafik suhu per titik ukur, 7 sampai 90 hari',
        route: '/temperature-trend',
      ),
      if (canReview)
        const _FormChoice(
          icon: Icons.monitor_heart_outlined,
          title: 'Pemantauan & persetujuan',
          subtitle: 'Suhu kritis, lembar yang perlu disetujui, semua regu',
          route: '/monitoring',
        ),
      if (canReview)
        const _FormChoice(
          icon: Icons.thermostat_auto_rounded,
          title: 'Laporan suhu tinggi',
          subtitle: 'Pembacaan 60 °C ke atas dari ketiga lembar',
          route: '/high-temperature',
        ),
      if (canReview)
        const _FormChoice(
          icon: Icons.assignment_turned_in_outlined,
          title: 'Tindak lanjut suhu kritis',
          subtitle: 'Tindakan, WO, dan foto sampai peringatan ditutup',
          route: '/temperature-alerts',
        ),
      if (canReview)
        const _FormChoice(
          icon: Icons.event_available_outlined,
          title: 'Kepatuhan pengisian',
          subtitle: 'Kalender lembar terisi dan tepat waktu per crew',
          route: '/compliance',
        ),
    ];
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
            for (final choice in choices) _card(context, choice),
            const SizedBox(height: 14),
            const Text('Alat bantu', style: AppTextStyles.sectionTitle),
            const SizedBox(height: 10),
            for (final choice in tools) _card(context, choice),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, _FormChoice choice) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: MenuChoiceCard(
      icon: choice.icon,
      title: choice.title,
      subtitle: choice.subtitle,
      onTap: () => context.go(choice.route),
    ),
  );
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
