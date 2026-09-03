import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'models/work_order.dart';
import 'utils/app_colors.dart';
import 'utils/date_format.dart';

const _taskLineColor = Color(0xFF5B9BD5);
const _personLineColor = Color(0xFFED7D31);

/// Compact "work density, last 5 hours" card — two overlaid lines
/// showing (1) how many tasks were concurrently running and (2) how
/// many unique people (JO + CF combined) were concurrently engaged, at
/// each sampled moment. Tapping it opens the same chart full-width,
/// covering midnight to now instead of just the last 5 hours.
class WorkDensityCard extends StatelessWidget {
  const WorkDensityCard({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final windowStart = now.subtract(const Duration(hours: 5));
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _ExpandedWorkDensityScreen())),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.show_chart, size: 20),
                const SizedBox(width: 8),
                const Expanded(child: Text('Work Density · Last 5 hours', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
                const Icon(Icons.open_in_full, size: 16, color: AppColors.muted),
              ]),
              const SizedBox(height: 12),
              SizedBox(
                height: 180,
                child: _WorkDensityChart(windowStart: windowStart, windowEnd: now, stepMinutes: 5),
              ),
              const SizedBox(height: 10),
              _legend(),
            ],
          ),
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

class _ExpandedWorkDensityScreen extends StatelessWidget {
  const _ExpandedWorkDensityScreen();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final windowStart = DateTime(now.year, now.month, now.day); // 00:00 today
    return Scaffold(
      appBar: AppBar(title: const Text('Work Density · Today')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _legend(),
            const SizedBox(height: 20),
            Expanded(
              child: _WorkDensityChart(windowStart: windowStart, windowEnd: now, stepMinutes: 10, showAxisLabels: true),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fetches every work order whose active interval overlaps
/// [windowStart, windowEnd], samples the window at regular intervals,
/// and renders two overlaid lines: concurrent task count and unique
/// concurrent person count at each sampled moment.
class _WorkDensityChart extends StatelessWidget {
  final DateTime windowStart;
  final DateTime windowEnd;
  final int stepMinutes;
  final bool showAxisLabels;

  const _WorkDensityChart({
    required this.windowStart,
    required this.windowEnd,
    required this.stepMinutes,
    this.showAxisLabels = false,
  });

  @override
  Widget build(BuildContext context) {
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

            final sampleCount = (windowEnd.difference(windowStart).inMinutes / stepMinutes).ceil().clamp(2, 300);
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
              painter: _LineChartPainter(
                taskSeries: taskSeries,
                personSeries: personSeries,
                times: times,
                showAxisLabels: showAxisLabels,
              ),
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
  final bool showAxisLabels;

  _LineChartPainter({required this.taskSeries, required this.personSeries, required this.times, required this.showAxisLabels});

  @override
  void paint(Canvas canvas, Size size) {
    if (taskSeries.isEmpty) return;
    final leftPad = showAxisLabels ? 28.0 : 4.0;
    final bottomPad = showAxisLabels ? 22.0 : 4.0;
    final chartRect = Rect.fromLTWH(leftPad, 4, size.width - leftPad - 4, size.height - bottomPad - 4);

    final maxVal = [...taskSeries, ...personSeries].fold<double>(1, (m, v) => v > m ? v : m);
    final gridPaint = Paint()..color = AppColors.muted.withValues(alpha: 0.15)..strokeWidth = 1;
    final textStyle = const TextStyle(fontSize: 9, color: AppColors.muted);

    // Horizontal grid lines at 0, half, and max.
    for (final fraction in [0.0, 0.5, 1.0]) {
      final y = chartRect.bottom - fraction * chartRect.height;
      canvas.drawLine(Offset(chartRect.left, y), Offset(chartRect.right, y), gridPaint);
      if (showAxisLabels) {
        final label = (maxVal * fraction).round().toString();
        final painter = TextPainter(text: TextSpan(text: label, style: textStyle), textDirection: TextDirection.ltr)..layout();
        painter.paint(canvas, Offset(0, y - painter.height / 2));
      }
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

    if (showAxisLabels && times.isNotEmpty) {
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
