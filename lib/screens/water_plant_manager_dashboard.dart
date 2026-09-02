import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/water_plant_personnel.dart';
import '../services/technician_session_service.dart';
import '../utils/app_colors.dart';
import '../utils/water_plant.dart';
import '../utils/offline_commit.dart';
import 'login_screen.dart';

// Landing screen for the generic Water Plant login. Shows every Water
// Plant Personnel with a Day/Night/On-Leave toggle and a GP/Softgel
// toggle, edited locally and saved all at once via Confirm — rather than
// writing to Firestore on every single tap.
class WaterPlantManagerDashboard extends StatefulWidget {
  const WaterPlantManagerDashboard({super.key});

  @override
  State<WaterPlantManagerDashboard> createState() => _WaterPlantManagerDashboardState();
}

class _WaterPlantManagerDashboardState extends State<WaterPlantManagerDashboard> {
  final Map<String, String> _dutyEdits = {};
  final Map<String, String> _plantEdits = {};
  bool _isSaving = false;

  Future<void> _logout(BuildContext context) async {
    await TechnicianSessionService().clear();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _confirm(List<WaterPlantPersonnel> people) async {
    setState(() => _isSaving = true);
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    for (final person in people) {
      final duty = _dutyEdits[person.id] ?? person.dutyStatus;
      final plant = _plantEdits[person.id] ?? person.plant;
      batch.update(firestore.collection('water_plant_personnel').doc(person.id), {
        'dutyStatus': duty,
        'plant': plant,
        'statusSetAt': FieldValue.serverTimestamp(),
      });
    }
    try {
      final outcome = await commitAllowingOffline(batch);
      if (mounted) {
        setState(() {
          _dutyEdits.clear();
          _plantEdits.clear();
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              outcome == CommitOutcome.queuedOffline
                  ? "No signal — status saved and will sync automatically once you're back online."
                  : 'Status updated.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Water Plant'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Log out', onPressed: () => _logout(context)),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('water_plant_personnel').orderBy('name').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Unable to load: ${snapshot.error}'));
          }
          final people = (snapshot.data?.docs ?? [])
              .map((d) => WaterPlantPersonnel.fromMap(d.id, d.data()))
              .toList();

          if (people.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No Water Plant Personnel added yet.\n\nAsk an admin to add some from Settings \u2192 Add Personnel.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Set each person\'s status for today, then tap Confirm.',
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: people.length,
                    itemBuilder: (context, index) => _PersonRow(
                      person: people[index],
                      dutyOverride: _dutyEdits[people[index].id],
                      plantOverride: _plantEdits[people[index].id],
                      onDutyChanged: (value) => setState(() => _dutyEdits[people[index].id] = value),
                      onPlantChanged: (value) => setState(() => _plantEdits[people[index].id] = value),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _isSaving ? null : () => _confirm(people),
                    child: _isSaving
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Confirm'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  final WaterPlantPersonnel person;
  final String? dutyOverride;
  final String? plantOverride;
  final ValueChanged<String> onDutyChanged;
  final ValueChanged<String> onPlantChanged;

  const _PersonRow({
    required this.person,
    required this.dutyOverride,
    required this.plantOverride,
    required this.onDutyChanged,
    required this.onPlantChanged,
  });

  @override
  Widget build(BuildContext context) {
    final duty = dutyOverride ?? person.dutyStatus;
    final plant = plantOverride ?? person.plant;
    final currentlyAt = effectivePlant(plant);
    final swapped = currentlyAt != plant;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(person.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'day', label: Text('Day')),
                ButtonSegment(value: 'night', label: Text('Night')),
                ButtonSegment(value: 'on_leave', label: Text('On-Leave')),
              ],
              selected: {duty},
              onSelectionChanged: (selection) => onDutyChanged(selection.first),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'gp', label: Text('GP')),
                ButtonSegment(value: 'softgel', label: Text('Softgel')),
              ],
              selected: {plant},
              onSelectionChanged: (selection) => onPlantChanged(selection.first),
            ),
            if (swapped) ...[
              const SizedBox(height: 6),
              Text(
                'Morning: ${plantLabel(plant)} \u2192 currently at ${plantLabel(currentlyAt)} (after 1PM swap)',
                style: const TextStyle(fontSize: 12, color: AppColors.muted, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
