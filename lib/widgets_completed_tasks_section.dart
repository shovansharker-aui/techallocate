import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'models/app_user.dart';
import 'models/machine.dart';
import 'utils/task_type.dart';
import 'models/work_order.dart';
import 'screens/completed_tasks_screen.dart';

class CompletedTasksSection extends StatelessWidget {
  const CompletedTasksSection({super.key});

  String _type(WorkOrder order) => taskTypeCode(order.type);

  String _duration(int? seconds) {
    if (seconds == null) return '—';
    final d = Duration(seconds: seconds);
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m';
    return '${d.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month, now.day);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('work_orders').where('status', isEqualTo: 'completed').where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff)).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Text('Unable to load completed tasks: ${snapshot.error}');
        final orders = (snapshot.data?.docs ?? []).map((d) => WorkOrder.fromMap(d.id, d.data())).toList()
          ..sort((a, b) => (b.completedAt ?? DateTime(1970)).compareTo(a.completedAt ?? DateTime(1970)));
        return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Expanded(child: Text('Completed Tasks · Today', style: TextStyle(fontWeight: FontWeight.bold))), TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CompletedTasksScreen())), child: const Text('View History'))]),
          if (orders.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No task completed today.'))
          else FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
            future: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'technician').get(),
            builder: (context, techSnapshot) => FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance.collection('machines').get(),
              builder: (context, machineSnapshot) {
                final techs = {for (final d in (techSnapshot.data?.docs ?? [])) d.id: AppUser.fromMap(d.id, d.data())};
                final machines = {for (final d in (machineSnapshot.data?.docs ?? [])) d.id: Machine.fromMap(d.id, d.data())};
                return Column(children: orders.take(8).map((o) {
                  final machine = machines[o.machineId];
                  final names = o.assignedTechnicianIds.map((id) => techs[id]?.name).whereType<String>().toList();
                  return ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: CircleAvatar(radius: 16, child: Text(_type(o))), title: Text(machine?.displayName ?? o.machineId, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text('${names.join(', ')} · ${_duration(o.durationSeconds)}'),);
                }).toList());
              },
            ),
          ),
        ])));
      },
    );
  }
}
