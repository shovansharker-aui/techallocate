import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../utils/water_plant.dart';

/// Shows an admin-composed broadcast message to a person once — the
/// first time they open the app after it was sent, on any platform.
///
/// "Once" is tracked on the person's own `users/{uid}` doc
/// (lastNotifySeenId), not local device storage — a fresh browser
/// profile or incognito tab is still the same account and won't show
/// the message again just because it has no local storage of its own.
/// The message also has a hard 24-hour lifetime from when it was sent
/// (notifyMessageId doubles as that send time, see NotifySetting): open
/// the app for the first time more than a day after it was sent and it
/// never shows at all, seen or not.
class NotifyService {
  Future<void> checkAndShow(BuildContext context, {required AppUser user}) async {
    try {
      final snap = await waterPlantSettingsRef.get();
      final data = snap.data();
      final messageId = data?['notifyMessageId'] as String?;
      final message = (data?['notifyMessage'] as String?)?.trim();
      if (messageId == null || message == null || message.isEmpty) return;

      final sentAtMs = int.tryParse(messageId);
      if (sentAtMs != null) {
        final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(sentAtMs));
        if (age > const Duration(hours: 24)) return;
      }

      // No audience recorded (an older message sent before targeting
      // existed) defaults to everyone, matching the original behavior.
      final audience = (data?['notifyAudience'] as List?)?.cast<String>();
      if (audience != null && !audience.contains(user.role.toLowerCase())) return;

      if (user.lastNotifySeenId == messageId) return; // already shown to this person

      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Announcement'),
          content: Text(message),
          actions: [
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('OK')),
          ],
        ),
      );
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'lastNotifySeenId': messageId});
    } catch (_) {
      // Best-effort — a failed check just means no popup this time,
      // never something that should block the person from using the app.
    }
  }
}

final notifyService = NotifyService();
