// Parser de decklists en texto plano. Sin dependencias de React ni del navegador.
//
// Formatos aceptados por línea:
//   4 Lightning Bolt
//   4x Lightning Bolt
//   Lightning Bolt              (cantidad implícita: 1)
//   4 Lightning Bolt (M11) 149  (Arena: set y número de coleccionista)
//   SB: 2 Pyroblast             (sideboard MTGO; cuenta como parte del mazo)
//   Fire // Ice                 (cartas partidas)
//   // comentario  |  # comentario
//   Sideboard / Deck / Creatures (15)  → encabezados de sección, se saltan
//
// Devuelve { cards: [{name, qty, lines}], skipped: [{line, lineNumber, reason}] }
// donde reason ∈ 'blank' | 'comment' | 'header' | 'unrecognized'.

const SECTION_HEADER = new RegExp(
  '^(deck|main\\s?board|main\\s?deck|main|sideboard|side\\s?board|maybeboard|' +
    'commander|companion|creatures?|lands?|spells?|instants?|sorceries|' +
    'artifacts?|enchantments?|planeswalkers?|battles?|other(\\s+spells?)?|tokens?)' +
    '\\s*:?\\s*(\\(\\d+\\))?$',
  'i'
);

export function parseDecklist(text) {
  const byName = new Map();
  const skipped = [];

  const lines = String(text ?? '').split(/\r?\n/);

  lines.forEach((raw, i) => {
    const lineNumber = i + 1;
    const line = raw.trim();

    const skip = (reason) => skipped.push({ line: raw, lineNumber, reason });

    if (!line) return skip('blank');
    if (line.startsWith('//') || line.startsWith('#')) return skip('comment');
    if (SECTION_HEADER.test(line)) return skip('header');

    // Junk evidente: URLs, líneas sin letras, "60 cards"
    if (/https?:\/\//i.test(line)) return skip('unrecognized');
    if (!/[A-Za-zÀ-ÿ]/.test(line)) return skip('unrecognized');
    if (/^\d+\s+cards?$/i.test(line)) return skip('unrecognized');

    let rest = line;
    let sideboard = false;

    if (/^SB:\s*/i.test(rest)) {
      sideboard = true;
      rest = rest.replace(/^SB:\s*/i, '');
    }

    // Marcadores de foil/etched al final: *F*, *E*
    rest = rest.replace(/\s*\*[A-Za-z]+\*\s*$/, '');

    let qty = 1;
    const qtyMatch = rest.match(/^(\d+)\s*[xX]\s+(.+)$/) || rest.match(/^(\d+)\s+(.+)$/);
    if (qtyMatch) {
      qty = parseInt(qtyMatch[1], 10);
      rest = qtyMatch[2];
    }
    if (qty < 1) return skip('unrecognized');

    // Sufijo Arena: "(SET) 123" — el número de coleccionista es opcional
    rest = rest.replace(/\s+\(([A-Za-z0-9]{2,6})\)(\s+[\w★†]+)?\s*$/, '');

    const name = rest.trim();
    if (!name) return skip('unrecognized');

    const key = name.toLowerCase();
    if (byName.has(key)) {
      const entry = byName.get(key);
      entry.qty += qty;
      entry.lines.push(lineNumber);
      entry.sideboard = entry.sideboard && sideboard;
    } else {
      byName.set(key, { name, qty, sideboard, lines: [lineNumber] });
    }
  });

  return { cards: [...byName.values()], skipped };
}
