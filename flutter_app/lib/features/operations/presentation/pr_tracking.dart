import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/export/xlsx_export.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/purchase_requisition_models.dart';
import '../../../data/models/sicatat_types.dart';

/// PR tracking (owner request 2026-09-26): how far a PR has come, from
/// release to PO to goods received, and which open PRs are getting old.

final RegExp _poNumber = RegExp(r'^P\d+$');

/// A real Ellipse PO number, not a note such as "WAS APPROVED".
bool isPurchaseOrderNumber(String? value) =>
    value != null && _poNumber.hasMatch(value.trim());

/// Cancelled, rejected, deleted or closed PRs are not waiting any more.
bool isPurchaseRequisitionOpen(PurchaseRequisition pr) {
  if (pr.closedDate != null) return false;
  final String status = (pr.status ?? '').toLowerCase();
  final String po = (pr.noPo ?? '').toLowerCase();
  const List<String> ended = <String>['close', 'cancel', 'reject', 'delet'];
  return !ended.any(
    (String word) => status.contains(word) || po.contains(word),
  );
}

/// Age buckets of open PRs, in days since release.
const List<(String label, int from, int to)> prAgeBuckets =
    <(String, int, int)>[
      ('0–30 hari', 0, 30),
      ('31–60 hari', 31, 60),
      ('61–90 hari', 61, 90),
      ('> 90 hari', 91, 100000),
    ];

int prAgeDays(PurchaseRequisition pr, DateTime today) => pr.releaseDate == null
    ? 0
    : DateTime(
        today.year,
        today.month,
        today.day,
      ).difference(pr.releaseDate!).inDays;

String _date(DateTime? value) =>
    value == null ? '-' : DateFormat('d MMM yyyy', 'id_ID').format(value);

Future<void> exportPurchaseRequisitions(
  List<PurchaseRequisition> items, {
  required String title,
}) async {
  final DateTime today = DateTime.now();
  await saveExportFile(
    buildXlsx(
      sheetName: 'Data PR',
      title: title,
      columns: const <XlsxColumn>[
        XlsxColumn('No. PR', width: 10),
        XlsxColumn('No. PO', width: 14),
        XlsxColumn('Deskripsi', width: 60),
        XlsxColumn('Referensi alat', width: 14),
        XlsxColumn('Tanggal rilis', width: 12),
        XlsxColumn('Barang datang', width: 12),
        XlsxColumn('Status', width: 20),
        XlsxColumn('Umur (hari)', width: 10),
      ],
      rows: <List<Object?>>[
        for (final PurchaseRequisition pr in items)
          <Object?>[
            int.tryParse(pr.noPr) ?? pr.noPr,
            pr.noPo,
            pr.description,
            pr.equipmentReference,
            pr.releaseDate,
            pr.closedDate,
            pr.status,
            pr.closedDate == null && pr.releaseDate != null
                ? prAgeDays(pr, today)
                : null,
          ],
      ],
    ),
    fileName: 'Data PR ${DateFormat('dd-MM-yyyy').format(today)}.xlsx',
  );
}

/// Open PRs of the last 12 months by age, shown before a search.
class PrAgingCard extends StatefulWidget {
  const PrAgingCard({required this.onOpen, super.key});

  final ValueChanged<PurchaseRequisition> onOpen;

  @override
  State<PrAgingCard> createState() => _PrAgingCardState();
}

