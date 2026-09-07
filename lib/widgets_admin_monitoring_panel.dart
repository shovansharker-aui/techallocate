import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'widgets_live_activity_grid.dart';
import 'widgets_completed_tasks_section.dart';
import 'widgets_daily_summary.dart';
import 'widgets_task_type_chart.dart';
import 'services/android_widget_service.dart';
import 'screens/task_charts_detail_screen.dart';
import 'models/app_user.dart';
import 'models/helper.dart';
import 'utils/app_colors.dart';
import 'utils/duty_status.dart';

typedef DutyRosterEntry = ({AppUser user, DutyPresence presence});

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
                // "Available Now" is really "on duty now" — everyone
                // whose shift window covers this moment, whether or not
                // they're currently on a task (see dutyPresence). The
                // widget/Android-home-screen count below still only
                // counts the genuinely free half.
                final rosterTechs = techs
                    .map((d) => AppUser.fromMap(d.id, d.data()))
                    .map((u) => (user: u, presence: dutyPresence(u)))
                    .where((r) => r.presence != DutyPresence.off)
                    .toList()
                  ..sort((a, b) => a.user.name.toLowerCase().compareTo(b.user.name.toLowerCase()));
                final availableTechList = rosterTechs.where((r) => r.presence == DutyPresence.free).map((r) => r.user).toList();
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
                            Expanded(child: _availableNowCard(rosterTechs)),
                          ]),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          // Desktop keeps its own dedicated "Graphs"
                          // sidebar section for anything beyond this
                          // chart, so tapping here does nothing extra on
                          // desktop. Native Android and mobile/PWA web
                          // have no spare bottom-nav slot for that, so
                          // tapping this chart is how they reach the
                          // rest of the graphs instead.
                          child: (!kIsWeb || MediaQuery.sizeOf(context).width < 950)
                              ? GestureDetector(
                                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TaskChartsDetailScreen())),
                                  child: const TaskTypeBreakdownCard(),
                                )
                              : const TaskTypeBreakdownCard(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const LiveActivityGrid(),
                  const SizedBox(height: 18),
                  // Completed-task browsing now lives in its own
                  // dedicated "History" destination on native Android,
                  // Android browser, and PWA (see the bottom nav) —
                  // kept embedded here only for desktop-width web, which
                  // still uses the original sidebar layout unchanged.
                  if (kIsWeb && MediaQuery.sizeOf(context).width >= 950) const CompletedTasksSection(),
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

  Widget _availableNowCard(List<DutyRosterEntry> roster) {
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
              child: roster.isEmpty
                  ? const Text('No one on duty right now.', style: TextStyle(fontSize: 12, color: AppColors.muted))
                  : SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: roster.map((r) => _personBox(r)).toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // A small colored box per on-duty person — green while they're free,
  // gray while they're on a running task — instead of a single flat
  // dot-separated name list, so who's actually free to grab a task is
  // visible at a glance rather than needing the count above it.
  Widget _personBox(DutyRosterEntry entry) {
    final busy = entry.presence == DutyPresence.busy;
    final color = busy ? AppColors.danger : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(entry.user.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _SummaryRow {
  final String label;
  final String value;
  final VoidCallback? onTap;
  const _SummaryRow(this.label, this.value, {this.onTap});
}