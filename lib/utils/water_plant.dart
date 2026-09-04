// Shared logic for the Water Plant module — kept in one place so the
// manager dashboard and the admin's live view always agree on what
// "currently assigned" means.

import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore location of ALL cross-app shared settings this project
/// needs — Switching, the swap exchange time, the app-version reload
/// flag, and the admin "Notify" broadcast message all live in this one
/// document. It's a document INSIDE the water_plant_personnel
/// collection (under a reserved id filtered out of the personnel list
/// everywhere it's queried) rather than a new top-level "settings"
/// collection, because a brand new collection isn't covered by this
/// project's Firestore security rules and writes to it are silently
/// rejected.
///
/// IMPORTANT — this document ALSO needs one specific rule added in the
/// Firebase Console before ANY of the above actually works: writes here
/// are still being rejected with "permission denied" until this rule
/// exists. Add this inside your existing
/// `match /databases/{database}/documents { ... }` block:
///
///   match /water_plant_personnel/_settings {
///     allow read, write: if request.auth != null;
///   }
///
/// Until that's added, the Switching toggle, custom exchange time,
/// auto-reload, and Notify broadcast will all silently fail to save.
const waterPlantSettingsDocId = '_settings';
final waterPlantSettingsRef = FirebaseFirestore.instance.collection('water_plant_personnel').doc(waterPlantSettingsDocId);

/// Reads the Switching toggle out of a settings document's data,
/// defaulting to true — the swap behavior every install had before this
/// toggle existed — if the document hasn't been created yet.
bool switchingEnabledFrom(Map<String, dynamic>? settingsData) =>
    (settingsData?['switchingEnabled'] as bool?) ?? true;

/// The hour (0-23) personnel swap plants — defaults to 7 (7:30 AM),
/// matching the fixed time every install had before this became
/// configurable.
int exchangeHourFrom(Map<String, dynamic>? settingsData) =>
    (settingsData?['exchangeHour'] as int?) ?? 7;

/// The minute (0-59) personnel swap plants — defaults to 30.
int exchangeMinuteFrom(Map<String, dynamic>? settingsData) =>
    (settingsData?['exchangeMinute'] as int?) ?? 30;

/// The plant a person is actually AT right now, given the plant their
/// manager set for the morning.
///
/// When [switchingEnabled] is true, personnel physically swap plants at
/// [exchangeHour]:[exchangeMinute] each day, so from that time on the
/// effective assignment is the opposite of whatever was set that
/// morning — computed fresh on every read, no scheduled job needed.
/// When [switchingEnabled] is false, no swap ever happens and everyone
/// simply stays on their morning assignment all day.
String effectivePlant(
  String morningPlant, {
  required bool switchingEnabled,
  int exchangeHour = 7,
  int exchangeMinute = 30,
}) {
  if (!switchingEnabled) return morningPlant;
  final now = DateTime.now();
  final swapTime = DateTime(now.year, now.month, now.day, exchangeHour, exchangeMinute);
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
