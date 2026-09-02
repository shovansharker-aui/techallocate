import 'package:csv/csv.dart';
import '../models/app_user.dart';
import '../models/helper.dart';
import '../models/machine.dart';
import '../models/work_order.dart';
import 'date_format.dart';
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
      'Other Units',
      'Equipment ID',
      'Category',
      'Technician(s)',
      'CF(s)',
      'Started At',
      'Completed At',
      'Duration',
      'Remarks',
      'Late Entry',
    ],
  ];

  for (final order in orders) {
    final machine = machines[order.machineId];
    final techNames = order.assignedTechnicianIds.map((id) => technicians[id]?.name).whereType<String>().join(', ');
    final helperNames = order.helperIds.map((id) => helpers[id]?.name).whereType<String>().join(', ');
    // Original equipment name here — never the nickname — even though
    // the app shows the nickname to admin elsewhere. Backups are meant
    // to match the underlying equipment records exactly.
    final otherUnits = order.groupMachineIds.map((id) => machines[id]?.equipmentId).whereType<String>().join(', ');

    rows.add([
      taskTypeCode(order.type),
      taskTypeName(order.type),
      order.preventiveTypes.join(', '),
      machine?.equipmentName ?? (order.machineId.isEmpty ? '' : order.machineId),
      otherUnits,
      machine?.equipmentId ?? '',
      machine?.category ?? '',
      techNames,
      helperNames,
      formatDateTime12h(order.startedAt),
      formatDateTime12h(order.completedAt),
      formatDuration(order.durationSeconds),
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
