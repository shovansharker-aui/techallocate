import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'models/work_order.dart';
import 'utils/app_colors.dart';
import 'utils/date_format.dart';

const _taskLineColor = Color(0xFF5B9BD5);
const _personLineColor = Color(0xFFED7D31);

/// Work density from whenever the day's first task actually started up
/// to now (or, for a past day, up to end of day) -- two overlaid lines
/// showing (1) how many tasks were concurrently running and (2) how many
/// unique people (JO + CF combined) were concurrently engaged, at each
/// sampled moment.
///
/// [customRange] switches to a multi-day mode instead: the same two
/// series, but each point is the AVERAGE across every day in the range
/// at that time-of-day, so e.g. "9:00 AM" reads as "on average, this
/// many people were engaged at 9 AM across the selected days" rather
/// than one specific day's timeline. [date] is ignored whenever
/// [customRange] is set.
///
/// This card is meant to be placed in a page with real room to show it
/// (the desktop Graphs section, or the mobile "Today's Summary" detail
/// page) rather than a small dashboard tile, so it always renders at
/// full size with axis labels — no separate tap-to-expand view needed
/// anymore.
class WorkDensityCard extends StatelessWidget {
  // null = today, live, window keeps growing to now (the original,
  // still-default behavior). A past date shows that whole day instead.
  // Only the desktop Analysis view ever passes a non-null date/range
  // (see GraphsBody's nav) — the mobile embed always shows today.
  final DateTime? date;
  final DateTimeRange? customRange;
  const WorkDensityCard({super.key, this.date, this.customRange});

  @override
  Widget build(BuildContext context) {
    if (customRange != null) {
      return _WorkDensityAggregateCard(range: customRange!);
    }

    final now = DateTime.now();
    final day = date ?? now;
    final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEndExclusive = dayStart.add(const Duration(days: 1));
    final windowEnd = isToday ? now : DateTime(day.year, day.month, day.day, 23, 59, 59);
    final titleSuffix = isToday ? 'Today' : formatDate(day);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.show_chart, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Work Density · $titleSuffix', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              // Finds this specific day's own earliest task start (rather
              // than assuming a fixed start-of-day) so the chart's x-axis
              // begins exactly when work actually began that day.
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('work_orders')
                    .where('startedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
                    .where('startedAt', isLessThan: Timestamp.fromDate(dayEndExclusive))
                    .snapshots(),
                builder: (context, startedSnapshot) {
                  if (startedSnapshot.hasError) {
                    return Center(child: Text('Unable to load: ${startedSnapshot.error}', style: const TextStyle(color: AppColors.muted, fontSize: 12)));
                  }
                  if (!startedSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final starts = startedSnapshot.data!.docs
                      .map((d) => WorkOrder.fromMap(d.id, d.data()).startedAt)
                      .whereType<DateTime>();
                  if (starts.isEmpty) {
                    return Center(
                      child: Text(
                        isToday ? "No tasks started yet today." : 'No tasks were started this day.',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    );
                  }
                  final windowStart = starts.reduce((a, b) => a.isBefore(b) ? a : b);
                  return _WorkDensityChart(windowStart: windowStart, windowEnd: windowEnd);
                },
              ),
            ),
            const SizedBox(height: 10),
            _legend(),
          ],
        ),
      ),
    );
  }
}

Widget _legend() {
  return Wrap(spacing: 14, runSpacing: 4, children: [
    _legendItem('Tasks running', _taskLineColor),
    _legendItem('People engaged', _personLineColor),
  ]);
}

Widget _legendItem(String label, Color color) {
  return Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 14, height: 3, color: color),
    const SizedBox(width: 6),
    Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600)),
  ]);
}

/// Fetches every work order whose active interval overlaps
/// [windowStart, windowEnd], samples the window at regular intervals,
/// and renders two overlaid lines: concurrent task count and unique
/// concurrent person count at each sampled moment.
class _WorkDensityChart extends StatelessWidget {
  final DateTime windowStart;
  final DateTime windowEnd;

  const _WorkDensityChart({required this.windowStart, required this.windowEnd});

