import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'models/app_user.dart';
import 'models/work_order.dart';
import 'services/chart_mode_service.dart';
import 'utils/app_colors.dart';
import 'utils/task_type.dart';

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

// Rotating palette for however many JOs happen to have worked today —
// unlike task types there's no fixed category count to hand-pick colors for.
const List<Color> _joPalette = [
  Color(0xFF5B9BD5), Color(0xFFED7D31), Color(0xFF70AD47), Color(0xFF9C27B0),
  Color(0xFF00ACC1), Color(0xFFFFC000), Color(0xFF4472C4), Color(0xFFE91E63),
  Color(0xFF8D6E63), Color(0xFF43A047),
];

/// Swipeable pair of charts: page 1 is today's task-type breakdown (see
/// TaskTypeBreakdownCard's original behavior), page 2 is a per-JO work
/// chart — the legend shows each JO's task count, but the chart itself
/// (slice/tile size) is driven by how long they've been engaged today,
/// not how many tasks. Sunburst vs treemap applies to both pages, set
/// once in Settings.
class TaskTypeBreakdownCard extends StatefulWidget {
  const TaskTypeBreakdownCard({super.key});

  @override
  State<TaskTypeBreakdownCard> createState() => _TaskTypeBreakdownCardState();
}

class _TaskTypeBreakdownCardState extends State<TaskTypeBreakdownCard> {
  final _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return ListenableBuilder(
      listenable: chartModeService,
      builder: (context, _) {
        final mode = chartModeService.mode;
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('work_orders')
              .where('status', isEqualTo: 'completed')
              .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
              .snapshots(),
          builder: (context, completedSnapshot) {
            // A task still running counts toward today's tally too — it's
            // already part of today's work even though it isn't finished
            // yet. Kept as a second, separate query (plain equality, no
            // date range) rather than folded into the query above, since
            // 'in_progress' tasks have no completedAt to filter by at all.
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('work_orders').where('status', isEqualTo: 'in_progress').snapshots(),
              builder: (context, runningSnapshot) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'technician').snapshots(),
                  builder: (context, techSnapshot) {
                    final completedOrders = (completedSnapshot.data?.docs ?? []).map((d) => WorkOrder.fromMap(d.id, d.data())).toList();
                    final runningOrders = (runningSnapshot.data?.docs ?? []).map((d) => WorkOrder.fromMap(d.id, d.data())).toList();
                    final techs = {for (final d in (techSnapshot.data?.docs ?? [])) d.id: AppUser.fromMap(d.id, d.data())};

                    // --- Page 1: by task type ---
                    final typeCounts = <String, int>{};
                    for (final o in [...completedOrders, ...runningOrders]) {
                      typeCounts[o.type] = (typeCounts[o.type] ?? 0) + 1;
                    }
                    final typeData = taskTypeChartOrder
                        .map((key) => TaskTypeDatum(code: taskTypeCode(key), name: taskTypeName(key), value: typeCounts[key] ?? 0, color: taskTypeChartColors[key]!))
                        .toList();
                    final typeTotal = typeData.fold<int>(0, (s, d) => s + d.value);

                    // --- Page 2: by JO (chart = seconds engaged, legend = task count) ---
                    final joSeconds = <String, int>{};
                    final joTaskCount = <String, int>{};
                    for (final o in completedOrders) {
                      for (final id in o.assignedTechnicianIds) {
                        joSeconds[id] = (joSeconds[id] ?? 0) + (o.durationSeconds ?? 0);
                        joTaskCount[id] = (joTaskCount[id] ?? 0) + 1;
                      }
                    }
                    for (final o in runningOrders) {
                      final elapsed = now.difference(o.startedAt ?? now).inSeconds;
                      for (final id in o.assignedTechnicianIds) {
                        joSeconds[id] = (joSeconds[id] ?? 0) + (elapsed < 0 ? 0 : elapsed);
                        joTaskCount[id] = (joTaskCount[id] ?? 0) + 1;
                      }
                    }
                    final joIds = joSeconds.keys.toList()..sort((a, b) => (joSeconds[b] ?? 0).compareTo(joSeconds[a] ?? 0));
                    final joData = <TaskTypeDatum>[];
                    for (var i = 0; i < joIds.length; i++) {
                      final id = joIds[i];
                      joData.add(TaskTypeDatum(
                        code: techs[id]?.name ?? 'Unknown',
                        name: techs[id]?.name ?? 'Unknown',
                        value: joSeconds[id] ?? 0,
                        color: _joPalette[i % _joPalette.length],
                      ));
                    }
                    final joTotalSeconds = joData.fold<int>(0, (s, d) => s + d.value);

                    final titles = ["Today's Summary", "JO Work Today"];
                    final pages = [
                      _ChartPage(
                        data: typeData,
                        total: typeTotal,
                        mode: mode,
                        emptyText: 'No tasks today yet.',
                        centerBuilder: (total) => _CenterText(main: '$total', sub: 'today'),
                        legendBuilder: (data) => _Legend(data: data, formatValue: (d) => '${d.code}-${d.value}'),
                      ),
                      _ChartPage(
                        data: joData,
                        total: joTotalSeconds,
                        mode: mode,
                        emptyText: 'No one has worked today yet.',
                        centerBuilder: (total) => _CenterText(main: _hm(total), sub: 'engaged'),
                        legendBuilder: (data) => _Legend(
                          data: data,
                          formatValue: (d) {
                            final joId = joIds[joData.indexOf(d)];
                            final count = joTaskCount[joId] ?? 0;
                            return '${d.name} · $count task${count == 1 ? '' : 's'}';
                          },
                        ),
                      ),
                    ];

                    // Swipe-to-change-page relies on touch drag, which
                    // doesn't really exist with a mouse — desktop web
                    // gets small arrow buttons instead so switching
                    // charts is actually discoverable there.
                    final showArrows = kIsWeb && MediaQuery.sizeOf(context).width >= 950;

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
                              Expanded(child: Text(titles[_page], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
                            ]),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  PageView(
                                    controller: _pageController,
                                    onPageChanged: (i) => setState(() => _page = i),
                                    children: pages,
                                  ),
                                  if (showArrows)
                                    Positioned(
                                      left: 0,
                                      child: _ChartArrow(
                                        icon: Icons.chevron_left,
                                        onTap: _page > 0
                                            ? () => _pageController.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
                                            : null,
                                      ),
                                    ),
                                  if (showArrows)
                                    Positioned(
                                      right: 0,
                                      child: _ChartArrow(
                                        icon: Icons.chevron_right,
                                        onTap: _page < pages.length - 1
                                            ? () => _pageController.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
                                            : null,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(pages.length, (i) => Container(
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: i == _page ? Theme.of(context).colorScheme.primary : AppColors.muted.withValues(alpha: 0.3),
                                ),
                              )),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  static String _hm(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return '${h}h ${m}m';
  }
}

class _ChartPage extends StatelessWidget {
  final List<TaskTypeDatum> data;
  final int total;
  final ChartMode mode;
  final String emptyText;
  final Widget Function(int total) centerBuilder;
  final Widget Function(List<TaskTypeDatum> data) legendBuilder;

  const _ChartPage({
    required this.data,
    required this.total,
    required this.mode,
    required this.emptyText,
    required this.centerBuilder,
    required this.legendBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: total == 0
              ? Center(child: Text(emptyText, style: const TextStyle(color: AppColors.muted, fontSize: 12)))
              : mode == ChartMode.sunburst
                  ? _Sunburst(data: data, total: total, centerBuilder: centerBuilder)
                  : _Treemap(data: data),
        ),
        if (total > 0) ...[
          const SizedBox(height: 10),
          legendBuilder(data),
        ],
      ],
    );
  }
}

class _ChartArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _ChartArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
      shape: const CircleBorder(),
      elevation: enabled ? 1 : 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 20, color: enabled ? AppColors.muted : AppColors.muted.withValues(alpha: 0.25)),
        ),
      ),
    );
  }
}

