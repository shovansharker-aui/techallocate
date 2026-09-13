import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'models/app_user.dart';
import 'models/work_order.dart';
import 'utils/app_colors.dart';
import 'utils/engaged_time.dart';

/// Each JO's total engaged time over [rangeStart, rangeEndExclusive) as a
/// radar/spider chart -- one axis per JO. Every JO gets an axis
/// regardless of roster size (by explicit request); tap a point to see
/// that person's name and hours, since a large roster leaves little room
/// for a permanent label per axis.
///
/// Used for both the Daily and custom-range Analysis views -- see
/// GraphsBody. [includeRunning] should only be true when the range
/// covers this exact moment (today, or a range that includes today),
/// since a still-running task has no completedAt to attribute to a past
/// range at all.
///
/// "Engaged" here is overlap-aware (see unionDuration): a JO running two
/// tasks at once for an hour shows one hour here, not two -- even though
/// each of those two tasks still shows its own full hour wherever a
/// single task's duration is displayed (Live Activity Grid, Completed
/// Tasks, etc.), which is unaffected and correct as-is.
class HourWorkedRadarCard extends StatelessWidget {
  final DateTime rangeStart;
  final DateTime rangeEndExclusive;
  final bool includeRunning;
  final String title;
  final String subtitle;

  const HourWorkedRadarCard({
    super.key,
    required this.rangeStart,
    required this.rangeEndExclusive,
    required this.includeRunning,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.radar, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 10),
            SizedBox(
              height: 300,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'technician').snapshots(),
                builder: (context, techSnapshot) {
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('work_orders')
                        .where('status', isEqualTo: 'completed')
                        .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart))
                        .where('completedAt', isLessThan: Timestamp.fromDate(rangeEndExclusive))
                        .snapshots(),
                    builder: (context, completedSnapshot) {
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance.collection('work_orders').where('status', isEqualTo: 'in_progress').snapshots(),
                        builder: (context, runningSnapshot) {
                          if (techSnapshot.hasError || completedSnapshot.hasError || runningSnapshot.hasError) {
                            return const Text('Unable to load hours.');
                          }
                          if (!techSnapshot.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final now = DateTime.now();
                          final techs = (techSnapshot.data?.docs ?? []).map((d) => AppUser.fromMap(d.id, d.data())).toList();
                          final completedOrders = (completedSnapshot.data?.docs ?? []).map((d) => WorkOrder.fromMap(d.id, d.data()));
                          final runningOrders = includeRunning ? (runningSnapshot.data?.docs ?? []).map((d) => WorkOrder.fromMap(d.id, d.data())) : const <WorkOrder>[];

                          // Each order contributes every person's OWN
                          // interval on it (see WorkOrder.contributorInterval)
                          // -- assignedTechnicianIds ∪ contributorIds covers
                          // both whoever's still on the task and whoever
                          // left it early.
                          final intervals = <String, List<EngagedInterval>>{};
                          for (final o in [...completedOrders, ...runningOrders]) {
                            for (final id in {...o.assignedTechnicianIds, ...o.contributorIds}) {
                              final interval = o.contributorInterval(id, nowIfRunning: now);
                              if (interval != null) (intervals[id] ??= []).add(interval);
                            }
                          }

                          final rows = techs
                              .map((t) => (
                                    name: t.name.isEmpty ? t.employeeId : t.name,
                                    seconds: unionDuration(intervals[t.uid] ?? const <EngagedInterval>[]).inSeconds,
                                  ))
                              .toList()
                            ..sort((a, b) => b.seconds.compareTo(a.seconds));

                          if (rows.isEmpty) {
                            return const Center(child: Text('No Junior Officers found.', style: TextStyle(color: AppColors.muted, fontSize: 12)));
                          }

                          return _RadarChart(rows: rows);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

typedef _HourRow = ({String name, int seconds});

/// Tap-to-reveal radar chart: every row gets its own axis, but with a
/// large roster there's no room for a permanent label per axis, so the
/// name/duration only shows (as a small banner) for whichever point was
/// last tapped.
class _RadarChart extends StatefulWidget {
  final List<_HourRow> rows;
  const _RadarChart({required this.rows});

  @override
  State<_RadarChart> createState() => _RadarChartState();
}

class _RadarChartState extends State<_RadarChart> {
  String? _tooltip;

  int get _maxSeconds => widget.rows.map((r) => r.seconds).fold(0, (m, v) => v > m ? v : m);

  Offset _axisPoint(int index, Size size, {required double fraction}) {
    final n = widget.rows.length;
    final center = Offset(size.width / 2, size.height / 2);
    const labelPad = 44.0;
    final radius = (size.width < size.height ? size.width : size.height) / 2 - labelPad;
    final angle = -pi / 2 + 2 * pi * index / n;
    return center + Offset(cos(angle), sin(angle)) * radius * fraction;
  }

  void _handleTapUp(Offset localPosition, Size size) {
    final maxSeconds = _maxSeconds;
    var bestIndex = -1;
    var bestDistSq = double.infinity;
    for (var i = 0; i < widget.rows.length; i++) {
      final frac = maxSeconds == 0 ? 0.0 : widget.rows[i].seconds / maxSeconds;
      final p = _axisPoint(i, size, fraction: frac);
      final d = (p - localPosition).distanceSquared;
      if (d < bestDistSq) {
        bestDistSq = d;
        bestIndex = i;
      }
    }
    // 26px tap radius -- close enough to a vertex to count as "tapped
    // that one", not just anywhere on the chart.
    if (bestIndex == -1 || bestDistSq > 26 * 26) {
      setState(() => _tooltip = null);
      return;
    }
    final r = widget.rows[bestIndex];
    final h = r.seconds ~/ 3600;
    final m = (r.seconds % 3600) ~/ 60;
    setState(() => _tooltip = '${r.name} — ${h > 0 ? '${h}h ${m}m' : '${m}m'}');
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      return Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _handleTapUp(details.localPosition, size),
            child: CustomPaint(painter: _RadarChartPainter(rows: widget.rows, maxSeconds: _maxSeconds)),
          ),
        ),
        if (_tooltip != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                child: Text(_tooltip!, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
      ]);
    });
  }
}

