import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../utils/app_colors.dart';
import '../utils/maintenance_login.dart';
import 'add_personnel_screen.dart';
import 'manage_cfs_screen.dart';

/// One place for every kind of personnel: Maintenance JOs, CFs (live status,
/// force-available) and Water Plant personnel, plus adding new ones (+).
/// Access changes:
/// - a Water Plant person can be given (or lose) Maintenance access -- their
///   own login to work as a JO too;
/// - a Maintenance JO can be given (or lose) Water Plant access -- the
///   Water Plant overview + duty allocation on their dashboard.
/// Removing Maintenance access never deletes the login (work orders point
/// at it) -- it's parked with role 'inactive' so it can't sign in, and
/// switching it back on just restores it.
class ManagePersonnelScreen extends StatelessWidget {
  const ManagePersonnelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Manage Personnel'),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_add_alt_1_outlined),
              tooltip: 'Add Personnel',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddPersonnelScreen())),
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Maintenance JOs'),
            Tab(text: 'CFs'),
            Tab(text: 'Water Plant'),
          ]),
        ),
        body: TabBarView(
          children: [
            ListView(padding: const EdgeInsets.all(16), children: const [_JoSection()]),
            const ManageCfsBody(),
            ListView(padding: const EdgeInsets.all(16), children: const [_WaterPlantSection()]),
          ],
        ),
      ),
    );
  }
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _WaterPlantSection extends StatelessWidget {
  const _WaterPlantSection();

  Future<void> _toggle(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc, bool on) async {
    final data = doc.data();
    final linkedId = (data['maintenanceUserId'] ?? '').toString();
    final firestore = FirebaseFirestore.instance;
    try {
      if (linkedId.isNotEmpty) {
        await firestore.collection('users').doc(linkedId).update({'role': on ? 'technician' : 'inactive'});
        return;
      }
      if (!on) return;
      final creds = await _askCredentials(context, (data['name'] ?? '').toString());
      if (creds == null) return;
      await createMaintenanceLogin(
        personnelDocId: doc.id,
        name: (data['name'] ?? '').toString(),
        employeeId: (data['employeeId'] ?? '').toString(),
        phone: creds.phone,
        pin: creds.pin,
      );
    } catch (e) {
      if (context.mounted) _snack(context, 'Could not update access: $e');
    }
  }

  Future<({String phone, String pin})?> _askCredentials(BuildContext context, String name) async {
    final phone = TextEditingController();
    final pin = TextEditingController();
    final result = await showDialog<({String phone, String pin})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Maintenance login for $name'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Logs in with their Employee ID from the water plant list and this PIN.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 12),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: pin, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'PIN (4+ digits)', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final p = pin.text.trim();
              if (phone.text.trim().isEmpty || !RegExp(r'^\d{4,}$').hasMatch(p)) {
                _snack(dialogContext, 'Enter a phone number and a PIN of at least 4 digits.');
                return;
              }
              Navigator.pop(dialogContext, (phone: phone.text.trim(), pin: p));
            },
            child: const Text('Create login'),
          ),
        ],
      ),
    );
    phone.dispose();
    pin.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('water_plant_personnel').orderBy('name').snapshots(),
      builder: (context, personSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users').snapshots(),
          builder: (context, userSnap) {
            if (personSnap.hasError) return Text('Unable to load: ${personSnap.error}');
            if (!personSnap.hasData) return const Center(child: CircularProgressIndicator());
            final roles = {for (final d in (userSnap.data?.docs ?? [])) d.id: (d.data()['role'] ?? '').toString()};
            final docs = personSnap.data!.docs;
            if (docs.isEmpty) return const Text('No water plant personnel yet.', style: TextStyle(color: AppColors.muted));
            return Column(
              children: docs.map((doc) {
                final data = doc.data();
                final linkedId = (data['maintenanceUserId'] ?? '').toString();
                final enabled = linkedId.isNotEmpty && roles[linkedId] == 'technician';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: SwitchListTile(
                    title: Text((data['name'] ?? '').toString()),
                    subtitle: Text('ID ${data['employeeId'] ?? ''} · Maintenance access ${enabled ? 'on' : 'off'}'),
                    value: enabled,
                    onChanged: (v) => _toggle(context, doc, v),
                  ),
                );
              }).toList(),
            );
          },
        );
      },
    );
  }
}

class _JoSection extends StatelessWidget {
  const _JoSection();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'technician').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Text('Unable to load: ${snapshot.error}');
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final users = snapshot.data!.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        if (users.isEmpty) return const Text('No maintenance JOs yet.', style: TextStyle(color: AppColors.muted));
        return Column(
          children: users.map((u) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: SwitchListTile(
              title: Text(u.name),
              subtitle: Text('ID ${u.employeeId} · Water Plant access ${u.waterPlantAccess ? 'on' : 'off'}'),
              value: u.waterPlantAccess,
              onChanged: (v) async {
                try {
                  await FirebaseFirestore.instance.collection('users').doc(u.uid).update({'waterPlantAccess': v});
                } catch (e) {
                  if (context.mounted) _snack(context, 'Could not update access: $e');
                }
              },
            ),
          )).toList(),
        );
      },
    );
  }
}
