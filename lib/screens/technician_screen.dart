import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../models/helper.dart';
import '../models/machine.dart';
import '../models/work_order.dart';
import '../widgets_root_back_scope.dart';
import '../utils/task_type.dart';
import 'assign_helper_task_screen.dart';
import 'my_cf_assignments_screen.dart';
import '../utils/app_colors.dart';

class TechnicianScreen extends StatelessWidget {
  final AppUser user;
  final VoidCallback onLogout;

  const TechnicianScreen({super.key, required this.user, required this.onLogout});

  Future<void> _setDutyStatus(BuildContext context) async {
    if (user.status == 'assigned') {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Set Status'),
          children: [
            SimpleDialogOption(onPressed: () => Navigator.pop(context, 'day'), child: const ListTile(leading: Icon(Icons.wb_sunny_outlined), title: Text('Day'))),
            SimpleDialogOption(onPressed: () => Navigator.pop(context, 'night'), child: const ListTile(leading: Icon(Icons.nightlight_outlined), title: Text('Night'))),
          ],
        ),
      );
      if (choice != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'dutyStatus': choice});
      }
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Set Status'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'day'), child: const ListTile(leading: Icon(Icons.wb_sunny_outlined), title: Text('Day'))),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'night'), child: const ListTile(leading: Icon(Icons.nightlight_outlined), title: Text('Night'))),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'on_leave'), child: const ListTile(leading: Icon(Icons.event_busy_outlined), title: Text('On-leave'))),
        ],
      ),
    );
    if (choice == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'dutyStatus': choice,
      'status': choice == 'on_leave' ? 'on_leave' : 'available',
      'currentTaskId': choice == 'on_leave' ? null : user.currentTaskId,
    });
  }

  @override
  Widget build(BuildContext context) {
    final running = user.status == 'assigned' && user.currentTaskId != null;
    return RootBackScope(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Junior Officer Dashboard'),
          actions: [
            IconButton(icon: const Icon(Icons.toggle_on_outlined), tooltip: 'Set Status', onPressed: () => _setDutyStatus(context)),
            IconButton(icon: const Icon(Icons.logout), tooltip: 'Log out', onPressed: onLogout),
          ],
        ),
        body: running
            ? _CurrentTaskView(uid: user.uid, taskId: user.currentTaskId!)
            : _TechnicianHome(uid: user.uid, user: user, onSetStatus: () => _setDutyStatus(context)),
      ),
    );
  }
}

class _TechnicianHome extends StatelessWidget {
  final String uid;
  final AppUser user;
  final VoidCallback onSetStatus;
  const _TechnicianHome({required this.uid, required this.user, required this.onSetStatus});

  @override
  Widget build(BuildContext context) {
    final onLeave = user.dutyStatus == 'on_leave' || user.status == 'on_leave';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Hello, ${user.name}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Status: ${_dutyLabel(user.dutyStatus)}', style: TextStyle(color: onLeave ? AppColors.danger : AppColors.success, fontWeight: FontWeight.w600)),
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.play_arrow)),
            title: const Text('Start a task', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(onLeave ? 'Unavailable while on-leave.' : 'Select a machine, maintenance type and optional CFs.'),
            trailing: const Icon(Icons.chevron_right),
            enabled: !onLeave,
            onTap: onLeave ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _StartTaskPage(uid: uid))),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_add_alt_1)),
            title: const Text('Assign a CF', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(onLeave ? 'Unavailable while on-leave.' : 'Send a CF to a machine/task. You stay available.'),
            trailing: const Icon(Icons.chevron_right),
            enabled: !onLeave,
            onTap: onLeave ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AssignHelperTaskScreen(uid: uid))),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.playlist_add_check)),
            title: const Text('My CF Assignments', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Close out CF tasks you assigned.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MyCfAssignmentsScreen(uid: uid))),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.toggle_on_outlined)),
            title: const Text('Set Status', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Day, Night or On-leave'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onSetStatus,
          ),
        ),
      ],
    );
  }

  static String _dutyLabel(String value) {
    switch (value) {
      case 'night': return 'Night';
      case 'on_leave': return 'On-leave';
      default: return 'Day';
    }
  }
}

class _StartTaskPage extends StatefulWidget {
  final String uid;
  const _StartTaskPage({required this.uid});
  @override
  State<_StartTaskPage> createState() => _StartTaskPageState();
}

