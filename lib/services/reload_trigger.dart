// Picks the real browser-reload implementation when compiled for web,
// and a harmless no-op everywhere else (native Android/iOS) — same
// conditional-export pattern as status_reminder_notification.dart, for
// the same reason: dart:html can't be imported into code that's also
// compiled for a non-web target.
export 'reload_trigger_stub.dart' if (dart.library.html) 'reload_trigger_web.dart';
