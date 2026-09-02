import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/water_plant_personnel.dart';
import '../utils/app_colors.dart';
import '../utils/water_plant.dart';
import '../utils/offline_commit.dart';

// The per-person Day/Night/On-Leave + GP/Softgel editing table, reached
// from the "waterplant" account's overview dashboard via the calendar
// icon in the AppBar (or from anywhere else that pushes this screen).
// Since this is always pushed on top of another screen now, it doesn't
// carry its own logout button — the normal back arrow returns to
// whichever dashboard opened it.
class WaterPlantDutyAllocationScreen extends StatefulWidget {
  const WaterPlantDutyAllocationScreen({super.key});

  @override
  State<WaterPlantDutyAllocationScreen> createState() => _WaterPlantDutyAllocationScreenState();
}

class _WaterPlantDutyAllocationScreenState extends State<WaterPlantDutyAllocationScreen> {
  final Map<String, String> _dutyEdits = {};
  final Map<String, String> _plantEdits = {};
  bool _isSaving = false;

  void _confirm(List<WaterPlantPersonnel> people) {
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
    // Fire-and-forget: applies to the local cache immediately regardless
    // of signal, so there's nothing to wait on before letting the
    // manager get on with their day.
    commitAllowingOffline(batch);
    setState(() {
      _dutyEdits.clear();
      _plantEdits.clear();
      _isSaving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Status updated.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: waterPlantSettingsRef.snapshots(),
      builder: (context, settingsSnapshot) {
        final switchingEnabled = switchingEnabledFrom(settingsSnapshot.data?.data());

        return Scaffold(
          appBar: AppBar(title: const Text('Duty Allocation')),
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
                  .where((d) => d.id != waterPlantSettingsDocId)
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
                          switchingEnabled: switchingEnabled,
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
      },
    );
  }
}

class _PersonRow extends StatelessWidget {
  final WaterPlantPersonnel person;
  final String? dutyOverride;
  final String? plantOverride;
  final bool switchingEnabled;
  final ValueChanged<String> onDutyChanged;
  final ValueChanged<String> onPlantChanged;

  const _PersonRow({
    required this.person,
    required this.dutyOverride,
    required this.plantOverride,
    required this.switchingEnabled,
    required this.onDutyChanged,
    required this.onPlantChanged,
  });

  @override
  Widget build(BuildContext context) {
    final duty = dutyOverride ?? person.dutyStatus;
    final plant = plantOverride ?? person.plant;
    final currentlyAt = effectivePlant(plant, switchingEnabled: switchingEnabled);
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
              const SizedBox(height: 8),
              Text(
                'Currently at ${plantLabel(currentlyAt)} (swapped from ${plantLabel(plant)})',
                style: const TextStyle(fontSize: 12, color: AppColors.muted, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