class _StartTaskPageState extends State<_StartTaskPage> {
  String? _selectedMachineId;
  Machine? _selectedMachine;
  String _type = 'preventive';
  final Set<String> _preventiveTypes = <String>{};
  final Set<String> _selectedHelperIds = <String>{};
  final _remarksController = TextEditingController();
  final _machineSearchController = TextEditingController();
  bool _isSaving = false;
  bool _showSuggestions = false;
  String? _errorText;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _machinesStream = FirebaseFirestore.instance.collection('machines').orderBy('equipmentName').snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _helpersStream = FirebaseFirestore.instance.collection('helpers').orderBy('name').snapshots();

  @override
  void dispose() {
    _remarksController.dispose();
    _machineSearchController.dispose();
    super.dispose();
  }

  List<Machine> _filterMachines(List<Machine> machines, String query) {
    final search = query.trim().toLowerCase();
    if (search.isEmpty) return const [];
    final matches = machines.where((m) => m.displayName.toLowerCase().contains(search) || m.equipmentName.toLowerCase().contains(search) || m.equipmentId.toLowerCase().contains(search)).toList();
    matches.sort((a, b) {
      int score(Machine m) {
        final n = m.displayName.toLowerCase();
        final id = m.equipmentId.toLowerCase();
        return (n == search || id == search) ? 0 : (n.startsWith(search) || id.startsWith(search)) ? 1 : 2;
      }
      final c = score(a).compareTo(score(b));
      return c == 0 ? a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()) : c;
    });
    return matches.take(5).toList();
  }

  void _selectMachine(Machine machine) {
    setState(() {
      _selectedMachine = machine;
      _selectedMachineId = machine.id;
      _machineSearchController.text = machine.displayName;
      _machineSearchController.selection = TextSelection.fromPosition(TextPosition(offset: _machineSearchController.text.length));
      _showSuggestions = false;
      _errorText = null;
    });
  }

  Future<void> _chooseHelpers(List<Helper> helpers) async {
    final available = helpers.where((h) => h.status == 'available' || _selectedHelperIds.contains(h.uid)).toList();
    final result = Set<String>.from(_selectedHelperIds);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(builder: (context, setSheetState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Select CFs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (available.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('No available CFs right now.'))
            else ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView(shrinkWrap: true, children: available.map((h) => CheckboxListTile(
                value: result.contains(h.uid),
                title: Text(h.name),
                secondary: const Icon(Icons.handyman_outlined),
                onChanged: (v) => setSheetState(() => v == true ? result.add(h.uid) : result.remove(h.uid)),
              )).toList()),
            ),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: () { setState(() { _selectedHelperIds..clear()..addAll(result); }); Navigator.pop(sheetContext); }, child: Text('Done (${result.length} selected)'))),
          ]),
        ),
      )),
    );
  }

  Future<void> _startTask() async {
    setState(() => _errorText = null);
    if (_selectedMachineId == null) return setState(() => _errorText = 'Please select a machine.');
    if (_type == 'preventive' && _preventiveTypes.isEmpty) return setState(() => _errorText = 'Select at least one preventive maintenance type.');
    if (_type == 'others' && _remarksController.text.trim().isEmpty) return setState(() => _errorText = 'Please describe what this task is.');

    setState(() => _isSaving = true);
    final firestore = FirebaseFirestore.instance;
    final ref = firestore.collection('work_orders').doc();
    final batch = firestore.batch();
    batch.set(ref, {
      'type': _type,
      'preventiveTypes': _type == 'preventive' ? _preventiveTypes.toList() : <String>[],
      'machineId': _selectedMachineId,
      'description': _remarksController.text.trim(),
      'priority': 'medium',
      'status': 'in_progress',
      'assignedTechnicianIds': [widget.uid],
      'helperIds': _selectedHelperIds.toList(),
      'createdBy': widget.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'startedAt': FieldValue.serverTimestamp(),
    });
    batch.update(firestore.collection('users').doc(widget.uid), {'status': 'assigned', 'currentTaskId': ref.id});
    for (final id in _selectedHelperIds) {
      batch.update(firestore.collection('helpers').doc(id), {'status': 'assigned', 'currentTaskId': ref.id});
    }
    try {
      await batch.commit();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() { _errorText = 'Failed to start task: $e'; _isSaving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Start a Task')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Machine', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: _machinesStream, builder: (context, snapshot) {
          if (snapshot.hasError) return Text('Unable to load machines: ${snapshot.error}');
          final machines = snapshot.data?.docs.map((d) => Machine.fromMap(d.id, d.data())).toList() ?? [];
          final suggestions = _filterMachines(machines, _machineSearchController.text);
          return Column(children: [
            TextField(
              controller: _machineSearchController,
              onChanged: (v) => setState(() { _selectedMachine = null; _selectedMachineId = null; _showSuggestions = v.trim().isNotEmpty; }),
              onTap: () => setState(() => _showSuggestions = _machineSearchController.text.trim().isNotEmpty),
              decoration: InputDecoration(labelText: 'Search machine', hintText: 'Machine name or equipment ID', prefixIcon: const Icon(Icons.search), suffixIcon: _selectedMachine == null ? null : IconButton(onPressed: () => setState(() { _selectedMachine = null; _selectedMachineId = null; _machineSearchController.clear(); }), icon: const Icon(Icons.clear)), border: const OutlineInputBorder()),
            ),
            if (_showSuggestions && suggestions.isNotEmpty) Card(child: Column(children: suggestions.map((m) => ListTile(title: Text(m.displayName), subtitle: Text(m.equipmentId), onTap: () => _selectMachine(m))).toList())),
            if (_selectedMachine != null) Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(top: 8), child: Text('Selected: ${_selectedMachine!.displayName}', style: const TextStyle(fontWeight: FontWeight.w600)))),
          ]);
        }),
        const SizedBox(height: 20),
        const Text('Maintenance Type', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in allTaskTypes) _typeChip(t, taskTypeCodeAndName(t)),
        ]),
        if (_type == 'preventive') ...[
          const SizedBox(height: 14),
          const Text('Preventive Maintenance Type (multiple allowed)', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['W', 'M', '3M', '6M', 'Y', '2Y', '6Y'].map((v) {
              return FilterChip(
                label: Text(v),
                selected: _preventiveTypes.contains(v),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _preventiveTypes.add(v);
                    } else {
                      _preventiveTypes.remove(v);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 18),
        const Text('CFs (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: _helpersStream, builder: (context, snapshot) {
          if (snapshot.hasError) return Text('Unable to load CFs: ${snapshot.error}');
          final helpers = snapshot.data?.docs.map((d) => Helper.fromMap(d.id, d.data())).toList() ?? [];
          final selected = helpers.where((h) => _selectedHelperIds.contains(h.uid)).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            OutlinedButton.icon(onPressed: () => _chooseHelpers(helpers), icon: const Icon(Icons.group_add_outlined), label: Text(selected.isEmpty ? 'Select CF(s)' : 'Change CF(s) · ${selected.length}')),
            if (selected.isNotEmpty)
              Wrap(
                spacing: 6,
                children: selected.map((h) {
                  return Chip(
                    avatar: const Icon(Icons.handyman_outlined, size: 16),
                    label: Text(h.name),
                    onDeleted: () => setState(() => _selectedHelperIds.remove(h.uid)),
                  );
                }).toList(),
              ),
          ]);
        }),
        const SizedBox(height: 18),
        Text(
          _type == 'others' ? 'What is this task? (required)' : 'Starting remarks (optional)',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _remarksController,
          maxLines: 3,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: _type == 'others' ? 'Describe the task, e.g. "Cleaning storage room"' : 'Optional issue/background information',
          ),
        ),
        const SizedBox(height: 18),
        if (_errorText != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_errorText!, style: const TextStyle(color: AppColors.danger))),
        SizedBox(height: 50, child: FilledButton(onPressed: _isSaving ? null : _startTask, child: _isSaving ? const CircularProgressIndicator(strokeWidth: 2) : const Text('Start Task'))),
      ]),
    );
  }

  Widget _typeChip(String value, String label) => ChoiceChip(label: Text(label), selected: _type == value, onSelected: (_) => setState(() { _type = value; if (value != 'preventive') _preventiveTypes.clear(); }));
}

