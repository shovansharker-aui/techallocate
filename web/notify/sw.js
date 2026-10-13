// Minimal service worker used ONLY to show notifications (Android Chrome
// refuses `new Notification()`; it needs a service worker registration).
// Deliberately separate from Flutter's own flutter_service_worker.js, which
// unregisters itself, and kept on its own /notify/ scope so the two never
// replace each other's registration.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil((async () => {
    const all = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of all) {
      if ('focus' in client) return client.focus();
    }
    return self.clients.openWindow('/');
  })());
});
