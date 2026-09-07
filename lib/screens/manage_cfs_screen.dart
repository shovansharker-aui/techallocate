import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/helper.dart';
import '../models/machine.dart';
import '../models/work_order.dart';
import '../utils/app_colors.dart';
import '../utils/date_format.dart';
import '../utils/task_type.dart';

/// Lists every CF (Contract Force) with their live status, and lets
/// admin manually force a stuck one back to "available" — the escape
/// hatch for a CF who shows as "assigned" in the picker a JO uses to
/// add a CF to a task, but isn't actually doing anything: the task
/// they were on got abandoned, forgotten, or removed outside the app
/// (there's no Cloud Function on this project's Firebase plan to catch
/// that automatically and release them). Forcing a CF available does
/// NOT touch whatever work order they're still listed on — it only
/// clears their own record so they're selectable again; if that work
/// order really is still running, its own detail view still lists them
/// as one of its CF(s) regardless.
class ManageCfsScreen extends StatelessWidget {
  const ManageCfsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage CFs')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('helpers').orderBy('name').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Unable to load: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final helpers = snapshot.data!.docs.map((d) => Helper.fromMap(d.id, d.data())).toList();
          if (helpers.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No CFs added yet.')));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: helpers.length,
            itemBuilder: (context, i) => _HelperCard(helper: helpers[i]),
          );
        },
      ),
    );
  }
}

class _HelperCard extends StatefulWidget {
  final Helper helper;
  const _HelperCard({required this.helper});

  @override
  State<_HelperCard> createState() => _HelperCardState();
}

class _HelperCardState extends State<_HelperCard> {
  bool _isResetting = false;

  Future<void> _forceAvailable() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Force this CF available?'),
        content: Text(
          'Only do this if ${widget.helper.name.isEmpty ? 'this CF' : widget.helper.name} is NOT actually still '
          'working — e.g. the task they were on was abandoned or removed outside the app. This clears their own '
          'status only; it does not change whatever task they may still be listed on.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Force Available'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isResetting = true);
    try {
      await FirebaseFirestore.instance.collection('helpers').doc(widget.helper.uid).update({
        'status': 'available',
        'currentTaskId': null,
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update: $e')));
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final helper = widget.helper;
    final assigned = helper.status == 'assigned';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(child: Text(helper.name.isEmpty ? '?' : helper.name[0].toUpperCase())),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(helper.name.isEmpty ? '(No name)' : helper.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    if (helper.employeeId.isNotEmpty) Text(helper.employeeId, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (assigned ? AppColors.danger : AppColors.success).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  assigned ? 'Assigned' : 'Available',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: assigned ? AppColors.danger : AppColors.success),
                ),
              ),
            ]),
            if (assigned && (helper.currentTaskId ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              _CurrentTaskLine(taskId: helper.currentTaskId!),
            ],
            if (assigned) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isResetting ? null : _forceAvailable,
                  icon: _isResetting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.restart_alt),
                  label: const Text('Force Available'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Resolves and shows which task/machine a CF is currently attached to,
// so admin can judge whether "Force Available" is actually safe before
// using it, rather than guessing blind.
class _CurrentTaskLine extends StatelessWidget {
  final String taskId;
  const _CurrentTaskLine({required this.taskId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('work_orders').doc(taskId).get(),
      builder: (context, snap) {
        const style = TextStyle(color: AppColors.muted, fontSize: 12);
        if (!snap.hasData) {
          return const Text('Loading current task…', style: style);
        }
        if (!snap.data!.exists) {
          return const Text(
            "Their current task record no longer exists — safe to force available.",
            style: TextStyle(color: AppColors.muted, fontSize: 12, fontStyle: FontStyle.italic),
          );
        }
        final order = WorkOrder.fromMap(snap.data!.id, snap.data!.data()!);
        if (order.status != 'in_progress') {
          return Text(
            'Their current task is already ${order.status} — safe to force available.',
            style: const TextStyle(color: AppColors.muted, fontSize: 12, fontStyle: FontStyle.italic),
          );
        }
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: order.machineId.isEmpty ? null : FirebaseFirestore.instance.collection('machines').doc(order.machineId).get(),
          builder: (context, machineSnap) {
            final machine = machineSnap.data != null && machineSnap.data!.exists ? Machine.fromMap(machineSnap.data!.id, machineSnap.data!.data()!) : null;
            final name = machine?.displayName ?? (order.machineId.isEmpty ? 'No machine' : order.machineId);
            return Text(
              'Still running: $name (${taskTypeCode(order.type)}), started ${formatDateTime12h(order.startedAt)}.',
              style: style,
            );
          },
        );
      },
    );
  }
}
