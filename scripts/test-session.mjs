// Guion de partida real contra la lógica de sesión.
// Correr con: node scripts/test-session.mjs
//
// Guion: creo tres goblins, ataco con dos, uno muere bloqueando, untap all.
// También: la heurística del menos, el vaciado de un tipo, y el tope de 4.

import {
  createSession,
  createToken,
  tapToken,
  destroyToken,
  untapAll,
  untapType,
  MAX_ACTIVE_TYPES,
} from '../src/lib/session.js';

const GOBLIN = 'goblin-oracle-id';
const SPIRIT = 'spirit-oracle-id';

function show(label, state) {
  const parts = state.active.map(
    (t) => `${t.oracleId.split('-')[0]}: ${t.untapped} destapados, ${t.tapped} tapeados`
  );
  console.log(`${label.padEnd(34)} → ${parts.length ? parts.join(' | ') : '(zona activa vacía)'}`);
}

let s = createSession();
show('inicio', s);

s = createToken(s, GOBLIN);
s = createToken(s, GOBLIN);
s = createToken(s, GOBLIN);
show('creo 3 goblins', s);

s = tapToken(s, GOBLIN);
s = tapToken(s, GOBLIN);
show('ataco con 2 (dos taps)', s);

s = destroyToken(s, GOBLIN);
show('uno muere bloqueando (−)', s);

s = untapAll(s);
show('untap all', s);

console.log('\n--- casos extra ---');

s = destroyToken(s, GOBLIN);
show('− sin tapeados: resta destapado', s);

s = destroyToken(s, GOBLIN);
s = destroyToken(s, GOBLIN);
show('− hasta cero: el tipo sale', s);

s = createToken(s, SPIRIT);
s = createToken(s, SPIRIT);
s = tapToken(s, SPIRIT);
show('2 spirits, tapeo 1', s);

s = untapAll(s);
show('untap all', s);

let two = createSession();
two = createToken(two, GOBLIN);
two = createToken(two, GOBLIN);
two = createToken(two, SPIRIT);
two = tapToken(two, GOBLIN);
two = tapToken(two, SPIRIT);
two = untapType(two, GOBLIN);
show('untap solo del tipo goblin', two);

let full = createSession();
for (const id of ['a-1', 'b-1', 'c-1', 'd-1']) full = createToken(full, id);
const overflow = createToken(full, 'e-1');
console.log(
  `tope de ${MAX_ACTIVE_TYPES} tipos: quinto tipo ${
    overflow === full ? 'ignorado (correcto)' : 'aceptado (ERROR)'
  }`
);

const noop = tapToken(createSession(), GOBLIN);
console.log(
  `tap sobre tipo ausente: ${noop.active.length === 0 ? 'no hace nada (correcto)' : 'ERROR'}`
);
