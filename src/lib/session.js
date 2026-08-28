// Lógica de sesión de juego. Sin React, sin navegador: probable con node.
//
// Una sesión es el estado vivo de una partida. Cada tipo de token en juego
// lleva exactamente dos contadores: untapped y tapped. Nada más — el
// dispositivo es un registro, no un árbitro.
//
// Reglas:
//   - createToken: crea un token del tipo dado; entra untapped. Si el tipo no
//     estaba en juego, entra a la zona activa (máximo MAX_ACTIVE_TYPES tipos
//     simultáneos; si ya está llena, la creación de un tipo nuevo se ignora).
//   - tapToken: mueve un token de untapped a tapped. Atacar con dos goblins
//     son dos taps.
//   - destroyToken: resta primero de tapped; solo si no hay tapeados, resta
//     de untapped. Heurística deliberada: va a fallar a veces y corregirla
//     cuesta poco. Cuando ambos contadores llegan a cero, el tipo sale de la
//     zona activa.
//   - untapAll: mueve todos los tapped a untapped, en todos los tipos a la
//     vez. La operación más frecuente del producto.
//
// El estado es inmutable: cada operación devuelve un estado nuevo. El orden
// del array `active` es el orden de entrada en juego; solo cambia cuando
// entra o sale un tipo, nunca cuando cambia una cantidad.

export const MAX_ACTIVE_TYPES = 4;

export function createSession() {
  return { active: [] };
}

function findIndex(state, oracleId) {
  return state.active.findIndex((t) => t.oracleId === oracleId);
}

export function createToken(state, oracleId) {
  const i = findIndex(state, oracleId);
  if (i === -1) {
    if (state.active.length >= MAX_ACTIVE_TYPES) return state;
    return { active: [...state.active, { oracleId, untapped: 1, tapped: 0 }] };
  }
  const active = state.active.map((t, j) =>
    j === i ? { ...t, untapped: t.untapped + 1 } : t
  );
  return { active };
}

export function tapToken(state, oracleId) {
  const i = findIndex(state, oracleId);
  if (i === -1 || state.active[i].untapped === 0) return state;
  const active = state.active.map((t, j) =>
    j === i ? { ...t, untapped: t.untapped - 1, tapped: t.tapped + 1 } : t
  );
  return { active };
}

export function destroyToken(state, oracleId) {
  const i = findIndex(state, oracleId);
  if (i === -1) return state;
  const t = state.active[i];

  let next;
  if (t.tapped > 0) next = { ...t, tapped: t.tapped - 1 };
  else if (t.untapped > 0) next = { ...t, untapped: t.untapped - 1 };
  else next = t;

  if (next.untapped === 0 && next.tapped === 0) {
    return { active: state.active.filter((_, j) => j !== i) };
  }
  return { active: state.active.map((x, j) => (j === i ? next : x)) };
}

// Untap de un solo tipo: el botón circular de la píldora de cada ficha.
export function untapType(state, oracleId) {
  const i = findIndex(state, oracleId);
  if (i === -1 || state.active[i].tapped === 0) return state;
  const active = state.active.map((t, j) =>
    j === i ? { ...t, untapped: t.untapped + t.tapped, tapped: 0 } : t
  );
  return { active };
}

export function untapAll(state) {
  if (state.active.every((t) => t.tapped === 0)) return state;
  return {
    active: state.active.map((t) => ({
      ...t,
      untapped: t.untapped + t.tapped,
      tapped: 0,
    })),
  };
}
