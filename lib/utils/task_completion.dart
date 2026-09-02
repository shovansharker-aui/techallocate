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
/// Fires the write and returns immediately — see offline_commit.dart for
/// why callers never wait on this before updating their own UI.
void completeWorkOrder({
  required String orderId,
  required List<String> technicianIds,
  required List<String> helperIds,
  required DateTime completedAt,
}) {
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

  commitAllowingOffline(batch);
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
