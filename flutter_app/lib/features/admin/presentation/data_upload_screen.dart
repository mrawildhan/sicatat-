import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../core/widgets/source_update_card.dart';
import '../../../data/models/sicatat_types.dart';

/// One spreadsheet SICATAT imports, and the sync function that imports it.
class DataUploadPart {
  const DataUploadPart({
    required this.part,
    required this.title,
    required this.expected,
    required this.function,
    this.warehouseSource,
  });

  /// Key in data_source_upload and the Storage path current/<part>.
  final String part;
  final String title;

  /// The file the owner normally uploads, shown as a hint.
  final String expected;
  final String function;

  /// "source" of sync-warehouse-drive for the Gudang files.
  final String? warehouseSource;
}

class DataUploadGroup {
  const DataUploadGroup(this.title, this.menu, this.parts);

  final String title;

  /// Where the data shows up in the app.
  final String menu;
  final List<DataUploadPart> parts;
}

const List<DataUploadGroup> dataUploadGroups = <DataUploadGroup>[
  DataUploadGroup('Data PR', 'Operasional → Data PR', <DataUploadPart>[
    DataUploadPart(
      part: 'pr',
      title: 'Data PR',
      expected: 'PR.xlsx, sheet Data PR',
      function: 'sync-purchase-requisitions',
    ),
  ]),
  DataUploadGroup(
    'PM & CM Tertunda',
    'Operasional → PM & CM Tertunda',
    <DataUploadPart>[
      DataUploadPart(
        part: 'pm_cpp',
        title: 'PM CPP',
        expected: 'CPP PM.xlsx (export Ellipse)',
        function: 'sync-preventive-maintenance',
      ),
      DataUploadPart(
        part: 'pm_port',
        title: 'PM PORT',
        expected: 'PORT PM.xlsx (export Ellipse)',
        function: 'sync-preventive-maintenance',
      ),
      DataUploadPart(
        part: 'cm',
        title: 'CM (Weekly Meeting)',
        expected: 'Weekly Meeting.xlsm, sheet CPP dan Port',
        function: 'sync-corrective-maintenance',
      ),
    ],
  ),
  DataUploadGroup('Anggaran', 'Operasional → Anggaran', <DataUploadPart>[
    DataUploadPart(
      part: 'budget',
      title: 'Budget 2026',
      expected: 'Budget 2026 ASM…xlsx, sheet 3271 (Mtc) dan 3275 (Mtc)',
      function: 'sync-operational-budget',
    ),
    DataUploadPart(
      part: 'actual_cpp',
      title: 'Aktual CPP',
      expected: 'cpp asm.xlsx, sheet PLDetail',
      function: 'sync-operational-budget',
    ),
    DataUploadPart(
      part: 'actual_port',
      title: 'Aktual PORT',
      expected: 'port asm.xlsx, sheet PLDetail',
      function: 'sync-operational-budget',
    ),
  ]),
  DataUploadGroup(
    'Gudang',
    'Gudang → Cari barang, Barang dipesan, Peminjaman Alat',
    <DataUploadPart>[
      DataUploadPart(
        part: 'gudang_inventory',
        title: 'Warehouse Inventory',
        expected: 'Warehouse_inventory….xlsx (export Ellipse)',
        function: 'sync-warehouse-drive',
        warehouseSource: 'inventory',
      ),
      DataUploadPart(
        part: 'gudang_list_order',
        title: 'LIST ORDER',
        expected: 'LIST ORDER….xlsx',
        function: 'sync-warehouse-drive',
        warehouseSource: 'list_order',
      ),
      DataUploadPart(
        part: 'gudang_outstanding_po',
        title: 'Outstanding PO',
        expected: 'Outstanding_Purchase_Order….xlsx (export Ellipse)',
        function: 'sync-warehouse-drive',
        warehouseSource: 'outstanding_po',
      ),
    ],
  ),
];

class _StoredUpload {
  const _StoredUpload({
    required this.fileName,
    required this.uploadedAt,
    this.uploadedBy,
  });

