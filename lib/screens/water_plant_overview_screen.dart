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

  // Admin's live overview drops day-duty personnel off the list once
  // their shift is over (4:30 PM) — admin is checking who's physically
  // there right now. The water_plant_manager's own dashboard needs to
  // keep seeing everyone regardless of time, since they're the one
  // managing tomorrow's allocation from this same screen, so this stays
  // false there.
  final bool hideOffDutyDayStaff;

  const WaterPlantOverviewBody({super.key, this.showSwitchingToggle = true, this.hideOffDutyDayStaff = false});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: waterPlantSettingsRef.snapshots(),
      builder: (context, settingsSnapshot) {
        if (settingsSnapshot.hasError) {
          // Surfacing this rather than silently defaulting: if reads to
          // this doc are blocked too (not just writes), the toggle would
          // otherwise just look stuck on "On" forever with no clue why.
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              color: AppColors.danger.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text('Could not load Switching setting: ${settingsSnapshot.error}'),
              ),
            ),
          );
        }
        final switchingEnabled = switchingEnabledFrom(settingsSnapshot.data?.data());
        final exchangeHour = exchangeHourFrom(settingsSnapshot.data?.data());
        final exchangeMinute = exchangeMinuteFrom(settingsSnapshot.data?.data());
        final exchangeLabel = TimeOfDay(hour: exchangeHour, minute: exchangeMinute).format(context);

        Future<void> pickExchangeTime() async {
          final picked = await showTimePicker(
            context: context,
            initialTime: TimeOfDay(hour: exchangeHour, minute: exchangeMinute),
          );
          if (picked == null) return;
          try {
            await waterPlantSettingsRef.set({'exchangeHour': picked.hour, 'exchangeMinute': picked.minute}, SetOptions(merge: true));
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not save: $e'), duration: const Duration(seconds: 6)),
              );
            }
          }
        }

        return Column(
          children: [
            if (showSwitchingToggle)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Switching', style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          switchingEnabled
                              ? 'On — personnel automatically swap plants at $exchangeLabel.'
                              : 'Off — personnel stay on their morning-assigned plant all day.',
                        ),
                        value: switchingEnabled,
                        onChanged: (value) async {
                          try {
                            // Awaited (not fire-and-forget) specifically so a
                            // rejected write is visible instead of silently
                            // reverting next time this doc is re-read — that
                            // silent-revert is exactly what "the toggle
                            // doesn't work" looks like from the outside.
                            await waterPlantSettingsRef.set({'switchingEnabled': value}, SetOptions(merge: true));
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Could not save: $e'), duration: const Duration(seconds: 6)),
                              );
                            }
                          }
                        },
                      ),
                      if (switchingEnabled)
                        ListTile(
                          leading: const Icon(Icons.schedule_outlined),
                          title: const Text('Exchange time'),
                          subtitle: Text(exchangeLabel),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: pickExchangeTime,
                        ),
                    ],
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

                  final now = DateTime.now();
                  final dayShiftEnded = now.isAfter(DateTime(now.year, now.month, now.day, 16, 30));
                  // On-leave personnel aren't physically at either plant
                  // today, so they're excluded from both tiles entirely
                  // rather than shown with an "On-Leave" badge. Admin's
                  // view additionally drops day-duty personnel once
                  // 4:30 PM has passed (see hideOffDutyDayStaff above).
                  final people = (snapshot.data?.docs ?? [])
                      .where((d) => d.id != waterPlantSettingsDocId)
                      .map((d) => WaterPlantPersonnel.fromMap(d.id, d.data()))
                      .where((p) => p.dutyStatus != 'on_leave')
                      .where((p) => !(hideOffDutyDayStaff && dayShiftEnded && p.dutyStatus == 'day'))
                      .toList();

                  final gp = people.where((p) => effectivePlant(p.plant, switchingEnabled: switchingEnabled, exchangeHour: exchangeHour, exchangeMinute: exchangeMinute) == 'gp').toList();
                  final softgel = people.where((p) => effectivePlant(p.plant, switchingEnabled: switchingEnabled, exchangeHour: exchangeHour, exchangeMinute: exchangeMinute) == 'softgel').toList();

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
                      _dutyBadge(p.dutyStatus),
                    ]),
                  )),
          ],
        ),
      ),
    );
  }

  // Night gets a bluish tint with a night icon, Day keeps its original
  // green with a sun icon added, On-Leave (never actually reached here
  // — this tile's list already excludes on-leave personnel — kept as a
  // sane fallback rather than assuming dutyStatus is always one of the
  // other two) stays red with no icon, same as before.
  Widget _dutyBadge(String dutyStatus) {
    final IconData? icon;
    final Color color;
    switch (dutyStatus) {
      case 'night':
        icon = Icons.nightlight_round;
        color = AppColors.primary;
        break;
      case 'on_leave':
        icon = null;
        color = AppColors.danger;
        break;
      default:
        icon = Icons.wb_sunny_outlined;
        color = AppColors.success;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
        Text(dutyStatusLabel(dutyStatus), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }
}
