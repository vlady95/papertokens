// Construcción del archivo .txt que se copia al Kindle.
//
// Autosuficiente: el dispositivo no tiene red y el plugin no sabe nada de
// Magic. Solo pinta lo que este archivo le dice.
//
// Formato de LÍNEAS, no JSON: Lua no trae parser de JSON de fábrica, y así
// el archivo se puede abrir y corregir a mano en la Mac.

import { iconKey } from './icons.js';

export const FORMAT = 'PAPERTOKENS';
export const FORMAT_VERSION = 1;

// Codificación de valores multilínea (el texto de reglas trae saltos).
//   barra invertida literal → \\
//   salto de línea          → \n
// Se decodifica en UNA pasada de izquierda a derecha, nunca con reemplazos
// encadenados: "\\n" es barra literal seguida de ene, no un salto.
export function encodeValue(s) {
  return String(s ?? '')
    .replace(/\\/g, '\\\\')
    .replace(/\r\n?/g, '\n')
    .replace(/\n/g, '\\n');
}

// Referencia del decodificador que el plugin debe implementar en Lua.
// Se usa en las pruebas para verificar el viaje redondo.
export function decodeValue(s) {
  let out = '';
  for (let i = 0; i < s.length; i++) {
    if (s[i] === '\\' && i + 1 < s.length) {
      const next = s[i + 1];
      if (next === '\\') { out += '\\'; i++; continue; }
      if (next === 'n') { out += '\n'; i++; continue; }
    }
    out += s[i];
  }
  return out;
}

// Identificador estable del mazo. Se deriva del CONTENIDO de la decklist,
// no del nombre: el nombre puede cambiar y el dispositivo tiene que seguir
// reconociendo que es el mismo mazo. Reexportar la misma lista da el mismo
// id; dos listas distintas dan ids distintos.
// FNV-1a de 64 bits, en hexadecimal.
export function deckId(cardNames) {
  const basis = [...cardNames]
    .map((n) => n.trim().toLowerCase())
    .sort()
    .join('\n');

  const MASK = (1n << 64n) - 1n;
  const PRIME = 0x100000001b3n;
  let hash = 0xcbf29ce484222325n;
  for (const b of new TextEncoder().encode(basis)) {
    hash = (hash ^ BigInt(b)) & MASK;
    hash = (hash * PRIME) & MASK;
  }
  return hash.toString(16).padStart(16, '0');
}

const HEADER_COMMENTS = [
  '# PaperTokens — catálogo de tokens de un mazo.',
  '# Generado por la webapp; se copia a mano a la carpeta del plugin.',
  '#',
  '# Formato de líneas: "clave valor", una por línea. Codificación UTF-8,',
  '# saltos de línea LF. Los bloques de token empiezan con una línea "token"',
  '# y terminan en la línea en blanco siguiente.',
  '#',
  '# En los valores, los saltos de línea van codificados como \\n y la barra',
  '# invertida literal como \\\\. Para revertirlos hay que recorrer el valor',
  '# UNA vez de izquierda a derecha: al ver \\ se mira el carácter siguiente,',
  '# \\ produce una barra y n produce un salto. Encadenar dos reemplazos',
  '# rompe el caso "\\\\n" (barra literal seguida de ene).',
  '#',
  '# "icon" es la clave de imagen que el plugin debe buscar. Si viene vacía,',
  '# o si el plugin no trae esa imagen, se pinta un "?" — pero el token',
  '# igual lleva nombre, fuerza/resistencia y reglas completos aquí.',
];

export function buildFile({ deckName, cards, tokens }) {
  const lines = [];
  lines.push(`${FORMAT} ${FORMAT_VERSION}`);
  lines.push(...HEADER_COMMENTS);
  lines.push('');
  lines.push(`deck-id ${deckId(cards)}`);
  lines.push(`deck-name ${encodeValue(deckName)}`);

  for (const t of tokens) {
    lines.push('');
    lines.push('token');
    lines.push(`name ${encodeValue(t.name)}`);
    lines.push(`oracle-id ${t.oracleId}`);
    lines.push(`type ${encodeValue(t.typeLine)}`);
    if (t.isCreature && t.power != null) {
      lines.push(`pt ${t.power}/${t.toughness}`);
    }
    lines.push(`colors ${(t.colors ?? []).join('')}`);
    lines.push(`icon ${iconKey(t)}`);
    lines.push(`rules ${encodeValue(t.oracleText)}`);
  }

  lines.push('');
  return lines.join('\n'); // LF explícito, nunca CRLF
}

export function fileName(deckName) {
  const slug = String(deckName ?? '')
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
  return `${slug || 'mazo'}.txt`;
}

// Descarga con bytes UTF-8 explícitos: no se depende de lo que el navegador
// decida hacer con la codificación.
export function downloadFile(deckName, content) {
  const bytes = new TextEncoder().encode(content);
  const blob = new Blob([bytes], { type: 'text/plain;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = fileName(deckName);
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
