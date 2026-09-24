import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/pdf/pdf_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../major_job_api.dart';
import '../major_job_models.dart';
import '../major_job_pdf.dart';
import 'major_job_photo_view.dart';

/// Major Job: the owner's weekly/monthly photo report of maintenance work.
/// Jobs are grouped into Tuesday-to-Monday periods and exported to PDF.
class MajorJobScreen extends StatefulWidget {
  const MajorJobScreen({this.initialMonth, this.api, super.key});

  /// `YYYY-MM`; the current month when absent or malformed.
  final String? initialMonth;
  final MajorJobApi? api;

  @override
  State<MajorJobScreen> createState() => _MajorJobScreenState();
}

class _MajorJobScreenState extends State<MajorJobScreen> {
  late final MajorJobApi _api = widget.api ?? MajorJobApi();
  late int _year;
  late int _month;
  List<MajorJob>? _jobs;
  MajorJobUsage? _usage;
  String? _error;
  bool _loading = true;
  int _loadRequest = 0;

  @override
  void initState() {
    super.initState();
    _applyMonth(widget.initialMonth);
    _load();
  }

  /// GoRouter keeps this State when only `?month=` changes (same route), so
  /// the new month must be read and loaded here, not only in initState.
  @override
  void didUpdateWidget(MajorJobScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialMonth != widget.initialMonth) {
      _applyMonth(widget.initialMonth);
      _jobs = null;
      _load();
    }
  }

  void _applyMonth(String? value) {
    final DateTime now = DateTime.now();
    final RegExpMatch? match = RegExp(
      r'^(\d{4})-(0[1-9]|1[0-2])$',
    ).firstMatch(value ?? '');
    _year = match == null ? now.year : int.parse(match.group(1)!);
    _month = match == null ? now.month : int.parse(match.group(2)!);
  }

  Future<void> _load() async {
    // Only the latest request may update the screen: switching month while an
    // older request is in flight must not bring the old month's list back.
    final int request = ++_loadRequest;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<MajorJob> jobs = await _api.listMonth(_year, _month);
      if (!mounted || request != _loadRequest) return;
      setState(() {
        _jobs = jobs;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || request != _loadRequest) return;
      setState(() {
        _error = error is MajorJobApiException
            ? error.message
            : 'Data Major Job gagal dimuat.';
        _loading = false;
      });
      return;
    }
    try {
      final MajorJobUsage usage = await _api.usage();
      if (mounted) setState(() => _usage = usage);
    } on Object {
      // Storage usage is informational only.
    }
  }

  void _shiftMonth(int delta) {
    final DateTime target = DateTime(_year, _month + delta);
    setState(() {
      _year = target.year;
      _month = target.month;
      _jobs = null;
    });
    _load();
  }

  void _addJob() {
    final DateTime today = majorJobDateOnly(DateTime.now());
    final DateTime date = today.year == _year && today.month == _month
        ? today
        : DateTime(_year, _month);
    context.go('/major-job/new?date=${majorJobIsoDate(date)}');
  }

  Future<void> _export() async {
    final List<MajorJob> jobs = _jobs ?? <MajorJob>[];
    final List<MajorJobSection> sections = majorJobSections(_year, _month, jobs);
    if (sections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada pekerjaan pada bulan ini.')),
      );
      return;
    }
    final MajorJobReport? report = await showModalBottomSheet<MajorJobReport>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => _ExportSheet(
        year: _year,
        month: _month,
        jobs: jobs,
        sections: sections,
      ),
    );
    if (report == null || !mounted) return;
    await _buildAndShare(report);
  }

  Future<void> _buildAndShare(MajorJobReport report) async {
    final List<MajorJobPhoto> photos = <MajorJobPhoto>[
      for (final MajorJob job in report.jobs) ...job.photos,
    ];
    final ValueNotifier<String> progress = ValueNotifier<String>(
      'Mengambil foto 0/${photos.length}',
    );
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(width: 18),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: progress,
                  builder: (_, value, __) => Text(value),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    try {
      final Map<String, Uint8List> bytes = <String, Uint8List>{};
      int done = 0;
      // A few photos at a time: fast enough, and gentle on a phone connection.
      for (int i = 0; i < photos.length; i += 6) {
        await Future.wait(
          photos.skip(i).take(6).map((photo) async {
            bytes[photo.id] = await _api.photoBytes(photo.id);
            progress.value = 'Mengambil foto ${++done}/${photos.length}';
          }),
        );
      }
      progress.value = 'Menyusun PDF…';
      final pw.ThemeData theme = await loadPdfTheme();
      final Uint8List pdf = await buildMajorJobPdf(
        report,
        photos: bytes,
        theme: theme,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await Printing.sharePdf(bytes: pdf, filename: report.fileName);
    } on Object catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is MajorJobApiException
                ? error.message
                : 'PDF gagal dibuat: $error',
          ),
        ),
      );
    } finally {
      progress.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<MajorJob> jobs = _jobs ?? <MajorJob>[];
    final List<MajorJobSection> sections = majorJobSections(_year, _month, jobs);
    final int photoCount = jobs.fold(0, (sum, job) => sum + job.photos.length);
    int number = 0;
    return AppBackScope(
      fallbackRoute: '/dashboard',
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallbackRoute: '/dashboard'),
          title: const Text(
            'Major Job',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: <Widget>[
            IconButton(
              tooltip: 'Muat ulang',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: 'Export PDF',
              onPressed: _loading || _error != null ? null : _export,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
            const SizedBox(width: 4),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addJob,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text('Tambah pekerjaan'),
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
            children: <Widget>[
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 12),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          IconButton(
                            tooltip: 'Bulan sebelumnya',
                            onPressed: _loading ? null : () => _shiftMonth(-1),
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          Expanded(
                            child: Text(
                              majorJobMonthLabel(_year, _month),
                              textAlign: TextAlign.center,
                              style: AppTextStyles.sectionTitle,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Bulan berikutnya',
                            onPressed: _loading ? null : () => _shiftMonth(1),
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ],
                      ),
                      Text(
                        _jobs == null
                            ? 'Memuat…'
                            : '${jobs.length} pekerjaan · $photoCount foto',
                        style: AppTextStyles.supporting,
                      ),
                      if (_usage != null) ...<Widget>[
                        const SizedBox(height: 10),
                        _UsageBar(usage: _usage!),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_loading && _jobs == null)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _Message(
                  icon: Icons.cloud_off_rounded,
                  text: _error!,
                  action: TextButton(onPressed: _load, child: const Text('Coba lagi')),
                )
              else if (sections.isEmpty)
                const _Message(
                  icon: Icons.photo_library_outlined,
                  text:
                      'Belum ada pekerjaan di bulan ini. Tekan "Tambah pekerjaan" untuk mulai.',
                )
              else
                for (final MajorJobSection section in sections) ...<Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                    child: Text(
                      section.period.label,
                      style: AppTextStyles.sectionTitle,
                    ),
                  ),
                  for (final MajorJob job in section.jobs)
                    _JobCard(
                      api: _api,
                      job: job,
                      number: ++number,
                      onTap: () => context.go('/major-job/job/${job.id}'),
                    ),
                  const SizedBox(height: 8),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.usage});

  final MajorJobUsage usage;

  @override
  Widget build(BuildContext context) {
    final double share = usage.capacityBytes == 0
        ? 0
        : (usage.bytes / usage.capacityBytes).clamp(0, 1).toDouble();
    String size(int bytes) => bytes >= 1024 * 1024 * 1024
        ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} GB'
        : '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 6,
              backgroundColor: AppColors.mint,
              color: share > .85 ? AppColors.danger : AppColors.green,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Penyimpanan foto ${size(usage.bytes)} dari ${size(usage.capacityBytes)} '
            '(${usage.photos} foto, semua bulan)',
            style: AppTextStyles.supporting,
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
    child: Column(
      children: <Widget>[
        Icon(icon, size: 40, color: AppColors.muted),
        const SizedBox(height: 10),
        Text(text, textAlign: TextAlign.center, style: AppTextStyles.body),
        if (action != null) ...<Widget>[const SizedBox(height: 6), action!],
      ],
    ),
  );
}

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.api,
    required this.job,
    required this.number,
    required this.onTap,
  });

  final MajorJobApi api;
  final MajorJob job;
  final int number;
  final VoidCallback onTap;

  static const double _thumbHeight = 52;
  static const int _maxThumbs = 4;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CircleAvatar(
              radius: 15,
              backgroundColor: AppColors.mint,
              child: Text(
                '$number',
                style: const TextStyle(
                  color: AppColors.green,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(job.description, style: AppTextStyles.cardTitle),
                  const SizedBox(height: 2),
                  Text(
                    '${majorJobDayLabel(job.workDate)} · ${job.photos.length} foto',
                    style: AppTextStyles.supporting,
                  ),
                  const SizedBox(height: 8),
                  if (job.photos.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Belum ada foto, tidak ikut di PDF',
                        style: AppTextStyles.badge,
                      ),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        for (final MajorJobPhoto photo
                            in job.photos.take(_maxThumbs))
                          MajorJobPhotoView(
                            api: api,
                            photo: photo,
                            height: _thumbHeight,
                          ),
                        if (job.photos.length > _maxThumbs)
                          Text(
                            '+${job.photos.length - _maxThumbs}',
                            style: AppTextStyles.supporting,
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    ),
  );
}

class _ExportSheet extends StatelessWidget {
  const _ExportSheet({
    required this.year,
    required this.month,
    required this.jobs,
    required this.sections,
  });

  final int year;
  final int month;
  final List<MajorJob> jobs;
  final List<MajorJobSection> sections;

  Widget _option(
    BuildContext context, {
    required IconData icon,
    required String title,
    required MajorJobReport report,
  }) {
    final int jobCount = report.jobs.length;
    final int photoCount = report.jobs.fold(
      0,
      (sum, job) => sum + job.photos.length,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.mint,
          child: Icon(icon, color: AppColors.green),
        ),
        title: Text(title, style: AppTextStyles.cardTitle),
        subtitle: Text(
          '${report.rangeLabel} · $jobCount pekerjaan · $photoCount foto',
          style: AppTextStyles.supporting,
        ),
        trailing: const Icon(Icons.download_rounded),
        enabled: jobCount > 0,
        onTap: () => Navigator.pop(context, report),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int withoutPhotos = jobs.where((job) => job.photos.isEmpty).length;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: <Widget>[
          const Text('Export PDF', style: AppTextStyles.sectionTitle),
          const SizedBox(height: 4),
          const Text(
            'Report mingguan berisi pekerjaan sejak tanggal 1 sampai akhir minggu yang dipilih.',
            style: AppTextStyles.supporting,
          ),
          if (withoutPhotos > 0) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              '$withoutPhotos pekerjaan belum punya foto dan tidak ikut di PDF.',
              style: AppTextStyles.supporting.copyWith(color: AppColors.danger),
            ),
          ],
          const SizedBox(height: 14),
          const Text('Weekly Job Report', style: AppTextStyles.cardTitle),
          const SizedBox(height: 8),
          for (final MajorJobSection section in sections.reversed)
            _option(
              context,
              icon: Icons.date_range_rounded,
              title: 'Minggu s.d. ${section.period.label}',
              report: majorJobReportFor(
                kind: MajorJobReportKind.weekly,
                year: year,
                month: month,
                jobs: jobs,
                until: section.period,
              ),
            ),
          const SizedBox(height: 10),
          const Text('Major Job Report (bulanan)', style: AppTextStyles.cardTitle),
          const SizedBox(height: 8),
          _option(
            context,
            icon: Icons.calendar_month_rounded,
            title: 'Major Job ${majorJobMonthLabel(year, month)}',
            report: majorJobReportFor(
              kind: MajorJobReportKind.monthly,
              year: year,
              month: month,
              jobs: jobs,
            ),
          ),
        ],
      ),
    );
  }
}
