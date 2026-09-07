import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'models/machine.dart';
import 'models/work_order.dart';
import 'utils/app_colors.dart';

typedef _MachineBreakdowns = ({String name, int count, int seconds});

/// Breakdown Trend — for the selected month, how many breakdown (BM)
/// tasks each machine had, ranked worst-first, as a columnar bar chart:
/// x-axis is machine name, y-axis (bar height) is breakdown count. The
/// total downtime for that machine, in "10h35m" format, is shown as a
/// label on the bar itself — count and duration tell two different
/// parts of the same story and both matter to admin at a glance.
class BreakdownTrendChart extends StatelessWidget {
  final DateTime month; // any date within the target month
  const BreakdownTrendChart({super.key, required this.month});

  @override
  Widget build(BuildContext context) {
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEndExclusive = DateTime(month.year, month.month + 1, 1);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.leaderboard_outlined, size: 20),
              const SizedBox(width: 8),
              const Expanded(child: Text('Breakdown Trend', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Breakdown (BM) tasks per machine this month, ranked highest first.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('machines').snapshots(),
              builder: (context, machineSnapshot) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  // Deliberately NOT filtering by type: 'breakdown' in
                  // the query itself — two equality filters (type,
                  // status) plus a range filter on a third field
                  // (completedAt) is exactly the combination that needs
                  // a manual Firestore composite index, and none exists
                  // for this one (same reasoning as the "today's stats"
                  // query in technician_screen.dart). A single equality
                  // filter plus one range filter needs no composite
                  // index, so the type filter is applied client-side
                  // below instead.
                  stream: FirebaseFirestore.instance
                      .collection('work_orders')
                      .where('status', isEqualTo: 'completed')
                      .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
                      .where('completedAt', isLessThan: Timestamp.fromDate(monthEndExclusive))
                      .snapshots(),
                  builder: (context, orderSnapshot) {
                    if (machineSnapshot.hasError || orderSnapshot.hasError) {
                      return Text(
                        'Unable to load breakdown data: ${orderSnapshot.error ?? machineSnapshot.error}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      );
                    }
                    if (!machineSnapshot.hasData || !orderSnapshot.hasData) {
                      return const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Center(child: CircularProgressIndicator()));
                    }
                    final Map<String, Machine> machines = {for (final d in machineSnapshot.data!.docs) d.id: Machine.fromMap(d.id, d.data())};
                    final orders = orderSnapshot.data!.docs.map((d) => WorkOrder.fromMap(d.id, d.data())).where((o) => o.type == 'breakdown');

                    final countByMachine = <String, int>{};
                    final secondsByMachine = <String, int>{};
                    for (final o in orders) {
                      if (o.machineId.isEmpty) continue;
                      countByMachine[o.machineId] = (countByMachine[o.machineId] ?? 0) + 1;
                      secondsByMachine[o.machineId] = (secondsByMachine[o.machineId] ?? 0) + (o.durationSeconds ?? 0);
                    }

                    final rows = countByMachine.entries
                        .map<_MachineBreakdowns>((e) => (
                              name: machines[e.key]?.displayName ?? e.key,
                              count: e.value,
                              seconds: secondsByMachine[e.key] ?? 0,
                            ))
                        .toList()
                      ..sort((a, b) => b.count.compareTo(a.count));

                    if (rows.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('No breakdown tasks completed this month.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      );
                    }

                    final maxCount = rows.map((r) => r.count).reduce((a, b) => a > b ? a : b);
                    return _BreakdownBarChart(rows: rows, maxCount: maxCount);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownBarChart extends StatelessWidget {
  final List<_MachineBreakdowns> rows;
  final int maxCount;
  const _BreakdownBarChart({required this.rows, required this.maxCount});

  static const _plotHeight = 190.0;
  static const _barWidth = 54.0;
  static const _columnWidth = 84.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _yAxis(),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rows.map(_bar).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _yAxis() {
    final mid = (maxCount / 2).round();
    return SizedBox(
      height: _plotHeight,
      width: 20,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('$maxCount', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
          Text('$mid', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
          const Text('0', style: TextStyle(fontSize: 10, color: AppColors.muted)),
        ],
      ),
    );
  }

  Widget _bar(_MachineBreakdowns r) {
    const minBarHeight = 32.0;
    const maxBarHeight = _plotHeight - 22; // leaves room for the count label above the bar
    final fraction = maxCount == 0 ? 0.0 : r.count / maxCount;
    var barHeight = maxBarHeight * fraction;
    if (barHeight < minBarHeight) barHeight = minBarHeight;

    final h = r.seconds ~/ 3600;
    final m = (r.seconds % 3600) ~/ 60;
    String two(int n) => n.toString().padLeft(2, '0');
    final durationLabel = h > 0 ? '${h}h${two(m)}m' : '${m}m';

    return SizedBox(
      width: _columnWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: _plotHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('${r.count}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  width: _barWidth,
                  height: barHeight,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppColors.danger.withValues(alpha: 0.75), AppColors.danger],
                    ),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(durationLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 30,
            child: Text(
              r.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
