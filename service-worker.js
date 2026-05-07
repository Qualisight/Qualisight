const CACHE_NAME = 'qualisight-v3';

// Cache only the single HTML file — it contains everything
const ASSETS = [
  '/',
  '/index.html',
  '/manifest.json',
  '/icon-192.png',
  '/icon-512.png',
];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(ASSETS))
  );
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  // Delete ALL old caches so stale versions are wiped completely
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => {
        console.log('[SW] Deleting old cache:', k);
        return caches.delete(k);
      }))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);

  // Never intercept Supabase, Stripe, Alpha Vantage or any external API
  const external = [
    'supabase.co',
    'stripe.com',
    'alphavantage.co',
    'financialmodelingprep.com',
    'fonts.googleapis.com',
    'fonts.gstatic.com',
    'cdnjs.cloudflare.com',
  ];
  if(external.some(h => url.hostname.includes(h))) return;

  // Network-first for same-origin requests so the app always gets latest code
  e.respondWith(
    fetch(e.request)
      .then(response => {
        if(response.ok) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(e.request, clone));
        }
        return response;
      })
      .catch(() =>
        // Offline fallback — serve cached version
        caches.match(e.request)
          .then(cached => cached || caches.match('/index.html'))
      )
  );
});
