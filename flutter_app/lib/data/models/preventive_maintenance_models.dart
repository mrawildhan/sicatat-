import '../models/sicatat_types.dart';

class PreventiveMaintenanceWorkOrder {
  const PreventiveMaintenanceWorkOrder({
    required this.workOrder,
    required this.description,
    required this.equipmentReference,
    required this.crew,
    required this.site,
    required this.status,
    this.raisedOn,
    this.plannedStartOn,
    this.assignedTo,
    this.assignedToDescription,
    this.priority,
    this.priorityDescription,
  });

  factory PreventiveMaintenanceWorkOrder.fromJson(JsonMap json) =>
      PreventiveMaintenanceWorkOrder(
        workOrder: json.requiredString('work_order'),
        description: json.requiredString('work_order_description'),
        equipmentReference: json.requiredString('equipment_reference'),
        crew: json.requiredString('crew_code'),
        site: json.requiredString('site_code'),
        status: json.requiredString('status_code'),
        raisedOn: _date(json.optionalString('raised_on')),
        plannedStartOn: _date(json.optionalString('planned_start_on')),
        assignedTo: json.optionalString('assigned_to'),
        assignedToDescription: json.optionalString('assigned_to_description'),
        priority: json.optionalString('priority'),
        priorityDescription: json.optionalString('priority_description'),
      );

  final String workOrder;
  final String description;
  final String equipmentReference;
  final String crew;
  final String site;
  final String status;
  final DateTime? raisedOn;
  final DateTime? plannedStartOn;
  final String? assignedTo;
  final String? assignedToDescription;
  final String? priority;
  final String? priorityDescription;

  static DateTime? _date(String? value) =>
      value == null ? null : DateTime.tryParse(value);
}

class PreventiveMaintenanceSyncResult {
  const PreventiveMaintenanceSyncResult({
    required this.changed,
    required this.rows,
    this.updatedAt,
  });

  final bool changed;
  final int rows;
  final DateTime? updatedAt;
}
