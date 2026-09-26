import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/pdf/pdf_fonts.dart';
import '../../../core/pdf/report_pdf.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../core/widgets/info_tag.dart';
import '../../../data/models/preventive_maintenance_models.dart';
import '../../../data/models/purchase_requisition_models.dart';
import '../../../data/models/sicatat_types.dart';
import '../../../data/services/preventive_maintenance_service.dart';
import '../../daily_checks/alert_follow_up.dart';
import 'equipment_reference_screen.dart';

/// Which critical temperatures belong to an Ellipse unit. Only the CPP
/// Asam-Asam units that SICATAT measures: the feeder breaker (Feeder Sizer
/// breaker gearbox and the hydraulic feeder sheet), the sizer, and the four
/// coal gate valves (RV01–RV04 on the Coal Valve sheet).
bool alertBelongsToAsset(String reference, TemperatureAlertRecord alert) {
  final String ref = reference.toUpperCase();
  final String form = alert.formLabel;
  final String point = alert.pointLabel;
  return switch (ref) {
    'AFB01' =>
      (form == 'Daily Temperature Feeder Sizer' &&
              point.startsWith('Gearbox Breaker')) ||
          form == 'Daily Check Sheet Hydraulic Feeder',
    'ACR01' =>
      form == 'Daily Temperature Feeder Sizer' &&
          point.startsWith('Gearbox Sizer'),
    'AGV1' || 'AGV2' || 'AGV3' || 'AGV4' =>
      form == 'Temperature Coal Valve' &&
          point.contains('RV0${ref.substring(3)}'),
    _ => false,
  };
}

bool assetHasTemperature(String reference) => const <String>{
  'AFB01',
  'ACR01',
  'AGV1',
  'AGV2',
  'AGV3',
  'AGV4',
}.contains(reference.toUpperCase());

final RegExp _poNumber = RegExp(r'^P\d+$');

/// Everything SICATAT knows about one unit.
class AssetHistory {
  const AssetHistory({
    required this.reference,
    required this.entry,
    required this.pm,
    required this.cm,
    required this.prs,
    required this.orders,
    required this.receipts,
    required this.pickups,
    required this.alerts,
    required this.unavailable,
  });

  final String reference;
  final EquipmentEntry? entry;
  final List<PreventiveMaintenanceWorkOrder> pm;
  final List<CorrectiveMaintenanceWorkOrder> cm;
  final List<PurchaseRequisition> prs;

  /// Outstanding PO lines of this unit's PRs: (PO, item, qty, due date).
  final List<JsonMap> orders;

  /// Goods received for this unit's PR purchase orders.
  final List<JsonMap> receipts;

  /// Pickups recorded in SICATAT against this unit's work orders.
  final List<JsonMap> pickups;
  final List<TemperatureAlertRecord> alerts;

  /// Sections the user may not read (row-level security).
  final List<String> unavailable;
}

