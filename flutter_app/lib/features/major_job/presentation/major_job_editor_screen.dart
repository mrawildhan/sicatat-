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

  /// Photos picked for a new job; uploaded right after the job is created.
  final List<_PendingPhoto> _pending = <_PendingPhoto>[];
  int _pendingSerial = 0;

  bool get _isNew => widget.jobId == null;

  int get _photoCount => _job?.photos.length ?? _pending.length;

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
        final List<String> failures = <String>[];
        for (int i = 0; i < _pending.length; i++) {
          if (!mounted) return;
          setState(
            () => _uploadProgress =
                'Mengunggah foto ${i + 1}/${_pending.length}…',
          );
          try {
            await _api.uploadPhoto(
              created.id,
              _pending[i].bytes,
              _pending[i].mimeType,
            );
          } on Object catch (error) {
            failures.add(
              'Foto ${i + 1}: ${_errorText(error, 'gagal diunggah')}',
            );
          }
        }
        if (!mounted) return;
        if (failures.isEmpty) {
          _toast(
            _pending.isEmpty
                ? 'Pekerjaan tersimpan.'
                : 'Pekerjaan dan ${_pending.length} foto tersimpan.',
          );
          context.go(_backRoute);
        } else {
          // The job exists; its own page lets the owner add the missing photos.
          _toast(failures.join('\n'));
          context.go('/major-job/job/${created.id}');
        }
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
    if (job == null && !_isNew) return;
    final int room = majorJobMaxPhotos - _photoCount;
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
      setState(
        () => _uploadProgress = 'Memproses foto ${i + 1}/${files.length}…',
      );
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
        if (job == null) {
          // New job: keep the photo here until the job itself is saved.
          setState(
            () => _pending.add(
              _PendingPhoto(
                id: 'pending-${_pendingSerial++}',
                bytes: compressed.bytes,
                mimeType: compressed.mimeType,
                width: compressed.width,
                height: compressed.height,
              ),
            ),
          );
          continue;
        }
        setState(
          () => _uploadProgress = 'Mengunggah foto ${i + 1}/${files.length}…',
        );
        final MajorJobPhoto photo = await _api.uploadPhoto(
          job.id,
          compressed.bytes,
          compressed.mimeType,
        );
        if (!mounted) return;
        setState(
          () => _job = _job!.copyWith(
            photos: <MajorJobPhoto>[..._job!.photos, photo],
          ),
        );
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
    final MajorJob? current = _job;
    if (current == null) {
      setState(() => _pending.insert(index + delta, _pending.removeAt(index)));
      return;
    }
    final MajorJob job = current;
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
    if (!await _confirm(
      'Hapus foto?',
      'Foto ini akan dihapus permanen.',
      'Hapus',
    )) {
      return;
    }
    try {
      await _api.deletePhoto(photo.id);
      if (!mounted) return;
      setState(
        () => _job = _job!.copyWith(
          photos: _job!.photos.where((p) => p.id != photo.id).toList(),
        ),
      );
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

  void _openPhoto(int index) {
    final MajorJob? job = _job;
    showMajorJobPhotoViewer(
      context,
      initialIndex: index,
      photos: job == null
          ? <Future<Uint8List> Function()>[
              for (final _PendingPhoto photo in _pending)
                () => Future<Uint8List>.value(photo.bytes),
            ]
          : <Future<Uint8List> Function()>[
              for (final MajorJobPhoto photo in job.photos)
                () => _api.photoBytes(photo.id),
            ],
    );
  }

  Widget _saveButton(bool busy) => FilledButton.icon(
    onPressed: busy || !_dirty ? null : _save,
    icon: _saving
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : const Icon(Icons.save_outlined),
    label: Text(
      !_isNew
          ? 'Simpan perubahan'
          : _pending.isEmpty
          ? 'Simpan pekerjaan'
          : 'Simpan pekerjaan & ${_pending.length} foto',
    ),
  );

  List<Widget> _photoSection(bool busy) {
    final MajorJob? job = _job;
    final int count = _photoCount;
    return <Widget>[
      Text(
        'Foto ($count/$majorJobMaxPhotos)',
        style: AppTextStyles.sectionTitle,
      ),
      const SizedBox(height: 4),
      Text(
        'Foto tampil persis seperti potongan di PDF: landscape 5,4 × 3,6 cm, '
        'portrait 2,4 × 3,6 cm. Urutan di sini = urutan di PDF. '
        'Ketuk foto untuk memperbesar.'
        '${_isNew ? ' Foto diunggah saat pekerjaan disimpan.' : ''}',
        style: AppTextStyles.supporting,
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: <Widget>[
          for (int i = 0; i < count; i++)
            _PhotoTile(
              key: ValueKey<String>(
                job == null ? _pending[i].id : job.photos[i].id,
              ),
              api: _api,
              photo: job == null ? _pending[i].photo : job.photos[i],
              bytes: job == null ? _pending[i].bytes : null,
              onOpen: () => _openPhoto(i),
              onLeft: busy || i == 0 ? null : () => _move(i, -1),
              onRight: busy || i == count - 1 ? null : () => _move(i, 1),
              onDelete: busy
                  ? null
                  : job == null
                  ? () => setState(() => _pending.removeAt(i))
                  : () => _deletePhoto(job.photos[i]),
            ),
          if (count < majorJobMaxPhotos)
            _AddPhotoTile(
              progress: _uploadProgress,
              onTap: busy ? null : _addPhotos,
            ),
        ],
      ),
    ];
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
                      TextButton(
                        onPressed: _load,
                        child: const Text('Coba lagi'),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
                children: <Widget>[
                  const Text(
                    'Tanggal pekerjaan',
                    style: AppTextStyles.sectionTitle,
                  ),
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
                    'Masuk subjudul ${majorJobPeriodOf(_date).label} '
                    '(Weekly Report ${majorJobMonthLabel(majorJobPeriodOf(_date).end.year, majorJobPeriodOf(_date).end.month)})',
                    style: AppTextStyles.supporting,
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Deskripsi pekerjaan',
                    style: AppTextStyles.sectionTitle,
                  ),
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
                  // A new job saves its photos together with it, so the
                  // button comes after them; an existing job uploads each
                  // photo at once and the button only saves date and text.
                  if (_isNew) ...<Widget>[
                    const SizedBox(height: 8),
                    ..._photoSection(busy),
                    const SizedBox(height: 20),
                    _saveButton(busy),
                  ] else ...<Widget>[
                    const SizedBox(height: 6),
                    _saveButton(busy),
                    if (job != null) ...<Widget>[
                      const SizedBox(height: 26),
                      ..._photoSection(busy),
                    ],
                  ],
                ],
              ),
      ),
    );
  }
}

