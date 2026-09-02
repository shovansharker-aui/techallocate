// Shared logic for the Water Plant module — kept in one place so the
// manager dashboard and the admin's live view always agree on what
// "currently assigned" means.

import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore location of the Water Plant module's shared settings —
/// currently just the "Switching" toggle. Deliberately stored as a
/// document INSIDE the water_plant_personnel collection (under a
/// reserved id that's filtered out of the personnel list everywhere it's
/// queried) rather than a new top-level "settings" collection: a brand
/// new collection isn't covered by this project's existing Firestore
/// security rules, so writes to it were silently rejected — which is
/// exactly why the Switching toggle didn't previously save. Reusing an
/// already-writable collection sidesteps that without needing any
/// Firebase Console changes.
const waterPlantSettingsDocId = '_settings';
final waterPlantSettingsRef = FirebaseFirestore.instance.collection('water_plant_personnel').doc(waterPlantSettingsDocId);

/// Reads the Switching toggle out of a settings document's data,
/// defaulting to true — the swap behavior every install had before this
/// toggle existed — if the document hasn't been created yet.
bool switchingEnabledFrom(Map<String, dynamic>? settingsData) =>
    (settingsData?['switchingEnabled'] as bool?) ?? true;

/// The plant a person is actually AT right now, given the plant their
/// manager set for the morning.
///
/// When [switchingEnabled] is true, personnel physically swap plants
/// after 7:30 AM each day, so from that time on the effective assignment
/// is the opposite of whatever was set that morning — computed fresh on
/// every read, no scheduled job needed. When [switchingEnabled] is
/// false, no swap ever happens and everyone simply stays on their
/// morning assignment all day; this is an admin-controlled setting (see
/// the "Switching" toggle on the Water Plant dashboard), not a fixed
/// behavior.
String effectivePlant(String morningPlant, {required bool switchingEnabled}) {
  if (!switchingEnabled) return morningPlant;
  final now = DateTime.now();
  final swapTime = DateTime(now.year, now.month, now.day, 7, 30);
  final swapped = now.isAfter(swapTime);
  if (!swapped) return morningPlant;
  return morningPlant == 'gp' ? 'softgel' : 'gp';
}

String plantLabel(String plant) => plant == 'gp' ? 'GP' : 'Softgel';

String dutyStatusLabel(String status) {
  switch (status) {
    case 'night':
      return 'Night';
    case 'on_leave':
      return 'On-Leave';
    default:
      return 'Day';
  }
}
