// Vista previa del icono en la pantalla de revisión.
//
// La clave la decide src/lib/icons.js y es la misma que va al archivo. Aquí
// solo se busca la imagen correspondiente en public/tokens/ para poder ver
// qué le va a tocar a cada token. Si no hay clave, o no hay imagen, se
// muestra "?" — exactamente lo que pintará el dispositivo.

const BASE = (typeof import.meta !== 'undefined' && import.meta.env?.BASE_URL) || '/';

export function iconCandidates(key) {
  if (!key) return [];
  return [`${BASE}tokens/${key}.svg`, `${BASE}tokens/${key}.png`];
}
