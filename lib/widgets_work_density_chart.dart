import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'models/work_order.dart';
import 'utils/app_colors.dart';
import 'utils/date_format.dart';

const _taskLineColor = Color(0xFF5B9BD5);
const _personLineColor = Color(0xFFED7D31);

/// Work density since the start of the working day (00:00 AM) up to now —
/// two overlaid lines showing (1) how many tasks were concurrently
/// running and (2) how many unique people (JO + CF combined) were
/// concurrently engaged, at each sampled moment. The window keeps
/// growing through the day: checked at noon it's 00 AM-12 PM, checked at
/// 11 PM it's 00 AM-11 PM.
///
/// This card is meant to be placed in a page with real room to show it
/// (the desktop Graphs section, or the mobile "Today's Summary" detail
/// page) rather than a small dashboard tile, so it always renders at
/// full size with axis labels — no separate tap-to-expand view needed
/// anymore.
class WorkDensityCard extends StatelessWidget {
  const WorkDensityCard({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final eightAm = DateTime(now.year, now.month, now.day, 8);
    final windowStart = eightAm;
    final hasStarted = !now.isBefore(eightAm);

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
              const Expanded(child: Text('Work Density · Since 8:00 AM', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: hasStarted
                  ? _WorkDensityChart(windowStart: windowStart, windowEnd: now)
                  : const Center(child: Text("The work day hasn't started yet — check back after 8:00 AM.", style: TextStyle(color: AppColors.muted, fontSize: 12))),
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
