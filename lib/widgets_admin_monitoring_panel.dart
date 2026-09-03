import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'widgets_live_activity_grid.dart';
import 'widgets_completed_tasks_section.dart';
import 'widgets_daily_summary.dart';
import 'widgets_task_type_chart.dart';
import 'services/android_widget_service.dart';
import 'models/app_user.dart';
import 'models/helper.dart';
import 'utils/app_colors.dart';
import 'utils/duty_status.dart';

class AdminMonitoringPanel extends StatelessWidget {
  const AdminMonitoringPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'technician').snapshots(),
      builder: (context, techSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('helpers').snapshots(),
          builder: (context, helperSnapshot) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('work_orders').where('status', isEqualTo: 'in_progress').snapshots(),
              builder: (context, orderSnapshot) {
                final techs = techSnapshot.data?.docs ?? [];
                final helpers = helperSnapshot.data?.docs ?? [];
                final orders = orderSnapshot.data?.docs ?? [];
                final availableTechList = techs
                    .map((d) => AppUser.fromMap(d.id, d.data()))
                    .where(isEffectivelyAvailable)
                    .toList();
                final availableHelperList = helpers
                    .map((d) => Helper.fromMap(d.id, d.data()))
                    .where((h) => h.status != 'assigned')
                    .toList();
                final availableTech = availableTechList.length;
                final availableHelpers = availableHelperList.length;
                int countType(String type) => orders.where((d) => (d.data()['type'] ?? '') == type).length;
                final pmCount = countType('preventive');
                final bmCount = countType('breakdown');
                final clCount = countType('calibration');
                final adCount = countType('adjustment');
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  AndroidWidgetService.update(
                    jo: availableTech,
                    cf: availableHelpers,
                    pm: pmCount,
                    bm: bmCount,
                    cl: clCount,
                    ad: adCount,
                  );
                });
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // A 2x2 area with 3 cells: Today's hours (top-left),
                  // JO available count (bottom-left), and the
                  // completed-today chart spanning the full right column
                  // — replaces the old full-width Daily Summary card +
                  // separate Person Available / Task Running row, which
                  // together took up roughly this same footprint.
                  SizedBox(
                    height: 300,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Column(children: [
                            const Expanded(child: DailySummaryCard()),
                            const SizedBox(height: 12),
                            Expanded(child: _availableNowCard(availableTechList)),
                          ]),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(child: TaskTypeBreakdownCard()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const LiveActivityGrid(),
                  const SizedBox(height: 18),
                  const CompletedTasksSection(),
                ]);
              },
            );
          },
        );
      },
    );
  }

  Widget _summaryCard(String title, IconData icon, List<_SummaryRow> rows, {VoidCallback? onTap, bool twoColumn = false}) {
    Widget buildRow(_SummaryRow row) {
      final content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Text(row.label, style: const TextStyle(fontSize: 14, color: AppColors.muted, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text('- ${row.value}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          if (row.onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.muted),
          ],
        ]),
      );
      if (row.onTap == null) return content;
      return InkWell(borderRadius: BorderRadius.circular(6), onTap: row.onTap, child: content);
    }

    final List<Widget> rowWidgets;
    if (twoColumn) {
      // Pair rows into 2-column x N-row grid instead of stacking every
      // row in a single column — keeps the card compact when there are
      // several types to show.
      rowWidgets = [];
      for (var i = 0; i < rows.length; i += 2) {
        final second = i + 1 < rows.length ? rows[i + 1] : null;
        rowWidgets.add(Row(children: [
          Expanded(child: buildRow(rows[i])),
          Expanded(child: second == null ? const SizedBox.shrink() : buildRow(second)),
        ]));
      }
    } else {
      rowWidgets = rows.map(buildRow).toList();
    }

    final card = Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
              if (onTap != null) const Icon(Icons.touch_app_outlined, size: 16, color: AppColors.muted),
            ]),
            const SizedBox(height: 10),
            ...rowWidgets,
          ],
        ),
      ),
    );
    if (onTap == null) return card;
    return InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: card);
  }

  Widget _availableNowCard(List<AppUser> jos) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.groups_outlined, size: 20),
              const SizedBox(width: 8),
              const Expanded(child: Text('Available Now', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 10),
            Expanded(
              child: jos.isEmpty
                  ? const Text('No one available right now.', style: TextStyle(fontSize: 12, color: AppColors.muted))
                  : SingleChildScrollView(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: _namesWithDots(jos),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _namesWithDots(List<AppUser> jos) {
    final widgets = <Widget>[];
    for (var i = 0; i < jos.length; i++) {
      widgets.add(Text(jos[i].name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)));
      if (i != jos.length - 1) {
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: AppColors.muted, shape: BoxShape.circle)),
        ));
      }
    }
    return widgets;
  }
}

class _SummaryRow {
  final String label;
  final String value;
  final VoidCallback? onTap;
  const _SummaryRow(this.label, this.value, {this.onTap});
}