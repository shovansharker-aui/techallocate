/// No-op on native platforms (Android app) — see
/// status_reminder_notification_web.dart for the real implementation.
/// A true OS-level notification on native Android needs a plugin
/// (flutter_local_notifications) plus native Android manifest/permission
/// changes, which isn't wired up yet — see the note where this is
/// called from in technician_screen.dart.
Future<void> showStatusReminderNotification() async {}
