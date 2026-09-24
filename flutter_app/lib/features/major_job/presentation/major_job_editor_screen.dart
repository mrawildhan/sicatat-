import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../../../data/reports/meeting_minute_photo_compressor.dart';
import '../major_job_api.dart';
import '../major_job_models.dart';
import 'major_job_photo_view.dart';

/// Same limit as the Worker (`MAX_PHOTOS_PER_JOB`): eight photos still fit on
/// one PDF page inside a single table row.
const int majorJobMaxPhotos = 8;

/// Printed 5.4 cm wide, so 1200 px is ample; ~200 KB keeps the 1 GB
/// Cloudflare KV namespace good for a few thousand photos.
const int _photoMaxDimension = 1200;
const int _photoTargetBytes = 200 * 1024;

class MajorJobEditorScreen extends StatefulWidget {
  const MajorJobEditorScreen({
    this.jobId,
    this.initialDate,
    this.api,
    super.key,
  });

  /// Null for a new job.
  final String? jobId;
  final DateTime? initialDate;
  final MajorJobApi? api;

  @override
  State<MajorJobEditorScreen> createState() => _MajorJobEditorScreenState();
}

class _MajorJobEditorScreenState extends State<MajorJobEditorScreen> {
  late final MajorJobApi _api = widget.api ?? MajorJobApi();
  final TextEditingController _description = TextEditingController();
  MajorJob? _job;
  late DateTime _date = majorJobDateOnly(widget.initialDate ?? DateTime.now());
  bool _loading = false;
  bool _saving = false;
  String? _loadError;
  String? _uploadProgress;

  bool get _isNew => widget.jobId == null;

  String get _backRoute =>
      '/major-job?month=${_date.year}-${_date.month.toString().padLeft(2, '0')}';

  bool get _dirty {
    final MajorJob? job = _job;
    if (job == null) return _description.text.trim().isNotEmpty;
    return job.description != _cleanDescription ||
        majorJobDateOnly(job.workDate) != _date;
  }

  String get _cleanDescription =>
      _description.text.trim().replaceAll(RegExp(r'\s+'), ' ');