Future<AssetHistory> loadAssetHistory(
  SupabaseClient client,
  String reference,
) async {
  final String ref = reference.trim().toUpperCase();
  final PreventiveMaintenanceService maintenance = PreventiveMaintenanceService(
    client,
  );
  final List<Object?> base = await Future.wait<Object?>(<Future<Object?>>[
    maintenance.loadOutstanding(),
    maintenance.loadCorrectiveOutstanding(),
    client
        .from('purchase_requisition')
        .select(
          'id,no_pr,no_po,description,equip_ref,closed_date,release_date,status',
        )
        .ilike('equip_ref', ref)
        .order('release_date', ascending: false, nullsFirst: false)
        .limit(300),
  ]);
  final List<PreventiveMaintenanceWorkOrder> pm =
      (base[0]! as List<PreventiveMaintenanceWorkOrder>)
          .where((w) => w.equipmentReference.toUpperCase() == ref)
          .toList(growable: false);
  final List<CorrectiveMaintenanceWorkOrder> cm =
      (base[1]! as List<CorrectiveMaintenanceWorkOrder>)
          .where((w) => w.equipmentReference.toUpperCase() == ref)
          .toList(growable: false);
  final List<PurchaseRequisition> prs = <PurchaseRequisition>[
    for (final Object? row in base[2]! as List<Object?>)
      PurchaseRequisition.fromJson(requireJsonMap(row)),
  ];
  final List<String> pos = prs
      .map((PurchaseRequisition p) => p.noPo?.trim() ?? '')
      .where(_poNumber.hasMatch)
      .toSet()
      .take(200)
      .toList(growable: false);
  final List<String> workOrders = <String>{
    for (final PreventiveMaintenanceWorkOrder w in pm) w.workOrder,
    for (final CorrectiveMaintenanceWorkOrder w in cm) w.workOrder,
  }.toList(growable: false);
  final List<String> unavailable = <String>[];

  Future<List<JsonMap>> optional(
    String label,
    Future<Object?> Function() query,
  ) async {
    try {
      final Object? rows = await query();
      return <JsonMap>[
        if (rows is List)
          for (final Object? row in rows) requireJsonMap(row),
      ];
    } on Object {
      unavailable.add(label);
      return const <JsonMap>[];
    }
  }

  final List<List<JsonMap>> extra = await Future.wait(<Future<List<JsonMap>>>[
    pos.isEmpty
        ? Future<List<JsonMap>>.value(const <JsonMap>[])
        : optional(
            'barang dipesan',
            () => client
                .from('warehouse_outstanding_po')
                .select(
                  'po_no,po_item_no,description,qty_order,qty_outstanding,'
                  'order_date,due_date,supplier_name',
                )
                .inFilter('po_no', pos)
                .limit(300),
          ),
    pos.isEmpty
        ? Future<List<JsonMap>>.value(const <JsonMap>[])
        : optional(
            'penerimaan barang',
            () => client
                .from('warehouse_receipt')
                .select(
                  'received_on,po_number,description,quantity,uoi,supplier',
                )
                .inFilter('po_number', pos)
                .order('received_on', ascending: false)
                .limit(300),
          ),
    workOrders.isEmpty
        ? Future<List<JsonMap>>.value(const <JsonMap>[])
        : optional(
            'pengambilan barang',
            () => client
                .from('warehouse_issue')
                .select(
                  'issued_on,taken_by,job_number,'
                  'warehouse_issue_item(item_code,description,quantity,uoi)',
                )
                .inFilter('job_number', workOrders)
                .order('issued_on', ascending: false)
                .limit(100),
          ),
  ]);

  List<TemperatureAlertRecord> alerts = const <TemperatureAlertRecord>[];
  if (assetHasTemperature(ref)) {
    try {
      final DateTime now = DateTime.now();
      alerts = (await AlertFollowUpService(client).load(
        from: now.subtract(const Duration(days: 365)),
        to: now.add(const Duration(days: 1)),
      )).where((a) => alertBelongsToAsset(ref, a)).toList(growable: false);
    } on Object {
      unavailable.add('suhu kritis');
    }
  }

  return AssetHistory(
    reference: ref,
    entry: equipmentEntryOf(ref),
    pm: pm,
    cm: cm,
    prs: prs,
    orders: extra[0],
    receipts: extra[1],
    pickups: extra[2],
    alerts: alerts,
    unavailable: unavailable,
  );
}

class AssetHistoryScreen extends StatefulWidget {
  const AssetHistoryScreen({required this.reference, super.key});

  final String reference;

  @override
  State<AssetHistoryScreen> createState() => _AssetHistoryScreenState();
}