  factory _StoredUpload.fromJson(JsonMap json) {
    final Object? uploader = json['uploader'];
    return _StoredUpload(
      fileName: json.requiredString('file_name'),
      uploadedAt: DateTime.parse(json.requiredString('uploaded_at')),
      uploadedBy: uploader is Map ? uploader['name']?.toString() : null,
    );
  }

  final String fileName;
  final DateTime uploadedAt;
  final String? uploadedBy;
}

/// Unggah data: an admin uploads the spreadsheets straight into SICATAT
/// instead of keeping them on public Google Drive links (owner request
/// 2026-09-25). The file goes to Storage incoming/<part>; the sync function
/// imports it and keeps it only when the import succeeded.
class DataUploadScreen extends StatefulWidget {
  const DataUploadScreen({super.key});

  @override
  State<DataUploadScreen> createState() => _DataUploadScreenState();
}

class _DataUploadScreenState extends State<DataUploadScreen> {
  static const String _bucket = 'data-source-uploads';
  static const int _maxBytes = 15 * 1024 * 1024;

  final SupabaseClient _client = Supabase.instance.client;
  Map<String, _StoredUpload> _uploads = const <String, _StoredUpload>{};
  bool _loading = true;
  String? _error;

  /// Part being uploaded or switched back to Drive.
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final Object response = await _client
          .from('data_source_upload')
          .select('part,file_name,uploaded_at,uploader:uploaded_by(name)');
      if (response is! List) throw const FormatException('Data tidak valid.');
      if (!mounted) return;
      setState(() {
        _uploads = <String, _StoredUpload>{
          for (final Object? row in response)
            requireJsonMap(row).requiredString('part'): _StoredUpload.fromJson(
              requireJsonMap(row),
            ),
        };
        _error = null;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Runs the part's sync function; returns its JSON answer.
  Future<JsonMap> _runImport(DataUploadPart part, {PlatformFile? file}) async {
    final Map<String, Object?> body = <String, Object?>{
      if (part.warehouseSource != null) 'source': part.warehouseSource,
      if (file != null)
        'upload': <String, Object?>{
          'part': part.part,
          'file_name': file.name,
          'size': file.size,
        },
    };
    try {
      final FunctionResponse response = await _client.functions.invoke(
        part.function,
        body: body,
      );
      return requireJsonMap(response.data, source: part.title);
    } on FunctionException catch (error) {
      final Object? details = error.details;
      if (details is Map && details['error'] != null) {
        return <String, Object?>{'ok': false, 'error': details['error']};
      }
      rethrow;
    }
  }

  Future<void> _upload(DataUploadPart part) async {
    final FilePickerResult? picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['xlsx', 'xlsm'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty || !mounted) return;
    final PlatformFile file = picked.files.single;
    final List<int>? bytes = file.bytes;
    if (bytes == null) {
      _showResult(part, false, 'File tidak dapat dibaca.');
      return;
    }
    if (file.size > _maxBytes) {
      _showResult(part, false, 'File lebih dari 15 MB.');
      return;
    }
    setState(() => _busy = part.part);
    try {
      await _client.storage
          .from(_bucket)
          .uploadBinary(
            'incoming/${part.part}',
            Uint8List.fromList(bytes),
            fileOptions: FileOptions(
              upsert: true,
              contentType: file.extension?.toLowerCase() == 'xlsm'
                  ? 'application/vnd.ms-excel.sheet.macroEnabled.12'
                  : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ),
          );
      final JsonMap result = await _runImport(part, file: file);
      await _load();
      if (!mounted) return;
      if (result['ok'] == true) {
        final int? rows = (result['rows'] as num?)?.toInt();
        _showResult(
          part,
          true,
          result['changed'] == false
              ? '${file.name} tersimpan. Isinya sama dengan data sekarang, '
                    'jadi tidak ada yang berubah.'
              : '${file.name} berhasil diunggah'
                    '${rows == null || rows == 0 ? '' : ': ${NumberFormat.decimalPattern('id_ID').format(rows)} baris'}.',
        );
      } else {
        _showResult(
          part,
          false,
          '${result['error'] ?? 'File tidak dapat diimpor.'}',
        );
      }
    } on Object catch (error) {
      if (mounted) _showResult(part, false, error.toString());
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _backToDrive(DataUploadPart part) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Kembali ke Google Drive?'),
        content: Text(
          'File unggahan ${part.title} dihapus dan SICATAT membaca lagi '
          'file di Google Drive.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Kembali ke Drive'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = part.part);
    try {
      await _client.storage.from(_bucket).remove(<String>[
        'current/${part.part}',
      ]);
      await _client.from('data_source_upload').delete().eq('part', part.part);
      final JsonMap result = await _runImport(part);
      await _load();
      if (!mounted) return;
      _showResult(
        part,
        result['ok'] == true,
        result['ok'] == true
            ? '${part.title} kembali dibaca dari Google Drive.'
            : 'Sumber kembali ke Drive, tetapi Drive gagal dibaca: '
                  '${result['error']}',
      );
    } on Object catch (error) {
      if (mounted) _showResult(part, false, error.toString());
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _showResult(DataUploadPart part, bool ok, String message) {
    if (ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        icon: const Icon(Icons.error_outline_rounded, color: AppColors.danger),
        title: Text('${part.title} gagal diunggah'),
        content: Text('$message\n\nData lama tetap dipakai.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppBackScope(
      fallbackRoute: '/admin',
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallbackRoute: '/admin'),
          title: const Text('Unggah data'),
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: <Widget>[
              const Text(
                'Pilih file Excel dari perangkat. SICATAT memeriksa isinya '
                'dulu; kalau ada yang salah, data lama tetap dipakai. File '
                'yang belum pernah diunggah masih dibaca dari Google Drive.',
                style: AppTextStyles.supporting,
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Status unggahan tidak dapat dimuat. $_error',
                    style: const TextStyle(color: AppColors.danger),
                  ),
                )
              else
                for (final DataUploadGroup group
                    in dataUploadGroups) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(group.title, style: AppTextStyles.sectionTitle),
                  Text(group.menu, style: AppTextStyles.supporting),
                  const SizedBox(height: 8),
                  for (final DataUploadPart part in group.parts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _UploadTile(
                        part: part,
                        upload: _uploads[part.part],
                        busy: _busy == part.part,
                        enabled: _busy == null,
                        onUpload: () => _upload(part),
                        onBackToDrive: () => _backToDrive(part),
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

class _UploadTile extends StatelessWidget {
  const _UploadTile({
    required this.part,
    required this.upload,
    required this.busy,
    required this.enabled,
    required this.onUpload,
    required this.onBackToDrive,
  });

  final DataUploadPart part;
  final _StoredUpload? upload;
  final bool busy;
  final bool enabled;
  final VoidCallback onUpload;
  final VoidCallback onBackToDrive;

  @override
  Widget build(BuildContext context) {
    final _StoredUpload? stored = upload;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              backgroundColor: AppColors.mint,
              child: Icon(
                stored == null
                    ? Icons.cloud_outlined
                    : Icons.upload_file_rounded,
                color: AppColors.green,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(part.title, style: AppTextStyles.cardTitle),
                  const SizedBox(height: 2),
                  Text(
                    stored == null
                        ? 'Dari Google Drive · ${part.expected}'
                        : 'Diunggah ${sourceUpdateStamp(stored.uploadedAt)}'
                              '${stored.uploadedBy == null ? '' : ' oleh ${stored.uploadedBy}'}'
                              ' · ${stored.fileName}',
                    style: AppTextStyles.supporting,
                  ),
                ],
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              )
            else ...<Widget>[
              IconButton.filledTonal(
                onPressed: enabled ? onUpload : null,
                icon: const Icon(Icons.upload_rounded),
                tooltip: 'Unggah ${part.title}',
              ),
              if (stored != null)
                PopupMenuButton<void>(
                  enabled: enabled,
                  tooltip: 'Opsi lain',
                  itemBuilder: (_) => <PopupMenuEntry<void>>[
                    PopupMenuItem<void>(
                      onTap: onBackToDrive,
                      child: const Text('Kembali ke Google Drive'),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
