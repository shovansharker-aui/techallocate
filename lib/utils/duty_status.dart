import '../models/app_user.dart';

/// 'YYYY-MM-DD' for the given moment (defaults to now) — used to check
/// whether someone has set their status "today".
String todayKey([DateTime? now]) {
  final n = now ?? DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

/// Whether [user] should show as available right now.
///
/// From 8:00 AM on, someone only counts as available if they've actually
/// opened the app and set today's status (dutyStatusDate == today) — a
/// stale 'available' left over from a day they never logged in doesn't
/// count. Nobody's status is auto-updated in Firestore to make this
/// true; it's computed fresh wherever availability is displayed, which
/// is simpler and just as correct as writing it, since there's no
/// server-side job on this project's Firebase plan that could flip
/// everyone's status at 8:00 AM even if we wanted to store it.
bool isEffectivelyAvailable(AppUser user, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final setToday = user.dutyStatusDate == todayKey(n);
  if (n.hour >= 8 && !setToday) return false;
  return user.status != 'assigned' && user.dutyStatus != 'on_leave';
}