class _CurrentTaskView extends StatefulWidget {
  final String uid;
  final String taskId;
  const _CurrentTaskView({required this.uid, required this.taskId});
  @override
  State<_CurrentTaskView> createState() => _CurrentTaskViewState();
}

class _CurrentTaskViewState extends State<_CurrentTaskView> {
  bool _isCompleting = false;

  String _typeCode(WorkOrder order) => taskTypeCode(order.type);

  Future<void> _chooseAndAddHelpers(WorkOrder order) async {
    final snap = await FirebaseFirestore.instance.collection('helpers').orderBy('name').get();
    final helpers = snap.docs.map((d) => Helper.fromMap(d.id, d.data())).toList();
    final available = helpers.where((h) => h.status == 'available' || order.helperIds.contains(h.uid)).toList();
    final selected = Set<String>.from(order.helperIds);
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (sheetContext) => StatefulBuilder(builder: (context, setSheetState) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Add / Manage CFs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: ListView(
            shrinkWrap: true,
            children: available.map((h) {
              return CheckboxListTile(
                value: selected.contains(h.uid),
                title: Text(h.name),
                secondary: const Icon(Icons.handyman_outlined),
                onChanged: (v) {
                  setSheetState(() {
                    if (v == true) {
                      selected.add(h.uid);
                    } else {
                      selected.remove(h.uid);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () async { Navigator.pop(sheetContext); await _syncHelpers(order.helperIds.toSet(), selected); }, child: Text('Save (${selected.length})'))),
      ]),
    ))));
  }

  Future<void> _confirmReleaseAllHelpers(WorkOrder order) async {
    if (order.helperIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Release all CFs?'),
        content: Text('This will release all ${order.helperIds.length} CF(s) from this task.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Release all')),
        ],
      ),
    );
    if (confirmed == true) {
      await _syncHelpers(order.helperIds.toSet(), <String>{});
    }
  }

  Future<void> _syncHelpers(Set<String> oldIds, Set<String> newIds) async {
    final added = newIds.difference(oldIds);
    final removed = oldIds.difference(newIds);
    final firestore = FirebaseFirestore.instance;
    try {
      for (final id in added) {
        await firestore.runTransaction((tx) async {
          final ref = firestore.collection('helpers').doc(id);
          final snap = await tx.get(ref);
          if (!snap.exists) throw Exception('CF not found.');
          final data = snap.data()!;
          if ((data['status'] ?? 'available') != 'available') throw Exception('${data['name'] ?? 'CF'} is no longer available.');
          tx.update(ref, {'status': 'assigned', 'currentTaskId': widget.taskId});
          tx.update(firestore.collection('work_orders').doc(widget.taskId), {'helperIds': FieldValue.arrayUnion([id])});
        });
      }
      for (final id in removed) {
        final batch = firestore.batch();
        batch.update(firestore.collection('work_orders').doc(widget.taskId), {'helperIds': FieldValue.arrayRemove([id])});
        batch.update(firestore.collection('helpers').doc(id), {'status': 'available', 'currentTaskId': null});
        await batch.commit();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update CFs: $e')));
    }
  }

  Future<void> _confirmAndComplete(WorkOrder order) async {
    final required = order.type != 'preventive';

    // The TextEditingController is owned by the dialog itself.
    // This is important because Flutter may still dispatch a focus
    // notification for the TextField immediately after the dialog closes.
    // Disposing a controller here, immediately after showDialog returns,
    // can cause: "A TextEditingController was used after being disposed."
    final remarks = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CompletionConfirmationDialog(
        initialRemarks: order.completionRemarks,
        requiredRemarks: required,
      ),
    );

    if (!mounted || remarks == null) return;
    await _completeTask(order, remarks);
  }

  Future<void> _completeTask(WorkOrder order, String remarks) async {
    setState(() => _isCompleting = true);
    final firestore = FirebaseFirestore.instance;
    final now = DateTime.now();
    final duration = order.startedAt == null ? null : now.difference(order.startedAt!).inSeconds;
    final batch = firestore.batch();
    batch.update(firestore.collection('work_orders').doc(widget.taskId), {
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
      'durationSeconds': duration,
      'completionRemarks': remarks,
    });
    batch.update(firestore.collection('users').doc(widget.uid), {'status': 'available', 'currentTaskId': null});
    for (final id in order.helperIds) {
      batch.update(firestore.collection('helpers').doc(id), {'status': 'available', 'currentTaskId': null});
    }
    try {
      await batch.commit();
    } catch (e) {
      if (mounted) {
        setState(() => _isCompleting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to complete task: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('work_orders').doc(widget.taskId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (!snapshot.data!.exists) return const Center(child: Text('Task not found.'));
        final order = WorkOrder.fromMap(snapshot.data!.id, snapshot.data!.data()!);
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance.collection('machines').doc(order.machineId).get(),
          builder: (context, machineSnapshot) {
            final machine = machineSnapshot.data?.exists == true ? Machine.fromMap(machineSnapshot.data!.id, machineSnapshot.data!.data()!) : null;
            return Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: ListView(children: [
                const Text('Task Running', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 18),
                Row(children: [
                  CircleAvatar(radius: 16, child: Text(_typeCode(order), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Machine: ${machine?.displayName ?? order.machineId}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                ]),
                if (machine?.equipmentId.isNotEmpty == true) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Equipment ID: ${machine!.equipmentId}')),
                if (order.type == 'preventive' && order.preventiveTypes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Preventive type: ${order.preventiveTypes.join(', ')}')),
                if (order.description.isNotEmpty) ...[const SizedBox(height: 8), Text('Starting remarks: ${order.description}')],
                const SizedBox(height: 18),
                Row(children: [
                  const Expanded(child: Text('CFs', style: TextStyle(fontWeight: FontWeight.w600))),
                  if (order.helperIds.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => _confirmReleaseAllHelpers(order),
                      icon: const Icon(Icons.person_remove_alt_1, size: 18),
                      label: const Text('Release all'),
                      style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                    ),
                  OutlinedButton.icon(onPressed: () => _chooseAndAddHelpers(order), icon: const Icon(Icons.person_add_alt_1), label: const Text('Add CF')),
                ]),
                const SizedBox(height: 4),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: order.helperIds.isEmpty ? null : FirebaseFirestore.instance.collection('helpers').where(FieldPath.documentId, whereIn: order.helperIds).snapshots(),
                  builder: (context, helperSnapshot) {
                    final docs = helperSnapshot.data?.docs ?? [];
                    if (docs.isEmpty) return const Text('No CF selected.');
                    return Column(
                      children: docs.map((d) {
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.handyman_outlined),
                          title: Text((d.data()['name'] ?? '').toString()),
                          trailing: TextButton(
                            onPressed: () => _syncHelpers(
                              order.helperIds.toSet(),
                              order.helperIds.toSet()..remove(d.id),
                            ),
                            child: const Text('Release'),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 18),
                if (order.type != 'preventive') Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: .08), borderRadius: BorderRadius.circular(10)), child: const Text('Completion remarks are required for Breakdown, Calibration and Adjustment tasks.')),
              ])),
              SizedBox(width: double.infinity, height: 50, child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white), onPressed: _isCompleting ? null : () => _confirmAndComplete(order), icon: const Icon(Icons.check_circle_outline), label: _isCompleting ? const CircularProgressIndicator(strokeWidth: 2) : const Text('Complete Task'))),
            ]));
          },
        );
      },
    );
  }
}


class _CompletionConfirmationDialog extends StatefulWidget {
  final String initialRemarks;
  final bool requiredRemarks;

  const _CompletionConfirmationDialog({
    required this.initialRemarks,
    required this.requiredRemarks,
  });

  @override
  State<_CompletionConfirmationDialog> createState() =>
      _CompletionConfirmationDialogState();
}

class _CompletionConfirmationDialogState
    extends State<_CompletionConfirmationDialog> {
  late final TextEditingController _remarksController;

  @override
  void initState() {
    super.initState();
    _remarksController =
        TextEditingController(text: widget.initialRemarks);
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  void _submit() {
    final remarks = _remarksController.text.trim();

    if (widget.requiredRemarks && remarks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remarks are required for BM, CL and AD.'),
        ),
      );
      return;
    }

    Navigator.of(context).pop(remarks);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm Task Completion'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Please double-check the task details before final submission.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _remarksController,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                labelText: widget.requiredRemarks
                    ? 'Corrective action / adjustment / calibration remarks (required)'
                    : 'Completion remarks (optional)',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Confirm & Submit'),
        ),
      ],
    );
  }
}