class _RadarChartPainter extends CustomPainter {
  final List<_HourRow> rows;
  final int maxSeconds;

  _RadarChartPainter({required this.rows, required this.maxSeconds});

  @override
  void paint(Canvas canvas, Size size) {
    final n = rows.length;
    if (n < 3) {
      // A radar chart needs at least a triangle to mean anything -- fall
      // back to a centered note instead of drawing a degenerate shape.
      final tp = TextPainter(
        text: const TextSpan(text: 'Need at least 3 JOs for a radar chart.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
      return;
    }

    final center = Offset(size.width / 2, size.height / 2);
    const labelPad = 44.0;
    final radius = (size.width < size.height ? size.width : size.height) / 2 - labelPad;
    if (radius <= 10) return;

    final gridPaint = Paint()
      ..color = AppColors.muted.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    Offset onAxis(int i, double fraction) {
      final angle = -pi / 2 + 2 * pi * i / n;
      return center + Offset(cos(angle), sin(angle)) * radius * fraction;
    }

    // Concentric rings at 25/50/75/100%.
    for (final f in [0.25, 0.5, 0.75, 1.0]) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final p = onAxis(i, f);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    // Spokes -- no per-axis name labels (too many JOs to fit legibly);
    // tapping a vertex shows the name/hours instead (see _RadarChart).
    for (var i = 0; i < n; i++) {
      canvas.drawLine(center, onAxis(i, 1.0), gridPaint);
    }

    // Data polygon.
    final dataPath = Path();
    final points = <Offset>[];
    for (var i = 0; i < n; i++) {
      final frac = maxSeconds == 0 ? 0.0 : rows[i].seconds / maxSeconds;
      final p = onAxis(i, frac);
      points.add(p);
      if (i == 0) {
        dataPath.moveTo(p.dx, p.dy);
      } else {
        dataPath.lineTo(p.dx, p.dy);
      }
    }
    dataPath.close();
    canvas.drawPath(dataPath, Paint()..color = AppColors.primary.withValues(alpha: 0.22));
    canvas.drawPath(
      dataPath,
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (final p in points) {
      canvas.drawCircle(p, 2.5, Paint()..color = AppColors.primary);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarChartPainter oldDelegate) => oldDelegate.rows != rows || oldDelegate.maxSeconds != maxSeconds;
}
