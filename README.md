# PaperTokens

Registro de tokens de Magic: The Gathering para jugar con cartas físicas en
la mesa. El destino final es un dispositivo e-ink (Kindle Paperwhite); por
ahora todo vive en esta webapp, que simula esas condiciones.

## Estado actual (v2)

Sesión completa con persistencia:

- **Inicio** — cuatro ranuras por uso reciente (una sesión cuenta como "usada"
  solo si pasa de diez minutos), más biblioteca y crear deck.
- **Alta** — pegar decklist → analizar con Scryfall → pantalla de resultado
  con nombre, rejilla de tokens para marcar, y los huecos a la vista (cartas
  no encontradas, líneas ignoradas, cartas que mencionan crear tokens sin
  entrada en `all_parts`). La marca es *solo para hoy*: filtra el carrusel de
  la sesión; el deck guarda el catálogo completo. "Guardar y jugar" o
  "Guardar y salir".
- **Sesión** — header fijo con tres controles: "Reiniciar partida" (modal de
  confirmación; elimina todos los tokens en juego), el círculo de untap-all
  al centro (tap simple, sin confirmación — sigue siendo el dato a medir), y
  "Salir" (modal de confirmación; la sesión no se guarda). Zona activa
  (1 tipo = carta grande centrada; 2 = apilados; 3 = dos arriba y uno abajo
  del mismo tamaño; 4 = rejilla; nunca más de cuatro) donde las cartas
  guardan siempre la proporción 63×88 de una carta física — nunca se
  estiran. Carrusel fijo abajo con el catálogo del día, paginado por taps
  con bloques negros de chevron (sin scroll horizontal, deliberadamente).
  Las fichas sin fuerza/resistencia muestran su texto de reglas recortado;
  las criaturas, el badge de P/T.
- **Ficha** (según la referencia de diseño) — marco redondeado con barra de
  título (nombre + letra de color), caja de arte placeholder, barra de tipo y
  badge de fuerza/resistencia montado sobre el borde del arte. Encima, una
  píldora con los contadores del tipo y su botón de untap propio; el badge en
  cero no se dibuja. Tap en la carta tapea un token; `+` (círculo derecho,
  sobre el borde) crea; `−` (izquierdo) destruye restando primero de
  tapeados, y con el último token se vuelve bote de basura. Los contadores
  nunca usan `/` (reservada para fuerza/resistencia): destapado es un badge
  vertical sólido, tapeado uno apaisado con contorno, como se gira la carta.
  En cero y cero, el tipo vuelve al carrusel. El untap-all global sigue en el
  header.
- **Vista expandida** — long-press sobre una ficha: nombre, tipo, P/T y texto
  de reglas. Solo lectura; un tap en cualquier parte la cierra. El long-press
  no hace ninguna otra cosa en el producto.
- La sesión es efímera: vive en memoria; salir o recargar la descarta sin
  recuperación (decisión provisional del prototipo). Solo persiste la fecha
  de último uso, escrita al cumplirse los diez minutos.

Decisiones registradas: token no previsto en el catálogo queda fuera de
alcance en v2; biblioteca de solo lectura; sin anclaje de ranuras.

## Arte de tokens

Las ilustraciones se cargan por convención de archivos, sin código por
imagen: suelta en `public/tokens/` un archivo llamado

- `<slug-del-nombre>.png` o `.svg` — p. ej. `goblin.svg`, `eldrazi-spawn.png`
- o `<oracle_id>.png` / `.svg` para apuntar a un token exacto (gana sobre el
  slug; útil cuando dos tokens comparten nombre)

y aparecerá en la ficha, la expandida, el carrusel y la rejilla del alta. Si
no hay archivo, la interfaz cae al placeholder de letras. El arte debe ser
línea en blanco y negro (el CSS fuerza grayscale como red de seguridad).
`public/tokens/goblin.svg` es un ejemplo a sustituir.

Para saber qué ilustraciones producir primero, mete decklists del meta en
`decks/` y corre:

```
node scripts/common-pauper-tokens.mjs decks/*.txt
```

Imprime los tokens ordenados por cuántos decks los generan, con el nombre de
archivo exacto que espera `public/tokens/`.

## Restricciones e-ink (no negociables)

- Exactamente 4 grises. Sin color, gradientes ni sombras.
- Cero transiciones y cero animación. Único efecto permitido: la inversión
  breve al cambiar de vista (`.eink-flash`).
- Solo tap y long-press; targets mínimos de 48 px. Sin swipe, drag ni scroll
  horizontal.
- El layout solo se reacomoda cuando cambia el conjunto de tipos en juego,
  nunca cuando cambia una cantidad.
- Mobile primero.

## Estructura

- `src/lib/deck.js` — parser de decklists. Puro, sin React.
- `src/lib/scryfall.js` — deriva tokens vía `/cards/collection` (lotes de 75,
  ~100 ms de pausa, dedupe por `oracle_id`). Incluye colores y texto de
  reglas para que el payload guardado sea autosuficiente.
- `src/lib/session.js` — los dos contadores y sus transiciones. Puro.
- `src/lib/storage.js` — `serializeDeck`/`deserializeDeck` (la costura que en
  el futuro viajará a un dispositivo sin red) y el almacén en localStorage.
- `scripts/test-parser.mjs` — pruebas del parser.
- `scripts/test-session.mjs` — guion de partida contra la lógica de sesión.
- `src/App.jsx` — todas las pantallas.

## Publicación (GitHub Pages + PWA)

La app vive en https://vlady95.github.io/papertokens/ como PWA offline-first:
`vite build` genera `docs/` (rutas relativas, `base: './'`) y
`scripts/build-sw.mjs` escribe `docs/sw.js`, que precachea todo el build con
un nombre de caché derivado del contenido — cambia en cada publicación.
GitHub Pages sirve `docs/` desde la rama `main`.

Para publicar cambios:

```
npm run build
git add -A && git commit -m "..." && git push
```

Esperar ~1 min a que Pages reconstruya y abrir la app con conexión para que
tome la versión nueva.

## Correr

```
npm install
npm run dev -- --host
```

Lógica probable sin navegador:

```
node scripts/test-parser.mjs
node scripts/test-session.mjs
```

## Qué mide este prototipo

1. Si el untap-all sin confirmación se toca por accidente en partidas
   reales (si pasa seguido, se considerará deshacer — primero el dato).
2. Si la heurística del `−` (tapeados primero) acierta lo suficiente.
