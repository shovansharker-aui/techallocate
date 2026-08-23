import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/helper.dart';
import '../models/machine.dart';
import '../models/work_order.dart';
import '../utils/app_colors.dart';
import '../utils/task_type.dart';
import '../utils/task_completion.dart';
import '../widgets_root_back_scope.dart';

// Lists the CF-only tasks this Junior Officer has assigned that are still
// running, so they can close them out. Needed because a CF has no login
// of their own — without this screen, only Admin could ever close these.
class MyCfAssignmentsScreen extends StatelessWidget {
  final String uid;
  const MyCfAssignmentsScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return RootBackScope(
      child: Scaffold(
        appBar: AppBar(title: const Text('My CF Assignments')),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                    'No running CF assignments right now.\n\nAnything you assign via "Assign a CF" will show up here until it\'s completed.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              itemBuilder: (context, index) => _AssignmentCard(order: orders[index]),
            );
          },
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
              future: FirebaseFirestore.instance.collection('machines').doc(order.machineId).get(),
              builder: (context, snap) {
                final machine = snap.data != null && snap.data!.exists
                    ? Machine.fromMap(snap.data!.id, snap.data!.data()!)
                    : null;
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        machine?.equipmentName ?? order.machineId,
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
                      final time = await pickCompletionTime(context, startedAt: order.startedAt);
                      if (time == null) return;
                      await completeWorkOrder(
                        orderId: order.id,
                        technicianIds: order.assignedTechnicianIds,
                        helperIds: order.helperIds,
                        completedAt: time,
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
