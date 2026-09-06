import '../models/app_user.dart';

/// 'YYYY-MM-DD' for the given moment (defaults to now) — used to check
/// whether someone has set their status "today".
String todayKey([DateTime? now]) {
  final n = now ?? DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

/// Where someone stands on the "Available Now" roster right now.
///  - [off]: not on duty at all (on-leave, or their shift's window for
///    today has already ended) — doesn't appear on the roster.
///  - [free]: on duty and not currently on a task — shown green.
///  - [busy]: on duty but currently engaged on a running task — shown
///    gray, still on the roster so they don't just vanish mid-task.
enum DutyPresence { off, free, busy }

/// Day duty is on the roster through 4:30 PM, or through 7:30 PM if a
/// task they're on is still running past 4:30 — so someone mid-task
/// doesn't disappear from the roster just because their shift's nominal
/// end time passed. Night duty is on the roster from whenever it's set
/// through 7:00 AM the next calendar day, covering the overnight shift.
/// On-leave is never on the roster. Nobody's status is auto-updated in
/// Firestore to make any of this true; it's computed fresh every time
/// the roster is displayed, same reasoning as the old
/// isEffectivelyAvailable this replaces.
DutyPresence dutyPresence(AppUser user, {DateTime? now}) {
  final n = now ?? DateTime.now();
  if (user.dutyStatus == 'on_leave') return DutyPresence.off;

  final today = todayKey(n);
  final yesterday = todayKey(n.subtract(const Duration(days: 1)));
  bool onRoster;
  if (user.dutyStatusDate == today) {
    if (user.dutyStatus == 'night') {
      // Set today, valid all the way through 7:00 AM tomorrow — so
      // always "on roster" as of today, whatever the current time.
      onRoster = true;
    } else {
      final dayEnd = DateTime(n.year, n.month, n.day, 16, 30);
      final graceEnd = DateTime(n.year, n.month, n.day, 19, 30);
      onRoster = !n.isAfter(dayEnd) || (!n.isAfter(graceEnd) && user.status == 'assigned');
    }
  } else if (user.dutyStatusDate == yesterday && user.dutyStatus == 'night') {
    // Still covering last night's overnight shift, before this
    // morning's 7:00 AM cutoff.
    final cutoff = DateTime(n.year, n.month, n.day, 7, 0);
    onRoster = n.isBefore(cutoff);
  } else {
    // Stale (or never set) — hasn't confirmed a shift covering now.
    onRoster = false;
  }

  if (!onRoster) return DutyPresence.off;
  return user.status == 'assigned' ? DutyPresence.busy : DutyPresence.free;
}