class _CenterText extends StatelessWidget {
  final String main;
  final String sub;
  const _CenterText({required this.main, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(main, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(sub, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      ],
    );
  }
}

class _Sunburst extends StatelessWidget {
  final List<TaskTypeDatum> data;
  final int total;
  final Widget Function(int total) centerBuilder;
  const _Sunburst({required this.data, required this.total, required this.centerBuilder});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(
          painter: _SunburstPainter(data),
          child: Center(child: centerBuilder(total)),
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
                          Text(t.datum.code, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      )
                    : Text(t.datum.code, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
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
/// use, but for a handful of categories it tiles cleanly and every
/// tile's area is still exactly proportional to its value.
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
  final String Function(TaskTypeDatum d) formatValue;
  const _Legend({required this.data, required this.formatValue});

  @override
  Widget build(BuildContext context) {
    final visible = data.where((d) => d.value > 0).toList();
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: visible.map((d) {
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: d.color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(formatValue(d), style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600)),
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
    return ListenableBuilder(
      listenable: chartModeService,
      builder: (context, _) {
        final mode = chartModeService.mode;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Dashboard chart style', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Applies to both the "Today\'s Summary" and "JO Work Today" cards.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                const SizedBox(height: 12),
                SegmentedButton<ChartMode>(
                  segments: const [
                    ButtonSegment(value: ChartMode.sunburst, label: Text('Sunburst'), icon: Icon(Icons.donut_large_outlined)),
                    ButtonSegment(value: ChartMode.treemap, label: Text('Treemap'), icon: Icon(Icons.grid_view_outlined)),
                  ],
                  selected: {mode},
                  onSelectionChanged: (selection) => chartModeService.setMode(selection.first),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
