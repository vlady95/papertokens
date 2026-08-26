// Ranking de tokens más comunes dado un conjunto de decklists del meta.
// Dice exactamente qué ilustraciones conviene producir y con qué nombre de
// archivo soltarlas en public/tokens/.
//
// Uso:
//   node scripts/common-pauper-tokens.mjs decks/*.txt
//
// Cada archivo es una decklist en texto plano (mismos formatos que la app).

import { readFileSync } from 'node:fs';
import { basename } from 'node:path';
import { parseDecklist } from '../src/lib/deck.js';
import { deriveTokens } from '../src/lib/scryfall.js';
import { artSlug } from '../src/lib/art.js';

const files = process.argv.slice(2);
if (files.length === 0) {
  console.error('Uso: node scripts/common-pauper-tokens.mjs <decklist.txt> [...]');
  process.exit(1);
}

const byOracle = new Map(); // oracleId -> {token, decks:Set, sources:Set}

for (const file of files) {
  const text = readFileSync(file, 'utf8');
  const { cards } = parseDecklist(text);
  const { tokens, notFound } = await deriveTokens(cards.map((c) => c.name));
  for (const t of tokens) {
    if (!byOracle.has(t.oracleId)) {
      byOracle.set(t.oracleId, { token: t, decks: new Set(), sources: new Set() });
    }
    const entry = byOracle.get(t.oracleId);
    entry.decks.add(basename(file));
    for (const s of t.sources) entry.sources.add(s);
  }
  if (notFound.length) {
    console.error(`  [${basename(file)}] no encontradas: ${notFound.join(', ')}`);
  }
  await new Promise((r) => setTimeout(r, 200));
}

const ranked = [...byOracle.values()].sort((a, b) => b.decks.size - a.decks.size);

console.log(`\nTokens en ${files.length} decklists, por número de decks que los generan:\n`);
for (const { token, decks, sources } of ranked) {
  const pt = token.isCreature && token.power != null ? ` ${token.power}/${token.toughness}` : '';
  console.log(`${String(decks.size).padStart(2)} deck(s)  ${token.name}${pt} — ${token.typeLine}`);
  console.log(`           archivo: public/tokens/${artSlug(token.name)}.png  (o ${token.oracleId}.png)`);
  console.log(`           lo generan: ${[...sources].sort().join(', ')}`);
}
