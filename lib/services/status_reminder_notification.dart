// Picks the real browser-notification implementation when compiled for
// web, and a harmless no-op everywhere else (native Android/iOS) — this
// is the standard way to keep a dart:html-only API out of a shared file
// without breaking the non-web build.
export 'status_reminder_notification_stub.dart'
    if (dart.library.html) 'status_reminder_notification_web.dart';
