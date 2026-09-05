/// One continuous stretch of time someone was engaged on a task.
typedef EngagedInterval = ({DateTime start, DateTime end});

/// Total wall-clock time actually covered by [intervals], merging any
/// that overlap.
///
/// A JO can run several tasks at once (see technician_screen.dart), and
/// each task's own duration is shown exactly as recorded everywhere a
/// single task is displayed — that's correct and untouched. But summing
/// those same per-task durations to get "how long did this person work"
/// double-counts the overlap: someone who ran two one-hour tasks
/// simultaneously worked one hour, not two. This merges overlapping
/// intervals first so any "total engaged time for this person" figure
/// reflects real elapsed time instead of task-seconds added together.
Duration unionDuration(Iterable<EngagedInterval> intervals) {
  final sorted = intervals.where((i) => i.end.isAfter(i.start)).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  if (sorted.isEmpty) return Duration.zero;

  var total = Duration.zero;
  var curStart = sorted.first.start;
  var curEnd = sorted.first.end;
  for (final iv in sorted.skip(1)) {
    if (!iv.start.isAfter(curEnd)) {
      if (iv.end.isAfter(curEnd)) curEnd = iv.end;
    } else {
      total += curEnd.difference(curStart);
      curStart = iv.start;
      curEnd = iv.end;
    }
  }
  total += curEnd.difference(curStart);
  return total;
}
