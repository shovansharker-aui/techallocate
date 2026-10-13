import 'dart:html' as html;

/// Real OS-level notifications from the browser/PWA. Goes through the
/// service worker registration (showNotification) first because Android
/// Chrome -- the main PWA target here -- throws "Illegal constructor" for
/// the plain `Notification(...)` constructor; that's only the fallback for
/// desktop browsers without an active service worker.
Future<bool> _ensurePermission() async {
  if (!html.Notification.supported) return false;
  var permission = html.Notification.permission;
  if (permission != 'granted') {
    permission = await html.Notification.requestPermission();
  }
  return permission == 'granted';
}

// Flutter's own service worker unregisters itself, so there is usually NO
// active registration and `serviceWorker.ready` would never resolve. This
// registers a tiny dedicated worker (web/notify/sw.js) on its own scope
// purely so notifications can be shown -- and tapped to focus the app.
Future<html.ServiceWorkerRegistration?> _notificationRegistration() async {
  final container = html.window.navigator.serviceWorker;
  if (container == null) return null;
  try {
    final registration = await container.register('/notify/sw.js', {'scope': '/notify/'});
    for (var i = 0; i < 25 && registration.active == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return registration.active == null ? null : registration;
  } catch (_) {
    return null;
  }
}

Future<void> _show(String title, String body, String tag) async {
  if (!await _ensurePermission()) return;
  final registration = await _notificationRegistration();
  if (registration != null) {
    try {
      await registration.showNotification(title, {'body': body, 'tag': tag, 'renotify': true});
      return;
    } catch (_) {}
  }
  try {
    html.Notification(title, body: body, tag: tag);
  } catch (_) {}
}

Future<void> showStatusReminderNotification() => _show(
      'Set your status for today',
      "You haven't set your availability yet today. Open TechAllocate to set it.",
      'status-reminder',
    );

/// Asks for notification permission up front. Call from a user tap (e.g.
/// Start Task) -- browsers only reliably show the permission prompt in
/// response to a gesture.
Future<void> requestTaskReminderPermission() => _ensurePermission();

Future<void> showRunningTasksReminder(int count, String longestRunning) => _show(
      count == 1 ? 'You have a task still running' : 'You have $count tasks still running',
      'Longest running: $longestRunning. Finished? Open TechAllocate and complete it.',
      'running-tasks',
    );
