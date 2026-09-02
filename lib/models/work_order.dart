class WorkOrder {
  final String id;
  final String type; // preventive | breakdown | calibration | adjustment
  final String machineId;
  final String description;
  final String priority;
  final String status;
  final List<String> assignedTechnicianIds;
  final List<String> helperIds;
  final List<String> preventiveTypes;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int? durationSeconds;
  final String completionRemarks;
  final bool lateEntry;

  WorkOrder({
    required this.id,
    required this.type,
    required this.machineId,
    required this.description,
    required this.priority,
    required this.status,
    required this.assignedTechnicianIds,
    required this.helperIds,
    required this.preventiveTypes,
    this.startedAt,
    this.completedAt,
    this.durationSeconds,
    this.completionRemarks = '',
    this.lateEntry = false,
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
      priority: (data['priority'] ?? 'medium').toString(),
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
    );
  }
}
