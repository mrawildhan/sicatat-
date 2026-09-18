import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../daily_check_forms.dart';
import '../daily_check_repository.dart';
import 'daily_check_widgets.dart';

/// Data master → Batas & peringatan suhu: per-point limits of the daily
/// check sheets and who is emailed when a critical temperature is recorded.
class DailyCheckSettingsScreen extends StatefulWidget {
  const DailyCheckSettingsScreen({super.key});

  @override
  State<DailyCheckSettingsScreen> createState() =>
      _DailyCheckSettingsScreenState();
}

class _DailyCheckSettingsScreenState extends State<DailyCheckSettingsScreen> {
  final DailyCheckRepository _repository = DailyCheckRepository();
  List<AlertRecipient> _recipients = const <AlertRecipient>[];
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
      await _repository.loadThresholds();
      final recipients = await _repository.alertRecipients();
      if (mounted) setState(() => _recipients = recipients);
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Data tidak dapat dimuat: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _notice(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _addRecipient() async {
    final email = TextEditingController();
    final name = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tambah penerima'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: name,
              decoration: const InputDecoration(
                labelText: 'Nama / jabatan (opsional)',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    final address = email.text.trim();
    final label = name.text;
    email.dispose();
    name.dispose();
    if (saved != true) return;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(address)) {
      _notice('Alamat email tidak valid.');
      return;
    }
    try {
      await _repository.addAlertRecipient(address, label);
      await _load();
    } on Object catch (error) {
      _notice(error.toString());
    }
  }

  Future<void> _editLimits(
    DailyCheckFormType type,
    DailyCheckField field,
  ) async {
    final current = DailyCheckThresholds.of(type, field.key);
    final warning = TextEditingController(text: formatReading(current.warning));
    final critical = TextEditingController(
      text: formatReading(current.critical),
    );
    final formatter = FilteringTextInputFormatter.allow(
      RegExp(r'^-?\d*[.,]?\d*'),
    );
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(field.label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(type.form.title, style: AppTextStyles.supporting),
            const SizedBox(height: 12),
            TextField(
              controller: warning,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              inputFormatters: <TextInputFormatter>[formatter],
              decoration: const InputDecoration(
                labelText: 'Waspada mulai (°C)',
                helperText: 'Warna kuning/oranye',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: critical,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              inputFormatters: <TextInputFormatter>[formatter],
              decoration: const InputDecoration(
                labelText: 'Kritis mulai (°C)',
                helperText: 'Warna merah dan email peringatan',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          if (DailyCheckThresholds.isCustom(type, field.key))
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'reset'),
              child: const Text('Kembalikan 60/70'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    final warningValue = double.tryParse(warning.text.replaceAll(',', '.'));
    final criticalValue = double.tryParse(critical.text.replaceAll(',', '.'));
    warning.dispose();
    critical.dispose();
    try {
      if (action == 'reset') {
        await _repository.resetThreshold(type, field.key);
      } else if (action == 'save') {
        if (warningValue == null ||
            criticalValue == null ||
            warningValue >= criticalValue ||
            warningValue < minPlausibleTemperature ||
            criticalValue > maxPlausibleTemperature) {
          _notice(
            'Isi dua angka antara -50 dan 250 °C; batas waspada harus lebih '
            'kecil dari batas kritis.',
          );
          return;
        }
        await _repository.saveThreshold(
          type,
          field.key,
          DailyCheckLimits(warningValue, criticalValue),
        );
      } else {
        return;
      }
      await _load();
      _notice('Batas suhu tersimpan.');
    } on Object catch (error) {
      _notice(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AppBackScope(
    fallbackRoute: '/admin',
    child: Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackRoute: '/admin'),
        title: const Text('Batas & peringatan suhu'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                children: <Widget>[
                  if (_error case final error?) ...<Widget>[
                    DailyCheckNotice(error, error: true),
                    const SizedBox(height: 12),
                  ],
                  _recipientsSection(),
                  const SizedBox(height: 24),
                  for (final type in DailyCheckFormType.values) ...<Widget>[
                    _limitsSection(type),
                    const SizedBox(height: 20),
                  ],
                ],
              ),
            ),
    ),
  );

  Widget _recipientsSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Row(
        children: <Widget>[
          const Expanded(
            child: Text(
              'Penerima peringatan suhu kritis',
              style: AppTextStyles.sectionTitle,
            ),
          ),
          TextButton.icon(
            onPressed: _addRecipient,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Tambah'),
          ),
        ],
      ),
      const Text(
        'Setiap 5 menit SICATAT memeriksa pembacaan baru. Suhu yang mencapai '
        'batas kritis di ketiga lembar Suhu dikirim sekali ke email di bawah.',
        style: AppTextStyles.supporting,
      ),
      const SizedBox(height: 10),
      if (_recipients.isEmpty)
        const DailyCheckNotice(
          'Belum ada penerima. Tambahkan email foreman atau supervisor agar '
          'peringatan suhu kritis terkirim.',
        )
      else
        for (final recipient in _recipients)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                Icons.mail_outline_rounded,
                color: recipient.isActive ? AppColors.green : AppColors.muted,
              ),
              title: Text(recipient.email),
              subtitle: Text(
                '${recipient.name ?? 'Tanpa nama'}'
                '${recipient.isActive ? '' : ' · nonaktif'}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Switch(
                    value: recipient.isActive,
                    onChanged: (value) async {
                      await _repository.setAlertRecipientActive(
                        recipient.id,
                        value,
                      );
                      await _load();
                    },
                  ),
                  IconButton(
                    tooltip: 'Hapus penerima',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () async {
                      await _repository.removeAlertRecipient(recipient.id);
                      await _load();
                    },
                  ),
                ],
              ),
            ),
          ),
    ],
  );

  Widget _limitsSection(DailyCheckFormType type) {
    final fields = type.form.fields
        .where((field) => field.kind == DailyCheckValueKind.temperature)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Batas suhu · ${type.form.title}',
          style: AppTextStyles.sectionTitle,
        ),
        const SizedBox(height: 4),
        const Text(
          'Bawaan 60 °C waspada dan 70 °C kritis. Ketuk titik untuk memakai '
          'batas lain, misalnya sesuai manual OEM.',
          style: AppTextStyles.supporting,
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              for (final field in fields)
                ListTile(
                  dense: true,
                  title: Text(field.label),
                  subtitle: Text(
                    'Waspada ${formatReading(DailyCheckThresholds.of(type, field.key).warning)} °C · '
                    'Kritis ${formatReading(DailyCheckThresholds.of(type, field.key).critical)} °C',
                  ),
                  trailing: DailyCheckThresholds.isCustom(type, field.key)
                      ? const Chip(label: Text('Khusus'))
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: () => _editLimits(type, field),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
