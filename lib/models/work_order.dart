class WorkOrder {
  final String id;
  final String type; // preventive | breakdown | calibration | adjustment
  final String machineId;
  final String description;
  final String status;
  final List<String> assignedTechnicianIds;
  final List<String> helperIds;
  final List<String> preventiveTypes;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int? durationSeconds;
  final String completionRemarks;
  final bool lateEntry;
  // When machineId points at a grouped machine's MAIN unit, these are the
  // other subunit ids the JO actually selected alongside it (see
  // utils/machine_group.dart) — empty for an ungrouped, single-machine
  // task.
  final List<String> groupMachineIds;

  WorkOrder({
    required this.id,
    required this.type,
    required this.machineId,
    required this.description,
    required this.status,
    required this.assignedTechnicianIds,
    required this.helperIds,
    required this.preventiveTypes,
    this.startedAt,
    this.completedAt,
    this.durationSeconds,
    this.completionRemarks = '',
    this.lateEntry = false,
    this.groupMachineIds = const [],
  });

  static DateTime? _date(dynamic value) {
    if (value is DateTime) return value;
    if (value == null) return null;
    try {
      return value.toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }

  factory WorkOrder.fromMap(String id, Map<String, dynamic> data) {
    return WorkOrder(
      id: id,
      type: (data['type'] ?? 'breakdown').toString(),
      machineId: (data['machineId'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      status: (data['status'] ?? 'open').toString(),
      assignedTechnicianIds: List<String>.from(data['assignedTechnicianIds'] ?? const []),
      helperIds: List<String>.from(data['helperIds'] ?? const []),
      preventiveTypes: List<String>.from(data['preventiveTypes'] ?? const []),
      startedAt: _date(data['startedAt']),
      completedAt: _date(data['completedAt']),
      durationSeconds: data['durationSeconds'] is int
          ? data['durationSeconds'] as int
          : int.tryParse('${data['durationSeconds'] ?? ''}'),
      completionRemarks: (data['completionRemarks'] ?? '').toString(),
      lateEntry: data['lateEntry'] == true,
      groupMachineIds: List<String>.from(data['groupMachineIds'] ?? const []),
    );
  }
}
