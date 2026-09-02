import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'models/work_order.dart';
import 'utils/app_colors.dart';

/// Total engaged hours across every task completed today (each task
/// counted once, regardless of how many people were on it) — a quick
/// "how much got done today" figure at the top of the admin dashboard.
class DailySummaryCard extends StatelessWidget {
  const DailySummaryCard({super.key});

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
      builder: (context, snapshot) {
        final orders = (snapshot.data?.docs ?? []).map((d) => WorkOrder.fromMap(d.id, d.data()));
        final totalSeconds = orders.fold<int>(0, (sum, o) => sum + (o.durationSeconds ?? 0));
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
  }
}
