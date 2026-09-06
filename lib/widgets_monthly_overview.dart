import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'models/work_order.dart';
import 'utils/app_colors.dart';

/// A calendar-heatmap view of one month — each day cell shaded by that
/// day's total completed task-hours (every task counted once,
/// regardless of how many people were on it, same convention as the
/// dashboard's "Work Done" total), darker meaning more work done.
/// Tapping a day jumps the Analysis view to that day's Daily view,
/// tying the two views together instead of leaving Monthly as a
/// dead end.
class MonthlyOverviewCalendar extends StatelessWidget {
  final DateTime month; // any date within the target month
  final ValueChanged<DateTime> onSelectDay;

  const MonthlyOverviewCalendar({super.key, required this.month, required this.onSelectDay});

  @override
  Widget build(BuildContext context) {
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEndExclusive = DateTime(month.year, month.month + 1, 1);
    final daysInMonth = monthEndExclusive.difference(monthStart).inDays;
    // Dart's DateTime.weekday is 1=Monday..7=Sunday; this grid starts
    // the week on Monday, so day 1's column is (weekday - 1).
    final leadingBlanks = monthStart.weekday - 1;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.calendar_month_outlined, size: 20),
              const SizedBox(width: 8),
              const Expanded(child: Text('Daily Work Hours', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Darker = more total task-hours that day. Tap a day to see its full breakdown.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('work_orders')
                  .where('status', isEqualTo: 'completed')
                  .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
                  .where('completedAt', isLessThan: Timestamp.fromDate(monthEndExclusive))
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Text('Unable to load this month.', style: TextStyle(color: AppColors.muted, fontSize: 12));
                if (!snapshot.hasData) {
                  return const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator()));
                }
                final orders = (snapshot.data?.docs ?? []).map((d) => WorkOrder.fromMap(d.id, d.data()));
                final secondsByDay = <int, int>{};
                for (final o in orders) {
                  final completedAt = o.completedAt;
                  if (completedAt == null) continue;
                  secondsByDay[completedAt.day] = (secondsByDay[completedAt.day] ?? 0) + (o.durationSeconds ?? 0);
                }
                final maxSeconds = secondsByDay.values.fold<int>(0, (m, v) => v > m ? v : m);

                return Column(children: [
                  _weekdayHeader(),
                  const SizedBox(height: 6),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 4, crossAxisSpacing: 4),
                    itemCount: leadingBlanks + daysInMonth,
                    itemBuilder: (context, i) {
                      if (i < leadingBlanks) return const SizedBox.shrink();
                      final day = i - leadingBlanks + 1;
                      final date = DateTime(month.year, month.month, day);
                      final seconds = secondsByDay[day] ?? 0;
                      final intensity = maxSeconds == 0 ? 0.0 : seconds / maxSeconds;
                      final isFuture = date.isAfter(DateTime.now());
                      return _dayCell(day, seconds, intensity, isFuture);
                    },
                  ),
                ]);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _weekdayHeader() {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      children: labels
          .map((l) => Expanded(child: Center(child: Text(l, style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.bold)))))
          .toList(),
    );
  }

  Widget _dayCell(int day, int seconds, double intensity, bool isFuture) {
    final filled = !isFuture && intensity > 0;
    final bg = isFuture ? Colors.transparent : AppColors.primary.withValues(alpha: 0.10 + intensity * 0.55);
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final tooltip = seconds == 0 ? 'No completed tasks' : (h > 0 ? '${h}h ${m}m of task time' : '${m}m of task time');
    return Tooltip(
      message: isFuture ? '' : tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: isFuture ? null : () => onSelectDay(DateTime(month.year, month.month, day)),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.muted.withValues(alpha: 0.18)),
          ),
          alignment: Alignment.center,
          child: Text(
            '$day',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: filled && intensity > 0.55 ? Colors.white : null),
          ),
        ),
      ),
    );
  }
}