  @override
  Widget build(BuildContext context) {
    // A wider window (later in the day) is sampled more coarsely so the
    // point count — and therefore the drawing work — stays reasonable;
    // an early-morning check gets fine-grained 5-minute samples, a
    // late-evening check steps up to 15.
    final windowMinutes = windowEnd.difference(windowStart).inMinutes;
    final stepMinutes = windowMinutes <= 240 ? 5 : (windowMinutes <= 480 ? 10 : 15);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('work_orders').where('status', isEqualTo: 'in_progress').snapshots(),
      builder: (context, runningSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('work_orders')
              .where('status', isEqualTo: 'completed')
              .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(windowStart))
              .where('completedAt', isLessThanOrEqualTo: Timestamp.fromDate(windowEnd))
              .snapshots(),
          builder: (context, completedSnapshot) {
            final orders = [
              ...(runningSnapshot.data?.docs ?? []).map((d) => WorkOrder.fromMap(d.id, d.data())),
              ...(completedSnapshot.data?.docs ?? []).map((d) => WorkOrder.fromMap(d.id, d.data())),
            ];

            final sampleCount = (windowMinutes / stepMinutes).ceil().clamp(2, 300);
            final taskSeries = <double>[];
            final personSeries = <double>[];
            final times = <DateTime>[];

            for (var i = 0; i <= sampleCount; i++) {
              final t = windowStart.add(Duration(minutes: (stepMinutes * i)));
              final sampleTime = t.isAfter(windowEnd) ? windowEnd : t;
              times.add(sampleTime);

              var taskCount = 0;
              final people = <String>{};
              for (final o in orders) {
                final start = o.startedAt;
                if (start == null) continue;
                final end = o.completedAt ?? windowEnd;
                if (!sampleTime.isBefore(start) && !sampleTime.isAfter(end)) {
                  taskCount++;
                  people.addAll(o.assignedTechnicianIds);
                  people.addAll(o.helperIds);
                }
              }
              taskSeries.add(taskCount.toDouble());
              personSeries.add(people.length.toDouble());

              if (sampleTime == windowEnd) break;
            }

            return CustomPaint(
              painter: _LineChartPainter(taskSeries: taskSeries, personSeries: personSeries, times: times),
              child: Container(),
            );
          },
        );
      },
    );
  }
}

/// Multi-day version: same two series, but each sampled time-of-day is
/// averaged across every day in [range] instead of showing one day's
/// own timeline.
class _WorkDensityAggregateCard extends StatelessWidget {
  final DateTimeRange range;
  const _WorkDensityAggregateCard({required this.range});

