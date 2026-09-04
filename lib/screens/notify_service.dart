import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/water_plant.dart';

/// Shows an admin-composed broadcast message to a person once — the
/// first time they open the app after it was sent, on any platform.
///
/// "Once" is tracked locally per device (SharedPreferences), the same
/// mechanism ThemeService/ChartModeService use — a person seeing it
/// again on a different device isn't really a bug, since it genuinely
/// is a device they haven't seen the message on yet.
class NotifyService {
  static const _lastSeenKey = 'last_seen_notify_id';

  Future<void> checkAndShow(BuildContext context, {required String role}) async {
    try {
      final snap = await waterPlantSettingsRef.get();
      final data = snap.data();
      final messageId = data?['notifyMessageId'] as String?;
      final message = (data?['notifyMessage'] as String?)?.trim();
      if (messageId == null || message == null || message.isEmpty) return;

      // No audience recorded (an older message sent before targeting
      // existed) defaults to everyone, matching the original behavior.
      final audience = (data?['notifyAudience'] as List?)?.cast<String>();
      if (audience != null && !audience.contains(role)) return;

      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_lastSeenKey) == messageId) return; // already shown on this device

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
      await prefs.setString(_lastSeenKey, messageId);
    } catch (_) {
      // Best-effort — a failed check just means no popup this time,
      // never something that should block the person from using the app.
    }
  }
}

final notifyService = NotifyService();
