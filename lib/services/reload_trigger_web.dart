import 'dart:html' as html;

bool _reloadPending = false;

/// Reloads this browser tab/PWA to pick up whatever build is currently
/// deployed — but not necessarily right this instant.
///
/// If the tab is already hidden (backgrounded, switched away from, or
/// the PWA is minimized) there's nobody to interrupt, so it reloads
/// immediately. If the tab is the one currently being looked at, an
/// instant unannounced reload could wipe out something someone's in the
/// middle of typing — so instead this waits for the tab to actually go
/// hidden (they switch away, even briefly) and reloads at that point
/// instead. Either way the update lands before they next look at this
/// tab, without ever cutting off active work.
void triggerReload() {
  if (_reloadPending) return; // already waiting to reload — don't stack listeners
  if (html.document.visibilityState == 'hidden') {
    html.window.location.reload();
    return;
  }
  _reloadPending = true;
  html.document.addEventListener('visibilitychange', (event) {
    if (html.document.visibilityState == 'hidden') {
      html.window.location.reload();
    }
  });
}
