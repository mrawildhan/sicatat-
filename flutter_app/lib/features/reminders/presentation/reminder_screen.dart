import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/sicatat_types.dart';

const List<String> _categories = <String>[
  'General',
  'Vehicle document',
  'Servicing',
  'Inspection',
  'Certification',
  'Safety',
  'Other',
];

const List<String> _priorities = <String>['low', 'normal', 'high', 'critical'];

const List<int> _availableReminderOffsets = <int>[30, 14, 7, 1, 0];

enum _ReminderFilter { all, actionRequired, completed }

enum _ReminderMenuAction { delete }

class ReminderItem {
  const ReminderItem({
    required this.id,
    required this.title,
    required this.dueDate,
    required this.emails,
    required this.category,
    required this.priority,
    required this.status,
    required this.reminderOffsets,
    this.assetCode,
    this.description,
    this.assignedTo,
    this.location,
    this.recurrenceMonths,
    this.completedAt,
    this.completedNote,
    this.lastSentAt,
  });

  final String id;
  final String title;
  final DateTime dueDate;
  final List<String> emails;
  final String category;
  final String? assetCode;
  final String? description;
  final String priority;
  final String? assignedTo;
  final String? location;
  final String status;
  final List<int> reminderOffsets;
  final int? recurrenceMonths;
  final DateTime? completedAt;
  final String? completedNote;
  final DateTime? lastSentAt;

