// Cliente de Scryfall para derivar tokens de una lista de cartas.
// Sin dependencias de React. Usa fetch global (navegador o node >= 18).
//
// Flujo:
//   1. POST /cards/collection por nombre, en lotes de 75, ~100 ms entre lotes.
//   2. De cada carta, tomar all_parts con component === 'token'.
//   3. Resolver esos ids con otra pasada por /cards/collection.
//   4. Deduplicar por oracle_id, uniendo las cartas de origen.
//
// No se inventan tokens: si Scryfall no lo lista en all_parts, no aparece.
// Sí se reporta la sospecha: cartas cuyo texto menciona crear tokens pero
// que no traen ninguna entrada token en all_parts (campo `suspects`).

const COLLECTION_URL = 'https://api.scryfall.com/cards/collection';
const BATCH_SIZE = 75;
const BATCH_PAUSE_MS = 100;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function chunk(arr, size) {
  const out = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

export async function fetchCollection(identifiers, onBatch) {
  const found = [];
  const notFound = [];
  const batches = chunk(identifiers, BATCH_SIZE);

  for (let i = 0; i < batches.length; i++) {
    if (i > 0) await sleep(BATCH_PAUSE_MS);
    onBatch?.(i + 1, batches.length);

    // Scryfall rechaza User-Agents genéricos de librerías HTTP (p. ej. node).
    // En navegador este header puede ser ignorado; el UA real del browser pasa igual.
    const res = await fetch(COLLECTION_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'User-Agent': 'PaperTokens/0.1 (prototipo personal)',
      },
      body: JSON.stringify({ identifiers: batches[i] }),
    });
    if (!res.ok) {
      throw new Error(`Scryfall respondió ${res.status} en el lote ${i + 1}/${batches.length}`);
    }
    const data = await res.json();
    found.push(...(data.data ?? []));
    notFound.push(...(data.not_found ?? []));
  }

  return { found, notFound };
}

function oracleTexts(card) {
  if (card.card_faces?.length) return card.card_faces.map((f) => f.oracle_text ?? '');
  return [card.oracle_text ?? ''];
}

function mentionsTokenCreation(card) {
  const text = oracleTexts(card).join('\n');
  return /\bcreates?\b/i.test(text) && /\btoken/i.test(text);
}

function initials(name) {
  const words = name.split(/[\s//]+/).filter(Boolean);
  if (words.length >= 2) return (words[0][0] + words[1][0]).toUpperCase();
  return name.slice(0, 2).toUpperCase();
}

function simplifyToken(card, sources) {
  const face = card.card_faces?.[0] ?? card;
  const typeLine = card.type_line ?? face.type_line ?? '';
  const isCreature = /\bCreature\b/i.test(typeLine);
  const power = face.power ?? card.power ?? null;
  const toughness = face.toughness ?? card.toughness ?? null;

  return {
    id: card.id,
    oracleId: card.oracle_id ?? card.id,
    name: card.name,
    typeLine,
    isCreature,
    power,
    toughness,
    colors: face.colors ?? card.colors ?? [],
    oracleText: oracleTexts(card).join('\n//\n'),
    initials: initials(face.name ?? card.name),
    label: isCreature && power != null ? `${power}/${toughness}` : initials(face.name ?? card.name),
    sources: [...sources].sort(),
  };
}

// cardNames: array de strings. onProgress recibe {phase: 'cards'|'tokens', batch, total}.
export async function deriveTokens(cardNames, onProgress) {
  const { found, notFound } = await fetchCollection(
    cardNames.map((name) => ({ name })),
    (batch, total) => onProgress?.({ phase: 'cards', batch, total })
  );

  // token scryfall id -> Set de nombres de cartas que lo generan
  const tokenSources = new Map();
  for (const card of found) {
    for (const part of card.all_parts ?? []) {
      if (part.component !== 'token') continue;
      if (!tokenSources.has(part.id)) tokenSources.set(part.id, new Set());
      tokenSources.get(part.id).add(card.name);
    }
  }

  const suspects = found
    .filter((card) => mentionsTokenCreation(card))
    .filter((card) => !(card.all_parts ?? []).some((p) => p.component === 'token'))
    .map((card) => ({ name: card.name, oracleText: oracleTexts(card).join(' // ') }));

  let tokens = [];
  const ids = [...tokenSources.keys()];
  if (ids.length > 0) {
    await sleep(BATCH_PAUSE_MS);
    const resolved = await fetchCollection(
      ids.map((id) => ({ id })),
      (batch, total) => onProgress?.({ phase: 'tokens', batch, total })
    );

    const byOracle = new Map();
    for (const tokenCard of resolved.found) {
      const key = tokenCard.oracle_id ?? tokenCard.id;
      const sources = tokenSources.get(tokenCard.id) ?? new Set();
      if (byOracle.has(key)) {
        const existing = byOracle.get(key);
        for (const s of sources) existing.sourceSet.add(s);
      } else {
        byOracle.set(key, { card: tokenCard, sourceSet: new Set(sources) });
      }
    }
    tokens = [...byOracle.values()]
      .map(({ card, sourceSet }) => simplifyToken(card, sourceSet))
      .sort((a, b) => a.name.localeCompare(b.name));
  }

  return {
    tokens,
    notFound: notFound.map((nf) => nf.name ?? JSON.stringify(nf)),
    suspects,
    foundCount: found.length,
  };
}
