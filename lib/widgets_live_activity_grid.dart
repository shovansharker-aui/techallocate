import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'models/helper.dart';
import 'models/machine.dart';
import 'models/work_order.dart';
import 'models/app_user.dart';
import 'utils/task_type.dart';
import 'utils/task_completion.dart';
import 'utils/date_format.dart';
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
                    final Map<String, AppUser> techs = {for (final d in (techSnapshot.data?.docs ?? [])) d.id: AppUser.fromMap(d.id, d.data())};
                    final Map<String, Helper> helpers = {for (final d in (helperSnapshot.data?.docs ?? [])) d.id: Helper.fromMap(d.id, d.data())};
                    final Map<String, Machine> machines = {for (final d in (machineSnapshot.data?.docs ?? [])) d.id: Machine.fromMap(d.id, d.data())};
                    final orders = (orderSnapshot.data?.docs ?? [])
                        .map((d) => WorkOrder.fromMap(d.id, d.data()))
                        .where((o) => widget.filterType == null || o.type == widget.filterType)
                        .toList();

                    // One tile per task, not per person.
                    orders.sort((a, b) {
                      final aName = machines[a.machineId]?.fullLabel ?? a.machineId;
                      final bName = machines[b.machineId]?.fullLabel ?? b.machineId;
                      return aName.toLowerCase().compareTo(bName.toLowerCase());
                    });

                    if (orders.isEmpty) return const SizedBox.shrink();

                    final grid = LayoutBuilder(builder: (context, constraints) {
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
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => _showTaskDetail(context, order, machine, machines, technicianNames, helperNames),
                                child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            machine?.fullLabel ?? (order.machineId.isEmpty ? 'No machine' : order.machineId),
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
                                    if (order.groupMachineIds.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Group: ${machine?.group ?? ''} — ${order.groupMachineIds.map((id) => machines[id]?.equipmentId ?? id).join(', ')}',
                                        style: const TextStyle(fontSize: 11, color: AppColors.muted),
                                      ),
                                    ],
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
                                            final picked = await pickCompletionTime(context, startedAt: order.startedAt);
                                            if (picked == null) return;
                                            completeWorkOrder(
                                              orderId: order.id,
                                              technicianIds: order.assignedTechnicianIds,
                                              helperIds: order.helperIds,
                                              completedAt: picked.time,
                                              lateEntry: picked.isBacktime,
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
                          ),
                          );
                        }).toList(),
                      );
                    });

                    if (widget.filterType != null) return grid;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Running Task', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        grid,
                      ],
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

  void _showTaskDetail(BuildContext context, WorkOrder order, Machine? machine, Map<String, Machine> machines, List<String> technicianNames, List<String> helperNames) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(machine?.fullLabel ?? (order.machineId.isEmpty ? 'No machine' : order.machineId)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (machine?.isGrouped == true) _detailRow('Group', machine!.group),
              if (order.groupMachineIds.isNotEmpty)
                _detailRow('Other units', order.groupMachineIds.map((id) => machines[id]?.equipmentId ?? id).join(', ')),
              if (machine != null && machine.equipmentId.isNotEmpty)
                _detailRow('Equipment ID', machine.equipmentId),
              _detailRow('Type', '${_typeCode(order)} · ${taskTypeName(order.type)}'),
              if (order.preventiveTypes.isNotEmpty)
                _detailRow('Preventive type', order.preventiveTypes.join(', ')),
              _detailRow('Started', formatTime12h(order.startedAt ?? DateTime.now())),
              _detailRow('Running for', _duration(order.startedAt)),
              if (technicianNames.isNotEmpty)
                _detailRow('Junior Officer(s)', technicianNames.join(', ')),
              if (helperNames.isNotEmpty)
                _detailRow('CF(s)', helperNames.join(', ')),
              if (order.description.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Starting remarks', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.muted)),
                const SizedBox(height: 2),
                Text(order.description.trim()),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 14),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: value),
          ],
        ),
      ),
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
