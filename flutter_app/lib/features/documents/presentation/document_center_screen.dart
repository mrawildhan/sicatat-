import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';

class DocumentCenterScreen extends StatefulWidget {
  const DocumentCenterScreen({super.key});

  @override
  State<DocumentCenterScreen> createState() => _DocumentCenterScreenState();
}

class _DocumentCenterScreenState extends State<DocumentCenterScreen> {
  final TextEditingController _question = TextEditingController();
  _DocumentAnswer? _answer;
  bool _asking = false;

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _open(Uri link) async {
    final bool opened = await launchUrl(
      link,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tautan dokumen tidak dapat dibuka.')),
      );
    }
  }

  Future<void> _ask() async {
    final String question = _question.text.trim();
    if (question.length < 4 || _asking) return;
    setState(() {
      _asking = true;
      _answer = null;
    });
    try {
      final FunctionResponse response = await Supabase.instance.client.functions
          .invoke(
            'ask-technical-documents',
            body: <String, Object>{'question': question},
          )
          .timeout(const Duration(seconds: 70));
      final Object? raw = response.data;
      if (raw is! Map<Object?, Object?>) {
        throw const FormatException('Respons Pusat Dokumen tidak valid.');
      }
      if (raw['ok'] != true) {
        throw StateError(
          raw['error']?.toString() ?? 'Pencarian dokumen gagal.',
        );
      }
      if (!mounted) return;
      setState(() => _answer = _DocumentAnswer.fromJson(raw));
    } on TimeoutException {
      _showMessage(
        'Pencarian terlalu lama. Silakan coba pertanyaan yang lebih singkat.',
      );
    } on Object catch (error) {
      _showMessage(error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  void _showMessage(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final bool useDesktopHeader =
        kIsWeb && MediaQuery.sizeOf(context).width >= 920;
    return Scaffold(
      appBar: useDesktopHeader
          ? null
          : AppBar(
              leading: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Kembali',
              ),
              title: const Text('Pusat Dokumen'),
              actions: <Widget>[
                IconButton(
                  onPressed: () =>
                      _open(Uri.parse(AppConfig.technicalDocumentsFolderUrl)),
                  icon: const Icon(Icons.open_in_new_rounded),
                  tooltip: 'Buka folder Google Drive',
                ),
                const SizedBox(width: 8),
              ],
            ),
      body: Column(
        children: <Widget>[
          if (useDesktopHeader)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Pusat Dokumen',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.mint,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppColors.green.withValues(alpha: .2),
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.verified_user_outlined,
                        color: AppColors.green,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Jawaban hanya dari folder dokumen',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            SizedBox(height: 5),
                            Text(
                              'AI hanya membaca file yang berada di folder Google Drive ini. Setiap jawaban menyertakan file sumbernya.',
                              style: TextStyle(
                                color: AppColors.greenDark,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Tanya dokumen',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Contoh: Berapa minimal orang untuk pekerjaan sandblasting?',
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _question,
                  minLines: 2,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _ask(),
                  decoration: InputDecoration(
                    hintText: 'Tulis pertanyaan tentang SOP, izin kerja, JSEA, manual, atau drawing',
                    alignLabelWithHint: true,
                    suffixIcon: IconButton(
                      onPressed: _asking ? null : _ask,
                      icon: const Icon(Icons.send_rounded),
                      tooltip: 'Tanya dokumen',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _asking ? null : _ask,
                  icon: _asking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_rounded),
                  label: Text(_asking ? 'Mencari di dokumen…' : 'Cari jawaban'),
                ),
                const SizedBox(height: 16),
                if (_answer != null)
                  _AnswerCard(answer: _answer!, onOpen: _open),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () =>
                      _open(Uri.parse(AppConfig.technicalDocumentsFolderUrl)),
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text(
                    'Lihat dan unduh semua file di Google Drive',
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

class _DocumentAnswer {
  const _DocumentAnswer({
    required this.answer,
    required this.sourcesScanned,
    required this.citations,
  });

  final String answer;
  final int sourcesScanned;
  final List<_DocumentCitation> citations;

  factory _DocumentAnswer.fromJson(Map<Object?, Object?> json) {
    final Object? rawCitations = json['citations'];
    return _DocumentAnswer(
      answer: json['answer']?.toString() ?? 'Jawaban belum tersedia.',
      sourcesScanned:
          int.tryParse(json['sources_scanned']?.toString() ?? '') ?? 0,
      citations: rawCitations is List
          ? rawCitations
                .whereType<Map<Object?, Object?>>()
                .map(_DocumentCitation.fromJson)
                .toList(growable: false)
          : const <_DocumentCitation>[],
    );
  }
}

class _DocumentCitation {
  const _DocumentCitation({
    required this.name,
    required this.url,
    this.excerpt,
  });

  final String name;
  final String url;
  final String? excerpt;

  factory _DocumentCitation.fromJson(Map<Object?, Object?> json) =>
      _DocumentCitation(
        name: json['name']?.toString() ?? 'Dokumen sumber',
        url: json['url']?.toString() ?? '',
        excerpt: json['excerpt']?.toString(),
      );
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.answer, required this.onOpen});

  final _DocumentAnswer answer;
  final Future<void> Function(Uri link) onOpen;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.auto_awesome_rounded, color: AppColors.green),
              SizedBox(width: 10),
              Text('Jawaban AI', style: TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 12),
          Text(answer.answer, style: const TextStyle(height: 1.5)),
          const SizedBox(height: 14),
          Text(
            answer.sourcesScanned > 0
                ? 'File yang diperiksa: ${answer.sourcesScanned}'
                : 'Tidak ada file yang dapat diperiksa untuk pertanyaan ini.',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          if (answer.citations.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            const Text('Sumber', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            for (final _DocumentCitation citation in answer.citations)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.description_outlined,
                  color: AppColors.green,
                ),
                title: Text(citation.name),
                subtitle: citation.excerpt == null || citation.excerpt!.isEmpty
                    ? null
                    : Text(citation.excerpt!),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: citation.url.isEmpty
                    ? null
                    : () => onOpen(Uri.parse(citation.url)),
              ),
          ],
        ],
      ),
    ),
  );
}
