import 'package:csv/csv.dart';
import '../models/app_user.dart';
import '../models/helper.dart';
import '../models/machine.dart';
import '../models/work_order.dart';
import 'task_type.dart';

/// Builds the CSV backup content for a set of completed work orders,
/// resolving machine/technician/CF ids to human-readable names using the
/// lookup maps passed in. Pure and synchronous — callers fetch the data
/// first (see BackupExportScreen), this just formats it.
String buildWorkOrdersCsv({
  required List<WorkOrder> orders,
  required Map<String, Machine> machines,
  required Map<String, AppUser> technicians,
  required Map<String, Helper> helpers,
}) {
  String formatDateTime(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  String formatDuration(int? seconds) {
    if (seconds == null) return '';
    final d = Duration(seconds: seconds);
    return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  }

  final rows = <List<dynamic>>[
    [
      'Type Code',
      'Type',
      'Preventive Sub-types',
      'Machine',
      'Equipment ID',
      'Category',
      'Technician(s)',
      'CF(s)',
      'Started At',
      'Completed At',
      'Duration',
      'Priority',
      'Remarks',
      'Late Entry',
    ],
  ];

  for (final order in orders) {
    final machine = machines[order.machineId];
    final techNames = order.assignedTechnicianIds.map((id) => technicians[id]?.name).whereType<String>().join(', ');
    final helperNames = order.helperIds.map((id) => helpers[id]?.name).whereType<String>().join(', ');

    rows.add([
      taskTypeCode(order.type),
      taskTypeName(order.type),
      order.preventiveTypes.join(', '),
      machine?.displayName ?? (order.machineId.isEmpty ? '' : order.machineId),
      machine?.equipmentId ?? '',
      machine?.category ?? '',
      techNames,
      helperNames,
      formatDateTime(order.startedAt),
      formatDateTime(order.completedAt),
      formatDuration(order.durationSeconds),
      order.priority,
      order.completionRemarks,
      order.lateEntry ? 'Yes' : 'No',
    ]);
  }

  return const ListToCsvConverter().convert(rows);
}

/// A short, filesystem-safe filename for a given export range, e.g.
/// "techallocate_backup_2026-08-25_to_2026-08-31.csv".
String backupFileName(DateTime start, DateTime end) {
  String iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return 'techallocate_backup_${iso(start)}_to_${iso(end)}.csv';
}
