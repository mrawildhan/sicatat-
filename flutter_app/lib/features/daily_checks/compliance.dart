import 'dart:ui';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/sicatat_types.dart';
import 'check_schedule.dart';

/// Kepatuhan pengisian (owner request 2026-09-26): whether every check sheet
/// was filled for every shift, by the crew on duty, on time.
///
/// Three sheets are expected per shift: Daily Temperature Feeder Sizer,
/// Daily Check Sheet Hydraulic Feeder and Temperature Coal Valve. A sheet
/// sent within [complianceGrace] after its shift ends is on time.
enum ComplianceForm {
  feederSizer('Feeder Sizer', 'Daily Temperature Feeder Sizer'),
  hydraulicFeeder('Hydraulic', 'Daily Check Sheet Hydraulic Feeder'),
  coalValve('Coal Valve', 'Temperature Coal Valve');

  const ComplianceForm(this.shortLabel, this.title);

  final String shortLabel;
  final String title;

  static ComplianceForm? fromDailyCheck(String? formType) => switch (formType) {
    'hydraulic_feeder' => ComplianceForm.hydraulicFeeder,
    'coal_valve' => ComplianceForm.coalValve,
    _ => null,
  };
}

enum ComplianceStatus {
  onTime('Tepat waktu', AppColors.green),
  late('Terlambat', AppColors.warning),
  incomplete('Belum lengkap', AppColors.orange),
  missing('Tidak ada', AppColors.danger),
  running('Berjalan', AppColors.muted),
  upcoming('Belum waktunya', AppColors.line);

  const ComplianceStatus(this.label, this.color);

  final String label;
  final Color color;

  /// Counted in the percentages: shifts that have ended.
  bool get isDue =>
      this != ComplianceStatus.running && this != ComplianceStatus.upcoming;

  bool get isFilled =>
      this == ComplianceStatus.onTime || this == ComplianceStatus.late;
}

const Duration complianceGrace = Duration(hours: 2);
const List<String> complianceShifts = <String>['PAGI', 'MALAM'];

String complianceShiftLabel(String code) =>
    code == 'PAGI' ? 'Shift Pagi' : 'Shift Malam';

/// One stored sheet, from either `sheet` (Feeder Sizer) or
/// `daily_check_sheet`.
class ComplianceSheet {
  const ComplianceSheet({
    required this.form,
    required this.date,
    required this.shiftCode,
    required this.status,
    this.teamCode,
    this.submittedAt,
    this.approvedAt,
    this.needsApproval = false,
  });

  final ComplianceForm form;
  final DateTime date;
  final String shiftCode;

  /// Stored status: draft, submitted, submitted_incomplete or verified.
  final String status;
  final String? teamCode;
  final DateTime? submittedAt;
  final DateTime? approvedAt;

  /// Hydraulic and Coal Valve sheets are approved ("Mengetahui") by a
  /// reviewer; Feeder Sizer sheets are final when sent.
  final bool needsApproval;

  bool get isSent => status != 'draft';

  bool get isComplete => status == 'submitted' || status == 'verified';

  bool get waitingApproval => needsApproval && isSent && approvedAt == null;
}

/// One expected sheet: a form in a shift of a day.
class ComplianceCell {
  const ComplianceCell({
    required this.date,
    required this.shiftCode,
    required this.form,
    required this.status,
    this.teamCode,
    this.sheet,
  });

  final DateTime date;
  final String shiftCode;
  final ComplianceForm form;
  final ComplianceStatus status;

  /// The crew on duty by the roster, or the sheet's crew without a roster.
  final String? teamCode;
  final ComplianceSheet? sheet;
}

class ComplianceCrewSummary {
  const ComplianceCrewSummary({
    required this.teamCode,
    required this.due,
    required this.onTime,
    required this.late,
    required this.incomplete,
    required this.missing,
  });

  final String teamCode;
  final int due;
  final int onTime;
  final int late;
  final int incomplete;
  final int missing;

  double get onTimeRate => due == 0 ? 0 : onTime / due;
  double get filledRate => due == 0 ? 0 : (onTime + late) / due;
}

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

/// When [shiftCode] of [date] ends: Pagi 19:00, Malam 07:00 the next day.
DateTime complianceShiftEnd(DateTime date, String shiftCode) {
  final DateTime day = _day(date);
  return shiftCode == 'PAGI'
      ? DateTime(day.year, day.month, day.day, 19)
      : DateTime(day.year, day.month, day.day + 1, 7);
}

DateTime complianceShiftStart(DateTime date, String shiftCode) {
  final DateTime day = _day(date);
  return shiftCode == 'PAGI'
      ? DateTime(day.year, day.month, day.day, 7)
      : DateTime(day.year, day.month, day.day, 19);
}

