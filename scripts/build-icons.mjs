// Sincroniza el arte de tokens desde su ÚNICA fuente.
//
//   node scripts/build-icons.mjs
//
// Fuente:  public/tokens/<clave>.svg      (arte de línea, lo que ve la web)
// Deriva:  koreader/.../assets/<clave>-{96,160,224}.png   (para el Kindle)
//          la lista PACKAGED_IN_PLUGIN de src/lib/icons.js
//          la lista de la hoja de contactos public/tokens-preview.html
//
// Por qué existe: antes había tres sets de imágenes que se desincronizaron
// (la web tenía 12, el plugin 6, y solo 4 coincidían). Con un solo origen y
// este script, agregar un icono es soltar un SVG y correr un comando.
//
// Rasteriza con qlmanage + sips (macOS). El dispositivo NUNCA rasteriza SVG.

import { execFileSync } from 'node:child_process';
import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync, copyFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const SRC_DIR = 'public/tokens';
const PLUGIN_ASSETS = 'koreader/papertokens.koplugin/assets';
const SIZES = [224, 160, 96];

const keys = readdirSync(SRC_DIR)
  .filter((f) => f.endsWith('.svg'))
  .map((f) => f.replace(/\.svg$/, ''))
  .sort();

if (keys.length === 0) {
  console.error(`No hay SVG en ${SRC_DIR}`);
  process.exit(1);
}

// ---- rasterizar ----
const tmp = mkdtempSync(join(tmpdir(), 'papertokens-icons-'));
let written = 0;
for (const key of keys) {
  const svg = join(SRC_DIR, `${key}.svg`);
  execFileSync('qlmanage', ['-t', '-s', '512', '-o', tmp, svg], { stdio: 'ignore' });
  const big = join(tmp, `${key}.svg.png`);
  for (const size of SIZES) {
    const out = join(PLUGIN_ASSETS, `${key}-${size}.png`);
    execFileSync('sips', ['-z', String(size), String(size), big, '--out', out], { stdio: 'ignore' });
    written++;
  }
}
rmSync(tmp, { recursive: true, force: true });

// ---- limpiar PNG de claves que ya no existen ----
const valid = new Set(keys.flatMap((k) => SIZES.map((s) => `${k}-${s}.png`)));
let removed = 0;
for (const f of readdirSync(PLUGIN_ASSETS)) {
  if (f.endsWith('.png') && !valid.has(f)) {
    unlinkSync(join(PLUGIN_ASSETS, f));
    removed++;
  }
}

// ---- reescribir la lista que la web usa para avisar qué trae el plugin ----
const iconsPath = 'src/lib/icons.js';
const iconsSrc = readFileSync(iconsPath, 'utf8');
const list = keys.map((k) => `  '${k}',`).join('\n');
const next = iconsSrc.replace(
  /export const PACKAGED_IN_PLUGIN = \[[^\]]*\];/,
  `export const PACKAGED_IN_PLUGIN = [\n${list}\n];`
);
if (next === iconsSrc && !iconsSrc.includes(list)) {
  console.error('No pude actualizar PACKAGED_IN_PLUGIN en ' + iconsPath);
  process.exit(1);
}
writeFileSync(iconsPath, next);

// ---- reescribir la hoja de contactos ----
const sheetPath = 'public/tokens-preview.html';
const sheet = readFileSync(sheetPath, 'utf8');
writeFileSync(
  sheetPath,
  sheet.replace(
    /const names = \[[^\]]*\];/,
    `const names = [${keys.map((k) => `'${k}'`).join(',')}];`
  )
);

console.log(`${keys.length} iconos: ${keys.join(', ')}`);
console.log(`${written} PNG escritos, ${removed} obsoletos borrados`);
console.log('PACKAGED_IN_PLUGIN y la hoja de contactos, al día');
