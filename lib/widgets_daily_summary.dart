import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'models/work_order.dart';
import 'utils/app_colors.dart';

/// Today's total engaged hours across all JOs and all CFs, from every
/// task completed today — a quick "how much got done today" summary at
/// the top of the admin dashboard. Laid out as two stacked lines (JO,
/// then CF) rather than side-by-side, since this now shares a 2x2 grid
/// cell with "Person Available" instead of spanning the full width.
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
        final orders = (snapshot.data?.docs ?? []).map((d) => WorkOrder.fromMap(d.id, d.data())).toList();

        // One task's duration counts once toward JO hours if a JO was on
        // it, and once toward CF hours if a CF was on it — a
        // helper-assisted task (both present) counts toward both, same
        // as it took both of their time simultaneously.
        var joSeconds = 0, cfSeconds = 0;
        for (final o in orders) {
          final seconds = o.durationSeconds ?? 0;
          if (o.assignedTechnicianIds.isNotEmpty) joSeconds += seconds;
          if (o.helperIds.isNotEmpty) cfSeconds += seconds;
        }

        String hoursLabel(int seconds) {
          final h = seconds ~/ 3600;
          final m = (seconds % 3600) ~/ 60;
          return '${h}h ${m}m';
        }

        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.summarize_outlined, size: 18),
                  const SizedBox(width: 6),
                  const Expanded(child: Text('Today', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                ]),
                const SizedBox(height: 10),
                _statLine(context, Icons.engineering_outlined, hoursLabel(joSeconds), 'JO work hours'),
                const SizedBox(height: 8),
                _statLine(context, Icons.handyman_outlined, hoursLabel(cfSeconds), 'CF work hours'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statLine(BuildContext context, IconData icon, String value, String label) {
    return Row(children: [
      Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 8),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted), overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    ]);
  }
}
