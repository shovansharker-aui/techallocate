import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/helper.dart';
import '../models/machine.dart';
import '../models/work_order.dart';
import '../utils/app_colors.dart';
import '../utils/date_format.dart';
import '../utils/task_type.dart';
import '../utils/task_completion.dart';
import '../widgets_confirm_back_scope.dart';
import 'assign_helper_task_screen.dart';

// Combines what used to be two separate menu entries — "Assign a CF" and
// "My CF Assignments" — into one screen: a bar at the top starts a new
// CF-only assignment, and everything the JO has already assigned that's
// still running is listed below it, so they can close those out. Needed
// because a CF has no login of their own — without this, only Admin
// could ever close these out.
class CfAssignmentsScreen extends StatelessWidget {
  final String uid;
  final bool canAssign;
  const CfAssignmentsScreen({super.key, required this.uid, this.canAssign = true});

  @override
  Widget build(BuildContext context) {
    return ConfirmBackScope(
      title: 'Go back to the dashboard?',
      message: 'Leave CF Assignments?',
      child: Scaffold(
        appBar: AppBar(title: const Text('CF Assignments')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person_add_alt_1)),
                  title: const Text('Assign a CF', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(canAssign ? 'Send a CF to a machine/task. You stay available.' : 'Unavailable while on-leave.'),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: canAssign,
                  onTap: canAssign ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AssignHelperTaskScreen(uid: uid))) : null,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(alignment: Alignment.centerLeft, child: Text('Running CF Assignments', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('work_orders')
                    .where('createdBy', isEqualTo: uid)
                    .where('helperOnlyAssignment', isEqualTo: true)
                    .where('status', isEqualTo: 'in_progress')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Unable to load: ${snapshot.error}'));
                  }
                  final orders = (snapshot.data?.docs ?? [])
                      .map((d) => WorkOrder.fromMap(d.id, d.data()))
                      .toList();
                  if (orders.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No running CF assignments right now.\n\nAnything you assign above will show up here until it\'s completed.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: orders.length,
                    itemBuilder: (context, index) => _AssignmentCard(order: orders[index]),
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

class _AssignmentCard extends StatelessWidget {
  final WorkOrder order;
  const _AssignmentCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: order.machineId.isEmpty
                  ? null
                  : FirebaseFirestore.instance.collection('machines').doc(order.machineId).get(),
              builder: (context, snap) {
                final machine = snap.data != null && snap.data!.exists
                    ? Machine.fromMap(snap.data!.id, snap.data!.data()!)
                    : null;
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        machine?.displayName ?? (order.machineId.isEmpty ? 'No machine' : order.machineId),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(taskTypeCode(order.type), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                );
              },
            ),
            if (order.groupMachineIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  future: FirebaseFirestore.instance.collection('machines').where(FieldPath.documentId, whereIn: order.groupMachineIds).get(),
                  builder: (context, snap) {
                    final Map<String, Machine> byId = {for (final d in (snap.data?.docs ?? [])) d.id: Machine.fromMap(d.id, d.data())};
                    final labels = order.groupMachineIds.map((id) => byId[id]?.equipmentId ?? id).join(', ');
                    return Text('Other units: $labels', style: const TextStyle(color: AppColors.muted, fontSize: 12));
                  },
                ),
              ),
            const SizedBox(height: 4),
            if (order.startedAt != null)
              Text('Started ${formatDateTime12h(order.startedAt)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 6),
            FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
              future: order.helperIds.isEmpty
                  ? null
                  : FirebaseFirestore.instance
                      .collection('helpers')
                      .where(FieldPath.documentId, whereIn: order.helperIds)
                      .get(),
              builder: (context, snap) {
                final names = (snap.data?.docs ?? [])
                    .map((d) => Helper.fromMap(d.id, d.data()).name)
                    .join(', ');
                return Text('CF: ${names.isEmpty ? '…' : names}', style: const TextStyle(color: AppColors.muted));
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
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
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Complete Task'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
