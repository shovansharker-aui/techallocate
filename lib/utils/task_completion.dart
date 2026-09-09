import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'offline_commit.dart';

/// Marks a work order completed at a chosen time, and frees every
/// technician and helper who was on it back to available. Used by admin
/// closing any running task directly from the dashboard (Live Activity
/// Grid) — a JO's own "Complete Task" button has its own copy of this
/// logic in technician_screen.dart, since it also needs to know whether
/// this was their last running task before deciding to free themself.
///
/// [stillBusyTechnicianIds] is who among [technicianIds] is ALSO on a
/// different still-running task right now — e.g. a JO who's a second/
/// third contributor on another task, or (rarer) primary on one of their
/// own elsewhere. Callers must pass this in (Live Activity Grid already
/// has every running order loaded, so it costs nothing extra there) —
/// without it, completing just one of a busy JO's tasks would wrongly
/// flip them straight to "available" and drop them off the "Available
/// Now" roster's busy state while they're still actively on the other
/// task. Same "stillBusy" reasoning as technician_screen.dart's own
/// completion/leave flows.
///
/// Fires the write and returns immediately — see offline_commit.dart for
/// why callers never wait on this before updating their own UI.
void completeWorkOrder({
  required String orderId,
  required List<String> technicianIds,
  required List<String> helperIds,
  required DateTime completedAt,
  bool lateEntry = false,
  Set<String> stillBusyTechnicianIds = const {},
}) {
  final firestore = FirebaseFirestore.instance;
  final batch = firestore.batch();

  final update = <String, dynamic>{
    'status': 'completed',
    'completedAt': Timestamp.fromDate(completedAt),
  };
  // Only overwrite lateEntry when this completion actually was backdated
  // — leaves an already-true flag (e.g. from a LateEntryScreen record)
  // alone rather than accidentally clearing it.
  if (lateEntry) update['lateEntry'] = true;
  batch.update(firestore.collection('work_orders').doc(orderId), update);
  for (final id in technicianIds) {
    final stillBusy = stillBusyTechnicianIds.contains(id);
    batch.update(firestore.collection('users').doc(id), {
      'status': stillBusy ? 'assigned' : 'available',
      if (!stillBusy) 'currentTaskId': null,
    });
  }
  for (final id in helperIds) {
    batch.update(firestore.collection('helpers').doc(id), {
      'status': 'available',
      'currentTaskId': null,
    });
  }

  commitAllowingOffline(batch);
}

/// Shows a small "Now" vs "Specific time" choice, then returns the chosen
/// completion time along with whether it was backdated — or null if the
/// user cancelled. [isBacktime] is what callers use to decide whether to
/// flag a completion as a late entry.
Future<({DateTime time, bool isBacktime})?> pickCompletionTime(BuildContext context, {DateTime? startedAt}) async {
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Completion time'),
      content: const Text('When was this task actually finished?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, 'specific'), child: const Text('Specific time')),
        FilledButton(onPressed: () => Navigator.pop(context, 'now'), child: const Text('Now')),
      ],
    ),
  );

  if (choice == null) return null;
  if (choice == 'now') return (time: DateTime.now(), isBacktime: false);

  if (!context.mounted) return null;
  final now = DateTime.now();
  final earliest = startedAt ?? now.subtract(const Duration(days: 30));
  final date = await showDatePicker(
    context: context,
    initialDate: now,
    firstDate: earliest,
    lastDate: now,
  );
  if (date == null || !context.mounted) return null;

  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(now),
  );
  if (time == null) return null;

  return (time: DateTime(date.year, date.month, date.day, time.hour, time.minute), isBacktime: true);
}
