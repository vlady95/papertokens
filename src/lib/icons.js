// Mapeo de token a clave de icono.
//
// El plugin de KOReader trae empaquetado un set finito de imágenes. Aquí se
// decide qué imagen le toca a cada token; el archivo exportado lleva esa
// clave y el plugin solo busca un archivo con ese nombre. Si no lo
// encuentra, pinta un "?" grande.
//
// Criterio:
//   - Criaturas: por SUBTIPO, que es como Scryfall las nombra. "Token
//     Creature — Goblin" ⇒ subtipo "Goblin" ⇒ clave "goblin".
//   - No criaturas (Blood, Clue, Treasure, Map, Food): por NOMBRE.
//
// Si no hay coincidencia se devuelve la clave VACÍA. No se inventa una
// clave ni se adivina por aproximación: el "?" del dispositivo es la señal
// de qué iconos faltan por dibujar, y ese dato tiene que llegar limpio.
//
// Este archivo está pensado para editarse seguido: agregar una fila basta.

// Subtipo de criatura (tal cual lo escribe Scryfall) → clave de icono.
export const ICON_BY_SUBTYPE = {
  'Human Soldier': 'human-soldier',
  'Eldrazi Spawn': 'eldrazi-spawn',
  Bird: 'bird',
  Cat: 'cat',
  Elemental: 'elemental',
  Goblin: 'goblin',
  Plant: 'plant',
  Soldier: 'human-soldier',
  Spirit: 'spirit',
  Squirrel: 'squirrel',
};

// Token no-criatura, por nombre exacto → clave de icono.
export const ICON_BY_NAME = {
  Blood: 'blood',
  Clue: 'clue',
  Food: 'food',
  Map: 'map',
  Treasure: 'treasure',
};

// Claves que el build actual del plugin trae empaquetadas. Sirve solo para
// avisar en la pantalla de revisión: una clave fuera de esta lista se
// exporta igual, y en el dispositivo saldrá "?" hasta que se dibuje.
export const PACKAGED_IN_PLUGIN = [
  'blood',
  'cat',
  'clue',
  'eldrazi-spawn',
  'human-soldier',
  'map',
];

// Subtipos de una línea de tipo: lo que va después del guion largo.
// "Token Creature — Human Soldier" ⇒ ["Human Soldier", "Human", "Soldier"]
// Se prueba primero la cadena completa y luego cada subtipo suelto, en
// orden. Todas son coincidencias exactas contra la tabla, no aproximaciones.
export function subtypeCandidates(typeLine) {
  const dash = (typeLine ?? '').split(/\s+[—–-]\s+/);
  if (dash.length < 2) return [];
  const tail = dash[dash.length - 1].trim();
  if (!tail) return [];
  const parts = tail.split(/\s+/);
  return parts.length > 1 ? [tail, ...parts] : [tail];
}

// token → clave de icono, o '' si no hay ninguna.
export function iconKey(token) {
  const typeLine = token.typeLine ?? '';
  if (/\bCreature\b/i.test(typeLine)) {
    for (const cand of subtypeCandidates(typeLine)) {
      if (ICON_BY_SUBTYPE[cand]) return ICON_BY_SUBTYPE[cand];
    }
    return '';
  }
  return ICON_BY_NAME[token.name] ?? '';
}

export function isPackaged(key) {
  return key !== '' && PACKAGED_IN_PLUGIN.includes(key);
}
