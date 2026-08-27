import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'widgets_live_activity_grid.dart';
import 'widgets_completed_tasks_section.dart';
import 'services/android_widget_service.dart';
import 'models/app_user.dart';
import 'models/helper.dart';
import 'utils/app_colors.dart';

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
                    .where((t) => t.status != 'assigned' && t.dutyStatus != 'on_leave')
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
                final coCount = countType('changeover');
                final trCount = countType('trial');
                final otCount = countType('others');
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
                  Builder(builder: (context) {
                    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
                    final sideBySide = isAndroid || MediaQuery.sizeOf(context).width >= 650;
                    final jo = _summaryCard(
                      'Person Available',
                      Icons.groups_outlined,
                      [
                        _SummaryRow('JO', '$availableTech'),
                        _SummaryRow('CF', '$availableHelpers'),
                      ],
                      onTap: () => _showAvailablePeople(context, availableTechList, availableHelperList),
                    );
                    final task = _summaryCard('Task Running', Icons.work_history_outlined, [
                      _SummaryRow('PM', '$pmCount', onTap: pmCount == 0 ? null : () => _showTasksOfType(context, 'preventive', 'Preventive tasks')),
                      _SummaryRow('BM', '$bmCount', onTap: bmCount == 0 ? null : () => _showTasksOfType(context, 'breakdown', 'Breakdown tasks')),
                      _SummaryRow('CL', '$clCount', onTap: clCount == 0 ? null : () => _showTasksOfType(context, 'calibration', 'Calibration tasks')),
                      _SummaryRow('AD', '$adCount', onTap: adCount == 0 ? null : () => _showTasksOfType(context, 'adjustment', 'Adjustment tasks')),
                      _SummaryRow('CO', '$coCount', onTap: coCount == 0 ? null : () => _showTasksOfType(context, 'changeover', 'Changeover tasks')),
                      _SummaryRow('TR', '$trCount', onTap: trCount == 0 ? null : () => _showTasksOfType(context, 'trial', 'Trial tasks')),
                      _SummaryRow('OT', '$otCount', onTap: otCount == 0 ? null : () => _showTasksOfType(context, 'others', 'Other tasks')),
                    ]);
                    if (!sideBySide) {
                      return Column(children: [jo, const SizedBox(height: 12), task]);
                    }
                    // IntrinsicHeight makes both cards match the taller one's
                    // height without needing a hardcoded aspect ratio — a
                    // fixed ratio broke as soon as one card had more rows
                    // than the other and caused a bottom overflow.
                    return IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(child: jo),
                        const SizedBox(width: 12),
                        Expanded(child: task),
                      ]),
                    );
                  }),
                  const SizedBox(height: 18),
                  const Text('Running Task', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
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

  Widget _summaryCard(String title, IconData icon, List<_SummaryRow> rows, {VoidCallback? onTap}) {
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
            ...rows.map((row) {
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
            }),
          ],
        ),
      ),
    );
    if (onTap == null) return card;
    return InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: card);
  }

  Future<void> _showTasksOfType(BuildContext context, String type, String title) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black38,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.work_history_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                ]),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(
                    child: LiveActivityGrid(filterType: type),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAvailablePeople(BuildContext context, List<AppUser> jos, List<Helper> cfs) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black38,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380, maxHeight: 500),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.groups_outlined, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Person Available', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                ]),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Junior Officers (${jos.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.muted)),
                        const SizedBox(height: 4),
                        if (jos.isEmpty)
                          const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('None available'))
                        else
                          ...jos.map((jo) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(radius: 16, child: Text(jo.name.isEmpty ? '?' : jo.name[0].toUpperCase())),
                            title: Text(jo.name),
                            subtitle: Text(switch (jo.dutyStatus) {
                              'day_ot' => 'Day + OT',
                              'day_night' => 'Day + Night',
                              _ => 'Day',
                            }),
                          )),
                        const SizedBox(height: 12),
                        Text('CF (${cfs.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.muted)),
                        const SizedBox(height: 4),
                        if (cfs.isEmpty)
                          const Padding(padding: EdgeInsets.only(bottom: 4), child: Text('None available'))
                        else
                          ...cfs.map((h) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(radius: 16, child: Text(h.name.isEmpty ? '?' : h.name[0].toUpperCase())),
                            title: Text(h.name),
                          )),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryRow {
  final String label;
  final String value;
  final VoidCallback? onTap;
  const _SummaryRow(this.label, this.value, {this.onTap});
}