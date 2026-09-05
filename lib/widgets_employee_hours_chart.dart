import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'models/app_user.dart';
import 'models/work_order.dart';
import 'utils/app_colors.dart';
import 'utils/engaged_time.dart';

/// Each JO's total engaged time today, ranked highest first — a
/// horizontal bar per person instead of a chart with the usual axes,
/// since a roster of dozens of names reads far better as a sorted list
/// than crammed onto one category axis. Desktop-only (see GraphsBody):
/// a full-roster leaderboard like this needs more width than the mobile
/// Analysis page has to spare.
///
/// "Engaged" here is overlap-aware (see unionDuration): a JO running two
/// tasks at once for an hour shows one hour here, not two — even though
/// each of those two tasks still shows its own full hour wherever a
/// single task's duration is displayed (Live Activity Grid, Completed
/// Tasks, etc.), which is unaffected and correct as-is.
class EmployeeHoursCard extends StatelessWidget {
  const EmployeeHoursCard({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.bar_chart_outlined, size: 20),
              const SizedBox(width: 8),
              const Expanded(child: Text('Hours Worked · Today', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 4),
            const Text(
              "Each JO's total engaged time today — overlapping tasks are counted once, not added together.",
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'technician').snapshots(),
              builder: (context, techSnapshot) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('work_orders')
                      .where('status', isEqualTo: 'completed')
                      .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
                      .snapshots(),
                  builder: (context, completedSnapshot) {
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance.collection('work_orders').where('status', isEqualTo: 'in_progress').snapshots(),
                      builder: (context, runningSnapshot) {
                        if (techSnapshot.hasError || completedSnapshot.hasError || runningSnapshot.hasError) {
                          return const Text('Unable to load hours.');
                        }
                        if (!techSnapshot.hasData) {
                          return const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator()));
                        }
                        final techs = (techSnapshot.data?.docs ?? []).map((d) => AppUser.fromMap(d.id, d.data())).toList();
                        final completedOrders = (completedSnapshot.data?.docs ?? []).map((d) => WorkOrder.fromMap(d.id, d.data()));
                        final runningOrders = (runningSnapshot.data?.docs ?? []).map((d) => WorkOrder.fromMap(d.id, d.data()));

                        final intervals = <String, List<EngagedInterval>>{};
                        void addOrder(WorkOrder o, DateTime end) {
                          final start = o.startedAt;
                          if (start == null) return;
                          for (final id in o.assignedTechnicianIds) {
                            (intervals[id] ??= []).add((start: start, end: end));
                          }
                        }
                        for (final o in completedOrders) {
                          addOrder(o, o.completedAt ?? (o.startedAt ?? now));
                        }
                        for (final o in runningOrders) {
                          addOrder(o, now);
                        }

                        final rows = techs
                            .map((t) => (
                                  name: t.name.isEmpty ? t.employeeId : t.name,
                                  seconds: unionDuration(intervals[t.uid] ?? const <EngagedInterval>[]).inSeconds,
                                ))
                            .toList()
                          ..sort((a, b) => b.seconds.compareTo(a.seconds));

                        if (rows.isEmpty) {
                          return const Text('No Junior Officers found.', style: TextStyle(color: AppColors.muted, fontSize: 12));
                        }

                        final maxSeconds = rows.first.seconds;
                        return Column(children: rows.map((r) => _hourRow(r.name, r.seconds, maxSeconds)).toList());
                      },
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _hourRow(String name, int seconds, int maxSeconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final label = h > 0 ? '${h}h ${m}m' : '${m}m';
    final fraction = maxSeconds == 0 ? 0.0 : seconds / maxSeconds;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(width: 130, child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              return Stack(children: [
                Container(height: 14, decoration: BoxDecoration(color: AppColors.muted.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(7))),
                Container(
                  height: 14,
                  width: constraints.maxWidth * fraction,
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(7)),
                ),
              ]);
            }),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 56, child: Text(label, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
