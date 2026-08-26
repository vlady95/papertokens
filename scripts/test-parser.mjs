// Prueba del parser contra formatos reales de decklist.
// Correr con: node scripts/test-parser.mjs

import { parseDecklist } from '../src/lib/deck.js';

const samples = {
  'MTGO (qty + nombre, SB: en línea)': `
4 Lightning Bolt
4 Monastery Swiftspear
20 Mountain
SB: 3 Pyroblast
SB: 2 Smash to Smithereens
`,

  'Arena (set y número, encabezados Deck/Sideboard)': `
Deck
4 Lightning Bolt (M11) 149
4 Young Pyromancer (M14) 163
2 Fire // Ice (APC) 128
18 Mountain (UST) 215

Sideboard
3 Pyroblast (ICE) 213
`,

  'MTGGoldfish (4x, secciones con blancos)': `
4x Raffine's Informant
4x Prized Amalgam
2x Fire // Ice

Sideboard
2x Duress
`,

  'Con comentarios y basura de por medio': `
// Mi lista de pauper,版本 3
# actualizada ayer
4 Lightning Bolt
foo bar sin cantidad
Creatures (8)
4 Kor Skyfisher
!!!???
60 cards
https://www.mtggoldfish.com/deck/123456
0 Island
SB: 1 Gorilla Shaman *F*
`,
};

for (const [label, text] of Object.entries(samples)) {
  const { cards, skipped } = parseDecklist(text);
  console.log(`\n=== ${label} ===`);
  console.log('Cartas:');
  for (const c of cards) {
    console.log(`  ${String(c.qty).padStart(2)}  ${c.name}${c.sideboard ? '  [SB]' : ''}`);
  }
  const interesting = skipped.filter((s) => s.reason !== 'blank');
  if (interesting.length) {
    console.log('Saltadas:');
    for (const s of interesting) {
      console.log(`  L${s.lineNumber} (${s.reason}): ${s.line.trim()}`);
    }
  }
}
