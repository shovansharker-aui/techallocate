import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'models/work_order.dart';
import 'utils/app_colors.dart';
import 'utils/engaged_time.dart';

/// A bar chart of one month's combined work hours, day by day —
/// x-axis is the date, y-axis (bar height) is that day's combined work
/// hours. "Combined" is overlap-aware (see unionDuration), same
/// convention as the dashboard's "Work Done" total: two tasks active at
/// once that day, whether the same JO or two different JOs, count as
/// one hour of that day's bar, not two — this is real wall-clock time
/// with work happening, not total task-hours added up. Tapping a bar
/// jumps the Analysis view to that day's Daily view, tying the two
/// views together instead of leaving Monthly as a dead end.
class MonthlyWorkHoursChart extends StatelessWidget {
  final DateTime month; // any date within the target month
  final ValueChanged<DateTime> onSelectDay;

  const MonthlyWorkHoursChart({super.key, required this.month, required this.onSelectDay});

  @override
  Widget build(BuildContext context) {
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEndExclusive = DateTime(month.year, month.month + 1, 1);
    final daysInMonth = monthEndExclusive.difference(monthStart).inDays;

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
              const Expanded(child: Text('Daily Work Hours', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 4),
            const Text(
              "Combined work hours per day — overlapping tasks are counted once, not added together. Tap a day to see its full breakdown.",
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('work_orders')
                  .where('status', isEqualTo: 'completed')
                  .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
                  .where('completedAt', isLessThan: Timestamp.fromDate(monthEndExclusive))
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('Unable to load this month: ${snapshot.error}', style: const TextStyle(color: AppColors.muted, fontSize: 12));
                }
                if (!snapshot.hasData) {
                  return const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Center(child: CircularProgressIndicator()));
                }
                final orders = snapshot.data!.docs.map((d) => WorkOrder.fromMap(d.id, d.data()));

                // Each order's interval is clipped to the calendar day
                // it completed on (a task that ran past midnight only
                // contributes the portion that actually happened that
                // day), then every day's clipped intervals are merged
                // (unioned) separately — so one day's bar can never
                // read more than 24 hours, and overlapping tasks that
                // day are counted once.
                final intervalsByDay = <int, List<EngagedInterval>>{};
                for (final o in orders) {
                  final start = o.startedAt;
                  final completedAt = o.completedAt;
                  if (start == null || completedAt == null) continue;
                  final day = completedAt.day;
                  final dayStart = DateTime(month.year, month.month, day);
                  final dayEnd = dayStart.add(const Duration(days: 1));
                  final clippedStart = start.isBefore(dayStart) ? dayStart : start;
                  final clippedEnd = completedAt.isAfter(dayEnd) ? dayEnd : completedAt;
                  if (!clippedEnd.isAfter(clippedStart)) continue;
                  (intervalsByDay[day] ??= []).add((start: clippedStart, end: clippedEnd));
                }
                final secondsByDay = <int, int>{for (final e in intervalsByDay.entries) e.key: unionDuration(e.value).inSeconds};
                final maxSeconds = secondsByDay.values.fold<int>(0, (m, v) => v > m ? v : m);

                return _DailyHoursBarChart(
                  daysInMonth: daysInMonth,
                  secondsByDay: secondsByDay,
                  maxSeconds: maxSeconds,
                  onSelectDay: (day) => onSelectDay(DateTime(month.year, month.month, day)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyHoursBarChart extends StatelessWidget {
  final int daysInMonth;
  final Map<int, int> secondsByDay;
  final int maxSeconds;
  final ValueChanged<int> onSelectDay;

  const _DailyHoursBarChart({required this.daysInMonth, required this.secondsByDay, required this.maxSeconds, required this.onSelectDay});

  static const _plotHeight = 190.0;
  static const _barWidth = 18.0;
  static const _columnWidth = 30.0;

  static String _hm(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    if (maxSeconds == 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text('No completed tasks this month yet.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
      );
    }
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
              children: List.generate(daysInMonth, (i) => _bar(i + 1)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _yAxis() {
    return SizedBox(
      height: _plotHeight,
      width: 40,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(_hm(maxSeconds), style: const TextStyle(fontSize: 10, color: AppColors.muted)),
          Text(_hm(maxSeconds ~/ 2), style: const TextStyle(fontSize: 10, color: AppColors.muted)),
          const Text('0', style: TextStyle(fontSize: 10, color: AppColors.muted)),
        ],
      ),
    );
  }

  Widget _bar(int day) {
    const minBarHeight = 3.0;
    const maxBarHeight = _plotHeight - 18; // leaves room for the day-of-month label, drawn only on tap via tooltip
    final seconds = secondsByDay[day] ?? 0;
    final fraction = maxSeconds == 0 ? 0.0 : seconds / maxSeconds;
    var barHeight = maxBarHeight * fraction;
    if (seconds > 0 && barHeight < minBarHeight) barHeight = minBarHeight;

    return Tooltip(
      message: seconds == 0 ? 'Day $day — no completed tasks' : 'Day $day — ${_hm(seconds)}',
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => onSelectDay(day),
        child: SizedBox(
          width: _columnWidth,
          child: Column(
            children: [
              SizedBox(
                height: _plotHeight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      width: _barWidth,
                      height: barHeight,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [AppColors.primary.withValues(alpha: 0.7), AppColors.primary],
                        ),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text('$day', style: const TextStyle(fontSize: 9, color: AppColors.muted, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
