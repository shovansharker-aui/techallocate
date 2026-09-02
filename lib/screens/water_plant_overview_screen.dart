import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/water_plant_personnel.dart';
import '../utils/app_colors.dart';
import '../utils/water_plant.dart';
import 'water_plant_manager_dashboard.dart';

// Live Water Plant view — two tiles (GP / Softgel) each listing who's
// currently assigned there (after the Switching swap, if enabled) and
// their Day/Night/On-Leave status for today.
//
// Split into a body (no Scaffold/AppBar of its own — WaterPlantOverviewBody
// below) and a thin Scaffold wrapper (WaterPlantOverviewScreen), so the
// same content can either be pushed as its own screen (Android admin nav,
// the "waterplant" account's own root screen) or embedded directly inside
// the persistent web admin shell without stacking two AppBars.
class WaterPlantOverviewScreen extends StatelessWidget {
  final VoidCallback? onLogout;
  final bool showDutyAllocationButton;
  final bool showSwitchingToggle;

  const WaterPlantOverviewScreen({
    super.key,
    this.onLogout,
    this.showDutyAllocationButton = false,
    this.showSwitchingToggle = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Water Plant'),
        actions: [
          if (showDutyAllocationButton)
            IconButton(
              icon: const Icon(Icons.edit_calendar_outlined),
              tooltip: 'Duty Allocation',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WaterPlantDutyAllocationScreen()),
              ),
            ),
          if (onLogout != null)
            IconButton(icon: const Icon(Icons.logout), tooltip: 'Log out', onPressed: onLogout),
        ],
      ),
      body: WaterPlantOverviewBody(showSwitchingToggle: showSwitchingToggle),
    );
  }
}

/// The actual Switching toggle + GP/Softgel tiles, with no Scaffold or
/// AppBar of its own — embed this directly wherever a persistent shell
/// (like the web admin sidebar layout) already provides those.
class WaterPlantOverviewBody extends StatelessWidget {
  // Only admin can change this — the "waterplant" account sees the same
  // tiles but can't flip the switch itself.
  final bool showSwitchingToggle;

  const WaterPlantOverviewBody({super.key, this.showSwitchingToggle = true});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: waterPlantSettingsRef.snapshots(),
      builder: (context, settingsSnapshot) {
        final switchingEnabled = switchingEnabledFrom(settingsSnapshot.data?.data());

        return Column(
          children: [
            if (showSwitchingToggle)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Card(
                  child: SwitchListTile(
                    title: const Text('Switching', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      switchingEnabled
                          ? 'On — personnel automatically swap plants after 7:30 AM.'
                          : 'Off — personnel stay on their morning-assigned plant all day.',
                    ),
                    value: switchingEnabled,
                    onChanged: (value) {
                      // Single-document write, fire-and-forget: the local
                      // cache (and this Switch) updates instantly via the
                      // StreamBuilder above regardless of connectivity.
                      waterPlantSettingsRef.set({'switchingEnabled': value}, SetOptions(merge: true));
                    },
                  ),
                ),
              ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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

                  final gp = people.where((p) => effectivePlant(p.plant, switchingEnabled: switchingEnabled) == 'gp').toList();
                  final softgel = people.where((p) => effectivePlant(p.plant, switchingEnabled: switchingEnabled) == 'softgel').toList();

                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final twoColumn = constraints.maxWidth >= 500;
                        final tiles = [
                          _plantTile('GP Water Plant', Icons.water_drop_outlined, AppColors.categoryProduction, gp),
                          _plantTile('Softgel Water Plant', Icons.water_drop_outlined, AppColors.categoryEngineering, softgel),
                        ];
                        if (!twoColumn) {
                          return ListView(children: [tiles[0], const SizedBox(height: 12), tiles[1]]);
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: tiles[0]),
                            const SizedBox(width: 12),
                            Expanded(child: tiles[1]),
                          ],
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _plantTile(String title, IconData icon, Color color, List<WaterPlantPersonnel> people) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(backgroundColor: color.withValues(alpha: 0.15), child: Icon(icon, color: color)),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            ]),
            const SizedBox(height: 14),
            if (people.isEmpty)
              const Text('No one currently assigned here.', style: TextStyle(color: AppColors.muted))
            else
              ...people.map((p) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      CircleAvatar(radius: 14, child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase())),
                      const SizedBox(width: 10),
                      Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: p.dutyStatus == 'on_leave'
                              ? AppColors.danger.withValues(alpha: 0.12)
                              : AppColors.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          dutyStatusLabel(p.dutyStatus),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: p.dutyStatus == 'on_leave' ? AppColors.danger : AppColors.success,
                          ),
                        ),
                      ),
                    ]),
                  )),
          ],
        ),
      ),
    );
  }
}
