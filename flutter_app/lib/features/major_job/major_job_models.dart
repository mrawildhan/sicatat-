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

/// "29 September 2026".
String majorJobDateLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')} '
    '${majorJobMonthNames[date.month - 1]} ${date.year}';

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

/// One subheading of the report: a Tuesday–Monday week (reports go to the
/// boss on Tuesday). Weeks run on continuously across months, e.g.
/// 22–28 September, 29 September – 05 Oktober, 06–12 Oktober (owner decision
/// 2026-09-24). A week belongs to the month in which it ends.
class MajorJobPeriod {
  const MajorJobPeriod(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool contains(DateTime date) {
    final DateTime day = majorJobDateOnly(date);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  String get label => majorJobRangeLabel(start, end);

  /// This period limited to one calendar month (the monthly report shows
  /// 29 September – 05 Oktober as "29 – 30 September" and "01 – 05 Oktober").
  MajorJobPeriod clippedTo(int year, int month) {
    final DateTime first = DateTime(year, month);
    final DateTime last = DateTime(year, month + 1, 0);
    return MajorJobPeriod(
      start.isBefore(first) ? first : start,
      end.isAfter(last) ? last : end,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MajorJobPeriod && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// The Tuesday–Monday week that contains [date].
MajorJobPeriod majorJobPeriodOf(DateTime date) {
  final DateTime day = majorJobDateOnly(date);
  final int toMonday = (DateTime.monday - day.weekday + 7) % 7;
  final DateTime end = DateTime(day.year, day.month, day.day + toMonday);
  return MajorJobPeriod(DateTime(end.year, end.month, end.day - 6), end);
}

/// Weeks reported in this month: those that end (on a Monday) inside it.
/// October 2026 starts with 29 September – 05 Oktober and ends with 20–26
/// Oktober; 27 Oktober – 02 November belongs to November.
List<MajorJobPeriod> majorJobWeeksOfMonth(int year, int month) {
  final DateTime last = DateTime(year, month + 1, 0);
  final List<MajorJobPeriod> weeks = <MajorJobPeriod>[];
  // The week holding the 1st always ends on or after the 1st, so it counts.
  MajorJobPeriod week = majorJobPeriodOf(DateTime(year, month));
  while (!week.end.isAfter(last)) {
    weeks.add(week);
    week = majorJobPeriodOf(week.end.add(const Duration(days: 1)));
  }
  return weeks;
}

/// Every date whose jobs the month screen needs: its weeks (which may start
/// in the previous month) and the whole calendar month (the monthly report
/// includes the last days even when their week ends next month).
({DateTime from, DateTime to}) majorJobMonthRange(int year, int month) {
  final List<MajorJobPeriod> weeks = majorJobWeeksOfMonth(year, month);
  final DateTime first = DateTime(year, month);
  return (
    from: weeks.isNotEmpty && weeks.first.start.isBefore(first)
        ? weeks.first.start
        : first,
    to: DateTime(year, month + 1, 0),
  );
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

List<MajorJobSection> _group(
  Iterable<MajorJobPeriod> periods,
  List<MajorJob> jobs,
) => <MajorJobSection>[
  for (final MajorJobPeriod period in periods)
    if (jobs.any((job) => period.contains(job.workDate)))
      MajorJobSection(
        period,
        jobs.where((job) => period.contains(job.workDate)).toList(),
      ),
];

/// The month's weekly sections (weeks ending in the month, full labels such
/// as "29 September – 05 Oktober 2026"). Jobs keep the API order (date, then
/// creation). Weeks without jobs are left out.
List<MajorJobSection> majorJobSections(
  int year,
  int month,
  List<MajorJob> jobs,
) => _group(majorJobWeeksOfMonth(year, month), jobs);

/// The last days of the calendar month whose week ends next month (e.g.
/// 29 – 30 September). They go into next month's weekly reports but still
/// belong to this month's Major Job report. Null when there are none or they
/// have no jobs.
MajorJobSection? majorJobTailSection(
  int year,
  int month,
  List<MajorJob> jobs,
) {
  final DateTime last = DateTime(year, month + 1, 0);
  final List<MajorJobPeriod> weeks = majorJobWeeksOfMonth(year, month);
  final DateTime start = weeks.isEmpty
      ? DateTime(year, month)
      : weeks.last.end.add(const Duration(days: 1));
  if (start.isAfter(last)) return null;
  final List<MajorJobSection> tail = _group(<MajorJobPeriod>[
    MajorJobPeriod(start, last),
  ], jobs);
  return tail.isEmpty ? null : tail.first;
}

/// The calendar month in weekly sections clipped to the month: the monthly
/// Major Job report (01 – 30 September includes 29 – 30 September).
List<MajorJobSection> majorJobCalendarSections(
  int year,
  int month,
  List<MajorJob> jobs,
) {
  final DateTime last = DateTime(year, month + 1, 0);
  final List<MajorJobPeriod> periods = <MajorJobPeriod>[];
  MajorJobPeriod week = majorJobPeriodOf(DateTime(year, month));
  while (!week.start.isAfter(last)) {
    periods.add(week.clippedTo(year, month));
    week = majorJobPeriodOf(week.end.add(const Duration(days: 1)));
  }
  return _group(periods, jobs);
}
