// Service worker: guarda o app no aparelho para abrir sem internet
const VERSION = 'vistto-v1';
const SHELL = ['/app/', '/app/index.html', '/app/styles.css', '/app/manifest.webmanifest', '/app/icons/icon.svg', '/app/icons/icon-192.png',
  '/app/js/main.js', '/app/js/store.js', '/app/js/api.js', '/app/js/components.js', '/app/js/icons.js', '/app/js/screens.js', '/app/js/wizard.js', '/app/js/demo.js',
  '/shared/brand.css', '/shared/vendor/preact-htm.js',
  '/shared/fonts/poppins-latin-300-normal.woff2', '/shared/fonts/poppins-latin-400-normal.woff2', '/shared/fonts/poppins-latin-500-normal.woff2', '/shared/fonts/poppins-latin-600-normal.woff2', '/shared/fonts/poppins-latin-700-normal.woff2'];
self.addEventListener('install', (e) => { e.waitUntil(caches.open(VERSION).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting())); });
self.addEventListener('activate', (e) => { e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== VERSION).map((k) => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', (e) => {
  const u = new URL(e.request.url);
  if (e.request.method !== 'GET' || u.origin !== location.origin || u.pathname.startsWith('/api/')) return;
  if (u.pathname.startsWith('/app/') || u.pathname.startsWith('/shared/')) {
    // rede primeiro (sempre a versão nova), cache como reserva offline
    e.respondWith(fetch(e.request).then((r) => { const cp = r.clone(); caches.open(VERSION).then((c) => c.put(e.request, cp)); return r; }).catch(() => caches.match(e.request, { ignoreSearch: true }).then((r) => r || caches.match('/app/index.html'))));
  }
});