ComplianceStatus complianceStatusOf(
  ComplianceSheet? sheet,
  DateTime date,
  String shiftCode,
  DateTime now,
) {
  final DateTime end = complianceShiftEnd(date, shiftCode);
  if (now.isBefore(complianceShiftStart(date, shiftCode))) {
    return ComplianceStatus.upcoming;
  }
  if (sheet != null && sheet.isSent) {
    if (!sheet.isComplete) return ComplianceStatus.incomplete;
    final DateTime? sent = sheet.submittedAt;
    return sent != null && sent.isAfter(end.add(complianceGrace))
        ? ComplianceStatus.late
        : ComplianceStatus.onTime;
  }
  if (now.isBefore(end.add(complianceGrace))) return ComplianceStatus.running;
  return sheet == null ? ComplianceStatus.missing : ComplianceStatus.incomplete;
}

/// The month's grid of expected sheets, oldest first.
class ComplianceMonth {
  ComplianceMonth({
    required this.month,
    required List<ComplianceSheet> sheets,
    required this.anchor,
    required DateTime now,
    this.onlyTeam,
  }) : cells = _cells(month, sheets, anchor, now)
           .where(
             (ComplianceCell c) => onlyTeam == null || c.teamCode == onlyTeam,
           )
           .toList(growable: false),
       waitingApproval = sheets
           .where((ComplianceSheet sheet) => sheet.waitingApproval)
           .toList(growable: false);

  final DateTime month;
  final RosterAnchor? anchor;

  /// A foreman sees only their own crew's shifts (they cannot read the
  /// other crews' sheets).
  final String? onlyTeam;
  final List<ComplianceCell> cells;
  final List<ComplianceSheet> waitingApproval;

  static List<ComplianceCell> _cells(
    DateTime month,
    List<ComplianceSheet> sheets,
    RosterAnchor? anchor,
    DateTime now,
  ) {
    String key(DateTime date, String shift, ComplianceForm form) =>
        '${_day(date).toIso8601String()}|$shift|${form.name}';
    final Map<String, ComplianceSheet> byKey = <String, ComplianceSheet>{};
    for (final ComplianceSheet sheet in sheets) {
      final String k = key(sheet.date, sheet.shiftCode, sheet.form);
      final ComplianceSheet? other = byKey[k];
      // With two rows (another site) the most finished one counts.
      if (other == null || _rank(sheet) > _rank(other)) byKey[k] = sheet;
    }
    final int days = DateTime(month.year, month.month + 1, 0).day;
    return <ComplianceCell>[
      for (int d = 1; d <= days; d++)
        for (final String shift in complianceShifts)
          for (final ComplianceForm form in ComplianceForm.values)
            () {
              final DateTime date = DateTime(month.year, month.month, d);
              final ComplianceSheet? sheet = byKey[key(date, shift, form)];
              return ComplianceCell(
                date: date,
                shiftCode: shift,
                form: form,
                sheet: sheet,
                teamCode: anchor?.teamCodeFor(date, shift) ?? sheet?.teamCode,
                status: complianceStatusOf(sheet, date, shift, now),
              );
            }(),
    ];
  }

  static int _rank(ComplianceSheet sheet) =>
      sheet.isComplete ? 2 : (sheet.isSent ? 1 : 0);

  List<ComplianceCell> get due =>
      cells.where((ComplianceCell c) => c.status.isDue).toList();

  int count(ComplianceStatus status) =>
      cells.where((ComplianceCell c) => c.status == status).length;

  double get onTimeRate {
    final int due = this.due.length;
    return due == 0 ? 0 : count(ComplianceStatus.onTime) / due;
  }

  double get filledRate {
    final int due = this.due.length;
    return due == 0
        ? 0
        : (count(ComplianceStatus.onTime) + count(ComplianceStatus.late)) / due;
  }

  List<ComplianceCrewSummary> get crews {
    final Map<String, List<ComplianceCell>> byCrew =
        <String, List<ComplianceCell>>{};
    for (final ComplianceCell cell in due) {
      byCrew
          .putIfAbsent(cell.teamCode ?? '-', () => <ComplianceCell>[])
          .add(cell);
    }
    final List<String> codes = byCrew.keys.toList()..sort();
    return <ComplianceCrewSummary>[
      for (final String code in codes)
        ComplianceCrewSummary(
          teamCode: code,
          due: byCrew[code]!.length,
          onTime: byCrew[code]!
              .where((c) => c.status == ComplianceStatus.onTime)
              .length,
          late: byCrew[code]!
              .where((c) => c.status == ComplianceStatus.late)
              .length,
          incomplete: byCrew[code]!
              .where((c) => c.status == ComplianceStatus.incomplete)
              .length,
          missing: byCrew[code]!
              .where((c) => c.status == ComplianceStatus.missing)
              .length,
        ),
    ];
  }