  @override
  void initState() {
    super.initState();
    _description.addListener(() => setState(() {}));
    if (!_isNew) _load();
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final MajorJob job = await _api.get(widget.jobId!);
      if (!mounted) return;
      setState(() {
        _job = job;
        _date = majorJobDateOnly(job.workDate);
        _description.text = job.description;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error is MajorJobApiException
            ? error.message
            : 'Pekerjaan gagal dimuat.';
        _loading = false;
      });
    }
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  String _errorText(Object error, String fallback) =>
      error is MajorJobApiException ? error.message : '$fallback: $error';

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 366)),
      helpText: 'Tanggal pekerjaan',
    );
    if (picked != null) setState(() => _date = majorJobDateOnly(picked));
  }

  Future<void> _save() async {
    final String description = _cleanDescription;
    if (description.isEmpty) {
      _toast('Deskripsi pekerjaan wajib diisi.');
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isNew) {
        final MajorJob created = await _api.create(
          workDate: _date,
          description: description,
        );
        if (!mounted) return;
        // Photos belong to a saved job, so continue on its own page.
        context.go('/major-job/job/${created.id}');
        return;
      }
      final MajorJob job = _job!;
      await _api.update(
        job.id,
        workDate: majorJobDateOnly(job.workDate) == _date ? null : _date,
        description: job.description == description ? null : description,
      );
      if (!mounted) return;
      setState(() {
        _job = MajorJob(
          id: job.id,
          workDate: _date,
          description: description,
          createdBy: job.createdBy,
          photos: job.photos,
        );
        _description.text = description;
      });
      _toast('Perubahan disimpan.');
    } on Object catch (error) {
      if (mounted) _toast(_errorText(error, 'Gagal menyimpan'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addPhotos() async {
    final MajorJob? job = _job;
    if (job == null) return;
    final int room = majorJobMaxPhotos - job.photos.length;
    if (room <= 0) {
      _toast('Satu pekerjaan maksimal $majorJobMaxPhotos foto.');
      return;
    }
    final FilePickerResult? picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['jpg', 'jpeg', 'png'],
      allowMultiple: true,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty || !mounted) return;
    final List<PlatformFile> files = picked.files.take(room).toList();
    final List<String> failures = <String>[];
    if (picked.files.length > room) {
      failures.add(
        '${picked.files.length - room} foto tidak diunggah (maks. $majorJobMaxPhotos per pekerjaan)',
      );
    }
    for (int i = 0; i < files.length; i++) {
      final PlatformFile file = files[i];
      final Uint8List? bytes = file.bytes;
      if (bytes == null) {
        failures.add('${file.name}: file tidak dapat dibaca');
        continue;
      }
      setState(() => _uploadProgress = 'Memproses foto ${i + 1}/${files.length}…');
      // Let the progress text paint before the CPU-heavy compression.
      await Future<void>.delayed(const Duration(milliseconds: 16));
      try {
        final CompressedMeetingMinutePhoto compressed =
            MeetingMinutePhotoCompressor.compress(
              bytes: bytes,
              fileName: file.name,
              maxDimension: _photoMaxDimension,
              targetBytes: _photoTargetBytes,
            );
        if (!mounted) return;
        setState(() => _uploadProgress = 'Mengunggah foto ${i + 1}/${files.length}…');
        final MajorJobPhoto photo = await _api.uploadPhoto(
          job.id,
          compressed.bytes,
          compressed.mimeType,
        );
        if (!mounted) return;
        setState(() => _job = _job!.copyWith(
          photos: <MajorJobPhoto>[..._job!.photos, photo],
        ));
      } on FormatException catch (error) {
        failures.add('${file.name}: ${error.message}');
      } on Object catch (error) {
        failures.add('${file.name}: ${_errorText(error, 'gagal diunggah')}');
      }
    }
    if (!mounted) return;
    setState(() => _uploadProgress = null);
    if (failures.isNotEmpty) _toast(failures.join('\n'));
  }

  Future<void> _move(int index, int delta) async {
    final MajorJob job = _job!;
    final List<MajorJobPhoto> previous = job.photos;
    final List<MajorJobPhoto> reordered = <MajorJobPhoto>[...previous];
    final MajorJobPhoto moved = reordered.removeAt(index);
    reordered.insert(index + delta, moved);
    setState(() => _job = job.copyWith(photos: reordered));
    try {
      await _api.reorderPhotos(job.id, <String>[
        for (final MajorJobPhoto photo in reordered) photo.id,
      ]);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _job = _job!.copyWith(photos: previous));
      _toast(_errorText(error, 'Urutan gagal disimpan'));
    }
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _deletePhoto(MajorJobPhoto photo) async {
    if (!await _confirm('Hapus foto?', 'Foto ini akan dihapus permanen.', 'Hapus')) {
      return;
    }
    try {
      await _api.deletePhoto(photo.id);
      if (!mounted) return;
      setState(() => _job = _job!.copyWith(
        photos: _job!.photos.where((p) => p.id != photo.id).toList(),
      ));
    } on Object catch (error) {
      if (mounted) _toast(_errorText(error, 'Foto gagal dihapus'));
    }
  }

  Future<void> _deleteJob() async {
    final MajorJob job = _job!;
    final bool confirmed = await _confirm(
      'Hapus pekerjaan?',
      'Pekerjaan ini beserta ${job.photos.length} fotonya akan dihapus permanen.',
      'Hapus',
    );
    if (!confirmed) return;
    setState(() => _saving = true);
    try {
      await _api.delete(job.id);
      if (mounted) context.go(_backRoute);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(_errorText(error, 'Pekerjaan gagal dihapus'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final MajorJob? job = _job;
    final bool busy = _saving || _uploadProgress != null;
    return AppBackScope(
      fallbackRoute: _backRoute,
      child: Scaffold(
        appBar: AppBar(
          leading: AppBackButton(fallbackRoute: _backRoute),
          title: Text(
            _isNew ? 'Pekerjaan baru' : 'Ubah pekerjaan',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: <Widget>[
            if (job != null)
              IconButton(
                tooltip: 'Hapus pekerjaan',
                onPressed: busy ? null : _deleteJob,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            const SizedBox(width: 4),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(_loadError!, textAlign: TextAlign.center),
                      TextButton(onPressed: _load, child: const Text('Coba lagi')),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
                children: <Widget>[
                  const Text('Tanggal pekerjaan', style: AppTextStyles.sectionTitle),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: busy ? null : _pickDate,
                    icon: const Icon(Icons.event_rounded),
                    label: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(majorJobDayLabel(_date)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Masuk subjudul ${majorJobPeriodsOfMonth(_date.year, _date.month).firstWhere((p) => p.contains(_date)).label}',
                    style: AppTextStyles.supporting,
                  ),
                  const SizedBox(height: 18),
                  const Text('Deskripsi pekerjaan', style: AppTextStyles.sectionTitle),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _description,
                    enabled: !busy,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Contoh: Fabrikasi lower chute sizer to CV12',
                    ),
                  ),
                  const SizedBox(height: 6),
                  FilledButton.icon(
                    onPressed: busy || !_dirty ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(_isNew ? Icons.arrow_forward_rounded : Icons.save_outlined),
                    label: Text(_isNew ? 'Simpan & lanjut tambah foto' : 'Simpan perubahan'),
                  ),
                  if (job != null) ...<Widget>[
                    const SizedBox(height: 26),
                    Text(
                      'Foto (${job.photos.length}/$majorJobMaxPhotos)',
                      style: AppTextStyles.sectionTitle,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Foto tampil persis seperti potongan di PDF: landscape 5,4 × 3,6 cm, '
                      'portrait 2,4 × 3,6 cm. Urutan di sini = urutan di PDF.',
                      style: AppTextStyles.supporting,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: <Widget>[
                        for (int i = 0; i < job.photos.length; i++)
                          _PhotoTile(
                            api: _api,
                            photo: job.photos[i],
                            onLeft: busy || i == 0 ? null : () => _move(i, -1),
                            onRight: busy || i == job.photos.length - 1
                                ? null
                                : () => _move(i, 1),
                            onDelete: busy ? null : () => _deletePhoto(job.photos[i]),
                          ),
                        if (job.photos.length < majorJobMaxPhotos)
                          _AddPhotoTile(
                            progress: _uploadProgress,
                            onTap: busy ? null : _addPhotos,
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

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.api,
    required this.photo,
    required this.onLeft,
    required this.onRight,
    required this.onDelete,
  });

  static const double height = 108;

  final MajorJobApi api;
  final MajorJobPhoto photo;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      MajorJobPhotoView(api: api, photo: photo, height: height),
      SizedBox(
        width: MajorJobPhotoView.widthFor(photo, height).clamp(108, 200),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _smallButton(Icons.chevron_left_rounded, 'Geser ke kiri', onLeft),
            _smallButton(Icons.delete_outline_rounded, 'Hapus foto', onDelete),
            _smallButton(Icons.chevron_right_rounded, 'Geser ke kanan', onRight),
          ],
        ),
      ),
    ],
  );

  Widget _smallButton(IconData icon, String tooltip, VoidCallback? onTap) =>
      IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        onPressed: onTap,
        icon: Icon(icon),
      );
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.progress, required this.onTap});

  final String? progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: MajorJobPhotoView.widthFor(
      const MajorJobPhoto(
        id: '',
        position: 0,
        mimeType: 'image/jpeg',
        width: 3,
        height: 2,
        sizeBytes: 0,
      ),
      _PhotoTile.height,
    ),
    height: _PhotoTile.height,
    child: OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      onPressed: onTap,
      child: progress == null
          ? const Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.add_photo_alternate_outlined),
                SizedBox(height: 4),
                Text('Tambah foto', textAlign: TextAlign.center),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(height: 6),
                Text(
                  progress!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.badge,
                ),
              ],
            ),
    ),
  );
}
