import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../data/local/local_database.dart';
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
    final Object? rawEmails = json['emails'];
    final List<String> emails;
    if (rawEmails is String) {
      emails = rawEmails
          .split(RegExp(r'[,;\s]+'))
          .where((String email) => email.contains('@'))
          .toList(growable: false);
    } else if (rawEmails is List) {
      emails = rawEmails
          .map((Object? item) {
            if (item is! String) {
              throw const FormatException('Reminder email must be text.');
            }
            return item;
          })
          .where((String email) => email.contains('@'))
          .toList(growable: false);
    } else {
      throw const FormatException('Reminder recipients are invalid.');
    }
    return ReminderItem(
      id: json.requiredString('id'),
      title: json.requiredString('title'),
      dueDate: DateTime.parse(json.requiredString('date')),
      emails: emails,
    );
  }
  JsonMap toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'date': dueDate.toIso8601String(),
    'emails': emails,
  };
}

class ReminderScreen extends StatefulWidget {
  const ReminderScreen({super.key});
  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen> {
  List<ReminderItem> _items = const <ReminderItem>[];
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _load() async {
    try {
      final Database db = await LocalDatabase.instance.database;
      final List<Map<String, Object?>> rows = await db.query(
        'cache_app_config',
        columns: const <String>['data'],
        where: 'id = ?',
        whereArgs: const <Object?>['reminders'],
      );
      if (rows.isEmpty) return;
      final Object? rawData = rows.single['data'];
      if (rawData is! String) {
        throw const FormatException('Saved reminder data is invalid.');
      }
      final Object? rawItems = jsonDecode(rawData);
      if (rawItems is! List) {
        throw const FormatException('Saved reminder list is invalid.');
      }
      final List<ReminderItem> items =
          rawItems
              .map(
                (Object? rawItem) => ReminderItem.fromJson(
                  requireJsonMap(rawItem, source: 'reminder'),
                ),
              )
              .toList(growable: false)
            ..sort(
              (ReminderItem left, ReminderItem right) =>
                  left.dueDate.compareTo(right.dueDate),
            );
      if (mounted) setState(() => _items = items);
    } on Object catch (error) {
      if (mounted) _message('Unable to load reminders: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final Database db = await LocalDatabase.instance.database;
    await db.insert('cache_app_config', <String, Object?>{
      'id': 'reminders',
      'data': jsonEncode(
        _items
            .map((ReminderItem item) => item.toJson())
            .toList(growable: false),
      ),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _edit(ReminderItem? existing) async {
    final TextEditingController title = TextEditingController(
      text: existing?.title ?? '',
    );
    final TextEditingController emails = TextEditingController(
      text: existing?.emails.join(', ') ?? '',
    );
    DateTime dueDate = existing?.dueDate ?? DateTime.now();
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder:
            (
              BuildContext context,
              void Function(void Function()) setModalState,
            ) => AlertDialog(
              title: Text(existing == null ? 'Add reminder' : 'Edit reminder'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextField(
                      controller: title,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emails,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Recipient emails (separate with commas)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Due date'),
                      subtitle: Text(_date(dueDate)),
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
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Save'),
                ),
              ],
            ),
      ),
    );
    if (saved != true) {
      title.dispose();
      emails.dispose();
      return;
    }
    try {
      final String cleanTitle = title.text.trim();
      final List<String> recipients = emails.text
          .split(RegExp(r'[,;\s]+'))
          .map((String value) => value.trim())
          .where((String value) => value.contains('@'))
          .toSet()
          .toList(growable: false);
      if (cleanTitle.isEmpty || recipients.isEmpty) {
        throw const FormatException(
          'A title and at least one valid email are required.',
        );
      }
      final ReminderItem item = ReminderItem(
        id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        title: cleanTitle,
        dueDate: dueDate,
        emails: recipients,
      );
      final List<ReminderItem> updated =
          <ReminderItem>[
            for (final ReminderItem current in _items)
              if (current.id != item.id) current,
            item,
          ]..sort(
            (ReminderItem left, ReminderItem right) =>
                left.dueDate.compareTo(right.dueDate),
          );
      setState(() => _items = updated);
      await _save();
    } on Object catch (error) {
      if (mounted) _message('Unable to save reminder: $error');
    } finally {
      title.dispose();
      emails.dispose();
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
    setState(
      () => _items = _items
          .where((ReminderItem current) => current.id != item.id)
          .toList(growable: false),
    );
    await _save();
  }

  Future<void> _mail(ReminderItem item) async {
    final Uri uri = Uri(
      scheme: 'mailto',
      path: item.emails.join(','),
      queryParameters: <String, String>{
        'subject': 'SICATAT reminder: ${item.title}',
        'body': '${item.title} is due on ${_date(item.dueDate)}.',
      },
    );
    if (!await launchUrl(uri) && mounted) {
      _message('No email application is available.');
    }
  }

  String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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
              child: Text(
                'No reminders yet. Add a due date for vehicle documents, servicing, or any other item.',
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, int index) {
                final ReminderItem item = _items[index];
                return Card(
                  child: ListTile(
                    onTap: () => _edit(item),
                    leading: const Icon(
                      Icons.notifications_active_rounded,
                      color: AppColors.green,
                    ),
                    title: Text(
                      item.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${_date(item.dueDate)} · ${item.emails.join(', ')}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(
                          icon: const Icon(Icons.email_outlined),
                          tooltip: 'Compose email',
                          onPressed: () => _mail(item),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded),
                          tooltip: 'Delete reminder',
                          onPressed: () => _delete(item),
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
