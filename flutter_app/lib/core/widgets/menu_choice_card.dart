import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The row card used by menus (Suhu, activity lists): icon on the left, title
/// and one supporting line, chevron on the right.  Menus share it so their
/// cards look identical.
class MenuChoiceCard extends StatelessWidget {
  const MenuChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.sortTitle,
    super.key,
  });

  /// Title used for the A–Z order when [title] changes with state (for
  /// example "Memeriksa…" while Sinkronisasi runs).
  final String? sortTitle;

  String get orderKey => (sortTitle ?? title).toLowerCase();

  final IconData icon;
  final String title;
  final String subtitle;

  /// Null shows the card disabled (for example while a sync is running).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.mint,
              child: Icon(icon, color: AppColors.green),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: AppTextStyles.cardTitle.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(subtitle, style: AppTextStyles.supporting),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    ),
  );
}

/// Sorts menu entries A–Z; every menu in SICATAT is alphabetical (owner
/// request 2026-09-26).
List<T> alphabetical<T>(Iterable<T> items, String Function(T item) title) =>
    items.toList()..sort(
      (T a, T b) => title(a).toLowerCase().compareTo(title(b).toLowerCase()),
    );

/// A list of [MenuChoiceCard]s, A–Z: one column on phones, two on wide
/// screens.
class MenuChoiceList extends StatelessWidget {
  const MenuChoiceList({required this.cards, super.key});

  final List<MenuChoiceCard> cards;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      const double gap = 10;
      final bool twoColumns = constraints.maxWidth >= 700;
      final double width = twoColumns
          ? (constraints.maxWidth - gap) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: <Widget>[
          for (final MenuChoiceCard card in alphabetical(
            cards,
            (MenuChoiceCard c) => c.orderKey,
          ))
            SizedBox(width: width, child: card),
        ],
      );
    },
  );
}
