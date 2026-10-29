/* Keşif service worker: yalnızca sitenin kendi dosyalarına dokunur.
   Strateji: önce ağ, ağ yoksa son kopya. Böylece güncelleme hiç gecikmez; çevrimdışıyken
   sayfa ve yedek veri (mekanlar.json) açılır. Veritabanı, harita karoları ve yazı tipi
   gibi başka sunuculara giden istekler hiç ele alınmaz. */
const ONBELLEK = 'kesif-v1';
const ILK = ['./', 'index.html', 'kategoriler.json', 'sinirlar.json', 'manifest.webmanifest', 'ikon/ikon-192.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(ONBELLEK).then(c => c.addAll(ILK)).catch(() => {}).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys()
    .then(adlar => Promise.all(adlar.filter(a => a.startsWith('kesif-') && a !== ONBELLEK).map(a => caches.delete(a))))
    .then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const r = e.request;
  if (r.method !== 'GET') return;
  const u = new URL(r.url);
  if (u.origin !== location.origin || !u.pathname.startsWith(new URL('./', self.registration.scope).pathname)) return;
  if (u.pathname.endsWith('/yonetim.html')) return;   // yönetim sayfası önbelleğe alınmaz
  e.respondWith((async () => {
    try {
      const yanit = await fetch(r);
      if (yanit.ok && yanit.type === 'basic') {
        const kopya = yanit.clone();
        caches.open(ONBELLEK).then(c => c.put(r.mode === 'navigate' ? './' : r, kopya)).catch(() => {});
      }
      return yanit;
    } catch (hata) {
      const c = await caches.match(r.mode === 'navigate' ? './' : r, { ignoreSearch: r.mode === 'navigate' });
      if (c) return c;
      throw hata;
    }
  })());
});
