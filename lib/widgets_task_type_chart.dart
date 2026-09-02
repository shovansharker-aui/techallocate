import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'models/work_order.dart';
import 'utils/app_colors.dart';
import 'utils/task_type.dart';

enum ChartMode { sunburst, treemap }

/// Where the admin's chosen chart mode (sunburst vs treemap) is stored.
/// Deliberately a document inside the already-writable 'users'
/// collection, under a reserved id, rather than a new top-level
/// collection — a brand new collection isn't covered by this project's
/// Firestore rules and writes to it are silently rejected (see
/// water_plant.dart's waterPlantSettingsRef for the same fix applied to
/// the Switching toggle). This particular doc is invisible to every
/// existing users-collection query in the app, since they all filter on
/// role == 'technician' / 'admin' / 'water_plant_manager', which this
/// document's role never matches.
const appSettingsDocId = '_app_settings';
final appSettingsRef = FirebaseFirestore.instance.collection('users').doc(appSettingsDocId);

ChartMode chartModeFrom(Map<String, dynamic>? data) {
  return (data?['chartMode'] == 'treemap') ? ChartMode.treemap : ChartMode.sunburst;
}

class TaskTypeDatum {
  final String code;
  final String name;
  final int value;
  final Color color;
  const TaskTypeDatum({required this.code, required this.name, required this.value, required this.color});
}

// Colors chosen to match a standard Office-chart palette so PM/BM/CL/CO/OT/AD
// stay visually consistent with any exported chart image elsewhere.
const Map<String, Color> taskTypeChartColors = {
  'preventive': Color(0xFF5B9BD5), // PM
  'breakdown': Color(0xFFED7D31), // BM
  'calibration': Color(0xFFA5A5A5), // CL
  'changeover': Color(0xFFFFC000), // CO
  'others': Color(0xFF4472C4), // OT
  'adjustment': Color(0xFF70AD47), // AD
};

const List<String> taskTypeChartOrder = ['preventive', 'breakdown', 'calibration', 'changeover', 'others', 'adjustment'];

