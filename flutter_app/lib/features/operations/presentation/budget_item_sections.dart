import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/operational_budget_models.dart';

class BudgetItemInsights extends StatelessWidget {
  const BudgetItemInsights({
    required this.items,
    required this.onBrowse,
    required this.onSelect,
    super.key,
  });

  final List<OperationalBudgetItem> items;
  final VoidCallback onBrowse;
  final ValueChanged<OperationalBudgetItem> onSelect;

  @override
  Widget build(BuildContext context) {
    final List<OperationalBudgetItem> spending = items
        .where((item) => item.actualUsd > 0)
        .take(3)
        .toList(growable: false);
    final List<OperationalBudgetItem> overBudget =
        items.where((item) => item.overBudget).toList(growable: false)..sort(
          (left, right) => left.remainingUsd.compareTo(right.remainingUsd),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        FilledButton.icon(
          onPressed: onBrowse,
          icon: const Icon(Icons.search_rounded),
          label: const Text('Cari kode atau nama item'),
        ),
        const SizedBox(height: 18),
        const Text(
          'Pemakaian terbesar',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        ...spending.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _BudgetItemCard(item: item, onTap: () => onSelect(item)),
          ),
        ),
        if (overBudget.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          const Text(
            'Perlu perhatian: overbudget',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          ...overBudget
              .take(3)
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _BudgetItemCard(
                    item: item,
                    onTap: () => onSelect(item),
                    emphasis: AppColors.danger,
                  ),
                ),
              ),
        ],
      ],
    );
  }
}

Future<OperationalBudgetItem?> showBudgetItemBrowser(
  BuildContext context,
  List<OperationalBudgetItem> items,
) => showModalBottomSheet<OperationalBudgetItem>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _BudgetItemBrowserSheet(items: items),
);

Future<void> showBudgetItemDetail(
  BuildContext context,
  OperationalBudgetItem item,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _BudgetItemDetailSheet(item: item),
);

class _BudgetItemBrowserSheet extends StatefulWidget {
  const _BudgetItemBrowserSheet({required this.items});

  final List<OperationalBudgetItem> items;

  @override
  State<_BudgetItemBrowserSheet> createState() =>
      _BudgetItemBrowserSheetState();
}

class _BudgetItemBrowserSheetState extends State<_BudgetItemBrowserSheet> {
  String _query = '';
  String _site = 'Semua';

  @override
  Widget build(BuildContext context) {
    final List<OperationalBudgetItem> items = widget.items
        .where(
          (item) =>
              (_site == 'Semua' || item.site == _site) && item.matches(_query),
        )
        .toList(growable: false);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .9,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                'Rincian anggaran',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Cari kode atau nama item',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 8,
                children: <String>['Semua', 'CPP', 'PORT']
                    .map(
                      (site) => ChoiceChip(
                        label: Text(site),
                        selected: _site == site,
                        onSelected: (_) => setState(() => _site = site),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Text(
                        'Tidak ada item yang sesuai pencarian.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, index) => _BudgetItemCard(
                        item: items[index],
                        onTap: () => Navigator.of(context).pop(items[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetItemDetailSheet extends StatelessWidget {
  const _BudgetItemDetailSheet({required this.item});

  final OperationalBudgetItem item;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .9,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
        children: <Widget>[
          _DetailHeader(item: item),
          const SizedBox(height: 16),
          _DetailNumbers(item: item),
          const SizedBox(height: 18),
          const Text(
            'Realisasi per bulan',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: _periods
                  .map((period) {
                    final double budget = item.budgetMonths[period] ?? 0;
                    final double actual = item.actualMonths[period] ?? 0;
                    return ListTile(
                      title: Text(_period(period)),
                      subtitle: Text('Budget ${_usd(budget)}'),
                      trailing: Text(
                        _usd(actual),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
          ),
          if (item.largestTransactionUsd > 0) ...<Widget>[
            const SizedBox(height: 16),
            const Text(
              'Transaksi terbesar',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.mint,
                  child: Icon(
                    Icons.receipt_long_rounded,
                    color: AppColors.green,
                  ),
                ),
                title: Text(_usd(item.largestTransactionUsd)),
                subtitle: Text(
                  '${item.largestTransactionDate == null ? 'Tanggal tidak tersedia' : DateFormat('dd MMMM yyyy', 'id_ID').format(item.largestTransactionDate!)}'
                  '${item.largestTransactionNo == null ? '' : '\nNo. ${item.largestTransactionNo}'}',
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.item});

  final OperationalBudgetItem item;

  @override
  Widget build(BuildContext context) => Card(
    color: AppColors.green,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            backgroundColor: Colors.white.withValues(alpha: .2),
            child: Text(
              item.site,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.accountCode,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.description,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _DetailNumbers extends StatelessWidget {
  const _DetailNumbers({required this.item});

  final OperationalBudgetItem item;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(child: _number('Budget', item.budgetUsd, AppColors.green)),
      const SizedBox(width: 8),
      Expanded(child: _number('Aktual', item.actualUsd, AppColors.orange)),
      const SizedBox(width: 8),
      Expanded(
        child: _number(
          item.overBudget ? 'Melebihi' : 'Sisa',
          item.overBudget ? -item.remainingUsd : item.remainingUsd,
          item.overBudget ? AppColors.danger : AppColors.green,
        ),
      ),
    ],
  );

  Widget _number(String label, double value, Color color) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
          const SizedBox(height: 5),
          Text(
            _usd(value),
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    ),
  );
}

class _BudgetItemCard extends StatelessWidget {
  const _BudgetItemCard({
    required this.item,
    required this.onTap,
    this.emphasis,
  });

  final OperationalBudgetItem item;
  final VoidCallback onTap;
  final Color? emphasis;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              backgroundColor: AppColors.mint,
              child: Text(
                item.site,
                style: const TextStyle(
                  color: AppColors.green,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${item.accountCode} · ${item.description}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Aktual ${_usd(item.actualUsd)} · ${item.overBudget ? 'Melebihi' : 'Sisa'} ${_usd(item.remainingUsd.abs())}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: emphasis ?? AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    ),
  );
}

const List<String> _periods = <String>[
  '202601',
  '202602',
  '202603',
  '202604',
  '202605',
  '202606',
];

String _period(String value) => DateFormat(
  'MMMM yyyy',
  'id_ID',
).format(DateTime.parse('${value.substring(0, 4)}-${value.substring(4)}-01'));

String _usd(double value) => NumberFormat.currency(
  locale: 'en_US',
  symbol: 'US\$',
  decimalDigits: 0,
).format(value);
