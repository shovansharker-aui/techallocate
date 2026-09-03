import 'dart:html' as html;

/// Shows a real OS-level notification via the browser's Notification API
/// — this is what actually lets a PWA/mobile-web session surface a
/// system notification, not just an in-app dialog. Requests permission
/// the first time; does nothing if the person denies it or the browser
/// doesn't support notifications (Notification.supported handles that
/// check for us).
Future<void> showStatusReminderNotification() async {
  if (!html.Notification.supported) return;

  var permission = html.Notification.permission;
  if (permission != 'granted') {
    permission = await html.Notification.requestPermission();
  }
  if (permission != 'granted') return;

  html.Notification(
    'Set your status for today',
    body: "You haven't set your availability yet today. Open TechAllocate to set it.",
  );
}