  @override
  Widget build(BuildContext context) {
    final rangeStartDay = DateTime(range.start.year, range.start.month, range.start.day);
    final rangeEndExclusive = DateTime(range.end.year, range.end.month, range.end.day).add(const Duration(days: 1));
    final now = DateTime.now();
    final includesToday = !now.isBefore(rangeStartDay) && now.isBefore(rangeEndExclusive);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.show_chart, size: 20),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    'Work Density · ${formatDate(rangeStartDay)} – ${formatDate(range.end)}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Average concurrent tasks/people by time of day, across every day in this range.',
              style: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('work_orders')
                    .where('startedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStartDay))
                    .where('startedAt', isLessThan: Timestamp.fromDate(rangeEndExclusive))
                    .snapshots(),
                builder: (context, startedSnapshot) {
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance.collection('work_orders').where('status', isEqualTo: 'in_progress').snapshots(),
                    builder: (context, runningSnapshot) {
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('work_orders')
                            .where('status', isEqualTo: 'completed')
                            .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStartDay))
                            .where('completedAt', isLessThan: Timestamp.fromDate(rangeEndExclusive))
                            .snapshots(),
                        builder: (context, completedSnapshot) {
                          if (!startedSnapshot.hasData || !runningSnapshot.hasData || !completedSnapshot.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final startedOrders = startedSnapshot.data!.docs.map((d) => WorkOrder.fromMap(d.id, d.data())).toList();
                          if (startedOrders.isEmpty) {
                            return const Center(child: Text('No tasks were started in this range.', style: TextStyle(color: AppColors.muted, fontSize: 12)));
                          }

                          // Union by id: a task might qualify via more
                          // than one of the three queries above.
                          final pool = <String, WorkOrder>{};
                          for (final o in startedOrders) {
                            pool[o.id] = o;
                          }
                          for (final d in runningSnapshot.data!.docs) {
                            final o = WorkOrder.fromMap(d.id, d.data());
                            pool[o.id] = o;
                          }
                          for (final d in completedSnapshot.data!.docs) {
                            final o = WorkOrder.fromMap(d.id, d.data());
                            pool[o.id] = o;
                          }
                          final orders = pool.values.toList();

                          final days = <DateTime>[];
                          for (var d = rangeStartDay; d.isBefore(rangeEndExclusive); d = d.add(const Duration(days: 1))) {
                            days.add(d);
                          }

                          // Earliest hour-of-day any day's first task
                          // began, across the whole range.
                          double? globalStartHour;
                          for (final o in startedOrders) {
                            final s = o.startedAt;
                            if (s == null) continue;
                            final hour = s.hour + s.minute / 60.0;
                            if (globalStartHour == null || hour < globalStartHour) globalStartHour = hour;
                          }
                          globalStartHour ??= 8.0;
                          final globalEndHour = includesToday ? (now.hour + now.minute / 60.0) : 24.0;
                          if (globalEndHour <= globalStartHour) {
                            return const Center(child: Text("Not enough of today has happened yet to chart.", style: TextStyle(color: AppColors.muted, fontSize: 12)));
                          }

                          const stepMinutes = 15;
                          final totalSteps = (((globalEndHour - globalStartHour) * 60) / stepMinutes).ceil().clamp(2, 200);

                          final taskSeries = <double>[];
                          final personSeries = <double>[];
                          final times = <DateTime>[];
                          final labelDay = days.first;

                          for (var i = 0; i <= totalSteps; i++) {
                            final hour = globalStartHour + (globalEndHour - globalStartHour) * i / totalSteps;
                            final h = hour.floor();
                            final min = ((hour - h) * 60).round();
                            times.add(DateTime(labelDay.year, labelDay.month, labelDay.day, h, min));

                            var taskTotal = 0.0;
                            var personTotal = 0.0;
                            for (final day in days) {
                              final dayIsToday = day.year == now.year && day.month == now.month && day.day == now.day;
                              final sampleTime = DateTime(day.year, day.month, day.day, h, min);
                              var taskCount = 0;
                              final people = <String>{};
                              for (final o in orders) {
                                final start = o.startedAt;
                                if (start == null) continue;
                                final end = o.completedAt ?? (dayIsToday ? now : DateTime(day.year, day.month, day.day, 23, 59, 59));
                                if (!sampleTime.isBefore(start) && !sampleTime.isAfter(end)) {
                                  taskCount++;
                                  people.addAll(o.assignedTechnicianIds);
                                  people.addAll(o.helperIds);
                                }
                              }
                              taskTotal += taskCount;
                              personTotal += people.length;
                            }
                            taskSeries.add(taskTotal / days.length);
                            personSeries.add(personTotal / days.length);
                          }

                          return CustomPaint(
                            painter: _LineChartPainter(taskSeries: taskSeries, personSeries: personSeries, times: times),
                            child: Container(),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            _legend(),
          ],
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> taskSeries;
  final List<double> personSeries;
  final List<DateTime> times;

  _LineChartPainter({required this.taskSeries, required this.personSeries, required this.times});

  @override
  void paint(Canvas canvas, Size size) {
    if (taskSeries.isEmpty) return;
    const leftPad = 28.0;
    const bottomPad = 22.0;
    final chartRect = Rect.fromLTWH(leftPad, 4, size.width - leftPad - 4, size.height - bottomPad - 4);

    final maxVal = [...taskSeries, ...personSeries].fold<double>(1, (m, v) => v > m ? v : m);
    final gridPaint = Paint()..color = AppColors.muted.withValues(alpha: 0.15)..strokeWidth = 1;
    const textStyle = TextStyle(fontSize: 9, color: AppColors.muted);

    // Horizontal grid lines at 0, half, and max.
    for (final fraction in [0.0, 0.5, 1.0]) {
      final y = chartRect.bottom - fraction * chartRect.height;
      canvas.drawLine(Offset(chartRect.left, y), Offset(chartRect.right, y), gridPaint);
      final label = (maxVal * fraction).round().toString();
      final painter = TextPainter(text: TextSpan(text: label, style: textStyle), textDirection: TextDirection.ltr)..layout();
      painter.paint(canvas, Offset(0, y - painter.height / 2));
    }

    void drawSeries(List<double> series, Color color) {
      final path = Path();
      for (var i = 0; i < series.length; i++) {
        final x = chartRect.left + (series.length == 1 ? 0 : chartRect.width * i / (series.length - 1));
        final y = chartRect.bottom - (series[i] / maxVal) * chartRect.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.4..strokeJoin = StrokeJoin.round);
    }

    drawSeries(taskSeries, _taskLineColor);
    drawSeries(personSeries, _personLineColor);

    if (times.isNotEmpty) {
      for (final fraction in [0.0, 0.5, 1.0]) {
        final index = ((times.length - 1) * fraction).round();
        final label = formatTime12h(times[index]);
        final painter = TextPainter(text: TextSpan(text: label, style: textStyle), textDirection: TextDirection.ltr)..layout();
        final x = chartRect.left + chartRect.width * fraction;
        final dx = fraction == 0.0 ? 0.0 : (fraction == 1.0 ? -painter.width : -painter.width / 2);
        painter.paint(canvas, Offset(x + dx, chartRect.bottom + 4));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.taskSeries != taskSeries || oldDelegate.personSeries != personSeries;
}
