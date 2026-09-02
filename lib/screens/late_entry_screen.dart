import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/machine.dart';
import '../utils/app_colors.dart';
import '../utils/task_type.dart';
import '../utils/offline_commit.dart';

/// Lets a JO log a task that already happened but couldn't be entered
/// live (phone unavailable, no signal at the time, etc.) — machine,
/// maintenance type, start/stop time, and remarks, saved straight in as
/// already completed. Admin sees a "Late Entry" badge wherever this task
/// shows up, so it's clear the times were typed in afterwards rather
/// than captured as they happened.
class LateEntryScreen extends StatefulWidget {
  final String uid;
  const LateEntryScreen({super.key, required this.uid});

  @override
  State<LateEntryScreen> createState() => _LateEntryScreenState();
}

class _LateEntryScreenState extends State<LateEntryScreen> {
  String? _selectedMachineId;
  Machine? _selectedMachine;
  String _type = 'breakdown';
  final Set<String> _preventiveTypes = <String>{};
  DateTime? _startedAt;
  DateTime? _completedAt;
  final _remarksController = TextEditingController();
  final _machineSearchController = TextEditingController();
  bool _isSaving = false;
  bool _showSuggestions = false;
  String? _errorText;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _machinesStream =
      FirebaseFirestore.instance.collection('machines').orderBy('equipmentName').snapshots();

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

  Future<void> _pickDateTime({required bool isStart}) async {
    final now = DateTime.now();
    final initial = (isStart ? _startedAt : _completedAt) ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 60)),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    final picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startedAt = picked;
      } else {
        _completedAt = picked;
      }
      _errorText = null;
    });
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _save() async {
    setState(() => _errorText = null);
    if (_type != 'others' && _selectedMachineId == null) return setState(() => _errorText = 'Please select a machine.');
    if (_type == 'preventive' && _preventiveTypes.isEmpty) return setState(() => _errorText = 'Select at least one preventive maintenance type.');
    if (_startedAt == null) return setState(() => _errorText = 'Please set the start date & time.');
    if (_completedAt == null) return setState(() => _errorText = 'Please set the stop date & time.');
    if (!_completedAt!.isAfter(_startedAt!)) return setState(() => _errorText = 'Stop time must be after the start time.');
    final remarksRequired = _type != 'preventive';
    if (remarksRequired && _remarksController.text.trim().isEmpty) {
      return setState(() => _errorText = _type == 'others'
          ? 'Please describe what this task was.'
          : 'Remarks are required for BM, CL, AD and OT entries.');
    }

    setState(() => _isSaving = true);
    final firestore = FirebaseFirestore.instance;
    final ref = firestore.collection('work_orders').doc();
    final batch = firestore.batch();
    batch.set(ref, {
      'type': _type,
      'preventiveTypes': _type == 'preventive' ? _preventiveTypes.toList() : <String>[],
      'machineId': _selectedMachineId,
      'description': '',
      'priority': 'medium',
      'status': 'completed',
      'assignedTechnicianIds': [widget.uid],
      'helperIds': <String>[],
      'createdBy': widget.uid,
      // createdAt is when this record was actually typed in — separate
      // from startedAt/completedAt below, which are the JO's own
      // recollection of when the work really happened.
      'createdAt': Timestamp.fromDate(DateTime.now()),
      'startedAt': Timestamp.fromDate(_startedAt!),
      'completedAt': Timestamp.fromDate(_completedAt!),
      'durationSeconds': _completedAt!.difference(_startedAt!).inSeconds,
      'completionRemarks': _remarksController.text.trim(),
      'lateEntry': true,
    });

    commitAllowingOffline(batch);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Past task saved.')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Past Task')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: const [
              Icon(Icons.info_outline),
              SizedBox(width: 10),
              Expanded(child: Text('Use this only for a task you already finished but couldn\'t log at the time. Admin will see it marked as a late entry.')),
            ]),
          ),
        ),
        const SizedBox(height: 18),
        Text(_type == 'others' ? 'Machine (optional)' : 'Machine', style: const TextStyle(fontWeight: FontWeight.w600)),
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
              decoration: InputDecoration(labelText: _type == 'others' ? 'Search machine (optional)' : 'Search machine', hintText: 'Machine name or equipment ID', prefixIcon: const Icon(Icons.search), suffixIcon: _selectedMachine == null ? null : IconButton(onPressed: () => setState(() { _selectedMachine = null; _selectedMachineId = null; _machineSearchController.clear(); }), icon: const Icon(Icons.clear)), border: const OutlineInputBorder()),
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
        const SizedBox(height: 20),
        const Text('Start date & time', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () => _pickDateTime(isStart: true),
          icon: const Icon(Icons.schedule_outlined),
          label: Text(_startedAt == null ? 'Set start time' : _formatDateTime(_startedAt!)),
        ),
        const SizedBox(height: 16),
        const Text('Stop date & time', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () => _pickDateTime(isStart: false),
          icon: const Icon(Icons.schedule_outlined),
          label: Text(_completedAt == null ? 'Set stop time' : _formatDateTime(_completedAt!)),
        ),
        const SizedBox(height: 18),
        Text(
          _type == 'others' ? 'What was this task? (required)' : 'Remarks${_type == 'preventive' ? ' (optional)' : ' (required)'}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _remarksController,
          maxLines: 3,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'What was done, and why it\'s being logged late',
          ),
        ),
        const SizedBox(height: 18),
        if (_errorText != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_errorText!, style: const TextStyle(color: AppColors.danger))),
        SizedBox(height: 50, child: FilledButton(onPressed: _isSaving ? null : _save, child: _isSaving ? const CircularProgressIndicator(strokeWidth: 2) : const Text('Save Past Task'))),
      ]),
    );
  }

  Widget _typeChip(String value, String label) => ChoiceChip(label: Text(label), selected: _type == value, onSelected: (_) => setState(() { _type = value; if (value != 'preventive') _preventiveTypes.clear(); }));
}