  bool get isOpen => status == 'open';
  bool get isCompleted => status == 'completed';

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
    final Object? rawOffsets = json['reminder_offsets_days'];
    final List<int> offsets = rawOffsets is List
        ? rawOffsets
              .whereType<num>()
              .map((num value) => value.toInt())
              .where(_availableReminderOffsets.contains)
              .toSet()
              .toList(growable: false)
        : _availableReminderOffsets;
    offsets.sort((int a, int b) => b.compareTo(a));
    final Object? rawRecurrence = json['recurrence_months'];
    return ReminderItem(
      id: json.requiredString('id'),
      title: json.requiredString('title'),
      dueDate: DateTime.parse(json.requiredString('due_date')),
      emails: emails,
      category: json.optionalString('category') ?? 'General',
      assetCode: _cleanOptional(json.optionalString('asset_code')),
      description: _cleanOptional(json.optionalString('description')),
      priority: json.optionalString('priority') ?? 'normal',
      assignedTo: _cleanOptional(json.optionalString('assigned_to')),
      location: _cleanOptional(json.optionalString('location')),
      status: json.optionalString('status') ?? 'open',
      reminderOffsets: offsets.isEmpty ? _availableReminderOffsets : offsets,
      recurrenceMonths: rawRecurrence is num ? rawRecurrence.toInt() : null,
      completedAt: _parseOptionalDate(json.optionalString('completed_at')),
      completedNote: _cleanOptional(json.optionalString('completed_note')),
      lastSentAt: _parseOptionalDate(json.optionalString('last_sent_at')),
    );
  }

  Map<String, Object?> toPayload() => <String, Object?>{
    'title': title,
    'due_date': _dateOnly(dueDate),
    'recipient_emails': emails,
    'category': category,
    'asset_code': assetCode,
    'description': description,
    'priority': priority,
    'assigned_to': assignedTo,
    'location': location,
    'reminder_offsets_days': reminderOffsets,
    'recurrence_months': recurrenceMonths,
  };
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
  final Set<String> _sendingIds = <String>{};
  _ReminderFilter _filter = _ReminderFilter.all;
  bool _loading = true;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final List<Object> responses = await Future.wait<Object>(<Future<Object>>[
        _client
            .from('operational_reminder')
            .select(
              'id,title,due_date,recipient_emails,category,asset_code,description,priority,assigned_to,location,status,reminder_offsets_days,recurrence_months,completed_at,completed_note,last_sent_at',
            )
            .order('due_date'),
        _client
            .from('reminder_recipient')
            .select('email')
            .eq('is_active', true)
            .order('email'),
      ]);
      final Object reminderResponse = responses[0];
      final Object recipientResponse = responses[1];
      if (reminderResponse is! List || recipientResponse is! List) {
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
      if (mounted) {
        setState(() {
          _items = reminders;
          _recipientDirectory = recipients;
        });
      }
    } on Object catch (error) {
      if (mounted) _message('Unable to load reminders: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    final TextEditingController description = TextEditingController(
      text: existing?.description ?? '',
    );
    final TextEditingController assignedTo = TextEditingController(
      text: existing?.assignedTo ?? '',
    );
    final TextEditingController location = TextEditingController(
      text: existing?.location ?? '',
    );
    final TextEditingController addEmail = TextEditingController();
    DateTime dueDate = existing?.dueDate ?? DateTime.now();
    String category = existing?.category ?? 'General';
    if (!_categories.contains(category)) category = 'Other';
    String priority = existing?.priority ?? 'normal';
    if (!_priorities.contains(priority)) priority = 'normal';
    int? recurrenceMonths = existing?.recurrenceMonths;
    final Set<int> selectedOffsets = <int>{
      ...(existing?.reminderOffsets ?? _availableReminderOffsets),
    };
    final Set<String> selected = <String>{...?existing?.emails};
    final List<String> available = <String>{
      ..._recipientDirectory,
    }.toList(growable: true)..sort();
    String? addEmailError;

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder:
            (
              BuildContext context,
              void Function(void Function()) setModalState,
            ) => AlertDialog(
              title: Text(existing == null ? 'Add reminder' : 'Edit reminder'),
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
                        decoration: const InputDecoration(
                          labelText: 'Reminder title',
                          hintText: 'e.g. Renew vehicle registration',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: category,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                        ),
                        items: _categories
                            .map(
                              (String value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (String? value) =>
                            setModalState(() => category = value ?? category),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: assetCode,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Asset / reference',
                          hintText: 'e.g. SMG 001',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: description,
                        textCapitalization: TextCapitalization.sentences,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Required action',
                          hintText: 'Describe what must be completed.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: priority,
                        decoration: const InputDecoration(
                          labelText: 'Priority',
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
                          labelText: 'Responsible person / team',
                          hintText: 'e.g. Maintenance Clerk',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: location,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Location',
                          hintText: 'e.g. Asam-Asam',
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_rounded),
                        title: const Text('Due date'),
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
                        'Automatic email schedule',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Emails are sent at 08:00 WITA on every selected day.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _availableReminderOffsets
                            .map(
                              (int offset) => FilterChip(
                                label: Text(_offsetLabel(offset)),
                                selected: selectedOffsets.contains(offset),
                                onSelected: (bool selected) =>
                                    setModalState(() {
                                      if (selected) {
                                        selectedOffsets.add(offset);
                                      } else if (selectedOffsets.length > 1) {
                                        selectedOffsets.remove(offset);
                                      }
                                    }),
                              ),
                            )
                            .toList(growable: false),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int?>(
                        initialValue: recurrenceMonths,
                        decoration: const InputDecoration(
                          labelText: 'Repeat after completion',
                        ),
                        items: const <DropdownMenuItem<int?>>[
                          DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Does not repeat'),
                          ),
                          DropdownMenuItem<int?>(
                            value: 1,
                            child: Text('Every month'),
                          ),
                          DropdownMenuItem<int?>(
                            value: 3,
                            child: Text('Every 3 months'),
                          ),
                          DropdownMenuItem<int?>(
                            value: 6,
                            child: Text('Every 6 months'),
                          ),
                          DropdownMenuItem<int?>(
                            value: 12,
                            child: Text('Every year'),
                          ),
                        ],
                        onChanged: (int? value) =>
                            setModalState(() => recurrenceMonths = value),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Email recipients',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tick every person who should receive this reminder.',
                      ),
                      const SizedBox(height: 8),
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
                                labelText: 'Add another email',
                                errorText: addEmailError,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: 'Add and select email',
                            icon: const Icon(Icons.person_add_alt_1_rounded),
                            onPressed: () {
                              final String email = addEmail.text
                                  .trim()
                                  .toLowerCase();
                              if (!_isValidEmail(email)) {
                                setModalState(
                                  () => addEmailError = 'Enter a valid email.',
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
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save'),
                ),
              ],
            ),
      ),
    );
    if (saved != true) {
      _disposeControllers(<TextEditingController>[
        title,
        assetCode,
        description,
        assignedTo,
        location,
        addEmail,
      ]);
      return;
    }
    try {
      final String cleanTitle = title.text.trim();
      final List<String> recipients = selected.toList()..sort();
      if (cleanTitle.isEmpty || recipients.isEmpty || selectedOffsets.isEmpty) {
        throw const FormatException(
          'Enter a title, tick at least one recipient, and choose an automatic email day.',
        );
      }
      final ReminderItem item = ReminderItem(
        id: existing?.id ?? '',
        title: cleanTitle,
        dueDate: dueDate,
        emails: recipients,
        category: category,
        assetCode: _cleanOptional(assetCode.text),
        description: _cleanOptional(description.text),
        priority: priority,
        assignedTo: _cleanOptional(assignedTo.text),
        location: _cleanOptional(location.text),
        status: existing?.status ?? 'open',
        reminderOffsets: selectedOffsets.toList()
          ..sort((int a, int b) => b.compareTo(a)),
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
        await _client.from('operational_reminder').insert(item.toPayload());
      } else {
        await _client
            .from('operational_reminder')
            .update(item.toPayload())
            .eq('id', existing.id);
      }
      await _load();
      if (mounted) {
        _message('Reminder saved. Automatic schedule is active at 08:00 WITA.');
      }
    } on Object catch (error) {
      if (mounted) _message('Unable to save reminder: $error');
    } finally {
      _disposeControllers(<TextEditingController>[
        title,
        assetCode,
        description,
        assignedTo,
        location,
        addEmail,
      ]);
    }
  }

  Future<void> _complete(ReminderItem item) async {
    final TextEditingController note = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Mark reminder as complete?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Complete "${item.title}"?'),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Completion note (optional)',
              ),
            ),
            if (item.recurrenceMonths != null) ...<Widget>[
              const SizedBox(height: 12),
              const Text(
                'A new recurring reminder will be created automatically.',
                style: TextStyle(color: AppColors.muted),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.task_alt_rounded),
            label: const Text('Mark complete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      note.dispose();
      return;
    }
    try {
      await _client
          .from('operational_reminder')
          .update(<String, Object?>{
            'status': 'completed',
            'completed_at': DateTime.now().toUtc().toIso8601String(),
            'completed_note': _cleanOptional(note.text),
          })
          .eq('id', item.id);
      if (item.recurrenceMonths case final int months) {
        final Map<String, Object?> next = item.toPayload()
          ..addAll(<String, Object?>{
            'due_date': _dateOnly(_addMonths(item.dueDate, months)),
            'status': 'open',
            'parent_reminder_id': item.id,
            'completed_at': null,
            'completed_note': null,
            'last_sent_at': null,
          });
        await _client.from('operational_reminder').insert(next);
      }
      await _load();
      if (mounted) {
        _message(
          item.recurrenceMonths == null
              ? 'Reminder marked as complete.'
              : 'Reminder completed and the next cycle was created.',
        );
      }
    } on Object catch (error) {
      if (mounted) _message('Unable to complete reminder: $error');
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
      if (mounted) _message('Reminder reopened.');
    } on Object catch (error) {
      if (mounted) _message('Unable to reopen reminder: $error');
    }
  }

  Future<void> _delete(ReminderItem item) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Delete reminder?'),
        content: Text('Delete "${item.title}" and its history?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _client.from('operational_reminder').delete().eq('id', item.id);
      await _load();
      if (mounted) _message('Reminder deleted.');
    } on Object catch (error) {
      if (mounted) _message('Unable to delete reminder: $error');
    }
  }

  Future<void> _sendEmail(ReminderItem item) async {
    setState(() => _sendingIds.add(item.id));
    try {
      final FunctionResponse response = await _client.functions.invoke(
        'send-reminder-email',
        body: <String, Object?>{'reminder_id': item.id},
      );
      final JsonMap data = requireJsonMap(
        response.data,
        source: 'send reminder email response',
      );
      if (data['ok'] != true) {
        throw FormatException(
          data.optionalString('error') ??
              'The email service rejected the request.',
        );
      }
      await _load();
      if (mounted) {
        _message('Email sent to ${item.emails.length} recipient(s).');
      }
    } on Object catch (error) {
      if (mounted) _message('Email was not sent: ${_emailFailure(error)}');
    } finally {
      if (mounted) setState(() => _sendingIds.remove(item.id));
    }
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
              'delivery_type,scheduled_offset_days,status,recipients,sent_at,error_message,created_at',
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
                          ? 'Automatic email · ${_offsetLabel(offset ?? 0)}'
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
        switch (_filter) {
          case _ReminderFilter.all:
            return true;
          case _ReminderFilter.actionRequired:
            return item.isOpen;
          case _ReminderFilter.completed:
            return item.isCompleted;
        }
      })
      .toList(growable: false);

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
  Widget build(BuildContext context) => AppBackScope(
    fallbackRoute: '/dashboard',
    child: Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/dashboard'),
        title: const Text('Reminders'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh reminders',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                children: <Widget>[
                  const Text(
                    'Operational follow-ups',
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Track action, ownership, delivery history, and due-date risk.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _edit(null),
                      icon: const Icon(Icons.add_alert_rounded),
                      label: const Text('Add reminder'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _summaryGrid(context),
                  const SizedBox(height: 18),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        _filterChip('All', _ReminderFilter.all),
                        const SizedBox(width: 8),
                        _filterChip(
                          'Action required',
                          _ReminderFilter.actionRequired,
                        ),
                        const SizedBox(width: 8),
                        _filterChip('Completed', _ReminderFilter.completed),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_visibleItems.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 50),
                      child: Text(
                        'No reminders in this view. Add a due date for servicing, documents, or any operational follow-up.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted),
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
  );

  Widget _summaryGrid(BuildContext context) {
    final double width = (MediaQuery.sizeOf(context).width - 52) / 2;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        _summaryTile(
          width,
          'Overdue',
          _overdueCount,
          AppColors.danger,
          Icons.warning_amber_rounded,
        ),
        _summaryTile(
          width,
          'Due soon',
          _dueSoonCount,
          AppColors.orange,
          Icons.schedule_rounded,
        ),
        _summaryTile(
          width,
          'Open',
          _openCount,
          AppColors.green,
          Icons.pending_actions_rounded,
        ),
        _summaryTile(
          width,
          'Completed',
          _completedCount,
          AppColors.muted,
          Icons.task_alt_rounded,
        ),
      ],
    );
  }

  Widget _summaryTile(
    double width,
    String label,
    int count,
    Color color,
    IconData icon,
  ) => SizedBox(
    width: width,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _filterChip(String label, _ReminderFilter value) => FilterChip(
    label: Text(label),
    selected: _filter == value,
    onSelected: (_) => setState(() => _filter = value),
  );

  Widget _reminderCard(ReminderItem item) {
    final bool sending = _sendingIds.contains(item.id);
    final int days = _daysUntil(item.dueDate);
    final Color statusColor = _statusColor(item, days);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
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
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.history_rounded),
                  tooltip: 'Reminder history',
                  onPressed: () => _showHistory(item),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit reminder',
                  onPressed: () => _edit(item),
                ),
                PopupMenuButton<_ReminderMenuAction>(
                  tooltip: 'More actions',
                  onSelected: (_ReminderMenuAction action) {
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
                              'Delete reminder',
                              style: TextStyle(color: AppColors.danger),
                            ),
                          ),
                        ),
                      ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            _infoRow(
              Icons.event_rounded,
              item.isCompleted ? 'Completed' : 'Due',
              item.isCompleted
                  ? _prettyDate(item.completedAt ?? item.dueDate)
                  : '${_dueLabel(item, days)} · ${_prettyDate(item.dueDate)}',
              statusColor,
            ),
            _infoRow(
              Icons.category_outlined,
              'Category',
              '${item.category}${item.assetCode == null ? '' : ' · ${item.assetCode}'}',
            ),
            if (item.assignedTo != null)
              _infoRow(
                Icons.person_outline_rounded,
                'Responsible',
                item.assignedTo!,
              ),
            if (item.location != null)
              _infoRow(Icons.location_on_outlined, 'Location', item.location!),
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
            const SizedBox(height: 12),
            Text(
              'Recipients · ${item.emails.length} person(s)',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              item.emails.join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 10),
            Text(
              'Automatic email · ${item.reminderOffsets.map(_offsetLabel).join(', ')} · 08:00 WITA',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            if (item.lastSentAt != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'Last email · ${_prettyDateTime(item.lastSentAt!)}',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
            if (item.isCompleted && item.completedNote != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Completion note · ${item.completedNote}',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                if (item.isOpen)
                  OutlinedButton.icon(
                    onPressed: () => _complete(item),
                    icon: const Icon(Icons.task_alt_rounded),
                    label: const Text('Mark complete'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => _reopen(item),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Reopen'),
                  ),
                if (item.isOpen)
                  FilledButton.icon(
                    onPressed: sending ? null : () => _sendEmail(item),
                    icon: sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(sending ? 'Sending...' : 'Send email now'),
                  ),
              ],
            ),
          ],
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

DateTime _addMonths(DateTime date, int months) {
  final int targetMonth = date.month + months;
  final DateTime lastDay = DateTime(date.year, targetMonth + 1, 0);
  return DateTime(date.year, targetMonth, min(date.day, lastDay.day));
}

String _dateOnly(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

String _prettyDate(DateTime date) => DateFormat('dd MMM yyyy').format(date);

String _prettyDateTime(DateTime date) =>
    DateFormat('dd MMM yyyy, HH:mm').format(date);

String _sentenceCase(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

String _priorityLabel(String priority) => switch (priority) {
  'low' => 'Low',
  'high' => 'High',
  'critical' => 'Critical',
  _ => 'Normal',
};

Color _priorityColor(String priority) => switch (priority) {
  'critical' => AppColors.danger,
  'high' => AppColors.orange,
  'low' => AppColors.muted,
  _ => AppColors.green,
};

String _offsetLabel(int days) => switch (days) {
  0 => 'Due date',
  1 => 'H-1',
  _ => 'H-$days',
};

Color _statusColor(ReminderItem item, int days) {
  if (item.isCompleted) return AppColors.green;
  if (item.status == 'cancelled') return AppColors.muted;
  if (days < 0) return AppColors.danger;
  if (days <= 7) return AppColors.orange;
  return AppColors.green;
}

String _statusLabel(ReminderItem item, int days) {
  if (item.isCompleted) return 'Completed';
  if (item.status == 'cancelled') return 'Cancelled';
  if (days < 0) return 'Overdue';
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  if (days <= 7) return 'Due soon';
  return 'Upcoming';
}

String _dueLabel(ReminderItem item, int days) {
  if (days < 0) return 'Overdue by ${-days} day(s)';
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  return 'Due in $days days';
}
