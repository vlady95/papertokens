// Genera docs/sw.js después de `vite build`: precachea TODOS los archivos
// del build y sirve cache-first con actualización en segundo plano. El
// nombre de la caché sale de un hash del contenido del build, así que cambia
// en cada publicación con cambios y las actualizaciones llegan.
//
// Se corre automáticamente desde `npm run build`.

import { readdirSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { createHash } from 'node:crypto';

const OUT = 'docs';

function walk(dir) {
  const files = [];
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) files.push(...walk(full));
    else files.push(full);
  }
  return files;
}

const files = walk(OUT)
  .map((f) => relative(OUT, f))
  .filter((f) => f !== 'sw.js' && !f.startsWith('.'));

const hash = createHash('sha256');
for (const f of files.sort()) {
  hash.update(f);
  hash.update(readFileSync(join(OUT, f)));
}
const version = hash.digest('hex').slice(0, 12);

const precache = ['./', ...files.map((f) => './' + f.split('\\').join('/'))];

const sw = `// Generado por scripts/build-sw.mjs — no editar a mano.
const CACHE = 'papertokens-${version}';
const PRECACHE = ${JSON.stringify(precache, null, 2)};

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
`;

writeFileSync(join(OUT, 'sw.js'), sw);
console.log(`sw.js: caché papertokens-${version}, ${precache.length} archivos precacheados`);
