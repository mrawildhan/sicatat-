import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../data/cost_code_catalog.dart';

class CostCodeReferenceScreen extends StatefulWidget {
  const CostCodeReferenceScreen({super.key});

  @override
  State<CostCodeReferenceScreen> createState() =>
      _CostCodeReferenceScreenState();
}

class _CostCodeReferenceScreenState extends State<CostCodeReferenceScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _segment = 'Semua';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CostCodeEntry> get _results => <CostCodeEntry>[
    for (final _CostCodeSegment segment in _costCodeStructure)
      if (_segment == 'Semua' || _segment == segment.filter)
        ..._entriesOf(segment.filter)
            .where((CostCodeEntry entry) => entry.matches(_query)),
  ];

  Future<void> _openGuide() async {
    final Uri uri = Uri.base.resolve(
      'assets/assets/documents/cost_code_user_guide_2014_r01.pdf',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Panduan PDF belum dapat dibuka.')),
      );
    }
  }

  void _showSegmentCodes(_CostCodeSegment segment) {
    final List<CostCodeEntry> entries = _entriesOf(segment.filter);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.muted,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    CircleAvatar(
                      backgroundColor: AppColors.mint,
                      child: Text(
                        segment.order.toString(),
                        style: const TextStyle(
                          color: AppColors.green,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(segment.label, style: AppTextStyles.cardTitle),
                          Text(
                            '${segment.digits} digit · ${entries.length} kode tersedia',
                            style: AppTextStyles.supporting,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int index) {
                      final CostCodeEntry entry = entries[index];
                      final String? detail = _detail(entry);
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.mint,
                            child: Icon(
                              _iconFor(entry),
                              color: AppColors.green,
                              size: 19,
                            ),
                          ),
                          title: SelectableText(
                            entry.code,
                            style: const TextStyle(
                              color: AppColors.green,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          subtitle: Text(
                            detail == null || detail.isEmpty
                                ? entry.description
                                : '${entry.description}\n$detail',
                            style: AppTextStyles.supporting,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool desktop = kIsWeb && MediaQuery.sizeOf(context).width >= 920;
    return AppBackScope(
      fallbackRoute: '/dashboard',
      child: Scaffold(
        appBar: desktop
            ? null
            : AppBar(
                leading: const AppBackButton(fallbackRoute: '/dashboard'),
                title: const Text('Referensi Cost Code'),
              ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              desktop ? 18 : 20,
              20,
              120 + MediaQuery.paddingOf(context).bottom,
            ),
            children: <Widget>[
              if (desktop) ...<Widget>[
                const Text(
                  'Referensi Cost Code',
                  style: AppTextStyles.pageTitle,
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Cari 00396, maintenance, A001, atau aktivitas',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Hapus pencarian',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _openGuide,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Unduh manual Cost Code (PDF)'),
              ),
              const SizedBox(height: 22),
              const Text(
                'Struktur kode biaya',
                style: AppTextStyles.sectionTitle,
              ),
              const SizedBox(height: 3),
              const Text(
                'Tekan segmen untuk melihat angka yang sesuai.',
                style: AppTextStyles.supporting,
              ),
              const SizedBox(height: 10),
              _CostCodeStructure(onTap: _showSegmentCodes),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _segments
                      .map(
                        (segment) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(segment),
                            selected: _segment == segment,
                            onSelected: (_) =>
                                setState(() => _segment = segment),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
              const SizedBox(height: 12),
              if (_query.trim().isEmpty)
                const _SearchPrompt()
              else if (_results.isEmpty)
                const _EmptySearchResult()
              else ...<Widget>[
                Text(
                  '${_results.length} referensi ditemukan',
                  style: AppTextStyles.supporting,
                ),
                const SizedBox(height: 8),
                ..._results.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _CostCodeCard(entry: entry),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CostCodeStructure extends StatelessWidget {
  const _CostCodeStructure({required this.onTap});

  final ValueChanged<_CostCodeSegment> onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: _costCodeStructure
            .map(
              (segment) => InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onTap(segment),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  child: Row(
                    children: <Widget>[
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: AppColors.mint,
                        child: Text(
                          segment.order.toString(),
                          style: const TextStyle(
                            color: AppColors.green,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          segment.label,
                          style: AppTextStyles.cardTitle,
                        ),
                      ),
                      Text(
                        '${segment.digits} digit',
                        style: AppTextStyles.supporting,
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.muted,
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    ),
  );
}

class _SearchPrompt extends StatelessWidget {
  const _SearchPrompt();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(18),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            backgroundColor: AppColors.mint,
            child: Icon(
              Icons.lightbulb_outline_rounded,
              color: AppColors.green,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Pencarian cepat', style: AppTextStyles.cardTitle),
                SizedBox(height: 3),
                Text(
                  'Ketik kode atau kata kunci untuk melihat referensi segment yang tersedia.',
                  style: AppTextStyles.supporting,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _EmptySearchResult extends StatelessWidget {
  const _EmptySearchResult();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: Text(
        'Tidak ada referensi yang cocok. Coba kode atau kata lain.',
        textAlign: TextAlign.center,
        style: AppTextStyles.supporting,
      ),
    ),
  );
}

class _CostCodeCard extends StatelessWidget {
  const _CostCodeCard({required this.entry});

  final CostCodeEntry entry;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            backgroundColor: AppColors.mint,
            child: Icon(_iconFor(entry), color: AppColors.green, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(entry.segment, style: AppTextStyles.supporting),
                const SizedBox(height: 2),
                SelectableText(
                  entry.code,
                  style: const TextStyle(
                    color: AppColors.green,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(entry.description, style: AppTextStyles.cardTitle),
                if (_detail(entry) case final String detail
                    when detail.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(detail, style: AppTextStyles.supporting),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _CostCodeSegment {
  const _CostCodeSegment(this.order, this.label, this.filter, this.digits);

  final int order;
  final String label;
  final String filter;
  final String digits;
}

const List<_CostCodeSegment> _costCodeStructure = <_CostCodeSegment>[
  _CostCodeSegment(1, 'Site', 'Site', '2'),
  _CostCodeSegment(2, 'Function', 'Function', '2'),
  _CostCodeSegment(3, 'Pit / Plant', 'Pit/Plant', '4'),
  _CostCodeSegment(4, 'Activity', 'Activity', '3'),
  _CostCodeSegment(5, 'Expense element', 'Expense', '5'),
];

const List<String> _segments = <String>[
  'Semua',
  'Site',
  'Function',
  'Pit/Plant',
  'Activity',
  'Expense',
];

/// Every code of one segment, smallest code first.
List<CostCodeEntry> _entriesOf(String segment) =>
    costCodeCatalog
        .where((CostCodeEntry entry) => entry.segment == segment)
        .toList(growable: false)
      ..sort((CostCodeEntry a, CostCodeEntry b) => a.code.compareTo(b.code));

/// Site or heading from the manual, shown under the description.
String? _detail(CostCodeEntry entry) => switch (entry.segment) {
  'Pit/Plant' => entry.site,
  'Activity' => <String?>[
    entry.group,
    entry.site,
  ].whereType<String>().join(' · '),
  'Expense' => entry.group,
  _ => null,
};

IconData _iconFor(CostCodeEntry entry) {
  final String code = entry.code;
  final String text = entry.description.toLowerCase();
  switch (entry.segment) {
    case 'Site':
      return Icons.location_on_outlined;
    case 'Function':
      return switch (code) {
        '70' || '71' => Icons.factory_outlined,
        '75' || '80' => Icons.anchor_outlined,
        '90' => Icons.build_outlined,
        '32' || '30' => Icons.engineering_outlined,
        '57' || '58' || '59' => Icons.health_and_safety_outlined,
        '65' || '67' => Icons.eco_outlined,
        '27' || '28' || '45' => Icons.inventory_2_outlined,
        '48' => Icons.computer_outlined,
        '20' ||
        '21' ||
        '22' ||
        '24' ||
        '25' ||
        '26' ||
        '49' => Icons.account_balance_outlined,
        _ => Icons.business_outlined,
      };
    case 'Pit/Plant':
      if (code.startsWith('W') || code == 'F020') return Icons.anchor_outlined;
      if (code.startsWith('V')) return Icons.directions_car_outlined;
      if (code.startsWith('E') || code.startsWith('D')) {
        return Icons.handyman_outlined;
      }
      if (code.startsWith('F')) return Icons.factory_outlined;
      return Icons.landscape_outlined;
    case 'Activity':
      if (code.startsWith('3')) return Icons.directions_boat_outlined;
      if (code.startsWith('5')) return Icons.eco_outlined;
      if (code.startsWith('9')) return Icons.account_balance_outlined;
      if (code == '800') return Icons.build_outlined;
      if (code == '200') return Icons.anchor_outlined;
      if (code == '000') return Icons.account_tree_outlined;
      return Icons.terrain_outlined;
  }
  final String group = (entry.group ?? '').toLowerCase();
  if (group.contains('maintenance')) {
    if (text.contains('electric')) return Icons.electric_bolt_outlined;
    if (text.contains('tyre')) return Icons.tire_repair_outlined;
    if (text.contains('weld') || text.contains('gases')) {
      return Icons.local_fire_department_outlined;
    }
    return Icons.settings_outlined;
  }
  if (group.contains('fuel')) return Icons.local_gas_station_outlined;
  if (group.contains('contractor')) return Icons.engineering_outlined;
  if (group.contains('explosive') || group.contains('drilling')) {
    return Icons.precision_manufacturing_outlined;
  }
  if (group.contains('environment')) return Icons.eco_outlined;
  if (group.contains('freight') || group.contains('port')) {
    return Icons.local_shipping_outlined;
  }
  if (group.contains('office') || group.contains('communication')) {
    return Icons.business_outlined;
  }
  if (group.contains('allocation')) return Icons.call_split_rounded;
  if (group.contains('staff') ||
      group.contains('employee') ||
      group.contains('recruitment') ||
      group.contains('living') ||
      group.contains('education')) {
    return Icons.badge_outlined;
  }
  return Icons.receipt_long_outlined;
}
