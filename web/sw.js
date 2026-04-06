// MarkaAI Web Push Service Worker
// Handles push notifications for PWA

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(clients.claim());
});

self.addEventListener('push', (event) => {
  let data = { title: 'MarkaAI', body: 'Você tem uma nova notificação.' };

  if (event.data) {
    try {
      data = event.data.json();
    } catch (_) {
      data = { title: 'MarkaAI', body: event.data.text() };
    }
  }

  const title = data.title || 'MarkaAI';
  const icon = data.icon || data.data?.icon || '/icons/Icon-192.png';
  const options = {
    body: data.body || '',
    icon,
    badge: '/icons/Icon-192.png',
    data: data.data || {},
    vibrate: [200, 100, 200],
    actions: [
      { action: 'open', title: 'Ver agendamento' },
      { action: 'close', title: 'Fechar' },
    ],
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  if (event.action === 'close') return;

  const url = event.notification.data?.url || '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
      for (const client of windowClients) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          client.focus();
          client.navigate(url);
          return;
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(url);
      }
    })
  );
});
