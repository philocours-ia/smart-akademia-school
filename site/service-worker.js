const CACHE_NAME = 'smart-akademia-school-shell-v18-role-stability-mvola';
const APP_SHELL = [
  './', './index.html', './administration.html',
  './role-portal.js?v=18-role-stability-mvola',
  './manifest.webmanifest', './icons/icon-192.png', './icons/icon-512.png',
  './icons/apple-touch-icon.png', './icons/favicon-32.png',
  './assets/smart-akademia-emblem.webp', './assets/smart-akademia-logo-complet.webp'
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(APP_SHELL))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys
          .filter(key => key.startsWith('smart-akademia-school-shell-') && key !== CACHE_NAME)
          .map(key => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);

  // Ne jamais mettre en cache les réponses privées Supabase ou les requêtes d'écriture.
  if (url.hostname.endsWith('.supabase.co') || request.method !== 'GET') return;

  if (request.mode === 'navigate') {
    const isMainShell = url.origin === self.location.origin
      && (url.pathname.endsWith('/') || url.pathname.endsWith('/index.html'));

    event.respondWith(
      fetch(request).then(response => {
        // Seule la véritable page d'accueil peut remplacer le cache index.html.
        // Une navigation vers administration.html ou une autre URL ne l'écrase plus.
        if (response.ok && isMainShell) {
          const copy = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put('./index.html', copy));
        }
        return response;
      }).catch(() => caches.match(request).then(cached => cached || caches.match('./index.html')))
    );
    return;
  }

  if (url.origin === self.location.origin) {
    event.respondWith(
      caches.match(request).then(cached => cached || fetch(request).then(response => {
        if (response.ok) {
          const copy = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(request, copy));
        }
        return response;
      }))
    );
  }
});