class _AssetHistoryScreenState extends State<AssetHistoryScreen> {
  AssetHistory? _history;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final AssetHistory history = await loadAssetHistory(
        Supabase.instance.client,
        widget.reference,
      );
      if (mounted) setState(() => _history = history);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportPdf() async {
    final AssetHistory? history = _history;
    if (history == null) return;
    try {
      final Uint8List bytes = await buildAssetHistoryPdf(
        history,
        theme: await loadPdfTheme(),
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'Riwayat aset ${history.reference} ${DateFormat('dd-MM-yyyy').format(DateTime.now())}.pdf',
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('PDF gagal dibuat: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AssetHistory? history = _history;
    return AppBackScope(
      fallbackRoute: '/equipment-reference',
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallbackRoute: '/equipment-reference'),
          title: Text('Riwayat ${widget.reference.toUpperCase()}'),
          actions: <Widget>[
            IconButton(
              tooltip: 'Ekspor PDF',
              onPressed: history == null ? null : _exportPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
            children: <Widget>[
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: <Widget>[
                        Text('Riwayat belum dapat dimuat. $_error'),
                        const SizedBox(height: 8),
                        FilledButton.tonal(
                          onPressed: _load,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (history != null)
                ..._content(context, history),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, AssetHistory h) {
    final DateTime now = DateTime.now();
    final int openAlerts = h.alerts.where((a) => !a.isClosed).length;
    return <Widget>[
      Card(
        color: AppColors.green,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                h.reference,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                h.entry?.description ?? 'Tidak ada di daftar alat Ellipse',
                style: const TextStyle(color: Colors.white, height: 1.3),
              ),
              if (h.entry != null)
                Text(
                  '${h.entry!.siteLabel} · ${h.entry!.typeLabel} · '
                  '${h.entry!.statusLabel}',
                  style: const TextStyle(color: Color(0xC8FFFFFF)),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: <Widget>[
          Expanded(
            child: FigureTile(
              label: 'CM terbuka',
              value: '${h.cm.length}',
              color: h.cm.isEmpty ? AppColors.green : AppColors.danger,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FigureTile(
              label: 'PM terbuka',
              value: '${h.pm.length}',
              color: h.pm.isEmpty ? AppColors.green : AppColors.orange,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FigureTile(label: 'PR', value: '${h.prs.length}'),
          ),
          if (assetHasTemperature(h.reference)) ...<Widget>[
            const SizedBox(width: 8),
            Expanded(
              child: FigureTile(
                label: 'Suhu kritis',
                value: '${h.alerts.length}',
                color: openAlerts > 0 ? AppColors.danger : AppColors.green,
              ),
            ),
          ],
        ],
      ),
      if (h.unavailable.isNotEmpty) ...<Widget>[
        const SizedBox(height: 8),
        Text(
          'Tidak ditampilkan untuk peran Anda: ${h.unavailable.join(', ')}.',
          style: AppTextStyles.supporting,
        ),
      ],
      if (assetHasTemperature(h.reference))
        _Section(
          title: 'Suhu kritis (12 bulan)',
          action: TextButton.icon(
            onPressed: () => context.go('/temperature-trend'),
            icon: const Icon(Icons.show_chart_rounded),
            label: const Text('Tren suhu'),
          ),
          empty: 'Tidak ada suhu kritis.',
          children: <Widget>[
            for (final TemperatureAlertRecord a in h.alerts)
              _Line(
                title: '${_number(a.value)} °C · ${a.pointLabel}',
                subtitle:
                    '${_date(a.occurredAt)} · ${a.teamName ?? '-'} · '
                    '${a.action ?? 'belum ada tindakan'}',
                tag: InfoTag(a.status.label, color: a.status.color),
              ),
          ],
        ),
      _Section(
        title: 'CM terbuka',
        empty: 'Tidak ada CM terbuka.',
        children: <Widget>[
          for (final CorrectiveMaintenanceWorkOrder w in h.cm)
            _Line(
              title: '${w.workOrder} · ${w.description}',
              subtitle:
                  'Dibuat ${_date(w.raisedOn)} · ${w.site}'
                  '${w.progress == null ? '' : '\nProgress: ${w.progress}'}',
              tag: w.raisedOn == null
                  ? null
                  : InfoTag(
                      '${now.difference(w.raisedOn!).inDays} hari',
                      color: now.difference(w.raisedOn!).inDays > 30
                          ? AppColors.danger
                          : AppColors.orange,
                    ),
            ),
        ],
      ),
      _Section(
        title: 'PM terbuka',
        empty: 'Tidak ada PM terbuka.',
        children: <Widget>[
          for (final PreventiveMaintenanceWorkOrder w in h.pm)
            _Line(
              title: '${w.workOrder} · ${w.description}',
              subtitle:
                  'Crew ${w.crew} · ${w.site} · rencana ${_date(w.plannedStartOn)}',
            ),
        ],
      ),
      _Section(
        title: 'Purchase requisition',
        empty: 'Belum ada PR untuk unit ini.',
        children: <Widget>[
          for (final PurchaseRequisition p in h.prs)
            _Line(
              title: 'PR ${p.noPr} · ${p.description ?? '-'}',
              subtitle:
                  'Rilis ${_date(p.releaseDate)} · PO ${p.noPo ?? '-'}'
                  '${p.closedDate == null ? '' : ' · datang ${_date(p.closedDate)}'}'
                  '${p.status == null ? '' : ' · ${p.status}'}',
            ),
        ],
      ),
      _Section(
        title: 'Barang dipesan belum datang',
        empty: 'Tidak ada PO terbuka dari PR unit ini.',
        children: <Widget>[
          for (final JsonMap o in h.orders)
            _Line(
              title: '${o['po_no']} · ${o['description'] ?? '-'}',
              subtitle:
                  'Sisa ${o['qty_outstanding'] ?? '-'} dari ${o['qty_order'] ?? '-'} · '
                  'jatuh tempo ${_date(DateTime.tryParse('${o['due_date']}'))}',
            ),
        ],
      ),
      _Section(
        title: 'Barang diterima gudang',
        empty: 'Belum ada penerimaan untuk PO unit ini.',
        children: <Widget>[
          for (final JsonMap r in h.receipts)
            _Line(
              title: '${r['po_number']} · ${r['description'] ?? '-'}',
              subtitle:
                  '${_date(DateTime.tryParse('${r['received_on']}'))} · '
                  '${r['quantity'] ?? ''} ${r['uoi'] ?? ''} · ${r['supplier'] ?? ''}',
            ),
        ],
      ),
      _Section(
        title: 'Pengambilan barang untuk WO unit ini',
        empty: 'Belum ada pengambilan barang dengan nomor WO unit ini.',
        children: <Widget>[
          for (final JsonMap i in h.pickups)
            _Line(
              title: 'WO ${i['job_number']} · ${i['taken_by'] ?? '-'}',
              subtitle:
                  '${_date(DateTime.tryParse('${i['issued_on']}'))} · '
                  '${_items(i['warehouse_issue_item'])}',
            ),
        ],
      ),
    ];
  }
}

class _Section extends StatefulWidget {
  const _Section({
    required this.title,
    required this.children,
    required this.empty,
    this.action,
  });

  final String title;
  final List<Widget> children;
  final String empty;
  final Widget? action;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  static const int _preview = 5;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final List<Widget> shown = _all
        ? widget.children
        : widget.children.take(_preview).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${widget.title} (${widget.children.length})',
                  style: AppTextStyles.sectionTitle,
                ),
              ),
              if (widget.action != null) widget.action!,
            ],
          ),
          const SizedBox(height: 6),
          if (widget.children.isEmpty)
            Text(widget.empty, style: AppTextStyles.supporting)
          else
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < shown.length; i++) ...<Widget>[
                    if (i > 0) const Divider(height: 1),
                    shown[i],
                  ],
                  if (widget.children.length > _preview)
                    TextButton(
                      onPressed: () => setState(() => _all = !_all),
                      child: Text(
                        _all
                            ? 'Tampilkan lebih sedikit'
                            : 'Tampilkan semua (${widget.children.length})',
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.title, required this.subtitle, this.tag});

  final String title;
  final String subtitle;
  final Widget? tag;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(subtitle, style: AppTextStyles.supporting),
            ],
          ),
        ),
        if (tag != null) ...<Widget>[const SizedBox(width: 8), tag!],
      ],
    ),
  );
}