  /// Per form, the share of due sheets that were filled.
  Map<ComplianceForm, double> get filledRateByForm => <ComplianceForm, double>{
    for (final ComplianceForm form in ComplianceForm.values)
      form: () {
        final List<ComplianceCell> due = this.due
            .where((ComplianceCell c) => c.form == form)
            .toList();
        return due.isEmpty
            ? 0.0
            : due.where((ComplianceCell c) => c.status.isFilled).length /
                  due.length;
      }(),
  };

  /// The cells of one day and shift, in form order.
  List<ComplianceCell> cellsOf(DateTime date, String shiftCode) => cells
      .where(
        (ComplianceCell c) => c.date == _day(date) && c.shiftCode == shiftCode,
      )
      .toList(growable: false);

  /// Worst status of a day, for the calendar colour.
  ComplianceStatus dayStatus(DateTime date) {
    final List<ComplianceCell> day = cells
        .where((ComplianceCell c) => c.date == _day(date))
        .toList();
    for (final ComplianceStatus status in const <ComplianceStatus>[
      ComplianceStatus.missing,
      ComplianceStatus.incomplete,
      ComplianceStatus.late,
      ComplianceStatus.running,
    ]) {
      if (day.any((ComplianceCell c) => c.status == status)) return status;
    }
    return day.every(
          (ComplianceCell c) => c.status == ComplianceStatus.upcoming,
        )
        ? ComplianceStatus.upcoming
        : ComplianceStatus.onTime;
  }
}

/// Loads a month of sheets and the roster. Row-level security limits the
/// sheets to what the user may read (foreman: own crew).
Future<ComplianceMonth> loadComplianceMonth(
  SupabaseClient client,
  DateTime month, {
  DateTime? now,
  String? onlyTeamId,
}) async {
  final DateTime first = DateTime(month.year, month.month);
  final DateTime last = DateTime(month.year, month.month + 1, 0);
  String date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
  final List<Object?> responses = await Future.wait<Object?>(<Future<Object?>>[
    client
        .from('sheet')
        .select(
          'tanggal,status,submitted_at,shift:shift_id(code),team:team_id(code)',
        )
        .gte('tanggal', date(first))
        .lte('tanggal', date(last))
        .limit(2000),
    client
        .from('daily_check_sheet')
        .select(
          'form_type,tanggal,status,submitted_at,approved_at,'
          'shift:shift_id(code),team:team_id(code)',
        )
        .gte('tanggal', date(first))
        .lte('tanggal', date(last))
        .limit(2000),
    client
        .from('roster_anchor')
        .select('tanggal_mula,urutan_regu')
        .eq('is_active', true)
        .order('tanggal_mula', ascending: false)
        .limit(1),
    if (onlyTeamId != null)
      client.from('team').select('code').eq('id', onlyTeamId).maybeSingle()
    else
      Future<Object?>.value(),
  ]);
  String? code(Object? value) =>
      value is Map ? value['code']?.toString() : null;
  DateTime? time(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
  final List<ComplianceSheet> sheets = <ComplianceSheet>[
    for (final Object? raw in responses[0]! as List<Object?>)
      () {
        final JsonMap row = requireJsonMap(raw, source: 'sheet');
        return ComplianceSheet(
          form: ComplianceForm.feederSizer,
          date: DateTime.parse(row.requiredString('tanggal')),
          shiftCode: code(row['shift']) ?? '',
          teamCode: code(row['team']),
          status: row.requiredString('status'),
          submittedAt: time(row['submitted_at']),
        );
      }(),
    for (final Object? raw in responses[1]! as List<Object?>)
      if (ComplianceForm.fromDailyCheck(
            requireJsonMap(raw).optionalString('form_type'),
          )
          case final ComplianceForm form)
        () {
          final JsonMap row = requireJsonMap(raw, source: 'daily check');
          return ComplianceSheet(
            form: form,
            date: DateTime.parse(row.requiredString('tanggal')),
            shiftCode: code(row['shift']) ?? '',
            teamCode: code(row['team']),
            status: row.requiredString('status'),
            submittedAt: time(row['submitted_at']),
            approvedAt: time(row['approved_at']),
            needsApproval: true,
          );
        }(),
  ];
  RosterAnchor? anchor;
  final List<Object?> anchors = responses[2]! as List<Object?>;
  if (anchors.isNotEmpty) {
    final JsonMap row = requireJsonMap(anchors.first, source: 'roster');
    final List<String>? order = (row['urutan_regu'] as List?)
        ?.map((Object? c) => c.toString())
        .toList(growable: false);
    if (order != null) {
      anchor = RosterAnchor(
        start: DateTime.parse(row.requiredString('tanggal_mula')),
        order: order,
      );
    }
  }
  return ComplianceMonth(
    month: first,
    sheets: sheets,
    anchor: anchor,
    now: now ?? DateTime.now(),
    onlyTeam: code(responses[3]),
  );
}
