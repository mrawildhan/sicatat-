import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';

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

  List<_CostCodeEntry> get _results => _costCodeEntries
      .where(
        (entry) =>
            (_segment == 'Semua' || entry.segment == _segment) &&
            entry.matches(_query),
      )
      .toList(growable: false);

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

  final _CostCodeEntry entry;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            backgroundColor: AppColors.mint,
            child: Icon(entry.icon, color: AppColors.green, size: 20),
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
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(entry.description, style: AppTextStyles.cardTitle),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _CostCodeEntry {
  const _CostCodeEntry(this.segment, this.code, this.description, this.icon);

  final String segment;
  final String code;
  final String description;
  final IconData icon;

  bool matches(String query) {
    final String value = query.trim().toLowerCase();
    return value.isEmpty ||
        '$segment $code $description'.toLowerCase().contains(value);
  }
}

const List<String> _segments = <String>[
  'Semua',
  'Site',
  'Function',
  'Pit/Plant',
  'Activity',
  'Expense',
];

const List<_CostCodeEntry> _costCodeEntries = <_CostCodeEntry>[
  _CostCodeEntry('Site', '32', 'Asam Asam', Icons.location_on_outlined),
  _CostCodeEntry('Site', '40', 'NPLCT', Icons.location_on_outlined),
  _CostCodeEntry('Function', '70', 'Mining Operation', Icons.factory_outlined),
  _CostCodeEntry(
    'Function',
    '71',
    'OLC & CPP Operation',
    Icons.factory_outlined,
  ),
  _CostCodeEntry('Function', '75', 'Port Operation', Icons.anchor_outlined),
  _CostCodeEntry(
    'Function',
    '90',
    'Repair and Maintenance',
    Icons.build_outlined,
  ),
  _CostCodeEntry('Function', '56', 'Administration', Icons.business_outlined),
  _CostCodeEntry('Function', '32', 'Engineering', Icons.engineering_outlined),
  _CostCodeEntry('Function', '58', 'Safety', Icons.health_and_safety_outlined),
  _CostCodeEntry('Function', '65', 'Environment', Icons.eco_outlined),
  _CostCodeEntry(
    'Pit/Plant',
    'A001',
    'Darma Henwa - Asam Asam',
    Icons.landscape_outlined,
  ),
  _CostCodeEntry(
    'Pit/Plant',
    'A012',
    'Pit 4-5 PPA - Asam Asam',
    Icons.landscape_outlined,
  ),
  _CostCodeEntry(
    'Pit/Plant',
    'A013',
    'Pit 9-11 PPA - Asam Asam',
    Icons.landscape_outlined,
  ),
  _CostCodeEntry(
    'Pit/Plant',
    'A020',
    'MMT - Asam Asam',
    Icons.landscape_outlined,
  ),
  _CostCodeEntry(
    'Pit/Plant',
    'A030',
    'RA - Asam Asam',
    Icons.landscape_outlined,
  ),
  _CostCodeEntry(
    'Pit/Plant',
    'A040',
    'Asam Asam East',
    Icons.landscape_outlined,
  ),
  _CostCodeEntry(
    'Pit/Plant',
    'F020',
    'Port Plant / Equipment',
    Icons.anchor_outlined,
  ),
  _CostCodeEntry(
    'Pit/Plant',
    'F030',
    'OLC & CPP Plant / Equipment',
    Icons.factory_outlined,
  ),
  _CostCodeEntry(
    'Pit/Plant',
    'E010',
    'Minor Equipment',
    Icons.handyman_outlined,
  ),
  _CostCodeEntry(
    'Activity',
    '000',
    'General Overhead',
    Icons.account_tree_outlined,
  ),
  _CostCodeEntry('Activity', '100', 'Stripping', Icons.terrain_outlined),
  _CostCodeEntry(
    'Activity',
    '110',
    'Drilling',
    Icons.precision_manufacturing_outlined,
  ),
  _CostCodeEntry('Activity', '115', 'Blasting', Icons.warning_amber_rounded),
  _CostCodeEntry(
    'Activity',
    '130',
    'Coal Getting / Mining',
    Icons.landscape_outlined,
  ),
  _CostCodeEntry(
    'Activity',
    '140',
    'Coal Hauling',
    Icons.local_shipping_outlined,
  ),
  _CostCodeEntry(
    'Activity',
    '150',
    'Crushing / Washing',
    Icons.factory_outlined,
  ),
  _CostCodeEntry('Activity', '200', 'Port Activities', Icons.anchor_outlined),
  _CostCodeEntry(
    'Activity',
    '314',
    'Asam Asam to NPLCT',
    Icons.directions_boat_outlined,
  ),
  _CostCodeEntry(
    'Activity',
    '334',
    'Asam Asam to CBU',
    Icons.directions_boat_outlined,
  ),
  _CostCodeEntry(
    'Activity',
    '354',
    'Asam Asam to Transhipment',
    Icons.directions_boat_outlined,
  ),
  _CostCodeEntry(
    'Activity',
    '374',
    'Asam Asam to Direct Customer',
    Icons.directions_boat_outlined,
  ),
  _CostCodeEntry(
    'Activity',
    '800',
    'Repair and Maintenance',
    Icons.build_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00340',
    'Batteries',
    Icons.battery_charging_full_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00341',
    'Components / Spares',
    Icons.settings_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00342',
    'Conveyors & Accessories',
    Icons.settings_outlined,
  ),
  _CostCodeEntry('Expense', '00345', 'Instrumentation', Icons.speed_outlined),
  _CostCodeEntry(
    'Expense',
    '00346',
    'Electrical Parts',
    Icons.electric_bolt_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00360',
    'Tyres and Tubes',
    Icons.tire_repair_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00370',
    'Workshop Consumables',
    Icons.construction_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00380',
    'Bearings & Accessories',
    Icons.settings_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00381',
    'Pipes & Fittings',
    Icons.plumbing_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00382',
    'PM Service Kits (Filters, O Rings Etc)',
    Icons.build_circle_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00383',
    'Engines & Associated',
    Icons.settings_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00384',
    'Transmission, Torque Converter, Gearbox',
    Icons.settings_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00386',
    'Steering, Hydraulics & Associated',
    Icons.settings_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00390',
    'Electric Motors',
    Icons.electric_bolt_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00393',
    'Workshop Materials',
    Icons.construction_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00395',
    'Welding / Heating & Accessories',
    Icons.local_fire_department_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00396',
    'Minor Equip / Tools Replacement Non Capital',
    Icons.handyman_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00397',
    'Pneumatics, Air System Components',
    Icons.air_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00398',
    'Lubrication Systems and Components',
    Icons.oil_barrel_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00399',
    'Fire Suppression Systems and Components',
    Icons.fire_extinguisher_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00400',
    'Steering Systems and Components',
    Icons.settings_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00401',
    'Cooling Systems and Components',
    Icons.ac_unit_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00402',
    'Land & Building Repairs',
    Icons.home_repair_service_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00406',
    'Sand Blasting, Paint, Consumables',
    Icons.format_paint_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00470',
    'Environmental Monitoring',
    Icons.eco_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00480',
    'Import Duty / Handling Charge Overseas',
    Icons.public_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00481',
    'Freight / Delivery Cost',
    Icons.local_shipping_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00622',
    'Office Utilities & Supplies',
    Icons.business_outlined,
  ),
  _CostCodeEntry(
    'Expense',
    '00628',
    'Software License Fee',
    Icons.computer_outlined,
  ),
];
