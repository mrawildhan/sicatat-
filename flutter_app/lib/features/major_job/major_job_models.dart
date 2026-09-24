import '../../data/models/sicatat_types.dart';

/// Months written out in Indonesian, as in the owner's Word reports.
const List<String> majorJobMonthNames = <String>[
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];

const List<String> _dayNames = <String>[
  'Sen',
  'Sel',
  'Rab',
  'Kam',
  'Jum',
  'Sab',
  'Min',
];

DateTime majorJobDateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String majorJobIsoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String majorJobMonthLabel(int year, int month) =>
    '${majorJobMonthNames[month - 1]} $year';

/// "Sen, 03 Agustus 2026".
String majorJobDayLabel(DateTime date) =>
    '${_dayNames[date.weekday - 1]}, ${date.day.toString().padLeft(2, '0')} '
    '${majorJobMonthNames[date.month - 1]} ${date.year}';

/// "01 – 10 Agustus 2026", or "28 September – 04 Oktober 2026" across months.
String majorJobRangeLabel(DateTime start, DateTime end) {
  String day(DateTime d) => d.day.toString().padLeft(2, '0');
  final String endMonth = majorJobMonthNames[end.month - 1];
  if (start.year == end.year && start.month == end.month) {
    return '${day(start)} – ${day(end)} $endMonth ${end.year}';
  }
  final String startMonth = majorJobMonthNames[start.month - 1];
  if (start.year == end.year) {
    return '${day(start)} $startMonth – ${day(end)} $endMonth ${end.year}';
  }
  return '${day(start)} $startMonth ${start.year} – ${day(end)} $endMonth ${end.year}';
}

/// One subheading of the report. Reports go to the boss on Tuesday, so a
/// period closes on Monday and never crosses a month boundary: August 2026 is
/// 01–03, 04–10, 11–17, 18–24, 25–31.
class MajorJobPeriod {
  const MajorJobPeriod(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool contains(DateTime date) {
    final DateTime day = majorJobDateOnly(date);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  String get label => majorJobRangeLabel(start, end);

  @override
  bool operator ==(Object other) =>
      other is MajorJobPeriod && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

List<MajorJobPeriod> majorJobPeriodsOfMonth(int year, int month) {
  final DateTime last = DateTime(year, month + 1, 0);
  final List<MajorJobPeriod> periods = <MajorJobPeriod>[];
  DateTime start = DateTime(year, month);
  while (!start.isAfter(last)) {
    final int toMonday = (DateTime.monday - start.weekday + 7) % 7;
    DateTime end = DateTime(start.year, start.month, start.day + toMonday);
    if (end.isAfter(last)) end = last;
    periods.add(MajorJobPeriod(start, end));
    start = DateTime(end.year, end.month, end.day + 1);
  }
  return periods;
}

class MajorJobPhoto {
  const MajorJobPhoto({
    required this.id,
    required this.position,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.sizeBytes,
  });

  final String id;
  final int position;
  final String mimeType;
  final int width;
  final int height;
  final int sizeBytes;

  /// Square photos count as landscape, like the old Word script.
  bool get isLandscape => width >= height;

  factory MajorJobPhoto.fromJson(JsonMap json) => MajorJobPhoto(
    id: json.requiredString('id'),
    position: (json['position'] as num).toInt(),
    mimeType: json.requiredString('mime_type'),
    width: (json['width'] as num).toInt(),
    height: (json['height'] as num).toInt(),
    sizeBytes: (json['size_bytes'] as num).toInt(),
  );
}

class MajorJob {
  const MajorJob({
    required this.id,
    required this.workDate,
    required this.description,
    required this.createdBy,
    required this.photos,
  });

  final String id;
  final DateTime workDate;
  final String description;
  final String createdBy;
  final List<MajorJobPhoto> photos;

  MajorJob copyWith({List<MajorJobPhoto>? photos}) => MajorJob(
    id: id,
    workDate: workDate,
    description: description,
    createdBy: createdBy,
    photos: photos ?? this.photos,
  );

  factory MajorJob.fromJson(JsonMap json) {
    final Object? rawPhotos = json['photos'];
    final List<MajorJobPhoto> photos = rawPhotos is List
        ? rawPhotos
              .map((Object? item) =>
                  MajorJobPhoto.fromJson(requireJsonMap(item, source: 'foto')))
              .toList()
        : <MajorJobPhoto>[];
    photos.sort((a, b) => a.position.compareTo(b.position));
    return MajorJob(
      id: json.requiredString('id'),
      workDate: DateTime.parse(json.requiredString('work_date')),
      description: json.requiredString('description'),
      createdBy: json.optionalString('created_by') ?? '',
      photos: photos,
    );
  }
}

class MajorJobUsage {
  const MajorJobUsage({
    required this.photos,
    required this.bytes,
    required this.capacityBytes,
  });

  final int photos;
  final int bytes;
  final int capacityBytes;

  factory MajorJobUsage.fromJson(JsonMap json) => MajorJobUsage(
    photos: (json['photos'] as num).toInt(),
    bytes: (json['bytes'] as num).toInt(),
    capacityBytes: (json['capacity_bytes'] as num).toInt(),
  );
}

/// Jobs of one period, numbered continuously through the month.
class MajorJobSection {
  const MajorJobSection(this.period, this.jobs);

  final MajorJobPeriod period;
  final List<MajorJob> jobs;
}

/// Groups a month's jobs into its periods (date, then creation order as sent
/// by the API). Periods without jobs are left out.
List<MajorJobSection> majorJobSections(
  int year,
  int month,
  List<MajorJob> jobs,
) => <MajorJobSection>[
  for (final MajorJobPeriod period in majorJobPeriodsOfMonth(year, month))
    if (jobs.any((job) => period.contains(job.workDate)))
      MajorJobSection(
        period,
        jobs.where((job) => period.contains(job.workDate)).toList(),
      ),
];
