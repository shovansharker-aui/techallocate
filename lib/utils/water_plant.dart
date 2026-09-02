// Shared logic for the Water Plant module — kept in one place so the
// manager dashboard and the admin's live view always agree on what
// "currently assigned" means.

/// The plant a person is actually AT right now, given the plant their
/// manager set for the morning. Personnel physically swap plants at
/// 1:00 PM each day, so after that time the effective assignment is the
/// opposite of whatever was set — computed fresh on every read, no
/// scheduled job needed.
String effectivePlant(String morningPlant) {
  final now = DateTime.now();
  final swapTime = DateTime(now.year, now.month, now.day, 13);
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
