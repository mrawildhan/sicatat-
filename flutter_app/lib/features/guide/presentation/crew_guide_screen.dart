import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';

class CrewGuideScreen extends StatelessWidget {
  const CrewGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBackScope(
      fallbackRoute: '/dashboard',
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallbackRoute: '/dashboard'),
          title: const Text(
            'Crew guide',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: const <Widget>[
            _GuideSection(
              '1. Create a sheet',
              'Select the correct date and shift. One team uses one sheet for each date and shift combination.',
            ),
            _GuideSection(
              '2. Enter each round',
              'Complete Breaker Round 1, Sizer Round 1, Breaker Round 2, then Sizer Round 2. Complete West and East for every round.',
            ),
            _GuideSection(
              '3. Select a status',
              'Operating: enter all four gearbox temperatures. Not operating or not accessible: enter a reason without temperature values.',
            ),
            _GuideSection(
              '4. Review temperature',
              'Green is below 60°C, amber is 60-69.9°C, and red is 70°C or higher. Report red conditions under the operating procedure.',
            ),
            _GuideSection(
              '5. Save and submit',
              'Tap Save for each side. When internet is available, the app immediately tries to send drafts and progress so foremen and admins can see it. Data remains safe offline.',
            ),
            _GuideSection(
              'If data is not synced',
              'Do not delete the application. When internet returns, tap Sync data. Report Conflict status to a foreman or admin.',
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideSection extends StatelessWidget {
  const _GuideSection(this.title, this.description);

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: AppColors.greenDark,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(color: AppColors.muted, height: 1.45),
          ),
        ],
      ),
    ),
  );
}
