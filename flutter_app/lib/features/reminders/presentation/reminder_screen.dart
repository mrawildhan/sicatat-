import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/sicatat_types.dart';

const List<String> _categories = <String>[
  'General',
  'Taxes',
  'Vehicle document',
  'Servicing',
  'Inspection',
  'Certification',
  'Safety',
  'Other',
];

const List<String> _priorities = <String>['low', 'normal', 'high', 'critical'];

enum _ReminderFilter { all, overdue, dueSoon, open, completed }

enum _DueDateFilter { all, nextThirtyDays, custom }

enum _ReminderMenuAction { delete }

enum ReminderSchedule { weekly, monthly, custom }

class ReminderItem {
  const ReminderItem({
    required this.id,
    required this.siteId,
    required this.title,
    required this.dueDate,
    required this.emails,
    required this.category,
    required this.priority,
    required this.status,
    required this.reminderSchedule,
    required this.evidence,
    this.assetCode,
    this.documentNumber,
    this.governmentAgency,
    this.description,
    this.assignedTo,
    this.location,
    this.customReminderDays,
    this.recurrenceMonths,
    this.completedAt,
    this.completedNote,
    this.lastSentAt,
  });

  final String id;
  final String siteId;
  final String title;
  final DateTime dueDate;
  final List<String> emails;
  final String category;
  final String? assetCode;
  final String? documentNumber;
  final String? governmentAgency;
  final String? description;
  final String priority;
  final String? assignedTo;
  final String? location;
  final String status;
  final ReminderSchedule reminderSchedule;
  final List<ReminderEvidence> evidence;
  final int? customReminderDays;
  final int? recurrenceMonths;
  final DateTime? completedAt;
  final String? completedNote;
  final DateTime? lastSentAt;

  bool get isOpen => status == 'open';
  bool get isCompleted => status == 'completed';
  List<ReminderEvidence> get supportingDocuments => evidence
      .where(
        (ReminderEvidence file) => file.attachmentType == 'supporting_document',
      )
      .toList(growable: false);
  List<ReminderEvidence> get completionProof => evidence
      .where(
        (ReminderEvidence file) => file.attachmentType != 'supporting_document',
      )
      .toList(growable: false);

  factory ReminderItem.fromJson(JsonMap json) {
    final Object? rawEmails = json['recipient_emails'];
    if (rawEmails is! List) {
      throw const FormatException('Reminder recipients are invalid.');
    }
    final List<String> emails = rawEmails
        .whereType<String>()
        .map((String email) => email.trim().toLowerCase())
        .where((String email) => email.contains('@'))
        .toSet()
        .toList(growable: false);
    final Object? rawCustomDays = json['custom_reminder_days'];
    final int? customDays = rawCustomDays is num ? rawCustomDays.toInt() : null;
    final Object? rawRecurrence = json['recurrence_months'];
    final Object? rawEvidence = json['operational_reminder_evidence'];
    return ReminderItem(
      id: json.requiredString('id'),
      siteId: json.requiredString('site_id'),
      title: json.requiredString('title'),
      dueDate: DateTime.parse(json.requiredString('due_date')),
      emails: emails,
      category: json.optionalString('category') ?? 'General',
      assetCode: _cleanOptional(json.optionalString('asset_code')),
      documentNumber: _cleanOptional(json.optionalString('document_number')),
      governmentAgency: _cleanOptional(
        json.optionalString('government_agency'),
      ),
      description: _cleanOptional(json.optionalString('description')),
      priority: json.optionalString('priority') ?? 'normal',
      assignedTo: _cleanOptional(json.optionalString('assigned_to')),
      location: _cleanOptional(json.optionalString('location')),
      status: json.optionalString('status') ?? 'open',
      reminderSchedule: _reminderScheduleFromStorage(
        json.optionalString('reminder_schedule'),
      ),
      evidence: rawEvidence is List
          ? rawEvidence
                .map(
                  (Object? row) => ReminderEvidence.fromJson(
                    requireJsonMap(row, source: 'reminder evidence'),
                  ),
                )
                .toList(growable: false)
          : const <ReminderEvidence>[],
      customReminderDays: customDays,
      recurrenceMonths: rawRecurrence is num ? rawRecurrence.toInt() : null,
      completedAt: _parseOptionalDate(json.optionalString('completed_at')),
      completedNote: _cleanOptional(json.optionalString('completed_note')),
      lastSentAt: _parseOptionalDate(json.optionalString('last_sent_at')),
    );
  }

  Map<String, Object?> toPayload() => <String, Object?>{
    'site_id': siteId,
    'title': title,
    'due_date': _dateOnly(dueDate),
    'recipient_emails': emails,
    'category': category,
    'asset_code': assetCode,
    'document_number': documentNumber,
    'government_agency': governmentAgency,
    'description': description,
    'priority': priority,
    'assigned_to': assignedTo,
    'location': location,
    'reminder_schedule': _reminderScheduleStorageValue(reminderSchedule),
    'custom_reminder_days': reminderSchedule == ReminderSchedule.custom
        ? customReminderDays
        : null,
    'recurrence_months': recurrenceMonths,
  };
}

class ReminderEvidence {
  const ReminderEvidence({
    required this.id,
    required this.fileName,
    required this.storagePath,
    required this.mimeType,
    required this.sizeBytes,
    required this.uploadedAt,
    required this.attachmentType,
  });

  final String id;
  final String fileName;
  final String storagePath;
  final String mimeType;
  final int sizeBytes;
  final DateTime uploadedAt;
  final String attachmentType;

  factory ReminderEvidence.fromJson(JsonMap json) => ReminderEvidence(
    id: json.requiredString('id'),
    fileName: json.requiredString('file_name'),
    storagePath: json.requiredString('storage_path'),
    mimeType: json.requiredString('mime_type'),
    sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
    uploadedAt: DateTime.parse(json.requiredString('uploaded_at')).toLocal(),
    attachmentType:
        json.optionalString('attachment_type') ?? 'completion_proof',
  );
}

class _PendingEvidence {
  const _PendingEvidence({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });

  final String name;
  final Uint8List bytes;
  final String mimeType;
}

class _ReminderSite {
  const _ReminderSite({required this.id, required this.name});

  final String id;
  final String name;

  factory _ReminderSite.fromJson(JsonMap json) => _ReminderSite(
    id: json.requiredString('id'),
    name: json.requiredString('name'),
  );
}

class ReminderScreen extends StatefulWidget {
  const ReminderScreen({super.key});

  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen> {
  static const String _initialRecipient = 'mcasamasam@arutmin.com';

  List<ReminderItem> _items = const <ReminderItem>[];
  List<String> _recipientDirectory = const <String>[];
  List<_ReminderSite> _sites = const <_ReminderSite>[];
  AppUser? _actor;
  final Set<String> _sendingIds = <String>{};
  final TextEditingController _searchController = TextEditingController();
  RealtimeChannel? _reminderChannel;
  Timer? _realtimeRefreshDebounce;
  _ReminderFilter _filter = _ReminderFilter.all;
  String _searchQuery = '';
  String? _siteFilterId;
  _DueDateFilter _dueDateFilter = _DueDateFilter.all;
  DateTimeRange? _customDueRange;
  bool _loading = true;

  SupabaseClient get _client => Supabase.instance.client;

  bool get _canSelectSite =>
      _actor?.role == UserRole.admin ||
      _actor?.role == UserRole.supervisorSmg ||
      _actor?.role == UserRole.foremanLv;

  bool get _hasAdvancedFilter =>
      _siteFilterId != null ||
      _dueDateFilter != _DueDateFilter.all ||
      _filter != _ReminderFilter.all;

  bool get _hasActiveFilter =>
      _hasAdvancedFilter || _searchQuery.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeToReminderChanges();
  }

