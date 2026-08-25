import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../data/models/sicatat_types.dart';

class ReminderItem {
  const ReminderItem({
    required this.id,
    required this.title,
    required this.dueDate,
    required this.emails,
  });

  final String id;
  final String title;
  final DateTime dueDate;
  final List<String> emails;

  factory ReminderItem.fromJson(JsonMap json) {
    final Object? rawEmails = json['recipient_emails'];
    if (rawEmails is! List) {
      throw const FormatException('Reminder recipients are invalid.');
    }
    final List<String> emails = rawEmails
        .map((Object? email) {
          if (email is! String) {
            throw const FormatException('Reminder email must be text.');
          }
          return email.trim().toLowerCase();
        })
        .where((String email) => email.contains('@'))
        .toSet()
        .toList(growable: false);
    return ReminderItem(
      id: json.requiredString('id'),
      title: json.requiredString('title'),
      dueDate: DateTime.parse(json.requiredString('due_date')),
      emails: emails,
    );
  }

  Map<String, Object?> toPayload() => <String, Object?>{
    'title': title,
    'due_date': _dateOnly(dueDate),
    'recipient_emails': emails,
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
            .select('id,title,due_date,recipient_emails')
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
    final TextEditingController addEmail = TextEditingController();
    DateTime dueDate = existing?.dueDate ?? DateTime.now();
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
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TextField(
                        controller: title,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Reminder title',
                          hintText: 'e.g. Renew vehicle registration',
                        ),
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
                      if (available.isEmpty)
                        const Text(
                          'Add an email address below to create a recipient.',
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
                      const SizedBox(height: 4),
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
                      const SizedBox(height: 14),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_rounded),
                        title: const Text('Due date'),
                        subtitle: Text(_dateOnly(dueDate)),
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
      title.dispose();
      addEmail.dispose();
      return;
    }
    try {
      final String cleanTitle = title.text.trim();
      final List<String> recipients = selected.toList()..sort();
      if (cleanTitle.isEmpty || recipients.isEmpty) {
        throw const FormatException(
          'Enter a title and tick at least one email recipient.',
        );
      }
      final ReminderItem item = ReminderItem(
        id: existing?.id ?? '',
        title: cleanTitle,
        dueDate: dueDate,
        emails: recipients,
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
        _message('Reminder saved. Tap Send email to deliver it now.');
      }
    } on Object catch (error) {
      if (mounted) _message('Unable to save reminder: $error');
    } finally {
      title.dispose();
      addEmail.dispose();
    }
  }

  Future<void> _delete(ReminderItem item) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Delete reminder?'),
        content: Text('Delete "${item.title}"?'),
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
      if (mounted) {
        _message('Email sent to ${item.emails.length} recipient(s).');
      }
    } on Object catch (error) {
      if (mounted) _message('Email was not sent: ${_emailFailure(error)}');
    } finally {
      if (mounted) setState(() => _sendingIds.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) => AppBackScope(
    fallbackRoute: '/dashboard',
    child: Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/dashboard'),
        title: const Text('Reminders'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _edit(null),
        icon: const Icon(Icons.add_alert_rounded),
        label: const Text('Add reminder'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'No reminders yet. Add a due date for vehicle documents, servicing, or any other item.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, int index) {
                final ReminderItem item = _items[index];
                final bool sending = _sendingIds.contains(item.id);
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Padding(
                              padding: EdgeInsets.only(right: 12, top: 2),
                              child: Icon(
                                Icons.notifications_active_rounded,
                                color: AppColors.green,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                item.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Edit reminder',
                              onPressed: () => _edit(item),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded),
                              tooltip: 'Delete reminder',
                              onPressed: () => _delete(item),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Due date · ${_dateOnly(item.dueDate)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.emails.length} selected recipient(s): ${item.emails.join(', ')}',
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: sending ? null : () => _sendEmail(item),
                            icon: sending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded),
                            label: Text(
                              sending ? 'Sending email...' : 'Send email now',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    ),
  );
}

String _dateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
