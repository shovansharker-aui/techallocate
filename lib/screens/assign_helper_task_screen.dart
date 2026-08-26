import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/helper.dart';
import '../models/machine.dart';
import '../widgets_root_back_scope.dart';
import '../utils/app_colors.dart';

/// Creates a running work order for helper(s) without assigning the logged-in
/// technician to the work order. The technician therefore remains available.
class AssignHelperTaskScreen extends StatefulWidget {
  final String uid;

  const AssignHelperTaskScreen({super.key, required this.uid});

  @override
  State<AssignHelperTaskScreen> createState() => _AssignHelperTaskScreenState();
}

class _AssignHelperTaskScreenState extends State<AssignHelperTaskScreen> {
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

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _machinesStream =
      FirebaseFirestore.instance.collection('machines').orderBy('equipmentName').snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _helpersStream =
      FirebaseFirestore.instance.collection('helpers').orderBy('name').snapshots();

  @override
  void dispose() {
    _remarksController.dispose();
    _machineSearchController.dispose();
    super.dispose();
  }

  List<Machine> _filterMachines(List<Machine> machines, String query) {
    final search = query.trim().toLowerCase();
    if (search.isEmpty) return const [];
    final matches = machines
        .where((m) =>
            m.displayName.toLowerCase().contains(search) ||
            m.equipmentName.toLowerCase().contains(search) ||
            m.equipmentId.toLowerCase().contains(search))
        .toList();
    matches.sort((a, b) {
      int score(Machine m) {
        final n = m.displayName.toLowerCase();
        final id = m.equipmentId.toLowerCase();
        return (n == search || id == search)
            ? 0
            : (n.startsWith(search) || id.startsWith(search))
                ? 1
                : 2;
      }

      final c = score(a).compareTo(score(b));
      return c == 0
          ? a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase())
          : c;
    });
    return matches.take(5).toList();
  }

  void _selectMachine(Machine machine) {
    setState(() {
      _selectedMachine = machine;
      _selectedMachineId = machine.id;
      _machineSearchController.text = machine.displayName;
      _machineSearchController.selection = TextSelection.fromPosition(
        TextPosition(offset: _machineSearchController.text.length),
      );
      _showSuggestions = false;
      _errorText = null;
    });
  }

  Future<void> _chooseHelpers(List<Helper> helpers) async {
    final available = helpers
        .where((h) => h.status == 'available' || _selectedHelperIds.contains(h.uid))
        .toList();
    final result = Set<String>.from(_selectedHelperIds);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Select CFs',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (available.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('No available CFs right now.'),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 420),
                        child: ListView(
                          shrinkWrap: true,
                          children: available.map((helper) {
                            return CheckboxListTile(
                              value: result.contains(helper.uid),
                              title: Text(helper.name),
                              secondary: const Icon(Icons.handyman_outlined),
                              onChanged: (selected) {
                                setSheetState(() {
                                  if (selected == true) {
                                    result.add(helper.uid);
                                  } else {
                                    result.remove(helper.uid);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          setState(() {
                            _selectedHelperIds
                              ..clear()
                              ..addAll(result);
                          });
                          Navigator.pop(sheetContext);
                        },
                        child: Text('Done (${result.length} selected)'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _assign() async {
    setState(() => _errorText = null);

    if (_selectedMachineId == null) {
      setState(() => _errorText = 'Please select a machine.');
      return;
    }
    if (_selectedHelperIds.isEmpty) {
      setState(() => _errorText = 'Select at least one CF.');
      return;
    }
    if (_type == 'preventive' && _preventiveTypes.isEmpty) {
      setState(() => _errorText = 'Select at least one preventive maintenance type.');
      return;
    }

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
      'assignedTechnicianIds': <String>[],
      'helperIds': _selectedHelperIds.toList(),
      'createdBy': widget.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'startedAt': FieldValue.serverTimestamp(),
      'helperOnlyAssignment': true,
    });

    for (final helperId in _selectedHelperIds) {
      batch.update(
        firestore.collection('helpers').doc(helperId),
        {'status': 'assigned', 'currentTaskId': ref.id},
      );
    }

    try {
      await batch.commit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CF assignment started. You remain available.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Failed to assign CF: $e';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RootBackScope(
      child: Scaffold(
        appBar: AppBar(title: const Text('Assign a CF')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: const [
                    Icon(Icons.info_outline),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This creates a task for the selected CF(s). The Junior Officer assigning them remains available.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text('Machine', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _machinesStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('Unable to load machines: ${snapshot.error}');
                }
                final machines = snapshot.data?.docs
                        .map((d) => Machine.fromMap(d.id, d.data()))
                        .toList() ??
                    [];
                final suggestions = _filterMachines(
                  machines,
                  _machineSearchController.text,
                );
                return Column(
                  children: [
                    TextField(
                      controller: _machineSearchController,
                      onChanged: (value) {
                        setState(() {
                          _selectedMachine = null;
                          _selectedMachineId = null;
                          _showSuggestions = value.trim().isNotEmpty;
                        });
                      },
                      onTap: () => setState(() {
                        _showSuggestions =
                            _machineSearchController.text.trim().isNotEmpty;
                      }),
                      decoration: InputDecoration(
                        labelText: 'Search machine',
                        hintText: 'Machine name or equipment ID',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _selectedMachine == null
                            ? null
                            : IconButton(
                                onPressed: () => setState(() {
                                  _selectedMachine = null;
                                  _selectedMachineId = null;
                                  _machineSearchController.clear();
                                }),
                                icon: const Icon(Icons.clear),
                              ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (_showSuggestions && suggestions.isNotEmpty)
                      Card(
                        child: Column(
                          children: suggestions
                              .map(
                                (machine) => ListTile(
                                  title: Text(machine.displayName),
                                  subtitle: Text(machine.equipmentId),
                                  onTap: () => _selectMachine(machine),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    if (_selectedMachine != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Selected: ${_selectedMachine!.displayName}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            const Text('Maintenance Type', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in allTaskTypes) _typeChip(t, taskTypeCodeAndName(t)),
              ],
            ),
            if (_type == 'preventive') ...[
              const SizedBox(height: 14),
              const Text(
                'Preventive Maintenance Type (multiple allowed)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['W', 'M', '3M', '6M', 'Y', '2Y', '6Y'].map((value) {
                  return FilterChip(
                    label: Text(value),
                    selected: _preventiveTypes.contains(value),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _preventiveTypes.add(value);
                        } else {
                          _preventiveTypes.remove(value);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 18),
            const Text('Assign CF(s)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _helpersStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('Unable to load CFs: ${snapshot.error}');
                }
                final helpers = snapshot.data?.docs
                        .map((d) => Helper.fromMap(d.id, d.data()))
                        .toList() ??
                    [];
                final selected = helpers
                    .where((h) => _selectedHelperIds.contains(h.uid))
                    .toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _chooseHelpers(helpers),
                      icon: const Icon(Icons.group_add_outlined),
                      label: Text(
                        selected.isEmpty
                            ? 'Select CF(s)'
                            : 'Change CF(s) · ${selected.length}',
                      ),
                    ),
                    if (selected.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        children: selected.map((helper) {
                          return Chip(
                            avatar: const Icon(Icons.handyman_outlined, size: 16),
                            label: Text(helper.name),
                            onDeleted: () => setState(
                              () => _selectedHelperIds.remove(helper.uid),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            const Text('Starting remarks (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _remarksController,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Optional issue/background information',
              ),
            ),
            const SizedBox(height: 18),
            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_errorText!, style: const TextStyle(color: AppColors.danger)),
              ),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _assign,
                icon: const Icon(Icons.person_add_alt_1),
                label: _isSaving
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : const Text('Assign CF & Start Task'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeChip(String value, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _type == value,
      onSelected: (_) {
        setState(() {
          _type = value;
          if (value != 'preventive') {
            _preventiveTypes.clear();
          }
        });
      },
    );
  }
}
