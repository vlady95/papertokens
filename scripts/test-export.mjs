// Pruebas del formato de exportación y del mapeo de iconos.
//   node scripts/test-export.mjs

import { buildFile, encodeValue, decodeValue, deckId, fileName } from '../src/lib/export.js';
import { iconKey, isPackaged } from '../src/lib/icons.js';

let fails = 0, checks = 0;
const check = (cond, label) => {
  checks++;
  if (!cond) { fails++; console.log('  FALLA: ' + label); }
};

// ---- escapado de valores multilínea ----
const casos = [
  'Sin saltos.',
  'Flying\nVigilance',
  'Barra literal \\ suelta',
  'Caso feo: \\n no es un salto',
  'Acentos: Ánima, Peón, Ilusión',
  'Mezcla \\\\ y\nsalto',
];
for (const c of casos) {
  const round = decodeValue(encodeValue(c));
  check(round === c, `viaje redondo: ${JSON.stringify(c)} → ${JSON.stringify(round)}`);
  check(!encodeValue(c).includes('\n'), `codificado sin saltos reales: ${JSON.stringify(c)}`);
}

// ---- id estable ----
const listaA = ['Lightning Bolt', 'Young Pyromancer', 'Mountain'];
const listaB = ['mountain', 'LIGHTNING BOLT', 'Young Pyromancer']; // mismo mazo
const listaC = ['Lightning Bolt', 'Young Pyromancer', 'Island'];
check(deckId(listaA) === deckId(listaB), 'el id no depende del orden ni de mayúsculas');
check(deckId(listaA) !== deckId(listaC), 'listas distintas dan ids distintos');
check(/^[0-9a-f]{16}$/.test(deckId(listaA)), 'el id es hex de 16 caracteres');

// ---- mapeo de iconos ----
const t = (name, typeLine, extra = {}) => ({
  name, typeLine, oracleId: 'x', colors: [], oracleText: '',
  isCreature: /Creature/i.test(typeLine), ...extra,
});
check(iconKey(t('Goblin', 'Token Creature — Goblin')) === 'goblin', 'criatura por subtipo');
check(iconKey(t('Cat', 'Token Creature — Cat')) === 'cat', 'subtipo Cat');
check(iconKey(t('Human Soldier', 'Token Creature — Human Soldier')) === 'human-soldier',
  'subtipo compuesto');
check(iconKey(t('Clue', 'Token Artifact — Clue')) === 'clue', 'no-criatura por nombre');
check(iconKey(t('Blood', 'Token Artifact — Blood')) === 'blood', 'no-criatura Blood');
check(iconKey(t('Zombie', 'Token Creature — Zombie')) === '',
  'sin coincidencia ⇒ clave vacía, no se inventa');
check(iconKey(t('Wurm', 'Token Creature — Phyrexian Wurm')) === '',
  'subtipo desconocido ⇒ vacío, no aproxima');
check(isPackaged('cat') && !isPackaged('goblin') && !isPackaged(''),
  'se distingue lo que el plugin ya trae empaquetado');

// ---- archivo completo ----
const tokens = [
  t('Eldrazi Spawn', 'Token Creature — Eldrazi Spawn',
    { power: '0', toughness: '1', oracleText: 'Sacrifice this token: Add {C}.' }),
  t('Zombie', 'Token Creature — Zombie', { power: '2', toughness: '2' }),
  t('Clue', 'Token Artifact — Clue',
    { oracleText: '{2}, Sacrifice this token: Draw a card.' }),
];
const file = buildFile({ deckName: 'Jund Wildfire', cards: listaA, tokens });
const lines = file.split('\n');

check(lines[0] === 'PAPERTOKENS 1', 'primera línea: marcador de versión');
check(!file.includes('\r'), 'sin CR: saltos LF');
check(lines.filter((l) => l === 'token').length === 3, 'un bloque por token');
check(file.includes('deck-id '), 'lleva id de mazo');
check(file.includes('deck-name Jund Wildfire'), 'lleva nombre de mazo');
check(file.includes('icon eldrazi-spawn'), 'clave de icono resuelta');
check(file.includes('icon \n') || file.includes('icon \n'), 'clave vacía se escribe igual');
check(file.includes('pt 0/1') && file.includes('pt 2/2'), 'fuerza/resistencia');
check(!file.includes('pt \n'), 'los no-criatura no llevan pt');
check(fileName('Jund Wildfire') === 'jund-wildfire.txt', 'nombre de archivo');
check(fileName('Mazo de Iñaki  ') === 'mazo-de-inaki.txt', 'nombre con acentos');
check(fileName('') === 'mazo.txt', 'nombre vacío tiene respaldo');

// El plugin debe poder parsearlo: simulación del lado Lua.
const parsed = [];
let cur = null;
for (const line of lines) {
  if (line.startsWith('#') || line === '') { if (cur) { parsed.push(cur); cur = null; } continue; }
  if (line === 'token') { cur = {}; continue; }
  const i = line.indexOf(' ');
  const key = i === -1 ? line : line.slice(0, i);
  const val = i === -1 ? '' : line.slice(i + 1);
  if (cur) cur[key] = decodeValue(val);
}
if (cur) parsed.push(cur);
check(parsed.length === 3, `el parser recupera 3 tokens (recuperó ${parsed.length})`);
check(parsed[0].name === 'Eldrazi Spawn' && parsed[0].pt === '0/1', 'campos del primer token');
check(parsed[2].rules === '{2}, Sacrifice this token: Draw a card.', 'reglas recuperadas');

console.log('\n--- archivo de ejemplo ---');
console.log(file.split('\n').filter((l) => !l.startsWith('#')).join('\n').trim());
console.log(`\n${checks} checks, ${fails} fallas`);
process.exit(fails === 0 ? 0 : 1);