class _PrAgingCardState extends State<PrAgingCard> {
  List<PurchaseRequisition>? _open;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final DateTime since = DateTime.now().subtract(const Duration(days: 365));
      final Object rows = await Supabase.instance.client
          .from('purchase_requisition')
          .select(
            'id,no_pr,no_po,description,equip_ref,closed_date,release_date,status',
          )
          .isFilter('closed_date', null)
          .gte('release_date', DateFormat('yyyy-MM-dd').format(since))
          .order('release_date', ascending: true)
          .limit(2000);
      final List<PurchaseRequisition> open = <PurchaseRequisition>[
        if (rows is List)
          for (final Object? row in rows)
            PurchaseRequisition.fromJson(requireJsonMap(row)),
      ].where(isPurchaseRequisitionOpen).toList(growable: false);
      if (mounted) setState(() => _open = open);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  void _openBucket(String label, List<PurchaseRequisition> items) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .85,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'PR terbuka $label (${items.length})',
                      style: AppTextStyles.sectionTitle,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Ekspor Excel',
                    onPressed: () => exportPurchaseRequisitions(
                      items,
                      title: 'PR terbuka $label',
                    ),
                    icon: const Icon(Icons.table_view_outlined),
                  ),
                ],
              ),
              for (final PurchaseRequisition pr in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'PR ${pr.noPr} · ${pr.description ?? '-'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    'Rilis ${_date(pr.releaseDate)} · '
                    '${isPurchaseOrderNumber(pr.noPo) ? 'PO ${pr.noPo}' : 'belum ada PO'}',
                  ),
                  trailing: Text(
                    '${prAgeDays(pr, DateTime.now())} hr',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    widget.onOpen(pr);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<PurchaseRequisition>? open = _open;
    if (_error != null) return const SizedBox.shrink();
    final DateTime today = DateTime.now();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Umur PR terbuka (rilis 12 bulan terakhir)',
              style: AppTextStyles.cardTitle,
            ),
            const SizedBox(height: 2),
            const Text(
              'Belum ada tanggal barang datang. Hijau sudah ada PO, oranye '
              'belum ada PO. Ketuk baris untuk daftarnya.',
              style: AppTextStyles.supporting,
            ),
            const SizedBox(height: 10),
            if (open == null)
              const LinearProgressIndicator()
            else ...<Widget>[
              for (final (String label, int from, int to) in prAgeBuckets)
                () {
                  final List<PurchaseRequisition> items = open
                      .where((pr) {
                        final int age = prAgeDays(pr, today);
                        return age >= from && age <= to;
                      })
                      .toList(growable: false);
                  final int withPo = items
                      .where((pr) => isPurchaseOrderNumber(pr.noPo))
                      .length;
                  final int top = open.isEmpty ? 1 : open.length;
                  return InkWell(
                    onTap: items.isEmpty
                        ? null
                        : () => _openBucket(label, items),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: <Widget>[
                          SizedBox(
                            width: 84,
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (_, BoxConstraints box) {
                                final double unit = box.maxWidth / top;
                                return Row(
                                  children: <Widget>[
                                    Container(
                                      width: unit * withPo,
                                      height: 14,
                                      color: AppColors.green,
                                    ),
                                    Container(
                                      width: unit * (items.length - withPo),
                                      height: 14,
                                      color: AppColors.orange,
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          SizedBox(
                            width: 40,
                            child: Text(
                              '${items.length}',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }(),
              const SizedBox(height: 4),
              Text(
                '${open.length} PR terbuka · '
                '${open.where((pr) => !isPurchaseOrderNumber(pr.noPo)).length} belum ada PO',
                style: AppTextStyles.supporting,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// PR → PO → goods received, with the days between the steps.
class PrTimeline extends StatefulWidget {
  const PrTimeline({required this.item, super.key});

  final PurchaseRequisition item;

  @override
  State<PrTimeline> createState() => _PrTimelineState();
}

class _PrTimelineState extends State<PrTimeline> {
  List<JsonMap>? _orders;
  List<JsonMap>? _receipts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final String? po = widget.item.noPo?.trim();
    if (!isPurchaseOrderNumber(po)) {
      setState(() {
        _orders = const <JsonMap>[];
        _receipts = const <JsonMap>[];
      });
      return;
    }
    final SupabaseClient client = Supabase.instance.client;
    Future<List<JsonMap>> rows(Future<Object?> query) async {
      try {
        final Object? result = await query;
        return <JsonMap>[
          if (result is List)
            for (final Object? row in result) requireJsonMap(row),
        ];
      } on Object {
        return const <JsonMap>[];
      }
    }

    final List<List<JsonMap>> results = await Future.wait(
      <Future<List<JsonMap>>>[
        rows(
          client
              .from('warehouse_outstanding_po')
              .select(
                'po_item_no,description,qty_outstanding,order_date,due_date',
              )
              .eq('po_no', po!)
              .limit(100),
        ),
        rows(
          client
              .from('warehouse_receipt')
              .select('received_on,description,quantity,uoi')
              .eq('po_number', po)
              .order('received_on', ascending: true)
              .limit(100),
        ),
      ],
    );
    if (mounted) {
      setState(() {
        _orders = results[0];
        _receipts = results[1];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final PurchaseRequisition pr = widget.item;
    final List<JsonMap>? orders = _orders;
    final List<JsonMap>? receipts = _receipts;
    final bool hasPo = isPurchaseOrderNumber(pr.noPo);
    final DateTime? ordered = orders == null || orders.isEmpty
        ? null
        : DateTime.tryParse('${orders.first['order_date']}');
    final DateTime? due = orders == null || orders.isEmpty
        ? null
        : DateTime.tryParse('${orders.first['due_date']}');
    final DateTime? firstReceipt = receipts == null || receipts.isEmpty
        ? null
        : DateTime.tryParse('${receipts.first['received_on']}');
    final DateTime? arrived = pr.closedDate ?? firstReceipt;
    String days(DateTime? from, DateTime? to) => from == null || to == null
        ? ''
        : ' · ${to.difference(from).inDays} hari';
    final List<(bool done, String title, String detail)>
    steps = <(bool, String, String)>[
      (pr.releaseDate != null, 'PR dirilis', _date(pr.releaseDate)),
      (
        hasPo,
        hasPo ? 'PO ${pr.noPo}' : 'PO belum dibuat',
        hasPo
            ? (ordered == null
                  ? 'Tanggal PO tidak ada di laporan Outstanding PO'
                  : '${_date(ordered)}${days(pr.releaseDate, ordered)} sejak PR')
            : ((pr.noPo ?? '').trim().isEmpty
                  ? 'Menunggu proses pembelian'
                  : 'Catatan: ${pr.noPo}'),
      ),
      if (orders != null && orders.isNotEmpty)
        (
          false,
          'Menunggu barang (${orders.length} item belum datang)',
          'Jatuh tempo ${_date(due)}'
              '${due != null && due.isBefore(DateTime.now()) ? ' · sudah lewat' : ''}',
        ),
      (
        arrived != null,
        arrived != null ? 'Barang datang' : 'Barang belum datang',
        arrived == null
            ? (receipts == null ? 'Memeriksa penerimaan…' : '-')
            : '${_date(arrived)}${days(pr.releaseDate, arrived)} sejak PR'
                  '${receipts != null && receipts.isNotEmpty ? ' · ${receipts.length} penerimaan di gudang' : ''}',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < steps.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Column(
                children: <Widget>[
                  Icon(
                    steps[i].$1
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 20,
                    color: steps[i].$1 ? AppColors.green : AppColors.orange,
                  ),
                  if (i < steps.length - 1)
                    Container(width: 2, height: 26, color: AppColors.line),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        steps[i].$2,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(steps[i].$3, style: AppTextStyles.supporting),
                    ],
                  ),
                ),
              ),
            ],
          ),
        if ((pr.equipmentReference ?? '').trim().isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                context.go(
                  '/asset-history/${Uri.encodeComponent(pr.equipmentReference!.trim())}',
                );
              },
              icon: const Icon(Icons.history_rounded),
              label: Text('Riwayat aset ${pr.equipmentReference!.trim()}'),
            ),
          ),
      ],
    );
  }
}
