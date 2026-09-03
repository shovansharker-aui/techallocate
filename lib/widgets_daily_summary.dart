import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'models/work_order.dart';
import 'utils/app_colors.dart';

/// Total engaged hours across every task completed today, PLUS however
/// long any still-running task has been going so far — each task
/// counted once, regardless of how many people were on it. A running
/// task's time updates automatically as the Firestore doc it's built
/// from keeps streaming, same as everywhere else "still in progress"
/// time is shown in this app.
class DailySummaryCard extends StatefulWidget {
  const DailySummaryCard({super.key});

  @override
  State<DailySummaryCard> createState() => _DailySummaryCardState();
}

class _DailySummaryCardState extends State<DailySummaryCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Without this, the running-task portion of the total would only
    // visibly change whenever some unrelated Firestore write happened to
    // trigger a rebuild — same reasoning as the live-activity grid's own
    // ticker for its running-time labels.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('work_orders')
          .where('status', isEqualTo: 'completed')
          .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .snapshots(),
      builder: (context, completedSnapshot) {
        // Separate query (plain equality, no date range) since
        // 'in_progress' tasks have no completedAt to filter by at all.
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('work_orders').where('status', isEqualTo: 'in_progress').snapshots(),
          builder: (context, runningSnapshot) {
            final completedOrders = (completedSnapshot.data?.docs ?? []).map((d) => WorkOrder.fromMap(d.id, d.data()));
            final runningOrders = (runningSnapshot.data?.docs ?? []).map((d) => WorkOrder.fromMap(d.id, d.data()));

            var totalSeconds = completedOrders.fold<int>(0, (sum, o) => sum + (o.durationSeconds ?? 0));
            for (final o in runningOrders) {
              final start = o.startedAt;
              if (start == null) continue;
              final elapsed = now.difference(start).inSeconds;
              totalSeconds += elapsed < 0 ? 0 : elapsed;
            }
            final h = totalSeconds ~/ 3600;
            final m = (totalSeconds % 3600) ~/ 60;

            return Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(children: [
                      const Icon(Icons.summarize_outlined, size: 18),
                      const SizedBox(width: 6),
                      const Expanded(child: Text('Work Done', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                    ]),
                    const SizedBox(height: 14),
                    Text('${h}h ${m}m', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                    const Text('total work hours today', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}