/// A photo picked for a new job, compressed but not uploaded yet.
class _PendingPhoto {
  const _PendingPhoto({
    required this.id,
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
  });

  final String id;
  final Uint8List bytes;
  final String mimeType;
  final int width;
  final int height;

  /// Stand-in so the tile can crop it like an uploaded photo.
  MajorJobPhoto get photo => MajorJobPhoto(
    id: id,
    position: 0,
    mimeType: mimeType,
    width: width,
    height: height,
    sizeBytes: bytes.lengthInBytes,
  );
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.api,
    required this.photo,
    required this.onOpen,
    required this.onLeft,
    required this.onRight,
    required this.onDelete,
    this.bytes,
    super.key,
  });

  static const double height = 108;

  final MajorJobApi api;
  final MajorJobPhoto photo;
  final Uint8List? bytes;
  final VoidCallback onOpen;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      MajorJobPhotoView(
        api: api,
        photo: photo,
        bytes: bytes,
        height: height,
        onTap: onOpen,
      ),
      SizedBox(
        // Three compact 40 px buttons need 120 px, wider than a portrait photo.
        width: MajorJobPhotoView.widthFor(photo, height).clamp(124, 200),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _smallButton(Icons.chevron_left_rounded, 'Geser ke kiri', onLeft),
            _smallButton(Icons.delete_outline_rounded, 'Hapus foto', onDelete),
            _smallButton(
              Icons.chevron_right_rounded,
              'Geser ke kanan',
              onRight,
            ),
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
