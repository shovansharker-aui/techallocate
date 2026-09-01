import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

enum _PersonnelCategory { maintenanceJo, maintenanceCf, waterPlant }

// Consolidates what used to be separate "Add Employee" (JO) and "Add CF"
// screens, plus the new Water Plant Personnel category, behind one
// dropdown-driven form — matching whichever type is selected to its own
// Firestore collection and field set.
class AddPersonnelScreen extends StatefulWidget {
  const AddPersonnelScreen({super.key});

  @override
  State<AddPersonnelScreen> createState() => _AddPersonnelScreenState();
}

class _AddPersonnelScreenState extends State<AddPersonnelScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _employeeIdController = TextEditingController();
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();

  _PersonnelCategory _category = _PersonnelCategory.maintenanceJo;
  bool _isSaving = false;
  bool _hidePin = true;
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    _employeeIdController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  String get _collectionName => switch (_category) {
        _PersonnelCategory.maintenanceJo => 'users',
        _PersonnelCategory.maintenanceCf => 'helpers',
        _PersonnelCategory.waterPlant => 'water_plant_personnel',
      };

  String get _successNoun => switch (_category) {
        _PersonnelCategory.maintenanceJo => 'Junior Officer',
        _PersonnelCategory.maintenanceCf => 'CF',
        _PersonnelCategory.waterPlant => 'Water Plant personnel',
      };

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    final employeeId = _employeeIdController.text.trim();
    final firestore = FirebaseFirestore.instance;

    try {
      final existing = await firestore
          .collection(_collectionName)
          .where('employeeId', isEqualTo: employeeId)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        setState(() {
          _errorText = 'This Employee ID already exists in this category.';
          _isSaving = false;
        });
        return;
      }

      final Map<String, dynamic> data;
      switch (_category) {
        case _PersonnelCategory.maintenanceJo:
          data = {
            'name': _nameController.text.trim(),
            'employeeId': employeeId,
            'phone': _phoneController.text.trim(),
            'pin': _pinController.text.trim(),
            'role': 'technician',
            'trade': '',
            'shift': '',
            'status': 'available',
            'dutyStatus': 'day',
            'currentTaskId': null,
            'createdAt': FieldValue.serverTimestamp(),
          };
          break;
        case _PersonnelCategory.maintenanceCf:
          data = {
            'employeeId': employeeId,
            'name': _nameController.text.trim(),
            'status': 'available',
            'currentTaskId': null,
            'createdAt': FieldValue.serverTimestamp(),
          };
          break;
        case _PersonnelCategory.waterPlant:
          data = {
            'employeeId': employeeId,
            'name': _nameController.text.trim(),
            'dutyStatus': 'day',
            'plant': 'gp',
            'statusSetAt': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
          };
          break;
      }

      await firestore.collection(_collectionName).add(data);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$_successNoun added successfully.')),
      );
      Navigator.of(context).pop();
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Failed to save: ${e.message ?? e.code}';
        _isSaving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Failed to save: $e';
        _isSaving = false;
      });
    }
  }

  String? _required(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label is required.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final needsPhoneAndPin = _category == _PersonnelCategory.maintenanceJo;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Personnel')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Personnel Type', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                DropdownButtonFormField<_PersonnelCategory>(
                  initialValue: _category,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: _PersonnelCategory.maintenanceJo, child: Text('Maintenance JO')),
                    DropdownMenuItem(value: _PersonnelCategory.maintenanceCf, child: Text('Maintenance CF')),
                    DropdownMenuItem(value: _PersonnelCategory.waterPlant, child: Text('Water Plant Personnel')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _category = value;
                      _errorText = null;
                    });
                  },
                ),
                const SizedBox(height: 20),
                const Text('Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Employee Name',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => _required(value, 'Employee name'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _employeeIdController,
                  decoration: const InputDecoration(
                    labelText: 'Employee ID',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => _required(value, 'Employee ID'),
                ),
                if (needsPhoneAndPin) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      prefixIcon: Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => _required(value, 'Phone number'),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _pinController,
                    obscureText: _hidePin,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'PIN',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _hidePin = !_hidePin),
                        icon: Icon(_hidePin ? Icons.visibility : Icons.visibility_off),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final error = _required(value, 'PIN');
                      if (error != null) return error;
                      if (!RegExp(r'^\d+$').hasMatch(value!.trim())) return 'PIN must contain numbers only.';
                      if (value.trim().length < 4) return 'PIN must be at least 4 digits.';
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  switch (_category) {
                    _PersonnelCategory.maintenanceJo => 'Logs in with Employee ID + PIN, on Android or web.',
                    _PersonnelCategory.maintenanceCf => 'CFs do not log in — they\'re attached to a JO\'s active task.',
                    _PersonnelCategory.waterPlant => 'Water Plant Personnel do not log in individually — their availability is set through the Water Plant login.',
                  },
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 18),
                if (_errorText != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_errorText!, style: const TextStyle(color: AppColors.danger)),
                  ),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Add Personnel'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
