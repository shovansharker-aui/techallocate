import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'offline_commit.dart';

/// Marks a work order completed at a chosen time, and frees every
/// technician and helper who was on it back to available. Shared by:
///  - the technician's own "Complete Task" button
///  - admin closing any running task from the dashboard
///  - a Junior Officer closing a CF-only task they assigned (the CF has
///    no login of their own, so someone else has to be able to close it)
///
/// Returns whether the write reached the server or was only queued
/// locally (no signal) — callers can use this to tell the user their
/// action was saved and will sync automatically, rather than assuming
/// silence means success.
Future<CommitOutcome> completeWorkOrder({
  required String orderId,
  required List<String> technicianIds,
  required List<String> helperIds,
  required DateTime completedAt,
}) async {
  final firestore = FirebaseFirestore.instance;
  final batch = firestore.batch();

  batch.update(firestore.collection('work_orders').doc(orderId), {
    'status': 'completed',
    'completedAt': Timestamp.fromDate(completedAt),
  });
  for (final id in technicianIds) {
    batch.update(firestore.collection('users').doc(id), {
      'status': 'available',
      'currentTaskId': null,
    });
  }
  for (final id in helperIds) {
    batch.update(firestore.collection('helpers').doc(id), {
      'status': 'available',
      'currentTaskId': null,
    });
  }

  // Same offline-tolerant pattern as starting a task: the completion is
  // applied to the local cache immediately regardless of connectivity,
  // so we don't block the caller's UI waiting for a server ack that may
  // not arrive until the JO or admin is back in signal.
  return commitAllowingOffline(batch);
}

/// Shows a short "saved, will sync" message if [outcome] was queued
/// offline. Safe to call unconditionally after any completeWorkOrder /
/// commitAllowingOffline call — it does nothing when already synced.
void showOfflineSyncNoticeIfNeeded(BuildContext context, CommitOutcome outcome) {
  if (outcome != CommitOutcome.queuedOffline) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text("No signal — saved on this phone and will sync automatically once you're back online.")),
  );
}

/// Shows a small "Now" vs "Specific time" choice, then returns the chosen
/// completion DateTime — or null if the user cancelled.
Future<DateTime?> pickCompletionTime(BuildContext context, {DateTime? startedAt}) async {
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
  if (choice == 'now') return DateTime.now();

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

  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}