String _date(DateTime? value) =>
    value == null ? '-' : DateFormat('d MMM yyyy', 'id_ID').format(value);

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

String _items(Object? items) {
  if (items is! List || items.isEmpty) return '-';
  return items
      .map((Object? item) {
        if (item is! Map) return '';
        return '${item['description'] ?? item['item_code']} '
                '${item['quantity'] ?? ''} ${item['uoi'] ?? ''}'
            .trim();
      })
      .where((String text) => text.isNotEmpty)
      .join('; ');
}

/// The asset history as an A4 PDF.
Future<Uint8List> buildAssetHistoryPdf(
  AssetHistory h, {
  required pw.ThemeData theme,
}) {
  final String title = 'Riwayat Aset ${h.reference}';
  final DateTime now = DateTime.now();
  final pw.Document document = pw.Document(theme: theme, title: title);
  document.addPage(
    reportPage(
      title: title,
      build: (pw.Context context) => <pw.Widget>[
        ...reportHeading(
          title,
          <String>[
            h.entry?.description ?? 'Tidak ada di daftar alat Ellipse',
            if (h.entry != null) h.entry!.siteLabel,
            'per ${reportDate(now)}',
          ].join(' · '),
        ),
        reportFigures(<ReportFigure>[
          ReportFigure(
            'CM terbuka',
            '${h.cm.length}',
            color: h.cm.isEmpty ? reportGreen : reportDanger,
          ),
          ReportFigure(
            'PM terbuka',
            '${h.pm.length}',
            color: h.pm.isEmpty ? reportGreen : reportOrange,
          ),
          ReportFigure('PR', '${h.prs.length}'),
          if (assetHasTemperature(h.reference))
            ReportFigure(
              'Suhu kritis 12 bln',
              '${h.alerts.length}',
              color: h.alerts.isEmpty ? reportGreen : reportDanger,
            ),
        ]),
        if (assetHasTemperature(h.reference)) ...<pw.Widget>[
          reportSectionTitle('Suhu kritis (12 bulan)'),
          reportTable(
            headers: const <String>[
              'Waktu',
              'Titik ukur',
              '°C',
              'Status',
              'Tindakan',
            ],
            centered: const <int>{0, 2, 3},
            widths: const <int, pw.TableColumnWidth>{
              0: pw.FixedColumnWidth(60),
              1: pw.FlexColumnWidth(2),
              2: pw.FixedColumnWidth(26),
              3: pw.FixedColumnWidth(46),
              4: pw.FlexColumnWidth(2.4),
            },
            rows: <List<String>>[
              for (final TemperatureAlertRecord a in h.alerts)
                <String>[
                  DateFormat('d/M/yy HH.mm').format(a.occurredAt),
                  a.pointLabel,
                  _number(a.value),
                  a.status.label,
                  a.action ?? '-',
                ],
            ],
          ),
        ],
        reportSectionTitle('CM terbuka'),
        reportTable(
          headers: const <String>[
            'WO',
            'Pekerjaan',
            'Dibuat',
            'Umur',
            'Progress',
          ],
          centered: const <int>{0, 2, 3},
          widths: const <int, pw.TableColumnWidth>{
            0: pw.FixedColumnWidth(56),
            1: pw.FlexColumnWidth(2.2),
            2: pw.FixedColumnWidth(58),
            3: pw.FixedColumnWidth(30),
            4: pw.FlexColumnWidth(2.2),
          },
          rows: <List<String>>[
            for (final CorrectiveMaintenanceWorkOrder w in h.cm)
              <String>[
                w.workOrder,
                w.description,
                reportDate(w.raisedOn),
                w.raisedOn == null
                    ? '-'
                    : '${now.difference(w.raisedOn!).inDays}',
                w.progress ?? '-',
              ],
          ],
        ),
        reportSectionTitle('PM terbuka'),
        reportTable(
          headers: const <String>[
            'WO',
            'Pekerjaan',
            'Crew',
            'Lokasi',
            'Rencana mulai',
          ],
          centered: const <int>{0, 2, 3, 4},
          widths: const <int, pw.TableColumnWidth>{
            0: pw.FixedColumnWidth(56),
            1: pw.FlexColumnWidth(3),
            2: pw.FixedColumnWidth(30),
            3: pw.FixedColumnWidth(36),
            4: pw.FixedColumnWidth(64),
          },
          rows: <List<String>>[
            for (final PreventiveMaintenanceWorkOrder w in h.pm)
              <String>[
                w.workOrder,
                w.description,
                w.crew,
                w.site,
                reportDate(w.plannedStartOn),
              ],
          ],
        ),
        reportSectionTitle('Purchase requisition'),
        reportTable(
          headers: const <String>[
            'No. PR',
            'Deskripsi',
            'Rilis',
            'PO',
            'Datang',
            'Status',
          ],
          centered: const <int>{0, 2, 3, 4},
          widths: const <int, pw.TableColumnWidth>{
            0: pw.FixedColumnWidth(40),
            1: pw.FlexColumnWidth(3),
            2: pw.FixedColumnWidth(56),
            3: pw.FixedColumnWidth(50),
            4: pw.FixedColumnWidth(56),
            5: pw.FlexColumnWidth(1),
          },
          rows: <List<String>>[
            for (final PurchaseRequisition p in h.prs)
              <String>[
                p.noPr,
                p.description ?? '-',
                reportDate(p.releaseDate),
                p.noPo ?? '-',
                reportDate(p.closedDate),
                p.status ?? '-',
              ],
          ],
        ),
        if (h.orders.isNotEmpty) ...<pw.Widget>[
          reportSectionTitle('Barang dipesan belum datang'),
          reportTable(
            headers: const <String>['PO', 'Barang', 'Sisa', 'Jatuh tempo'],
            centered: const <int>{0, 2, 3},
            rows: <List<String>>[
              for (final JsonMap o in h.orders)
                <String>[
                  '${o['po_no']}',
                  '${o['description'] ?? '-'}',
                  '${o['qty_outstanding'] ?? '-'}',
                  reportDate(DateTime.tryParse('${o['due_date']}')),
                ],
            ],
          ),
        ],
        if (h.receipts.isNotEmpty) ...<pw.Widget>[
          reportSectionTitle('Barang diterima gudang'),
          reportTable(
            headers: const <String>['Tanggal', 'PO', 'Barang', 'Qty'],
            centered: const <int>{0, 1, 3},
            rows: <List<String>>[
              for (final JsonMap r in h.receipts)
                <String>[
                  reportDate(DateTime.tryParse('${r['received_on']}')),
                  '${r['po_number']}',
                  '${r['description'] ?? '-'}',
                  '${r['quantity'] ?? ''} ${r['uoi'] ?? ''}',
                ],
            ],
          ),
        ],
        if (h.pickups.isNotEmpty) ...<pw.Widget>[
          reportSectionTitle('Pengambilan barang'),
          reportTable(
            headers: const <String>['Tanggal', 'WO', 'Diambil oleh', 'Barang'],
            centered: const <int>{0, 1},
            rows: <List<String>>[
              for (final JsonMap i in h.pickups)
                <String>[
                  reportDate(DateTime.tryParse('${i['issued_on']}')),
                  '${i['job_number']}',
                  '${i['taken_by'] ?? '-'}',
                  _items(i['warehouse_issue_item']),
                ],
            ],
          ),
        ],
      ],
    ),
  );
  return document.save();
}
