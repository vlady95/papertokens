// Persistencia local de decks y la costura de serialización. Sin React.
//
// Un deck es un catálogo estático de tipos de token, con nombre y fecha de
// último uso. La serialización es una función aparte y explícita porque en el
// futuro el payload viajará a un dispositivo sin red: tiene que incluir todo
// lo que la sesión necesita —nombre, oracle_id, fuerza/resistencia, colores,
// texto de reglas— sin depender de Scryfall en tiempo de juego. Hoy los dos
// lados son la misma app; la costura queda escrita igual.

const STORAGE_KEY = 'papertokens.decks.v1';
export const PAYLOAD_VERSION = 1;

// ---- Serialización (la costura) ----

// Deck en memoria -> payload autosuficiente, apto para JSON.stringify.
export function serializeDeck(deck) {
  return {
    version: PAYLOAD_VERSION,
    id: deck.id,
    name: deck.name,
    createdAt: deck.createdAt,
    lastUsedAt: deck.lastUsedAt ?? null,
    tokens: deck.tokens.map((t) => ({
      oracleId: t.oracleId,
      name: t.name,
      typeLine: t.typeLine,
      isCreature: Boolean(t.isCreature),
      power: t.power ?? null,
      toughness: t.toughness ?? null,
      colors: t.colors ?? [],
      oracleText: t.oracleText ?? '',
      initials: t.initials,
      label: t.label,
      sources: t.sources ?? [],
    })),
  };
}

// Payload -> deck en memoria. Lanza si el payload no es autosuficiente.
export function deserializeDeck(payload) {
  if (!payload || payload.version !== PAYLOAD_VERSION) {
    throw new Error(`Payload de deck con versión desconocida: ${payload?.version}`);
  }
  for (const field of ['id', 'name', 'createdAt']) {
    if (payload[field] == null) throw new Error(`Payload de deck sin campo "${field}"`);
  }
  if (!Array.isArray(payload.tokens)) throw new Error('Payload de deck sin lista de tokens');
  for (const t of payload.tokens) {
    for (const field of ['oracleId', 'name', 'typeLine', 'initials', 'label']) {
      if (t[field] == null) throw new Error(`Token del payload sin campo "${field}"`);
    }
  }
  return {
    id: payload.id,
    name: payload.name,
    createdAt: payload.createdAt,
    lastUsedAt: payload.lastUsedAt ?? null,
    tokens: payload.tokens.map((t) => ({ ...t })),
  };
}

// ---- Almacenamiento (localStorage hoy; la interfaz no lo asume) ----

const CORRUPT_KEY = 'papertokens.decks.v1.corrupt';

// Si el almacén está corrupto, no se finge que está vacío: el crudo se
// aparta a CORRUPT_KEY para que un guardado posterior no lo sobrescriba
// en silencio, y la interfaz puede avisar (ver listDecks).
function readAll(storage) {
  const raw = storage.getItem(STORAGE_KEY);
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) throw new Error('el almacén no es una lista');
    return parsed;
  } catch {
    storage.setItem(CORRUPT_KEY, raw);
    return [];
  }
}

export function corruptBackup(storage = globalThis.localStorage) {
  return storage.getItem(CORRUPT_KEY);
}

function writeAll(storage, payloads) {
  storage.setItem(STORAGE_KEY, JSON.stringify(payloads));
}

// Devuelve los decks legibles, más recientes primero. Los payloads corruptos
// se reportan en `broken`, no se descartan en silencio.
export function listDecks(storage = globalThis.localStorage) {
  const decks = [];
  const broken = [];
  for (const payload of readAll(storage)) {
    try {
      decks.push(deserializeDeck(payload));
    } catch (e) {
      broken.push({ payload, error: e.message });
    }
  }
  decks.sort(
    (a, b) => (b.lastUsedAt ?? b.createdAt).localeCompare(a.lastUsedAt ?? a.createdAt)
  );
  return { decks, broken };
}

export function saveDeck(deck, storage = globalThis.localStorage) {
  const all = readAll(storage).filter((p) => p.id !== deck.id);
  all.push(serializeDeck(deck));
  writeAll(storage, all);
}

// Marca el último uso. Se llama cuando la sesión cumple los diez minutos,
// no al cerrarla — si solo se guardara al salir, nunca se guardaría.
export function touchDeck(deckId, when, storage = globalThis.localStorage) {
  const all = readAll(storage);
  const payload = all.find((p) => p.id === deckId);
  if (!payload) return;
  payload.lastUsedAt = when;
  writeAll(storage, all);
}

export function newDeckId() {
  return globalThis.crypto?.randomUUID?.() ?? `deck-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}
