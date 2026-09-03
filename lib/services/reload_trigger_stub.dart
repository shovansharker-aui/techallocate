/// No-op on native platforms — reloading a running native app the way a
/// browser tab reloads isn't a meaningful operation, and isn't what was
/// asked for anyway (this whole mechanism is scoped to web/PWA sessions).
void triggerReload() {}