  @override
  void dispose() {
    _realtimeRefreshDebounce?.cancel();
    final RealtimeChannel? channel = _reminderChannel;
    if (channel != null) unawaited(_client.removeChannel(channel));
    _searchController.dispose();
    super.dispose();
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _load({bool showLoading = true, bool showErrors = true}) async {
    if (showLoading && mounted) setState(() => _loading = true);
    try {
      final String? email = _client.auth.currentUser?.email;
      if (email == null) throw const FormatException('No active user session.');
      final String nik = email.split('@').first;
      final List<Object> responses = await Future.wait<Object>(<Future<Object>>[
        _client
            .from('operational_reminder')
            .select(
              'id,site_id,title,due_date,recipient_emails,category,asset_code,document_number,government_agency,description,priority,assigned_to,location,status,reminder_schedule,custom_reminder_days,recurrence_months,completed_at,completed_note,last_sent_at,operational_reminder_evidence(id,file_name,storage_path,mime_type,size_bytes,uploaded_at,attachment_type)',
            )
            .order('due_date'),
        _client
            .from('reminder_recipient')
            .select('email')
            .eq('is_active', true)
            .order('email'),
        _client
            .from('site')
            .select('id,name')
            .eq('is_active', true)
            .order('name'),
        _client
            .from('app_user')
            .select('id,nik,name,role,team_id,site_id,phone,is_active')
            .eq('nik', nik)
            .single(),
      ]);
      final Object reminderResponse = responses[0];
      final Object recipientResponse = responses[1];
      final Object siteResponse = responses[2];
      final Object profileResponse = responses[3];
      if (reminderResponse is! List ||
          recipientResponse is! List ||
          siteResponse is! List) {
        throw const FormatException(
          'The server returned invalid reminder data.',
        );
      }
      final List<ReminderItem> reminders = reminderResponse
          .map(
            (Object? row) =>
                ReminderItem.fromJson(requireJsonMap(row, source: 'reminder')),
          )
          .toList(growable: false);
      final List<String> recipients = <String>{
        _initialRecipient,
        ...recipientResponse.map((Object? row) {
          final String email = requireJsonMap(
            row,
            source: 'reminder recipient',
          ).requiredString('email');
          return email.trim().toLowerCase();
        }),
      }.toList()..sort();
      final List<_ReminderSite> sites = siteResponse
          .map(
            (Object? row) =>
                _ReminderSite.fromJson(requireJsonMap(row, source: 'site')),
          )
          .toList(growable: false);
      final AppUser actor = AppUser.fromJson(
        requireJsonMap(profileResponse, source: 'current user'),
      );
      if (mounted) {
        setState(() {
          _items = reminders;
          _recipientDirectory = recipients;
          _sites = sites;
          _actor = actor;
        });
      }
    } on Object catch (error) {
      if (mounted && showErrors) _message('Unable to load reminders: $error');
    } finally {
      if (mounted && showLoading) setState(() => _loading = false);
    }
  }

  void _subscribeToReminderChanges() {
    _reminderChannel = _client
        .channel(
          'operational-reminders-${DateTime.now().microsecondsSinceEpoch}',
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'operational_reminder',
          callback: (_) => _queueRealtimeRefresh(),
        )
        .subscribe();
  }

  void _queueRealtimeRefresh() {
    _realtimeRefreshDebounce?.cancel();
    _realtimeRefreshDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) unawaited(_load(showLoading: false, showErrors: false));
    });
  }

  bool _isValidEmail(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);

  String _emailFailure(Object error) {
    if (error is FunctionException) {
      final Object? details = error.details;
      if (details is Map && details['error'] is String) {
        return details['error']! as String;
      }
      if (details is! String) return error.toString();
      try {
        final dynamic decoded = jsonDecode(details);
        if (decoded is Map && decoded['error'] is String) {
          return decoded['error']! as String;
        }
      } on FormatException {
        return details;
      }
    }
    return error.toString();
  }

  Future<void> _edit(ReminderItem? existing) async {
    final TextEditingController title = TextEditingController(
      text: existing?.title ?? '',
    );
    final TextEditingController assetCode = TextEditingController(
      text: existing?.assetCode ?? '',
    );
    final TextEditingController documentNumber = TextEditingController(
      text: existing?.documentNumber ?? '',
    );
    final TextEditingController governmentAgency = TextEditingController(
      text: existing?.governmentAgency ?? '',
    );
    final TextEditingController description = TextEditingController(
      text: existing?.description ?? '',
    );
    final TextEditingController assignedTo = TextEditingController(
      text: existing?.assignedTo ?? '',
    );
    final TextEditingController addEmail = TextEditingController();
    DateTime dueDate =
        existing?.dueDate ??
        _dateOnlyDate(DateTime.now()).add(const Duration(days: 7));
    String? siteId = existing?.siteId ?? _actor?.siteId;
    if (siteId == null && _sites.isNotEmpty) siteId = _sites.first.id;
    String? category = existing?.category;
    if (category != null && !_categories.contains(category)) category = 'Other';
    String priority = existing?.priority ?? 'normal';
    if (!_priorities.contains(priority)) priority = 'normal';
    int? recurrenceMonths = existing?.recurrenceMonths;
    ReminderSchedule reminderSchedule =
        existing?.reminderSchedule ?? ReminderSchedule.weekly;
    final TextEditingController customReminderDays = TextEditingController(
      text: existing?.customReminderDays?.toString() ?? '7',
    );
    final Set<String> selected = <String>{
      ...?existing?.emails,
      if (existing == null) _initialRecipient,
    };
    final List<String> available = <String>{
      ..._recipientDirectory,
    }.toList(growable: true)..sort();
    String? addEmailError;
    final List<_PendingEvidence> pendingDocuments = <_PendingEvidence>[];
    bool showValidation = false;

    bool hasMissingRequiredFields() =>
        title.text.trim().isEmpty ||
        siteId == null ||
        category == null ||
        documentNumber.text.trim().isEmpty ||
        governmentAgency.text.trim().isEmpty ||
        description.text.trim().isEmpty ||
        selected.isEmpty;

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder:
            (
              BuildContext context,
              void Function(void Function()) setModalState,
            ) => AlertDialog(
              title: Text(
                existing == null ? 'Tambah pengingat' : 'Ubah pengingat',
              ),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TextField(
                        controller: title,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) {
                          if (showValidation) setModalState(() {});
                        },
                        decoration: InputDecoration(
                          labelText: 'Nama dokumen *',
                          hintText: 'e.g. PAJAK HILUX RESCUE',
                          errorText: showValidation && title.text.trim().isEmpty
                              ? 'Nama dokumen wajib diisi.'
                              : null,
                        ),
                      ),
                      if (_canSelectSite) ...<Widget>[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: siteId,
                          decoration: InputDecoration(
                            labelText: 'Site *',
                            errorText: showValidation && siteId == null
                                ? 'Pilih site.'
                                : null,
                          ),
                          items: _sites
                              .map(
                                (_ReminderSite site) =>
                                    DropdownMenuItem<String>(
                                      value: site.id,
                                      child: Text(site.name),
                                    ),
                              )
                              .toList(growable: false),
                          onChanged: (String? value) =>
                              setModalState(() => siteId = value),
                        ),
                      ] else if (_actor?.siteId != null) ...<Widget>[
                        const SizedBox(height: 12),
                        const Text(
                          'Site reminder mengikuti cakupan akun Anda.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ],
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: category,
                        decoration: InputDecoration(
                          labelText: 'Kategori *',
                          errorText: showValidation && category == null
                              ? 'Pilih kategori.'
                              : null,
                        ),
                        items: _categories
                            .map(
                              (String value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (String? value) => setModalState(() {
                          category = value;
                          if (value == 'Taxes' &&
                              governmentAgency.text.trim().isEmpty) {
                            governmentAgency.text =
                                'Samsat Provinsi Kalimantan Selatan';
                          }
                        }),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: assetCode,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Aset / referensi (opsional)',
                          hintText: 'e.g. SMG 001',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: documentNumber,
                        textCapitalization: TextCapitalization.characters,
                        onChanged: (_) {
                          if (showValidation) setModalState(() {});
                        },
                        decoration: InputDecoration(
                          labelText: 'Nomor dokumen *',
                          hintText: 'e.g. DA 8074 LN',
                          errorText:
                              showValidation &&
                                  documentNumber.text.trim().isEmpty
                              ? 'Nomor dokumen wajib diisi.'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: governmentAgency,
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) {
                          if (showValidation) setModalState(() {});
                        },
                        decoration: InputDecoration(
                          labelText: 'Instansi pemerintah *',
                          hintText: 'e.g. Samsat Provinsi Kalimantan Selatan',
                          errorText:
                              showValidation &&
                                  governmentAgency.text.trim().isEmpty
                              ? 'Instansi pemerintah wajib diisi.'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: description,
                        textCapitalization: TextCapitalization.sentences,
                        minLines: 2,
                        maxLines: 4,
                        onChanged: (_) {
                          if (showValidation) setModalState(() {});
                        },
                        decoration: InputDecoration(
                          labelText: 'Tindakan / catatan wajib *',
                          hintText:
                              'Jelaskan pekerjaan yang harus diselesaikan.',
                          errorText:
                              showValidation && description.text.trim().isEmpty
                              ? 'Tindakan atau catatan wajib diisi.'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: priority,
                        decoration: const InputDecoration(
                          labelText: 'Prioritas',
                        ),
                        items: _priorities
                            .map(
                              (String value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(_priorityLabel(value)),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (String? value) =>
                            setModalState(() => priority = value ?? priority),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: assignedTo,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Penanggung jawab / tim',
                          hintText: 'e.g. Maintenance Clerk',
                        ),
                      ),
                      if (existing == null) ...<Widget>[
                        const SizedBox(height: 12),
                        const Text(
                          'Dokumen pendukung (opsional)',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Lampirkan PDF, JPG, JPEG, atau PNG bila tersedia.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final List<_PendingEvidence> selectedFiles =
                                await _pickCompletionEvidence();
                            if (selectedFiles.isNotEmpty) {
                              setModalState(
                                () => pendingDocuments.addAll(selectedFiles),
                              );
                            }
                          },
                          icon: const Icon(Icons.attach_file_rounded),
                          label: Text(
                            pendingDocuments.isEmpty
                                ? 'Lampirkan dokumen'
                                : 'Tambah dokumen',
                          ),
                        ),
                        ...pendingDocuments.asMap().entries.map(
                          (MapEntry<int, _PendingEvidence> entry) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(_evidenceIcon(entry.value.mimeType)),
                            title: Text(entry.value.name),
                            subtitle: Text(
                              _prettyBytes(entry.value.bytes.length),
                            ),
                            trailing: IconButton(
                              tooltip: 'Hapus dokumen',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setModalState(
                                () => pendingDocuments.removeAt(entry.key),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_rounded),
                        title: const Text('Tanggal berakhir *'),
                        subtitle: Text(_prettyDate(dueDate)),
                        trailing: const Icon(Icons.calendar_month_rounded),
                        onTap: () async {
                          final DateTime? picked = await showDatePicker(
                            context: context,
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2040),
                            initialDate: dueDate,
                          );
                          if (picked != null) {
                            setModalState(() => dueDate = picked);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Jadwal email otomatis',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Email dikirim otomatis pukul 08.00 WITA.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<ReminderSchedule>(
                        initialValue: reminderSchedule,
                        decoration: const InputDecoration(
                          labelText: 'Waktu pengingat',
                        ),
                        items: const <DropdownMenuItem<ReminderSchedule>>[
                          DropdownMenuItem<ReminderSchedule>(
                            value: ReminderSchedule.weekly,
                            child: Text('Mingguan · 7 hari sebelumnya'),
                          ),
                          DropdownMenuItem<ReminderSchedule>(
                            value: ReminderSchedule.monthly,
                            child: Text(
                              'Bulanan · 1 bulan kalender sebelumnya',
                            ),
                          ),
                          DropdownMenuItem<ReminderSchedule>(
                            value: ReminderSchedule.custom,
                            child: Text(
                              'Kustom · pilih jumlah hari sebelumnya',
                            ),
                          ),
                        ],
                        onChanged: (ReminderSchedule? value) => setModalState(
                          () => reminderSchedule = value ?? reminderSchedule,
                        ),
                      ),
                      if (reminderSchedule ==
                          ReminderSchedule.custom) ...<Widget>[
                        const SizedBox(height: 12),
                        TextField(
                          controller: customReminderDays,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Hari sebelum jatuh tempo',
                            hintText: 'e.g. 14',
                            suffixText: 'hari',
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int?>(
                        initialValue: recurrenceMonths,
                        decoration: const InputDecoration(
                          labelText: 'Ulangi setelah selesai',
                        ),
                        items: const <DropdownMenuItem<int?>>[
                          DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Tidak berulang'),
                          ),
                          DropdownMenuItem<int?>(
                            value: 1,
                            child: Text('Setiap bulan'),
                          ),
                          DropdownMenuItem<int?>(
                            value: 3,
                            child: Text('Setiap 3 bulan'),
                          ),
                          DropdownMenuItem<int?>(
                            value: 6,
                            child: Text('Setiap 6 bulan'),
                          ),
                          DropdownMenuItem<int?>(
                            value: 12,
                            child: Text('Setiap tahun'),
                          ),
                        ],
                        onChanged: (int? value) =>
                            setModalState(() => recurrenceMonths = value),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Penerima email *',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: showValidation && selected.isEmpty
                              ? AppColors.danger
                              : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Pilih setiap orang yang perlu menerima pengingat ini.',
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Mode pengujian: seluruh email keluar dikirim ke mcasamasam@arutmin.com.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 8),
                      if (showValidation && selected.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 6),
                          child: Text(
                            'Pilih setidaknya satu penerima.',
                            style: TextStyle(color: AppColors.danger),
                          ),
                        ),
                      ...available.map(
                        (String email) => CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                          value: selected.contains(email),
                          title: Text(email),
                          onChanged: (bool? checked) => setModalState(() {
                            if (checked ?? false) {
                              selected.add(email);
                            } else {
                              selected.remove(email);
                            }
                          }),
                        ),
                      ),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: TextField(
                              controller: addEmail,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                labelText: 'Tambah email lain',
                                errorText: addEmailError,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: 'Tambah dan pilih email',
                            icon: const Icon(Icons.person_add_alt_1_rounded),
                            onPressed: () {
                              final String email = addEmail.text
                                  .trim()
                                  .toLowerCase();
                              if (!_isValidEmail(email)) {
                                setModalState(
                                  () => addEmailError =
                                      'Masukkan email yang valid.',
                                );
                                return;
                              }
                              setModalState(() {
                                if (!available.contains(email)) {
                                  available.add(email);
                                  available.sort();
                                }
                                selected.add(email);
                                addEmail.clear();
                                addEmailError = null;
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Batal'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    if (hasMissingRequiredFields()) {
                      setModalState(() => showValidation = true);
                      return;
                    }
                    Navigator.pop(dialogContext, true);
                  },
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Simpan'),
                ),
              ],
            ),
      ),
    );
    if (saved != true) {
      _disposeControllers(<TextEditingController>[
        title,
        assetCode,
        documentNumber,
        governmentAgency,
        description,
        assignedTo,
        customReminderDays,
        addEmail,
      ]);
      return;
    }
    try {
      final String cleanTitle = title.text.trim();
      final List<String> recipients = selected.toList()..sort();
      final int? parsedCustomDays = reminderSchedule == ReminderSchedule.custom
          ? int.tryParse(customReminderDays.text.trim())
          : null;
      if (cleanTitle.isEmpty ||
          recipients.isEmpty ||
          siteId == null ||
          category == null ||
          documentNumber.text.trim().isEmpty ||
          governmentAgency.text.trim().isEmpty ||
          description.text.trim().isEmpty ||
          (reminderSchedule == ReminderSchedule.custom &&
              (parsedCustomDays == null ||
                  parsedCustomDays < 0 ||
                  parsedCustomDays > 365))) {
        throw const FormatException(
          'Lengkapi setiap kolom wajib bertanda * dan isi jumlah hari kustom 0 sampai 365 bila diperlukan.',
        );
      }
      final ReminderItem item = ReminderItem(
        id: existing?.id ?? '',
        siteId: siteId!,
        title: cleanTitle,
        dueDate: dueDate,
        emails: recipients,
        category: category!,
        assetCode: _cleanOptional(assetCode.text),
        documentNumber: _cleanOptional(documentNumber.text),
        governmentAgency: _cleanOptional(governmentAgency.text),
        description: _cleanOptional(description.text),
        priority: priority,
        assignedTo: _cleanOptional(assignedTo.text),
        location: _siteName(siteId!),
        status: existing?.status ?? 'open',
        reminderSchedule: reminderSchedule,
        evidence: existing?.evidence ?? const <ReminderEvidence>[],
        customReminderDays: parsedCustomDays,
        recurrenceMonths: recurrenceMonths,
      );
      final List<String> newDirectoryEmails = available
          .where((String email) => !_recipientDirectory.contains(email))
          .toList(growable: false);
      if (newDirectoryEmails.isNotEmpty) {
        await _client
            .from('reminder_recipient')
            .upsert(
              newDirectoryEmails
                  .map(
                    (String email) => <String, Object?>{
                      'email': email,
                      'label': email,
                      'is_active': true,
                    },
                  )
                  .toList(growable: false),
              onConflict: 'email',
            );
      }
      if (existing == null) {
        final Object created = await _client
            .from('operational_reminder')
            .insert(item.toPayload())
            .select('id')
            .single();
        final String reminderId = requireJsonMap(
          created,
          source: 'created reminder',
        ).requiredString('id');
        if (pendingDocuments.isNotEmpty) {
          await _uploadSupportingDocuments(reminderId, pendingDocuments);
        }
      } else {
        await _client
            .from('operational_reminder')
            .update(item.toPayload())
            .eq('id', existing.id);
      }
      await _load();
      if (mounted) {
        _message(
          'Pengingat tersimpan. Jadwal otomatis aktif pukul 08.00 WITA.',
        );
      }
    } on Object catch (error) {
      if (mounted) _message('Pengingat tidak dapat disimpan: $error');
    } finally {
      _disposeControllers(<TextEditingController>[
        title,
        assetCode,
        documentNumber,
        governmentAgency,
        description,
        assignedTo,
        customReminderDays,
        addEmail,
      ]);
    }
  }

  Future<void> _complete(ReminderItem item) async {
    final TextEditingController note = TextEditingController();
    final List<_PendingEvidence> pendingEvidence = <_PendingEvidence>[];
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder:
            (
              BuildContext context,
              void Function(void Function()) setModalState,
            ) => AlertDialog(
              title: const Text('Tandai pengingat selesai?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text('Selesaikan "${item.title}"?'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: note,
                    minLines: 2,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Catatan penyelesaian (opsional)',
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'File bukti',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Unggah minimal satu PDF, JPG, JPEG, atau PNG (maksimal 10 MB per file).',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: pendingEvidence.length >= 5
                        ? null
                        : () async {
                            final List<_PendingEvidence> picked =
                                await _pickCompletionEvidence();
                            if (picked.isNotEmpty && context.mounted) {
                              setModalState(
                                () => pendingEvidence.addAll(
                                  picked.take(5 - pendingEvidence.length),
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.upload_file_rounded),
                    label: Text(
                      pendingEvidence.isEmpty
                          ? 'Pilih file bukti'
                          : 'Tambah file bukti',
                    ),
                  ),
                  if (pendingEvidence.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'File bukti wajib dilampirkan sebelum selesai.',
                        style: TextStyle(color: AppColors.orange),
                      ),
                    ),
                  ...pendingEvidence.asMap().entries.map(
                    (MapEntry<int, _PendingEvidence> entry) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_evidenceIcon(entry.value.mimeType)),
                      title: Text(entry.value.name),
                      subtitle: Text(_prettyBytes(entry.value.bytes.length)),
                      trailing: IconButton(
                        tooltip: 'Hapus file',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setModalState(
                          () => pendingEvidence.removeAt(entry.key),
                        ),
                      ),
                    ),
                  ),
                  if (item.recurrenceMonths != null) ...<Widget>[
                    const SizedBox(height: 12),
                    const Text(
                      'Pengingat berulang baru akan dibuat otomatis.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ],
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Batal'),
                ),
                FilledButton.icon(
                  onPressed: pendingEvidence.isEmpty
                      ? null
                      : () => Navigator.pop(dialogContext, true),
                  icon: const Icon(Icons.task_alt_rounded),
                  label: const Text('Tandai selesai'),
                ),
              ],
            ),
      ),
    );
    if (confirmed != true) {
      note.dispose();
      return;
    }
    final List<String> uploadedPaths = <String>[];
    try {
      final List<Map<String, Object?>> uploadedEvidence =
          <Map<String, Object?>>[];
      for (final _PendingEvidence evidence in pendingEvidence) {
        final String storagePath =
            '${item.id}/${DateTime.now().microsecondsSinceEpoch}_${_safeStorageFileName(evidence.name)}';
        await _client.storage
            .from('reminder-evidence')
            .uploadBinary(
              storagePath,
              evidence.bytes,
              fileOptions: FileOptions(contentType: evidence.mimeType),
            );
        uploadedPaths.add(storagePath);
        uploadedEvidence.add(<String, Object?>{
          'storage_path': storagePath,
          'file_name': evidence.name,
          'mime_type': evidence.mimeType,
          'size_bytes': evidence.bytes.length,
        });
      }
      await _client.rpc<dynamic>(
        'complete_operational_reminder',
        params: <String, Object?>{
          'p_reminder_id': item.id,
          'p_completed_note': _cleanOptional(note.text),
          'p_evidence': uploadedEvidence,
        },
      );
      await _load();
      if (mounted) {
        _message(
          item.recurrenceMonths == null
              ? 'Pengingat ditandai selesai.'
              : 'Pengingat selesai dan siklus berikutnya telah dibuat.',
        );
      }
    } on Object catch (error) {
      if (uploadedPaths.isNotEmpty) {
        await _client.storage.from('reminder-evidence').remove(uploadedPaths);
      }
      if (mounted) _message('Pengingat tidak dapat diselesaikan: $error');
    } finally {
      note.dispose();
    }
  }

  Future<void> _reopen(ReminderItem item) async {
    try {
      await _client
          .from('operational_reminder')
          .update(<String, Object?>{
            'status': 'open',
            'completed_at': null,
            'completed_note': null,
          })
          .eq('id', item.id);
      await _load();
      if (mounted) _message('Pengingat dibuka kembali.');
    } on Object catch (error) {
      if (mounted) _message('Pengingat tidak dapat dibuka kembali: $error');
    }
  }

  Future<List<_PendingEvidence>> _pickCompletionEvidence() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return const <_PendingEvidence>[];
    final List<_PendingEvidence> evidence = <_PendingEvidence>[];
    for (final PlatformFile file in result.files) {
      final Uint8List? bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      if (bytes.length > 10 * 1024 * 1024) {
        _message('${file.name} lebih besar dari 10 MB.');
        continue;
      }
      final String? mimeType = _evidenceMimeType(file.name);
      if (mimeType == null) continue;
      evidence.add(
        _PendingEvidence(name: file.name, bytes: bytes, mimeType: mimeType),
      );
    }
    return evidence;
  }

  Future<void> _uploadSupportingDocuments(
    String reminderId,
    List<_PendingEvidence> documents,
  ) async {
    final List<String> uploadedPaths = <String>[];
    try {
      final List<Map<String, Object?>> payload = <Map<String, Object?>>[];
      for (final _PendingEvidence document in documents) {
        final String storagePath =
            '$reminderId/${DateTime.now().microsecondsSinceEpoch}_${_safeStorageFileName(document.name)}';
        await _client.storage
            .from('reminder-evidence')
            .uploadBinary(
              storagePath,
              document.bytes,
              fileOptions: FileOptions(contentType: document.mimeType),
            );
        uploadedPaths.add(storagePath);
        payload.add(<String, Object?>{
          'storage_path': storagePath,
          'file_name': document.name,
          'mime_type': document.mimeType,
          'size_bytes': document.bytes.length,
        });
      }
      await _client.rpc<dynamic>(
        'attach_operational_reminder_documents',
        params: <String, Object?>{
          'p_reminder_id': reminderId,
          'p_documents': payload,
        },
      );
    } on Object catch (_) {
      if (uploadedPaths.isNotEmpty) {
        await _client.storage.from('reminder-evidence').remove(uploadedPaths);
      }
      rethrow;
    }
  }

  Future<void> _openEvidence(ReminderEvidence evidence) async {
    try {
      final String url = await _client.storage
          .from('reminder-evidence')
          .createSignedUrl(evidence.storagePath, 300);
      final bool opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) _message('File bukti tidak dapat dibuka.');
    } on Object catch (error) {
      if (mounted) _message('Bukti tidak dapat dibuka: $error');
    }
  }

  Future<void> _delete(ReminderItem item) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Hapus pengingat?'),
        content: Text('Hapus "${item.title}" beserta riwayatnya?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _client.from('operational_reminder').delete().eq('id', item.id);
      await _load();
      if (mounted) _message('Pengingat dihapus.');
    } on Object catch (error) {
      if (mounted) _message('Pengingat tidak dapat dihapus: $error');
    }
  }

  Future<void> _sendEmail(ReminderItem item) async {
    setState(() => _sendingIds.add(item.id));
    try {
      final FunctionResponse response = await _client.functions
          .invoke(
            'send-reminder-email',
            body: <String, Object?>{'reminder_id': item.id},
          )
          .timeout(
            const Duration(seconds: 25),
            onTimeout: () => throw TimeoutException(
              'Layanan email tidak merespons dalam 25 detik.',
            ),
          );
      final JsonMap data = requireJsonMap(
        response.data,
        source: 'send reminder email response',
      );
      if (data['ok'] != true) {
        throw FormatException(
          data.optionalString('error') ?? 'Layanan email menolak permintaan.',
        );
      }
      await _load();
      if (mounted) {
        _message('Email dikirim ke ${item.emails.length} penerima.');
      }
    } on Object catch (error) {
      if (mounted) _message('Email tidak terkirim: ${_emailFailure(error)}');
    } finally {
      if (mounted) setState(() => _sendingIds.remove(item.id));
    }
  }

  Future<void> _showAdvancedFilter() async {
    String? siteId = _siteFilterId;
    _DueDateFilter dueDateFilter = _dueDateFilter;
    _ReminderFilter reminderFilter = _filter;
    DateTimeRange? customRange = _customDueRange;
    final bool? apply = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder:
            (
              BuildContext context,
              void Function(void Function()) setModalState,
            ) => AlertDialog(
              title: const Text('Filter reminders'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    DropdownButtonFormField<String?>(
                      initialValue: siteId,
                      decoration: const InputDecoration(labelText: 'Site'),
                      items: <DropdownMenuItem<String?>>[
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All accessible sites'),
                        ),
                        ..._sites.map(
                          (_ReminderSite site) => DropdownMenuItem<String?>(
                            value: site.id,
                            child: Text(site.name),
                          ),
                        ),
                      ],
                      onChanged: (String? value) =>
                          setModalState(() => siteId = value),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<_DueDateFilter>(
                      initialValue: dueDateFilter,
                      decoration: const InputDecoration(labelText: 'Due date'),
                      items: const <DropdownMenuItem<_DueDateFilter>>[
                        DropdownMenuItem<_DueDateFilter>(
                          value: _DueDateFilter.all,
                          child: Text('All dates'),
                        ),
                        DropdownMenuItem<_DueDateFilter>(
                          value: _DueDateFilter.nextThirtyDays,
                          child: Text('Due in the next 30 days'),
                        ),
                        DropdownMenuItem<_DueDateFilter>(
                          value: _DueDateFilter.custom,
                          child: Text('Custom date range'),
                        ),
                      ],
                      onChanged: (_DueDateFilter? value) => setModalState(
                        () => dueDateFilter = value ?? dueDateFilter,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<_ReminderFilter>(
                      initialValue: reminderFilter,
                      decoration: const InputDecoration(
                        labelText: 'Reminder status',
                      ),
                      items: const <DropdownMenuItem<_ReminderFilter>>[
                        DropdownMenuItem<_ReminderFilter>(
                          value: _ReminderFilter.all,
                          child: Text('All reminders'),
                        ),
                        DropdownMenuItem<_ReminderFilter>(
                          value: _ReminderFilter.overdue,
                          child: Text('Overdue'),
                        ),
                        DropdownMenuItem<_ReminderFilter>(
                          value: _ReminderFilter.dueSoon,
                          child: Text('Due soon (next 7 days)'),
                        ),
                        DropdownMenuItem<_ReminderFilter>(
                          value: _ReminderFilter.open,
                          child: Text('Open'),
                        ),
                        DropdownMenuItem<_ReminderFilter>(
                          value: _ReminderFilter.completed,
                          child: Text('Completed'),
                        ),
                      ],
                      onChanged: (_ReminderFilter? value) => setModalState(
                        () => reminderFilter = value ?? reminderFilter,
                      ),
                    ),
                    if (dueDateFilter == _DueDateFilter.custom) ...<Widget>[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.date_range_rounded),
                        label: Text(
                          customRange == null
                              ? 'Choose date range'
                              : '${_prettyDate(customRange!.start)} – ${_prettyDate(customRange!.end)}',
                        ),
                        onPressed: () async {
                          final DateTimeRange? selected =
                              await showDateRangePicker(
                                context: context,
                                firstDate: DateTime(2024),
                                lastDate: DateTime(2040),
                                initialDateRange: customRange,
                              );
                          if (selected != null) {
                            setModalState(() => customRange = selected);
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    siteId = null;
                    dueDateFilter = _DueDateFilter.all;
                    customRange = null;
                    reminderFilter = _ReminderFilter.all;
                    Navigator.pop(dialogContext, true);
                  },
                  child: const Text('Clear filters'),
                ),
                FilledButton(
                  onPressed:
                      dueDateFilter == _DueDateFilter.custom &&
                          customRange == null
                      ? null
                      : () => Navigator.pop(dialogContext, true),
                  child: const Text('Apply'),
                ),
              ],
            ),
      ),
    );
    if (apply != true || !mounted) return;
    setState(() {
      _siteFilterId = siteId;
      _dueDateFilter = dueDateFilter;
      _customDueRange = customRange;
      _filter = reminderFilter;
    });
  }

  Future<void> _showHistory(ReminderItem item) async {
    try {
      final List<Object> responses = await Future.wait<Object>(<Future<Object>>[
        _client
            .from('operational_reminder_activity')
            .select('action,note,occurred_at')
            .eq('reminder_id', item.id)
            .order('occurred_at', ascending: false),
        _client
            .from('operational_reminder_delivery')
            .select(
              'delivery_type,scheduled_offset_days,scheduled_schedule_type,status,recipients,sent_at,error_message,created_at',
            )
            .eq('reminder_id', item.id)
            .order('created_at', ascending: false),
      ]);
      if (!mounted) return;
      final List<Object?> activities = responses[0] is List
          ? List<Object?>.from(responses[0] as List)
          : const <Object?>[];
      final List<Object?> deliveries = responses[1] is List
          ? List<Object?>.from(responses[1] as List)
          : const <Object?>[];
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (BuildContext context) => SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: .7,
            maxChildSize: .9,
            builder: (BuildContext context, ScrollController controller) => ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              children: <Widget>[
                Text(
                  'History · ${item.title}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Activity',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                if (activities.isEmpty)
                  const Text(
                    'No recorded activity yet.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ...activities.map((Object? raw) {
                  final JsonMap row = requireJsonMap(
                    raw,
                    source: 'reminder activity',
                  );
                  final String action = row
                      .requiredString('action')
                      .replaceAll('_', ' ');
                  final String? note = row.optionalString('note');
                  final DateTime at = DateTime.parse(
                    row.requiredString('occurred_at'),
                  ).toLocal();
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.history_rounded,
                      color: AppColors.green,
                    ),
                    title: Text(_sentenceCase(action)),
                    subtitle: Text(
                      '${_prettyDateTime(at)}${note == null || note.isEmpty ? '' : '\n$note'}',
                    ),
                  );
                }),
                const Divider(height: 30),
                const Text(
                  'Email delivery',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                if (deliveries.isEmpty)
                  const Text(
                    'No email delivery yet.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ...deliveries.map((Object? raw) {
                  final JsonMap row = requireJsonMap(
                    raw,
                    source: 'reminder delivery',
                  );
                  final String type = row.requiredString('delivery_type');
                  final String status = row.requiredString('status');
                  final int? offset = row['scheduled_offset_days'] is num
                      ? (row['scheduled_offset_days'] as num).toInt()
                      : null;
                  final String atValue =
                      row.optionalString('sent_at') ??
                      row.requiredString('created_at');
                  final String? error = row.optionalString('error_message');
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      status == 'sent'
                          ? Icons.mark_email_read_rounded
                          : Icons.error_outline_rounded,
                      color: status == 'sent'
                          ? AppColors.green
                          : AppColors.danger,
                    ),
                    title: Text(
                      type == 'scheduled'
                          ? 'Automatic email · ${_deliveryScheduleLabel(row.optionalString('scheduled_schedule_type'), offset ?? 0)}'
                          : 'Manual email',
                    ),
                    subtitle: Text(
                      '${_sentenceCase(status)} · ${_prettyDateTime(DateTime.parse(atValue).toLocal())}${error == null || error.isEmpty ? '' : '\n$error'}',
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) _message('Unable to load reminder history: $error');
    }
  }

  List<ReminderItem> get _visibleItems => _items
      .where((ReminderItem item) {
        final String query = _searchQuery.trim().toLowerCase();
        if (query.isNotEmpty) {
          final String searchableText = <String>[
            item.title,
            item.category,
            item.assetCode ?? '',
            item.documentNumber ?? '',
            item.description ?? '',
            item.assignedTo ?? '',
            item.location ?? '',
            _siteName(item.siteId),
          ].join(' ').toLowerCase();
          if (!searchableText.contains(query)) return false;
        }
        if (_siteFilterId != null && item.siteId != _siteFilterId) {
          return false;
        }
        final DateTime dueDate = _dateOnlyDate(item.dueDate);
        switch (_dueDateFilter) {
          case _DueDateFilter.all:
            break;
          case _DueDateFilter.nextThirtyDays:
            final DateTime today = _dateOnlyDate(DateTime.now());
            if (dueDate.isBefore(today) ||
                dueDate.isAfter(today.add(const Duration(days: 30)))) {
              return false;
            }
          case _DueDateFilter.custom:
            final DateTimeRange? range = _customDueRange;
            if (range == null ||
                dueDate.isBefore(_dateOnlyDate(range.start)) ||
                dueDate.isAfter(_dateOnlyDate(range.end))) {
              return false;
            }
        }
        switch (_filter) {
          case _ReminderFilter.all:
            return true;
          case _ReminderFilter.overdue:
            return item.isOpen && _daysUntil(item.dueDate) < 0;
          case _ReminderFilter.dueSoon:
            final int days = _daysUntil(item.dueDate);
            return item.isOpen && days >= 0 && days <= 7;
          case _ReminderFilter.open:
            return item.isOpen;
          case _ReminderFilter.completed:
            return item.isCompleted;
        }
      })
      .toList(growable: false);

  String _siteFilterLabel() {
    if (_siteFilterId == null) return 'All accessible sites';
    for (final _ReminderSite site in _sites) {
      if (site.id == _siteFilterId) return site.name;
    }
    return 'Selected site';
  }

  String _siteName(String siteId) {
    for (final _ReminderSite site in _sites) {
      if (site.id == siteId) return site.name;
    }
    return 'Assigned site';
  }

  String _reminderFilterLabel() => switch (_filter) {
    _ReminderFilter.all => 'Semua pengingat',
    _ReminderFilter.overdue => 'Terlambat',
    _ReminderFilter.dueSoon => 'Segera jatuh tempo',
    _ReminderFilter.open => 'Terbuka',
    _ReminderFilter.completed => 'Selesai',
  };

  void _selectReminderFilter(_ReminderFilter filter) {
    setState(() => _filter = filter);
  }

  String _dueDateFilterLabel() => switch (_dueDateFilter) {
    _DueDateFilter.all => 'Semua tanggal',
    _DueDateFilter.nextThirtyDays => '30 hari ke depan',
    _DueDateFilter.custom =>
      _customDueRange == null
          ? 'Tanggal kustom'
          : '${_prettyDate(_customDueRange!.start)} – ${_prettyDate(_customDueRange!.end)}',
  };

  String _activeFilterLabel() {
    final List<String> labels = <String>[
      if (_searchQuery.trim().isNotEmpty)
        'Pencarian: “${_searchQuery.trim()}” · ${_visibleItems.length} hasil',
      if (_filter != _ReminderFilter.all) _reminderFilterLabel(),
      if (_siteFilterId != null) _siteFilterLabel(),
      if (_dueDateFilter != _DueDateFilter.all) _dueDateFilterLabel(),
    ];
    return labels.join(' · ');
  }

  int get _overdueCount => _items
      .where((ReminderItem item) => item.isOpen && _daysUntil(item.dueDate) < 0)
      .length;
  int get _dueSoonCount => _items.where((ReminderItem item) {
    final int days = _daysUntil(item.dueDate);
    return item.isOpen && days >= 0 && days <= 7;
  }).length;
  int get _openCount => _items.where((ReminderItem item) => item.isOpen).length;
  int get _completedCount =>
      _items.where((ReminderItem item) => item.isCompleted).length;

  @override
  Widget build(BuildContext context) {
    final bool useDesktopHeader =
        kIsWeb && MediaQuery.sizeOf(context).width >= 920;
    return AppBackScope(
      fallbackRoute: '/dashboard',
      child: Scaffold(
        appBar: useDesktopHeader
            ? null
            : AppBar(
                leading: const AppBackButton(fallbackRoute: '/dashboard'),
                title: const Text('Pengingat'),
                actions: <Widget>[
                  IconButton(
                    tooltip: 'Filter pengingat',
                    icon: Badge(
                      isLabelVisible: _hasAdvancedFilter,
                      child: const Icon(Icons.filter_alt_outlined),
                    ),
                    onPressed: _loading ? null : _showAdvancedFilter,
                  ),
                  IconButton(
                    tooltip: 'Muat ulang pengingat',
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: _loading ? null : _load,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
        body: _withDesktopHeader(
          useDesktopHeader,
          _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                    children: <Widget>[
                      const Text(
                        'Tindak lanjut operasional',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Pantau tindakan, penanggung jawab, riwayat pengiriman, dan risiko tenggat waktu.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _edit(null),
                          icon: const Icon(Icons.add_alert_rounded),
                          label: const Text('Tambah pengingat'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _summaryGrid(context),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onChanged: (String value) =>
                            setState(() => _searchQuery = value),
                        decoration: InputDecoration(
                          labelText: 'Cari pengingat',
                          hintText: 'Ketik judul, aset, nomor dokumen, kategori, atau site',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _searchQuery.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Hapus pencarian',
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_hasActiveFilter) ...<Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.greenSurface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: <Widget>[
                              const Icon(Icons.filter_alt_rounded, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _activeFilterLabel(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Hapus filter',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () => setState(() {
                                  _siteFilterId = null;
                                  _dueDateFilter = _DueDateFilter.all;
                                  _customDueRange = null;
                                  _filter = _ReminderFilter.all;
                                  _searchController.clear();
                                  _searchQuery = '';
                                }),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: <Widget>[
                            _filterChip('Semua', _ReminderFilter.all),
                            const SizedBox(width: 8),
                            _filterChip('Terlambat', _ReminderFilter.overdue),
                            const SizedBox(width: 8),
                            _filterChip(
                              'Segera jatuh tempo',
                              _ReminderFilter.dueSoon,
                            ),
                            const SizedBox(width: 8),
                            _filterChip('Terbuka', _ReminderFilter.open),
                            const SizedBox(width: 8),
                            _filterChip('Selesai', _ReminderFilter.completed),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (_visibleItems.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 50),
                          child: Text(
                            _searchQuery.trim().isEmpty
                                ? 'Belum ada pengingat pada tampilan ini. Tambahkan tenggat untuk servis, dokumen, atau tindak lanjut operasional.'
                                : 'Tidak ada pengingat yang cocok dengan “${_searchQuery.trim()}”. Coba judul, aset, nomor dokumen, kategori, atau site lain.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        ),
                      ..._visibleItems.map(
                        (ReminderItem item) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _reminderCard(item),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _withDesktopHeader(bool useDesktopHeader, Widget body) {
    if (!useDesktopHeader) return body;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
          child: Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Pengingat',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: 'Filter pengingat',
                icon: Badge(
                  isLabelVisible: _hasAdvancedFilter,
                  child: const Icon(Icons.filter_alt_outlined),
                ),
                onPressed: _loading ? null : _showAdvancedFilter,
              ),
              IconButton(
                tooltip: 'Muat ulang pengingat',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _loading ? null : _load,
              ),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _summaryGrid(BuildContext context) => Row(
    children: <Widget>[
      _summaryTile(
        'Terlambat',
        _overdueCount,
        AppColors.danger,
        Icons.warning_amber_rounded,
        () => _selectReminderFilter(_ReminderFilter.overdue),
      ),
      const SizedBox(width: 8),
      _summaryTile(
        'Segera',
        _dueSoonCount,
        AppColors.orange,
        Icons.schedule_rounded,
        () => _selectReminderFilter(_ReminderFilter.dueSoon),
      ),
      const SizedBox(width: 8),
      _summaryTile(
        'Terbuka',
        _openCount,
        AppColors.green,
        Icons.pending_actions_rounded,
        () => _selectReminderFilter(_ReminderFilter.open),
      ),
      const SizedBox(width: 8),
      _summaryTile(
        'Selesai',
        _completedCount,
        AppColors.muted,
        Icons.task_alt_rounded,
        () => _selectReminderFilter(_ReminderFilter.completed),
      ),
    ],
  );

  Widget _summaryTile(
    String label,
    int count,
    Color color,
    IconData icon,
    VoidCallback onTap,
  ) => Expanded(
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          child: SizedBox(
            height: 76,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Icon(icon, color: color, size: 19),
                const SizedBox(height: 4),
                Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _filterChip(String label, _ReminderFilter value) => FilterChip(
    label: Text(label),
    selected: _filter == value,
    onSelected: (_) => setState(() => _filter = value),
  );

  Widget _reminderCard(ReminderItem item) {
    final int days = _daysUntil(item.dueDate);
    final Color statusColor = _statusColor(item, days);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showReminderDetails(item),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  item.isCompleted
                      ? Icons.task_alt_rounded
                      : Icons.notifications_active_rounded,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${item.documentNumber ?? item.assetCode ?? 'Tanpa nomor dokumen'} · ${item.category}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            item.isCompleted
                                ? 'Selesai · ${_prettyDate(item.completedAt ?? item.dueDate)}'
                                : '${_dueLabel(item, days)} · ${_prettyDate(item.dueDate)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _tag(_statusLabel(item, days), statusColor),
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

  Future<void> _showReminderDetails(ReminderItem item) async {
    final int days = _daysUntil(item.dueDate);
    final Color statusColor = _statusColor(item, days);
    final bool sending = _sendingIds.contains(item.id);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext detailContext) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: .78,
          maxChildSize: .94,
          builder: (BuildContext context, ScrollController controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            children: <Widget>[
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  PopupMenuButton<_ReminderMenuAction>(
                    tooltip: 'Tindakan lainnya',
                    onSelected: (_ReminderMenuAction action) {
                      Navigator.pop(detailContext);
                      if (action == _ReminderMenuAction.delete) {
                        _delete(item);
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        const <PopupMenuEntry<_ReminderMenuAction>>[
                          PopupMenuItem<_ReminderMenuAction>(
                            value: _ReminderMenuAction.delete,
                            child: ListTile(
                              leading: Icon(
                                Icons.delete_outline_rounded,
                                color: AppColors.danger,
                              ),
                              title: Text(
                                'Hapus pengingat',
                                style: TextStyle(color: AppColors.danger),
                              ),
                            ),
                          ),
                        ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 6,
                children: <Widget>[
                  _tag(_statusLabel(item, days), statusColor),
                  _tag(
                    _priorityLabel(item.priority),
                    _priorityColor(item.priority),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _infoRow(
                Icons.event_rounded,
                item.isCompleted ? 'Selesai' : 'Jatuh tempo',
                item.isCompleted
                    ? _prettyDate(item.completedAt ?? item.dueDate)
                    : '${_dueLabel(item, days)} · ${_prettyDate(item.dueDate)}',
                statusColor,
              ),
              _infoRow(
                Icons.category_outlined,
                'Kategori',
                '${item.category}${item.assetCode == null ? '' : ' · ${item.assetCode}'}',
              ),
              if (item.governmentAgency != null)
                _infoRow(
                  Icons.account_balance_outlined,
                  'Instansi pemerintah',
                  item.governmentAgency!,
                ),
              if (item.documentNumber != null)
                _infoRow(
                  Icons.numbers_rounded,
                  'Nomor dokumen',
                  item.documentNumber!,
                ),
              if (item.assignedTo != null)
                _infoRow(
                  Icons.person_outline_rounded,
                  'Penanggung jawab',
                  item.assignedTo!,
                ),
              _infoRow(
                Icons.location_on_outlined,
                'Site',
                _siteName(item.siteId),
              ),
              if (item.description != null) ...<Widget>[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.greenSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(item.description!),
                ),
              ],
              const Divider(height: 30),
              Text(
                'Penerima · ${item.emails.length} orang',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                item.emails.join(', '),
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 10),
              Text(
                'Email otomatis · ${_reminderScheduleLabel(item.reminderSchedule, item.customReminderDays)} · 08.00 WITA',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              if (item.lastSentAt != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  'Email terakhir · ${_prettyDateTime(item.lastSentAt!)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
              if (item.isCompleted && item.completedNote != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'Catatan penyelesaian · ${item.completedNote}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
              if (item.supportingDocuments.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  'Dokumen pendukung · ${item.supportingDocuments.length} file',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: item.supportingDocuments
                      .map(
                        (ReminderEvidence document) => ActionChip(
                          avatar: Icon(
                            _evidenceIcon(document.mimeType),
                            size: 18,
                          ),
                          label: Text(document.fileName),
                          onPressed: () => _openEvidence(document),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              if (item.completionProof.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  'Bukti penyelesaian · ${item.completionProof.length} file',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: item.completionProof
                      .map(
                        (ReminderEvidence evidence) => ActionChip(
                          avatar: Icon(
                            _evidenceIcon(evidence.mimeType),
                            size: 18,
                          ),
                          label: Text(evidence.fileName),
                          onPressed: () => _openEvidence(evidence),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(detailContext);
                      _showHistory(item);
                    },
                    icon: const Icon(Icons.history_rounded),
                    label: const Text('Riwayat'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(detailContext);
                      _edit(item);
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Ubah'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  if (item.isOpen)
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(detailContext);
                        _complete(item);
                      },
                      icon: const Icon(Icons.task_alt_rounded),
                      label: const Text('Tandai selesai'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(detailContext);
                        _reopen(item);
                      },
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Buka kembali'),
                    ),
                  if (item.isOpen)
                    FilledButton.icon(
                      onPressed: sending
                          ? null
                          : () {
                              Navigator.pop(detailContext);
                              _sendEmail(item);
                            },
                      icon: sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                      label: Text(
                        sending ? 'Mengirim...' : 'Kirim email sekarang',
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

  Widget _infoRow(
    IconData icon,
    String label,
    String value, [
    Color? valueColor,
  ]) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: <Widget>[
        Icon(icon, size: 18, color: AppColors.muted),
        const SizedBox(width: 8),
        Text('$label · ', style: const TextStyle(color: AppColors.muted)),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w700, color: valueColor),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );

  Widget _tag(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: color),
    ),
  );
}

String? _cleanOptional(String? value) {
  final String clean = value?.trim() ?? '';
  return clean.isEmpty ? null : clean;
}

DateTime? _parseOptionalDate(String? value) =>
    value == null ? null : DateTime.parse(value).toLocal();

void _disposeControllers(List<TextEditingController> controllers) {
  for (final TextEditingController controller in controllers) {
    controller.dispose();
  }
}

DateTime _dateOnlyDate(DateTime date) =>
    DateTime(date.year, date.month, date.day);

int _daysUntil(DateTime dueDate) =>
    _dateOnlyDate(dueDate).difference(_dateOnlyDate(DateTime.now())).inDays;

String _dateOnly(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

String _prettyDate(DateTime date) => DateFormat('dd MMM yyyy').format(date);

String _prettyDateTime(DateTime date) =>
    DateFormat('dd MMM yyyy, HH:mm').format(date);

String _sentenceCase(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

String _priorityLabel(String priority) => switch (priority) {
  'low' => 'Rendah',
  'high' => 'Tinggi',
  'critical' => 'Kritis',
  _ => 'Normal',
};

Color _priorityColor(String priority) => switch (priority) {
  'critical' => AppColors.danger,
  'high' => AppColors.orange,
  'low' => AppColors.muted,
  _ => AppColors.green,
};

ReminderSchedule _reminderScheduleFromStorage(String? value) => switch (value) {
  'monthly' => ReminderSchedule.monthly,
  'custom' => ReminderSchedule.custom,
  _ => ReminderSchedule.weekly,
};

String _reminderScheduleStorageValue(ReminderSchedule schedule) =>
    schedule.name;

String _reminderScheduleLabel(ReminderSchedule schedule, int? customDays) =>
    switch (schedule) {
      ReminderSchedule.weekly => 'Mingguan · H-7',
      ReminderSchedule.monthly => 'Bulanan · 1 bulan sebelumnya',
      ReminderSchedule.custom => 'Kustom · H-${customDays ?? 0}',
    };

String _deliveryScheduleLabel(String? schedule, int days) => switch (schedule) {
  'weekly' => 'Mingguan · H-7',
  'monthly' => 'Bulanan · 1 bulan sebelumnya',
  'custom' => 'Kustom · H-$days',
  _ => days == 0 ? 'Tanggal jatuh tempo' : 'H-$days',
};

Color _statusColor(ReminderItem item, int days) {
  if (item.isCompleted) return AppColors.green;
  if (item.status == 'cancelled') return AppColors.muted;
  if (days < 0) return AppColors.danger;
  if (days <= 7) return AppColors.orange;
  return AppColors.green;
}

String _statusLabel(ReminderItem item, int days) {
  if (item.isCompleted) return 'Selesai';
  if (item.status == 'cancelled') return 'Dibatalkan';
  if (days < 0) return 'Terlambat';
  if (days == 0) return 'Jatuh tempo hari ini';
  if (days == 1) return 'Jatuh tempo besok';
  if (days <= 7) return 'Segera jatuh tempo';
  return 'Mendatang';
}

String _dueLabel(ReminderItem item, int days) {
  if (days < 0) return 'Terlambat ${-days} hari';
  if (days == 0) return 'Jatuh tempo hari ini';
  if (days == 1) return 'Jatuh tempo besok';
  return 'Jatuh tempo dalam $days hari';
}

String? _evidenceMimeType(String fileName) =>
    switch (fileName.split('.').last.toLowerCase()) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      _ => null,
    };

IconData _evidenceIcon(String mimeType) => mimeType == 'application/pdf'
    ? Icons.picture_as_pdf_rounded
    : Icons.image_rounded;

String _safeStorageFileName(String value) => value
    .trim()
    .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
    .replaceAll(RegExp(r'_+'), '_');

String _prettyBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
