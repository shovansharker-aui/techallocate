import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'models/app_user.dart';
import 'models/machine.dart';
import 'models/work_order.dart';
import 'utils/app_colors.dart';
import 'utils/engaged_time.dart';
import 'utils/task_type.dart';

/// Shows an engaged JO's live snapshot — reached by tapping their name
/// box on the "Available Now" roster while they're busy (a free JO's
/// box isn't tappable — there's nothing running to show). Employee ID,
/// today's combined engaged time so far, and every task they currently
/// have running (machine, type, maintenance type if preventive, and
/// their initial remarks if any).
Future<void> showEngagedJoDetail(BuildContext context, AppUser user) {
  return showDialog<void>(
    context: context,
    builder: (context) => _EngagedJoDetailDialog(user: user),
  );
}

class _EngagedJoDetailDialog extends StatelessWidget {
  final AppUser user;
  const _EngagedJoDetailDialog({required this.user});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return AlertDialog(
      title: Row(children: [
        CircleAvatar(child: Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?')),
        const SizedBox(width: 10),
        Expanded(child: Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
      content: SizedBox(
        width: 420,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('machines').snapshots(),
          builder: (context, machineSnapshot) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              // Deliberately no completedAt range in this query — see
              // the identical reasoning in technician_screen.dart's own
              // "today's stats" query: array-contains + equality plus a
              // range filter on a third field needs a manual composite
              // index this project doesn't have. Today's cutoff is
              // applied client-side below instead.
              stream: FirebaseFirestore.instance
                  .collection('work_orders')
                  .where('assignedTechnicianIds', arrayContains: user.uid)
                  .where('status', isEqualTo: 'completed')
                  .snapshots(),
              builder: (context, completedSnapshot) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('work_orders')
                      .where('assignedTechnicianIds', arrayContains: user.uid)
                      .where('status', isEqualTo: 'in_progress')
                      .snapshots(),
                  builder: (context, runningSnapshot) {
                    if (machineSnapshot.hasError || completedSnapshot.hasError || runningSnapshot.hasError) {
                      return const Text('Unable to load details.', style: TextStyle(color: AppColors.muted));
                    }
                    if (!machineSnapshot.hasData || !completedSnapshot.hasData || !runningSnapshot.hasData) {
                      return const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Center(child: CircularProgressIndicator()));
                    }
                    final Map<String, Machine> machines = {for (final d in machineSnapshot.data!.docs) d.id: Machine.fromMap(d.id, d.data())};
                    final completedToday = completedSnapshot.data!.docs
                        .map((d) => WorkOrder.fromMap(d.id, d.data()))
                        .where((o) => o.completedAt != null && !o.completedAt!.isBefore(todayStart));
                    final running = runningSnapshot.data!.docs.map((d) => WorkOrder.fromMap(d.id, d.data())).toList()
                      ..sort((a, b) => (a.startedAt ?? now).compareTo(b.startedAt ?? now));

                    // Today's combined engaged time — same overlap-aware
                    // convention as everywhere else a "total hours"
                    // figure is shown (see unionDuration): running tasks'
                    // elapsed-so-far is included, since this dialog is
                    // specifically about someone who's engaged right now.
                    final intervals = <EngagedInterval>[];
                    for (final o in completedToday) {
                      final start = o.startedAt;
                      if (start == null) continue;
                      intervals.add((start: start, end: o.completedAt ?? start));
                    }
                    for (final o in running) {
                      final start = o.startedAt;
                      if (start == null) continue;
                      intervals.add((start: start, end: now));
                    }
                    final todaySeconds = unionDuration(intervals).inSeconds;
                    final h = todaySeconds ~/ 3600;
                    final m = (todaySeconds % 3600) ~/ 60;
                    final todayLabel = h > 0 ? '${h}h ${m}m' : '${m}m';

                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _detailRow(context, 'Employee ID', user.employeeId.isEmpty ? '—' : user.employeeId),
                          _detailRow(context, "Today's work hour", todayLabel),
                          const SizedBox(height: 12),
                          Text(
                            running.length == 1 ? 'Running Task' : 'Running Tasks (${running.length})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.muted),
                          ),
                          const SizedBox(height: 6),
                          if (running.isEmpty)
                            const Text('No running tasks.', style: TextStyle(color: AppColors.muted, fontSize: 13))
                          else
                            ...running.map((o) => _taskCard(o, machines[o.machineId])),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _taskCard(WorkOrder o, Machine? machine) {
    final maintenanceTypes = o.type == 'preventive' && o.preventiveTypes.isNotEmpty ? o.preventiveTypes.join(', ') : null;
    final remarks = o.description.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.muted.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            machine?.displayName ?? (o.machineId.isEmpty ? 'No machine' : o.machineId),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(taskTypeCodeAndName(o.type), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          if (maintenanceTypes != null) ...[
            const SizedBox(height: 2),
            Text('Maintenance type: $maintenanceTypes', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
          if (remarks.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Initial remarks: $remarks', style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