/// Streams today's completed work orders, buckets them by type, and
/// renders either a sunburst (ring) or treemap chart — whichever the
/// admin has chosen in Settings — with a short-form legend underneath.
class TaskTypeBreakdownCard extends StatelessWidget {
  const TaskTypeBreakdownCard({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: appSettingsRef.snapshots(),
      builder: (context, settingsSnapshot) {
        final mode = chartModeFrom(settingsSnapshot.data?.data());
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('work_orders')
              .where('status', isEqualTo: 'completed')
              .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
              .snapshots(),
          builder: (context, snapshot) {
            final orders = (snapshot.data?.docs ?? []).map((d) => WorkOrder.fromMap(d.id, d.data()));
            final counts = <String, int>{};
            for (final o in orders) {
              counts[o.type] = (counts[o.type] ?? 0) + 1;
            }
            final data = taskTypeChartOrder
                .map((key) => TaskTypeDatum(
                      code: taskTypeCode(key),
                      name: taskTypeName(key),
                      value: counts[key] ?? 0,
                      color: taskTypeChartColors[key]!,
                    ))
                .toList();
            final total = data.fold<int>(0, (s, d) => s + d.value);

            return Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.donut_large_outlined, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Completed Today by Type', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
                    ]),
                    const SizedBox(height: 8),
                    Expanded(
                      child: total == 0
                          ? const Center(child: Text('No tasks completed yet today.', style: TextStyle(color: AppColors.muted, fontSize: 12)))
                          : mode == ChartMode.sunburst
                              ? _Sunburst(data: data, total: total)
                              : _Treemap(data: data),
                    ),
                    if (total > 0) ...[
                      const SizedBox(height: 10),
                      _Legend(data: data),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Sunburst extends StatelessWidget {
  final List<TaskTypeDatum> data;
  final int total;
  const _Sunburst({required this.data, required this.total});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(
          painter: _SunburstPainter(data),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$total', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const Text('today', style: TextStyle(fontSize: 11, color: AppColors.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SunburstPainter extends CustomPainter {
  final List<TaskTypeDatum> data;
  _SunburstPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final total = data.fold<int>(0, (s, d) => s + d.value);
    if (total == 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    final ringThickness = radius * 0.4;
    final arcRadius = radius - ringThickness / 2 - 2;
    final rect = Rect.fromCircle(center: center, radius: arcRadius);
    const gap = 0.02; // small visual separation between segments
    var startAngle = -pi / 2;
    for (final d in data) {
      if (d.value == 0) continue;
      final sweep = 2 * pi * (d.value / total);
      final paint = Paint()
        ..color = d.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringThickness
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, startAngle + gap / 2, max(sweep - gap, 0.001), false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _SunburstPainter oldDelegate) => oldDelegate.data != data;
}

class _Treemap extends StatelessWidget {
  final List<TaskTypeDatum> data;
  const _Treemap({required this.data});

  @override
  Widget build(BuildContext context) {
    final visible = data.where((d) => d.value > 0).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final tiles = _layoutTreemap(visible, Rect.fromLTWH(0, 0, constraints.maxWidth, constraints.maxHeight));
        return Stack(
          children: tiles.map((t) {
            final big = t.rect.width > 60 && t.rect.height > 40;
            return Positioned(
              left: t.rect.left,
              top: t.rect.top,
              width: t.rect.width,
              height: t.rect.height,
              child: Container(
                margin: const EdgeInsets.all(1.5),
                color: t.datum.color,
                alignment: Alignment.bottomLeft,
                padding: const EdgeInsets.all(6),
                child: big
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.datum.code, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                          Text('${t.datum.value}', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      )
                    : Text(t.datum.code, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _TreemapRect {
  final TaskTypeDatum datum;
  final Rect rect;
  const _TreemapRect(this.datum, this.rect);
}

/// Simple proportional "slice and dice" treemap: peels the largest
/// remaining item off along whichever axis is currently longest, sized
/// to its share of the total, and recurses on the rest. Not the
/// optimal-aspect-ratio "squarified" algorithm real charting libraries
/// use, but for 6 fixed categories it tiles cleanly and every tile's
/// area is still exactly proportional to its value.
List<_TreemapRect> _layoutTreemap(List<TaskTypeDatum> items, Rect bounds) {
  if (items.isEmpty || bounds.width <= 0 || bounds.height <= 0) return [];
  if (items.length == 1) return [_TreemapRect(items.first, bounds)];

  final sorted = [...items]..sort((a, b) => b.value.compareTo(a.value));
  final total = sorted.fold<int>(0, (s, d) => s + d.value);
  if (total == 0) return [];
  final first = sorted.first;
  final rest = sorted.sublist(1);
  final fraction = first.value / total;
  final wide = bounds.width >= bounds.height;

  final Rect firstRect;
  final Rect restRect;
  if (wide) {
    final w = bounds.width * fraction;
    firstRect = Rect.fromLTWH(bounds.left, bounds.top, w, bounds.height);
    restRect = Rect.fromLTWH(bounds.left + w, bounds.top, bounds.width - w, bounds.height);
  } else {
    final h = bounds.height * fraction;
    firstRect = Rect.fromLTWH(bounds.left, bounds.top, bounds.width, h);
    restRect = Rect.fromLTWH(bounds.left, bounds.top + h, bounds.width, bounds.height - h);
  }
  return [_TreemapRect(first, firstRect), ..._layoutTreemap(rest, restRect)];
}

class _Legend extends StatelessWidget {
  final List<TaskTypeDatum> data;
  const _Legend({required this.data});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: data.map((d) {
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: d.color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text('${d.code} ${d.value}', style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600)),
        ]);
      }).toList(),
    );
  }
}

/// The "Chart style" picker — used by both the web and Android Settings
/// screens so admin can switch between sunburst and treemap from
/// wherever they happen to be.
class ChartModeSetting extends StatelessWidget {
  const ChartModeSetting({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: appSettingsRef.snapshots(),
      builder: (context, snapshot) {
        final mode = chartModeFrom(snapshot.data?.data());
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Completed-tasks chart style', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Shown on the admin dashboard\'s "Completed Today by Type" card.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                const SizedBox(height: 12),
                SegmentedButton<ChartMode>(
                  segments: const [
                    ButtonSegment(value: ChartMode.sunburst, label: Text('Sunburst'), icon: Icon(Icons.donut_large_outlined)),
                    ButtonSegment(value: ChartMode.treemap, label: Text('Treemap'), icon: Icon(Icons.grid_view_outlined)),
                  ],
                  selected: {mode},
                  onSelectionChanged: (selection) {
                    // Single-document write, fire-and-forget — updates
                    // instantly via the StreamBuilder above regardless
                    // of connectivity.
                    appSettingsRef.set({'chartMode': selection.first.name}, SetOptions(merge: true));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
