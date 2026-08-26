import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'models/helper.dart';
import 'models/machine.dart';
import 'models/work_order.dart';
import 'models/app_user.dart';
import 'utils/task_type.dart';
import 'utils/task_completion.dart';
import 'utils/app_colors.dart';

class LiveActivityGrid extends StatefulWidget {
  /// When set, only shows tasks of this type (e.g. 'preventive'). Used by
  /// the "Task Running" summary card so tapping "PM - 4" shows just those
  /// 4 tasks, reusing this widget's existing machine/technician lookups
  /// instead of duplicating that fetch logic elsewhere.
  final String? filterType;
  const LiveActivityGrid({super.key, this.filterType});

  @override
  State<LiveActivityGrid> createState() => _LiveActivityGridState();
}

class _LiveActivityGridState extends State<LiveActivityGrid> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Refresh periodically so the running-time labels stay live without
    // waiting for a Firestore update.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String _typeCode(WorkOrder order) => taskTypeCode(order.type);

  static String _duration(DateTime? startedAt) {
    if (startedAt == null) return '';
    final seconds = DateTime.now().difference(startedAt).inSeconds;
    final d = Duration(seconds: seconds < 0 ? 0 : seconds);
    if (d.inHours > 0) return '${d.inHours}h${d.inMinutes.remainder(60)}m';
    return '${d.inMinutes}m';
  }

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
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('machines').snapshots(),
                  builder: (context, machineSnapshot) {
                    if (techSnapshot.hasError || helperSnapshot.hasError || orderSnapshot.hasError || machineSnapshot.hasError) {
                      return const Text('Unable to load live activity.');
                    }
                    final techs = {for (final d in (techSnapshot.data?.docs ?? [])) d.id: AppUser.fromMap(d.id, d.data())};
                    final helpers = {for (final d in (helperSnapshot.data?.docs ?? [])) d.id: Helper.fromMap(d.id, d.data())};
                    final machines = {for (final d in (machineSnapshot.data?.docs ?? [])) d.id: Machine.fromMap(d.id, d.data())};
                    final orders = (orderSnapshot.data?.docs ?? [])
                        .map((d) => WorkOrder.fromMap(d.id, d.data()))
                        .where((o) => widget.filterType == null || o.type == widget.filterType)
                        .toList();

                    // One tile per task, not per person.
                    orders.sort((a, b) {
                      final aName = machines[a.machineId]?.displayName ?? a.machineId;
                      final bName = machines[b.machineId]?.displayName ?? b.machineId;
                      return aName.toLowerCase().compareTo(bName.toLowerCase());
                    });

                    if (orders.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('No one is currently engaged in a task.')));

                    return LayoutBuilder(builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 1000 ? 3 : constraints.maxWidth >= 650 ? 2 : 1;
                      final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: orders.map((order) {
                          final machine = machines[order.machineId];
                          final technicianNames = order.assignedTechnicianIds.map((id) => techs[id]?.name).whereType<String>().where((n) => n.isNotEmpty).toList();
                          final helperNames = order.helperIds.map((id) => helpers[id]?.name).whereType<String>().where((n) => n.isNotEmpty).toList();
                          return SizedBox(
                            width: width,
                            child: Card(
                              margin: EdgeInsets.zero,
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            machine?.displayName ?? order.machineId,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                          decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(5)),
                                          child: Text(_typeCode(order), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    _peopleRow(context, Icons.engineering_outlined, technicianNames, 'No JO'),
                                    if (helperNames.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      _peopleRow(context, Icons.handyman_outlined, helperNames, ''),
                                    ],
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(Icons.timer_outlined, size: 13, color: AppColors.muted),
                                        const SizedBox(width: 4),
                                        Text(_duration(order.startedAt), style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600)),
                                        const Spacer(),
                                        TextButton.icon(
                                          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28), visualDensity: VisualDensity.compact),
                                          onPressed: () async {
                                            final time = await pickCompletionTime(context, startedAt: order.startedAt);
                                            if (time == null) return;
                                            await completeWorkOrder(
                                              orderId: order.id,
                                              technicianIds: order.assignedTechnicianIds,
                                              helperIds: order.helperIds,
                                              completedAt: time,
                                            );
                                          },
                                          icon: const Icon(Icons.check_circle_outline, size: 15),
                                          label: const Text('Complete', style: TextStyle(fontSize: 12)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    });
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _peopleRow(BuildContext context, IconData icon, List<String> names, String emptyLabel) {
    if (names.isEmpty) {
      if (emptyLabel.isEmpty) return const SizedBox.shrink();
      return Row(children: [Icon(icon, size: 13, color: AppColors.muted), const SizedBox(width: 4), Expanded(child: Text(emptyLabel, style: const TextStyle(fontSize: 12, color: AppColors.muted)))]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: AppColors.muted),
        const SizedBox(width: 4),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 2,
            children: names.map((n) => Text(n, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))).toList(),
          ),
        ),
      ],
    );
  }
}
