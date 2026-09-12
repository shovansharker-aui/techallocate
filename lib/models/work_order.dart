class WorkOrder {
  final String id;
  final String type; // preventive | breakdown | calibration | adjustment
  final String machineId;
  final String description;
  // AI-generated short title for an 'others' task, derived from its
  // remarks -- see services/ai_title_service.dart. Null/empty for every
  // other task type, or an 'others' task the summarizer hasn't (or
  // couldn't) produce one for yet.
  final String? summaryTitle;
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

  // Every JO who has EVER been on this task, including one who joined a
  // multi-JO task after it started and then left before it finished --
  // unlike assignedTechnicianIds (the CURRENT roster, which shrinks when
  // someone leaves early), this only ever grows. Used to credit that
  // person's own history/stats with this task even after they're no
  // longer actively on it, and to still list them as a contributor on
  // the completed task's own detail view.
  final List<String> contributorIds;
  // uid -> when each contributor joined this task (the moment they
  // started it, or were added to it). uid -> when a contributor LEFT
  // EARLY, before the task itself was fully completed by whoever
  // stayed till the end -- absent for anyone who was still on the task
  // when it finished, since their own end time is just the task's own
  // completedAt. Together these give each person's own engaged
  // interval on a shared task, which can be shorter than the task's
  // overall startedAt..completedAt span. Both are empty for any record
  // written before this tracking existed, or a solo task that never
  // needed it -- callers fall back to the task's own startedAt/
  // completedAt in that case, which is exactly correct for a task only
  // one person was ever on.
  final Map<String, DateTime> contributorJoinTimes;
  final Map<String, DateTime> contributorLeaveTimes;

  WorkOrder({
    required this.id,
    required this.type,
    required this.machineId,
    required this.description,
    this.summaryTitle,
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
    this.contributorIds = const [],
    this.contributorJoinTimes = const {},
    this.contributorLeaveTimes = const {},
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

  static Map<String, DateTime> _dateMap(dynamic value) {
    if (value is! Map) return const {};
    final result = <String, DateTime>{};
    value.forEach((key, v) {
      final d = _date(v);
      if (d != null) result[key.toString()] = d;
    });
    return result;
  }

  static String? _trimmedOrNull(dynamic value) {
    final s = value?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  factory WorkOrder.fromMap(String id, Map<String, dynamic> data) {
    return WorkOrder(
      id: id,
      type: (data['type'] ?? 'breakdown').toString(),
      machineId: (data['machineId'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      summaryTitle: _trimmedOrNull(data['summaryTitle']),
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
      contributorIds: List<String>.from(data['contributorIds'] ?? const []),
      contributorJoinTimes: _dateMap(data['contributorJoinTimes']),
      contributorLeaveTimes: _dateMap(data['contributorLeaveTimes']),
    );
  }

  /// This contributor's own engaged interval on this task — may be
  /// shorter than the task's own startedAt/completedAt on a multi-JO
  /// task they joined late or left early. [nowIfRunning] should be
  /// passed for a still-running task (completedAt is null) so an
  /// active contributor's elapsed-so-far counts; leave it null for an
  /// already-completed task.
  ({DateTime start, DateTime end})? contributorInterval(String uid, {DateTime? nowIfRunning}) {
    final start = contributorJoinTimes[uid] ?? startedAt;
    if (start == null) return null;
    final end = contributorLeaveTimes[uid] ?? completedAt ?? nowIfRunning;
    if (end == null) return null;
    return (start: start, end: end);
  }

  /// What to show as this task's "title" wherever a task list currently
  /// falls back to the machine's name -- an 'others' task with an
  /// AI-generated summaryTitle uses that instead of [machineLabel]'s own
  /// "No machine" fallback, since "No machine" says nothing about what
  /// the task actually was.
  String displayTitle({String? machineLabel}) {
    if (type == 'others' && summaryTitle != null && summaryTitle!.isNotEmpty) {
      return summaryTitle!;
    }
    return machineLabel ?? (machineId.isEmpty ? 'No machine' : machineId);
  }
}
