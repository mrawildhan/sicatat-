import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';

class EquipmentReferenceScreen extends StatefulWidget {
  const EquipmentReferenceScreen({super.key});

  @override
  State<EquipmentReferenceScreen> createState() =>
      _EquipmentReferenceScreenState();
}

class _EquipmentReferenceScreenState extends State<EquipmentReferenceScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _site = 'Semua';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_EquipmentEntry> get _results => _equipmentEntries
      .where(
        (entry) =>
            (_site == 'Semua' || entry.siteLabel == _site) &&
            entry.matches(_query),
      )
      .toList(growable: false);

  Future<void> _openSourceFolder() async {
    final Uri uri = Uri.parse(
      'https://drive.google.com/drive/folders/1k_Eq2HkmZWnWG5dqq0pY0tMstUoeC-1D',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Folder Equipment belum dapat dibuka.')),
      );
    }
  }

  void _showDetail(_EquipmentEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(entry.reference, style: AppTextStyles.pageTitle),
              const SizedBox(height: 6),
              Text(entry.description, style: AppTextStyles.cardTitle),
              const SizedBox(height: 18),
              _DetailRow(label: 'Lokasi', value: entry.siteLabel),
              _DetailRow(label: 'Status', value: entry.statusLabel),
              _DetailRow(label: 'Tipe', value: entry.typeLabel),
              _DetailRow(
                label: 'Account code',
                value: entry.accountCode.isEmpty ? '—' : entry.accountCode,
              ),
            ],
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
                title: const Text('Equipment Reference'),
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
                  'Equipment Reference',
                  style: AppTextStyles.pageTitle,
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText:
                      'Cari referensi, nama unit, tipe, atau account code',
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
                onPressed: _openSourceFolder,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Buka sumber Equipment di Drive'),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _sites
                      .map(
                        (site) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(site),
                            selected: _site == site,
                            onSelected: (_) => setState(() => _site = site),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
              const SizedBox(height: 12),
              if (_query.trim().isEmpty)
                const _EquipmentSearchPrompt()
              else if (_results.isEmpty)
                const _EquipmentEmptyResult()
              else ...<Widget>[
                Text(
                  '${_results.length} equipment ditemukan',
                  style: AppTextStyles.supporting,
                ),
                const SizedBox(height: 8),
                ..._results.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _EquipmentCard(
                      entry: entry,
                      onTap: () => _showDetail(entry),
                    ),
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

class _EquipmentSearchPrompt extends StatelessWidget {
  const _EquipmentSearchPrompt();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(18),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            backgroundColor: AppColors.mint,
            child: Icon(
              Icons.precision_manufacturing_outlined,
              color: AppColors.green,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Cari equipment', style: AppTextStyles.cardTitle),
                SizedBox(height: 3),
                Text(
                  'Masukkan kode seperti ADS01, nama unit, tipe, atau account code.',
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

class _EquipmentEmptyResult extends StatelessWidget {
  const _EquipmentEmptyResult();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: Text(
        'Tidak ada equipment yang cocok. Coba kata atau kode lain.',
        textAlign: TextAlign.center,
        style: AppTextStyles.supporting,
      ),
    ),
  );
}

class _EquipmentCard extends StatelessWidget {
  const _EquipmentCard({required this.entry, required this.onTap});

  final _EquipmentEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const CircleAvatar(
              backgroundColor: AppColors.mint,
              child: Icon(
                Icons.precision_manufacturing_outlined,
                color: AppColors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(entry.reference, style: AppTextStyles.cardTitle),
                  const SizedBox(height: 3),
                  Text(entry.description, style: AppTextStyles.supporting),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: <Widget>[
                      _EquipmentTag(label: entry.siteLabel),
                      _EquipmentTag(label: entry.status),
                      if (entry.typeCode.isNotEmpty)
                        _EquipmentTag(label: entry.typeCode),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    ),
  );
}

class _EquipmentTag extends StatelessWidget {
  const _EquipmentTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.mint,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: AppTextStyles.supporting.copyWith(
        color: AppColors.green,
        fontSize: 11,
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 116,
          child: Text(label, style: AppTextStyles.supporting),
        ),
        Expanded(child: SelectableText(value, style: AppTextStyles.cardTitle)),
      ],
    ),
  );
}

class _EquipmentEntry {
  const _EquipmentEntry({
    required this.site,
    required this.reference,
    required this.description,
    required this.status,
    required this.statusLabel,
    required this.typeCode,
    required this.typeLabel,
    required this.accountCode,
  });

  factory _EquipmentEntry.fromRecord(String record) {
    final List<String> fields = record.split('|');
    return _EquipmentEntry(
      site: fields[0],
      reference: fields[1],
      description: fields[2],
      status: fields[3],
      statusLabel: fields[4],
      typeCode: fields[5],
      typeLabel: fields[6],
      accountCode: fields[7],
    );
  }

  final String site;
  final String reference;
  final String description;
  final String status;
  final String statusLabel;
  final String typeCode;
  final String typeLabel;
  final String accountCode;

  String get siteLabel => site == 'ASAM' ? 'Asamasam' : 'Kintap';

  bool matches(String query) {
    final String value = query.trim().toLowerCase();
    return value.isEmpty ||
        '$reference $description $status $statusLabel $typeCode $typeLabel $accountCode'
            .toLowerCase()
            .contains(value);
  }
}

final List<_EquipmentEntry> _equipmentEntries = utf8
    .decode(
      const GZipDecoder().decodeBytes(base64Decode(_compressedEquipmentData)),
    )
    .split(r'\n')
    .where((record) => record.isNotEmpty)
    .map(_EquipmentEntry.fromRecord)
    .toList(growable: false);

const List<String> _sites = <String>['Semua', 'Asamasam', 'Kintap'];

const String _compressedEquipmentData =
    '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'
    'AAA=';
