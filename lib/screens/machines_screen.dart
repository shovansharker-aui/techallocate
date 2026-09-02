import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/machine.dart';
import '../utils/app_colors.dart';
import 'bulk_import_machines_screen.dart';

class MachinesScreen extends StatefulWidget {
  const MachinesScreen({super.key});

  @override
  State<MachinesScreen> createState() => _MachinesScreenState();
}

class _MachinesScreenState extends State<MachinesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Machines'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Bulk import from CSV',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BulkImportMachinesScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showMachineForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Machine'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('machines').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Unable to load machines.\n${snapshot.error}', textAlign: TextAlign.center));
          }

          final machines = (snapshot.data?.docs ?? [])
              .map((doc) => Machine.fromMap(doc.id, doc.data()))
              .where(_matches)
              .toList()
            ..sort((a, b) => a.equipmentName.toLowerCase().compareTo(b.equipmentName.toLowerCase()));

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Search machine',
                    hintText: 'Search by machine name or equipment ID',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: _searchController.clear,
                            icon: const Icon(Icons.clear),
                          ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              Expanded(
                child: machines.isEmpty
                    ? Center(
                        child: Text(
                          _query.isEmpty
                              ? 'No machines yet. Tap Add Machine to create one.'
                              : 'No machines match "$_query".',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 90),
                        itemCount: machines.length,
                        itemBuilder: (context, index) {
                          final machine = machines[index];
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _categoryColor(machine.category),
                                child: const Icon(Icons.precision_manufacturing, color: Colors.white, size: 18),
                              ),
                              title: Text(machine.displayName),
                              subtitle: Text(
                                [
                                  machine.equipmentId,
                                  if (machine.brand.isNotEmpty) machine.equipmentName,
                                  machine.category,
                                  if (machine.isGrouped) 'Group: ${machine.group}',
                                ].join(' · '),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _showMachineForm(context, machine: machine),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  bool _matches(Machine machine) {
    if (_query.isEmpty) return true;
    return machine.equipmentName.toLowerCase().contains(_query) ||
        machine.equipmentId.toLowerCase().contains(_query) ||
        machine.brand.toLowerCase().contains(_query) ||
        machine.category.toLowerCase().contains(_query) ||
        machine.group.toLowerCase().contains(_query);
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'Engineering':
        return AppColors.categoryEngineering;
      case 'Warehouse':
        return AppColors.categoryWarehouse;
      default:
        return AppColors.categoryProduction;
    }
  }

  void _showMachineForm(BuildContext context, {Machine? machine}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _MachineFormSheet(machine: machine),
    );
  }
}

class _MachineFormSheet extends StatefulWidget {
  final Machine? machine;
  const _MachineFormSheet({this.machine});

  @override
  State<_MachineFormSheet> createState() => _MachineFormSheetState();
}

class _MachineFormSheetState extends State<_MachineFormSheet> {
  late final TextEditingController _equipmentIdController;
  late final TextEditingController _equipmentNameController;
  late final TextEditingController _brandController;
  late final TextEditingController _groupController;
  late String _category;
  bool _isSaving = false;
  String? _errorText;

  static const _categories = ['Engineering', 'Production', 'Warehouse'];
  bool get _isEditing => widget.machine != null;

  @override
  void initState() {
    super.initState();
    _equipmentIdController = TextEditingController(text: widget.machine?.equipmentId ?? '');
    _equipmentNameController = TextEditingController(text: widget.machine?.equipmentName ?? '');
    _brandController = TextEditingController(text: widget.machine?.brand ?? '');
    _groupController = TextEditingController(text: (widget.machine?.group ?? 'N/A') == 'N/A' ? '' : widget.machine!.group);
    _category = widget.machine?.category ?? 'Production';
  }

  @override
  void dispose() {
    _equipmentIdController.dispose();
    _equipmentNameController.dispose();
    _brandController.dispose();
    _groupController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_equipmentIdController.text.trim().isEmpty) {
      setState(() => _errorText = 'Equipment ID is required.');
      return;
    }
    if (_equipmentNameController.text.trim().isEmpty) {
      setState(() => _errorText = 'Equipment name is required.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    final data = {
      'equipmentId': _equipmentIdController.text.trim(),
      'equipmentName': _equipmentNameController.text.trim(),
      'brand': _brandController.text.trim(),
      'category': _category,
      'group': _groupController.text.trim().isEmpty ? 'N/A' : _groupController.text.trim(),
    };

    try {
      final machines = FirebaseFirestore.instance.collection('machines');
      final duplicate = await machines
          .where('equipmentId', isEqualTo: data['equipmentId'])
          .limit(1)
          .get();
      if (duplicate.docs.isNotEmpty && duplicate.docs.first.id != widget.machine?.id) {
        setState(() {
          _errorText = 'This Equipment ID already exists.';
          _isSaving = false;
        });
        return;
      }

      if (_isEditing) {
        await machines.doc(widget.machine!.id).update(data);
      } else {
        await machines.add(data);
      }
      if (mounted) Navigator.of(context).pop();
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() {
          _errorText = 'Failed to save: ${e.message ?? e.code}';
          _isSaving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorText = 'Failed to save: $e';
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete machine?'),
        content: Text('Remove "${widget.machine!.displayName}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance.collection('machines').doc(widget.machine!.id).delete();
        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        if (mounted) setState(() => _errorText = 'Failed to delete: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isEditing ? 'Edit Machine' : 'Add Machine',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_isEditing)
                  IconButton(
                    tooltip: 'Delete machine',
                    onPressed: _isSaving ? null : _delete,
                    icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _equipmentIdController,
              decoration: const InputDecoration(labelText: 'Equipment ID', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _equipmentNameController,
              decoration: const InputDecoration(labelText: 'Equipment Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _brandController,
              decoration: const InputDecoration(labelText: 'Nickname (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (value) => setState(() => _category = value!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _groupController,
              decoration: const InputDecoration(
                labelText: 'Group (optional)',
                helperText: 'e.g. "Tablet Compression-01" — leave blank if not part of a group',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_errorText!, style: const TextStyle(color: AppColors.danger)),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isEditing ? 'Save Changes' : 'Add Machine'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
