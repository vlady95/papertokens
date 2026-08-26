// Generado por scripts/build-sw.mjs — no editar a mano.
const CACHE = 'papertokens-bf3c023cd8e3';
const PRECACHE = [
  "./",
  "./assets/index-BsV9wdTB.css",
  "./assets/index-FE1xLe51.js",
  "./favicon.svg",
  "./icons.svg",
  "./icons/apple-touch-icon.png",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./icons/icon.svg",
  "./index.html",
  "./manifest.webmanifest",
  "./tokens-preview.html",
  "./tokens/bird.svg",
  "./tokens/clue.svg",
  "./tokens/eldrazi-spawn.svg",
  "./tokens/elemental.svg",
  "./tokens/food.svg",
  "./tokens/goblin.svg",
  "./tokens/human-soldier.svg",
  "./tokens/map.svg",
  "./tokens/plant.svg",
  "./tokens/spirit.svg",
  "./tokens/squirrel.svg",
  "./tokens/treasure.svg"
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE).then((c) => c.addAll(PRECACHE)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// Cache-first con actualización en segundo plano, solo GET del mismo origen.
// Todo lo demás (p. ej. Scryfall) va directo a la red.
self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== location.origin) return;

  e.respondWith(
    caches.match(req, { ignoreSearch: req.mode === 'navigate' }).then((cached) => {
      const update = fetch(req)
        .then((res) => {
          if (res.ok) {
            const copy = res.clone();
            caches.open(CACHE).then((c) => c.put(req, copy));
          }
          return res;
        })
        .catch(() => cached);
      if (cached) return cached;
      if (req.mode === 'navigate') {
        return update.catch(() => caches.match('./index.html')) || caches.match('./index.html');
      }
      return update;
    })
  );
});
