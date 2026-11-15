const CACHE_NAME = 'smart-akademia-school-shell-v18-teacher-adhesion-terms';
const APP_SHELL = [
  './', './index.html', './administration.html', './role-portal.js?v=17-t9-teacher-admin-fix', './teacher-adhesion-terms.js', './manifest.webmanifest',
  './icons/icon-192.png', './icons/icon-512.png', './icons/apple-touch-icon.png', './icons/favicon-32.png', './assets/smart-akademia-emblem.webp', './assets/smart-akademia-logo-complet.webp'
];

async function addTeacherConsentScript(response) {
  if (!response || !response.ok) return response;
  const contentType = response.headers.get('Content-Type') || '';
  if (!contentType.toLowerCase().includes('text/html')) return response;

  let html = await response.text();
  const scriptTag = '<script src="./teacher-adhesion-terms.js" defer></script>';
  if (!html.includes('teacher-adhesion-terms.js')) {
    html = /<\/body\s*>/i.test(html)
      ? html.replace(/<\/body\s*>/i, `${scriptTag}</body>`)
      : `${html}${scriptTag}`;
  }
  const headers = new Headers(response.headers);
  headers.delete('Content-Length');
  headers.delete('Content-Encoding');
  return new Response(html, { status: response.status, statusText: response.statusText, headers });
}

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(APP_SHELL);
    // Cache the application shell with the consent script reference included.
    const index = await cache.match('./index.html');
    if (index) await cache.put('./index.html', await addTeacherConsentScript(index));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil(caches.keys()
    .then(keys => Promise.all(keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key))))
    .then(() => self.clients.claim()));
});

self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  // Never cache private Supabase/API/auth/storage responses.
  if (url.hostname.endsWith('.supabase.co') || request.method !== 'GET') return;

  if (request.mode === 'navigate') {
    event.respondWith(fetch(request)
      .then(addTeacherConsentScript)
      .then(response => {
        const copy = response.clone();
        caches.open(CACHE_NAME).then(cache => cache.put('./index.html', copy));
        return response;
      })
      .catch(() => caches.match('./index.html')));
    return;
  }

  if (url.origin === self.location.origin) {
    event.respondWith(caches.match(request).then(cached => cached || fetch(request).then(response => {
      if (response.ok) {
        const copy = response.clone();
        caches.open(CACHE_NAME).then(cache => cache.put(request, copy));
      }
      return response;
    })));
  }
});
