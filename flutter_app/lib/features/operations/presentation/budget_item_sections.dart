import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/operational_budget_models.dart';

const TextStyle _budgetSheetLabelStyle = AppTextStyles.supporting;

const TextStyle _budgetSheetAmountStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w900,
);

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

Future<void> showBudgetMonthlyDetail(
  BuildContext context,
  OperationalBudgetSummary summary,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _BudgetMonthlyDetailSheet(summary: summary),
);

class _BudgetMonthlyDetailSheet extends StatelessWidget {
  const _BudgetMonthlyDetailSheet({required this.summary});

  final OperationalBudgetSummary summary;

  @override
  Widget build(BuildContext context) {
    final Map<DateTime, List<OperationalBudgetMonth>> grouped =
        <DateTime, List<OperationalBudgetMonth>>{};
    for (final OperationalBudgetMonth item in summary.months) {
      grouped
          .putIfAbsent(item.period, () => <OperationalBudgetMonth>[])
          .add(item);
    }
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .9,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
          children: <Widget>[
            const Text(
              'Realisasi per bulan',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            const Text(
              'Realisasi adalah total biaya yang sudah dipakai pada bulan tersebut.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            ...grouped.entries.map((entry) {
              final List<OperationalBudgetMonth> values = entry.value;
              final double budget = values.fold(
                0,
                (sum, row) => sum + row.budgetUsd,
              );
              final double actual = values.fold(
                0,
                (sum, row) => sum + row.actualUsd,
              );
              final double remaining = budget - actual;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _monthAndYear(entry.key),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: _MonthlyAmount(
                                label: 'Anggaran',
                                value: _usd(budget),
                              ),
                            ),
                            Expanded(
                              child: _MonthlyAmount(
                                label: 'Aktual',
                                value: _usd(actual),
                              ),
                            ),
                            Expanded(
                              child: _MonthlyAmount(
                                label: remaining < 0 ? 'Melebihi' : 'Sisa',
                                value: _usd(remaining.abs()),
                                color: remaining < 0
                                    ? AppColors.danger
                                    : AppColors.green,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _MonthlyAmount extends StatelessWidget {
  const _MonthlyAmount({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(label, style: _budgetSheetLabelStyle),
      const SizedBox(height: 3),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );
}

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
                  '${item.largestTransactionDate == null ? 'Tanggal tidak tersedia' : _fullDate(item.largestTransactionDate!)}'
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
          Text(label, style: _budgetSheetLabelStyle),
          const SizedBox(height: 5),
          Text(
            _usd(value),
            style: _budgetSheetAmountStyle.copyWith(color: color),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  backgroundColor: AppColors.mint,
                  child: Text(
                    item.site == 'CPP' ? 'C' : 'P',
                    style: const TextStyle(
                      color: AppColors.green,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${item.accountCode} · ${item.description}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: _ItemAmount(
                    label: 'Budget',
                    value: _usd(item.budgetUsd),
                  ),
                ),
                Expanded(
                  child: _ItemAmount(
                    label: 'Aktual',
                    value: _usd(item.actualUsd),
                  ),
                ),
                Expanded(
                  child: _ItemAmount(
                    label: item.overBudget ? 'Melebihi' : 'Sisa',
                    value: _usd(item.remainingUsd.abs()),
                    color: item.overBudget
                        ? AppColors.danger
                        : emphasis ?? AppColors.green,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _ItemAmount extends StatelessWidget {
  const _ItemAmount({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(label, style: _budgetSheetLabelStyle),
      const SizedBox(height: 3),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          value,
          style: _budgetSheetAmountStyle.copyWith(color: color),
        ),
      ),
    ],
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

const List<String> _monthNames = <String>[
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];

String _monthAndYear(DateTime value) =>
    '${_monthNames[value.month - 1]} ${value.year}';

String _fullDate(DateTime value) => '${value.day} ${_monthAndYear(value)}';

String _period(String value) => _monthAndYear(
  DateTime.parse('${value.substring(0, 4)}-${value.substring(4)}-01'),
);

String _usd(double value) =>
    'US\$${NumberFormat.decimalPattern('id_ID').format(value.round())}';
