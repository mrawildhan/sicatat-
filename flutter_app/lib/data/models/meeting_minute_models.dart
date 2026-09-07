import 'sicatat_types.dart';

enum MeetingMinuteStatus { draft, completed }

extension MeetingMinuteStatusX on MeetingMinuteStatus {
  String get storageValue => switch (this) {
    MeetingMinuteStatus.draft => 'draft',
    MeetingMinuteStatus.completed => 'completed',
  };

  String get label => switch (this) {
    MeetingMinuteStatus.draft => 'Draf',
    MeetingMinuteStatus.completed => 'Selesai',
  };

  static MeetingMinuteStatus fromStorage(String value) => switch (value) {
    'completed' => MeetingMinuteStatus.completed,
    _ => MeetingMinuteStatus.draft,
  };
}

class MeetingMinuteAction {
  const MeetingMinuteAction({
    this.id,
    this.itemDate,
    this.subjectDiscussion = '',
    this.assignedTo = '',
    this.dueDate,
    this.position = 0,
    this.photos = const <MeetingMinuteActionPhoto>[],
  });

  final String? id;
  final DateTime? itemDate;
  final String subjectDiscussion;
  final String assignedTo;
  final DateTime? dueDate;
  final int position;
  final List<MeetingMinuteActionPhoto> photos;

  factory MeetingMinuteAction.fromJson(JsonMap json) => MeetingMinuteAction(
    id: json.optionalString('id'),
    itemDate: _date(json.optionalString('item_date')),
    subjectDiscussion: json.optionalString('subject_discussion') ?? '',
    assignedTo: json.optionalString('assigned_to') ?? '',
    dueDate: _date(json.optionalString('due_date')),
    position: json['position'] is num ? (json['position'] as num).toInt() : 0,
    photos: _photos(json['meeting_minute_action_photo']),
  );

  Map<String, Object?> toJson({required String meetingMinuteId}) =>
      <String, Object?>{
        if (id != null) 'id': id,
        'meeting_minute_id': meetingMinuteId,
        'item_date': _dateText(itemDate),
        'subject_discussion': subjectDiscussion.trim(),
        'assigned_to': assignedTo.trim(),
        'due_date': _dateText(dueDate),
        'position': position,
      };

  static DateTime? _date(String? value) =>
      value == null || value.isEmpty ? null : DateTime.tryParse(value);

  static String? _dateText(DateTime? value) => value == null
      ? null
      : '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static List<MeetingMinuteActionPhoto> _photos(Object? raw) {
    if (raw is! List) return const <MeetingMinuteActionPhoto>[];
    final List<MeetingMinuteActionPhoto> photos =
        raw
            .map(
              (Object? item) => MeetingMinuteActionPhoto.fromJson(
                requireJsonMap(item, source: 'meeting minute action photo'),
              ),
            )
            .toList(growable: true)
          ..sort(
            (MeetingMinuteActionPhoto a, MeetingMinuteActionPhoto b) =>
                a.position.compareTo(b.position),
          );
    return photos;
  }
}

class MeetingMinuteActionPhoto {
  const MeetingMinuteActionPhoto({
    required this.id,
    required this.actionId,
    required this.storagePath,
    required this.fileName,
    required this.mimeType,
    required this.position,
  });

  final String id;
  final String actionId;
  final String storagePath;
  final String fileName;
  final String mimeType;
  final int position;

  factory MeetingMinuteActionPhoto.fromJson(JsonMap json) =>
      MeetingMinuteActionPhoto(
        id: json.requiredString('id'),
        actionId: json.requiredString('meeting_minute_action_id'),
        storagePath: json.requiredString('storage_path'),
        fileName: json.optionalString('file_name') ?? 'Foto pembahasan',
        mimeType: json.optionalString('mime_type') ?? 'image/jpeg',
        position: json['position'] is num
            ? (json['position'] as num).toInt()
            : 0,
      );
}

class MeetingMinute {
  const MeetingMinute({
    required this.id,
    required this.title,
    required this.status,
    required this.createdBy,
    required this.updatedAt,
    required this.actions,
    this.meetingDate,
    this.startTime,
    this.endTime,
    this.location = '',
    this.attendees = '',
    this.apologies = '',
    this.minuteTaker = '',
    this.distributionList = '',
    this.newBusinessAgenda = '',
    this.proposedBy = '',
    this.note = '',
  });

  final String id;
  final String title;
  final MeetingMinuteStatus status;
  final String createdBy;
  final DateTime updatedAt;
  final List<MeetingMinuteAction> actions;
  final DateTime? meetingDate;
  final String? startTime;
  final String? endTime;
  final String location;
  final String attendees;
  final String apologies;
  final String minuteTaker;
  final String distributionList;
  final String newBusinessAgenda;
  final String proposedBy;
  final String note;

  factory MeetingMinute.fromJson(JsonMap json) {
    final Object? rawActions = json['meeting_minute_action'];
    final List<MeetingMinuteAction> actions = rawActions is List
        ? rawActions
              .map(
                (Object? row) => MeetingMinuteAction.fromJson(
                  requireJsonMap(row, source: 'meeting minute action'),
                ),
              )
              .toList(growable: false)
        : const <MeetingMinuteAction>[];
    return MeetingMinute(
      id: json.requiredString('id'),
      title: json.optionalString('title') ?? '',
      status: MeetingMinuteStatusX.fromStorage(
        json.optionalString('status') ?? 'draft',
      ),
      createdBy: json.requiredString('created_by'),
      updatedAt:
          DateTime.tryParse(json.optionalString('updated_at') ?? '') ??
          DateTime.now(),
      actions: actions,
      meetingDate: MeetingMinuteAction._date(
        json.optionalString('meeting_date'),
      ),
      startTime: json.optionalString('start_time'),
      endTime: json.optionalString('end_time'),
      location: json.optionalString('location') ?? '',
      attendees: json.optionalString('attendees') ?? '',
      apologies: json.optionalString('apologies') ?? '',
      minuteTaker: json.optionalString('minute_taker') ?? '',
      distributionList: json.optionalString('distribution_list') ?? '',
      newBusinessAgenda: json.optionalString('new_business_agenda') ?? '',
      proposedBy: json.optionalString('proposed_by') ?? '',
      note: json.optionalString('note') ?? '',
    );
  }
}
