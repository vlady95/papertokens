// Arte de tokens por convención de archivos, sin manifiesto ni código por
// imagen. Una ilustración se agrega soltando un archivo en public/tokens/
// con uno de estos nombres (en orden de preferencia):
//
//   <oracle_id>.png / .svg      — apunta a un token exacto
//   <slug-del-nombre>.png / .svg — p. ej. goblin.svg, eldrazi-spawn.png
//
// Si no existe ninguno, la interfaz cae al placeholder de letras. Las
// imágenes deben ser arte de línea en blanco y negro (el CSS fuerza
// grayscale como red de seguridad de la paleta).

export function artSlug(name) {
  return name
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
}

// Prefijo de la app: '/' en dev, './' en el build (subruta de GitHub Pages).
// En node (scripts) import.meta.env no existe; ahí solo se usan los slugs.
const BASE = (typeof import.meta !== 'undefined' && import.meta.env?.BASE_URL) || '/';

export function artCandidates(token) {
  const bases = [token.oracleId, artSlug(token.name)];
  const urls = [];
  for (const base of bases) {
    urls.push(`${BASE}tokens/${base}.png`, `${BASE}tokens/${base}.svg`);
  }
  return urls;
}
