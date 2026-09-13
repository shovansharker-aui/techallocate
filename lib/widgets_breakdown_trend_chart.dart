import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'models/machine.dart';
import 'models/work_order.dart';
import 'services/ai_title_service.dart';
import 'utils/app_colors.dart';
import 'utils/date_format.dart';

typedef _MachineBreakdowns = ({String name, int count, int seconds, List<WorkOrder> tasks});

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
                    final tasksByMachine = <String, List<WorkOrder>>{};
                    for (final o in orders) {
                      if (o.machineId.isEmpty) continue;
                      countByMachine[o.machineId] = (countByMachine[o.machineId] ?? 0) + 1;
                      secondsByMachine[o.machineId] = (secondsByMachine[o.machineId] ?? 0) + (o.durationSeconds ?? 0);
                      (tasksByMachine[o.machineId] ??= []).add(o);
                    }

                    final rows = countByMachine.entries
                        .map<_MachineBreakdowns>((e) => (
                              name: machines[e.key]?.displayName ?? e.key,
                              count: e.value,
                              seconds: secondsByMachine[e.key] ?? 0,
                              tasks: (tasksByMachine[e.key] ?? [])..sort((a, b) => (a.completedAt ?? DateTime(0)).compareTo(b.completedAt ?? DateTime(0))),
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
              children: rows.map((r) => _bar(context, r)).toList(),
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

  Widget _bar(BuildContext context, _MachineBreakdowns r) {
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
                InkWell(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  // Tapping (touch) or clicking (mouse/web) a bar opens
                  // the detail popup -- it stays open until dismissed by
                  // tapping outside it (showDialog's default barrier
                  // behavior) rather than closing on its own.
                  onTap: () => _showBreakdownDetail(context, r),
                  child: Container(
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

  void _showBreakdownDetail(BuildContext context, _MachineBreakdowns r) {
    showDialog<void>(
      context: context,
      // barrierDismissible defaults to true -- tapping outside the
      // dialog is exactly how it's meant to close; nothing auto-closes
      // it otherwise.
      builder: (dialogContext) => AlertDialog(
        title: Text(r.name),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _BreakdownDetailTable(tasks: r.tasks),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
        ],
      ),
    );
  }
}

/// The popup's body: one row per breakdown task on this machine, oldest
/// first. The "Reason" column is AI-generated from each task's initial +
/// completion remarks (see ai_title_service.dart) and cached on the
/// task's own `reasonSummary` field the first time it's ever shown here
/// -- every later popup open for the same task reads the cached value
/// straight from Firestore instead of calling the AI again.
class _BreakdownDetailTable extends StatefulWidget {
  final List<WorkOrder> tasks;
  const _BreakdownDetailTable({required this.tasks});

  @override
  State<_BreakdownDetailTable> createState() => _BreakdownDetailTableState();
}

class _BreakdownDetailTableState extends State<_BreakdownDetailTable> {
  final Map<String, String> _reasons = {};
  final Set<String> _pending = {};

  @override
  void initState() {
    super.initState();
    for (final t in widget.tasks) {
      if (t.reasonSummary != null && t.reasonSummary!.isNotEmpty) {
        _reasons[t.id] = t.reasonSummary!;
      }
    }
    _summarizeMissing();
  }

  // Same reasoning as the AI-title backfill screen: only skip the UI
  // update if this popup's been closed, never abort the loop itself --
  // closing the popup shouldn't stop already-started summaries from
  // being computed and cached for next time.
  void _safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  Future<void> _summarizeMissing() async {
    for (final t in widget.tasks) {
      if (_reasons.containsKey(t.id)) continue;
      _pending.add(t.id);
      _safeSetState(() {});
      final reason = await summarizeBreakdownReason(t.description, t.completionRemarks);
      if (reason != null) {
        FirebaseFirestore.instance.collection('work_orders').doc(t.id).update({'reasonSummary': reason}).catchError((Object error) {
          debugPrint('Could not save AI reason: $error');
        });
      }
      _pending.remove(t.id);
      _safeSetState(() {
        if (reason != null) _reasons[t.id] = reason;
      });
      // Stays well under the free tier's per-minute request cap rather
      // than firing every call back-to-back.
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 20,
        columns: const [
          DataColumn(label: Text('Sl')),
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Breakdown Hour')),
          DataColumn(label: Text('Reason')),
        ],
        rows: widget.tasks.asMap().entries.map((entry) {
          final i = entry.key;
          final t = entry.value;
          final seconds = t.durationSeconds ?? 0;
          final h = seconds ~/ 3600;
          final m = (seconds % 3600) ~/ 60;
          final durationLabel = h > 0 ? '${h}h ${m}m' : '${m}m';
          final reason = _reasons[t.id];
          return DataRow(cells: [
            DataCell(Text('${i + 1}')),
            DataCell(Text(t.completedAt == null ? '—' : formatDate(t.completedAt!))),
            DataCell(Text(durationLabel)),
            DataCell(
              SizedBox(
                width: 220,
                child: Text(
                  reason ?? (_pending.contains(t.id) ? 'Summarizing…' : '—'),
                  softWrap: true,
                  style: reason == null ? const TextStyle(color: AppColors.muted, fontStyle: FontStyle.italic) : null,
                ),
              ),
            ),
          ]);
        }).toList(),
      ),
    );
  }
}
