import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'models/work_order.dart';
import 'utils/app_colors.dart';

/// Today's total engaged hours across all JOs and all CFs, from every
/// task completed today — a quick "how much got done today" summary at
/// the top of the admin dashboard.
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
        var joSeconds = 0, cfSeconds = 0, joTaskCount = 0, cfTaskCount = 0;
        for (final o in orders) {
          final seconds = o.durationSeconds ?? 0;
          if (o.assignedTechnicianIds.isNotEmpty) {
            joSeconds += seconds;
            joTaskCount++;
          }
          if (o.helperIds.isNotEmpty) {
            cfSeconds += seconds;
            cfTaskCount++;
          }
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
                  const Icon(Icons.summarize_outlined, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Daily Summary', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
                  Text('${orders.length} task${orders.length == 1 ? '' : 's'} completed', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _statBlock(context, Icons.engineering_outlined, hoursLabel(joSeconds), 'JO work hours · $joTaskCount task${joTaskCount == 1 ? '' : 's'}')),
                  SizedBox(height: 44, child: VerticalDivider(width: 24, color: Theme.of(context).dividerColor)),
                  Expanded(child: _statBlock(context, Icons.handyman_outlined, hoursLabel(cfSeconds), 'CF work hours · $cfTaskCount task${cfTaskCount == 1 ? '' : 's'}')),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statBlock(BuildContext context, IconData icon, String value, String label) {
    return Row(children: [
      Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 10),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        ],
      ),
    ]);
  }
}
