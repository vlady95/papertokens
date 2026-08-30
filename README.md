# PaperTokens

Registro de tokens de Magic: The Gathering para jugar con cartas físicas en
la mesa, en un dispositivo e-ink.

El proyecto son tres piezas, dos de ellas web:

| Pieza | URL | Para qué |
|---|---|---|
| **Generador** | [/papertokens/](https://vlady95.github.io/papertokens/) | Auxiliar del Kindle: se pega una decklist, se revisa y se descarga el `.txt` que lee el plugin. Aquí no se juega. |
| **Jugar** | [/papertokens/jugar/](https://vlady95.github.io/papertokens/jugar/) | La app completa de mesa, desde el teléfono: pegar mazo, elegir tokens, contadores, untap-all, carrusel y vista expandida. Guarda los mazos en el navegador. |
| **Plugin de KOReader** | `koreader/` | Lo mismo que "Jugar", pero en el Kindle e-ink. Lee los `.txt` del generador, sin red. |

Las dos webs son PWA instalables por separado, con su propio icono y nombre
("PT Generador" y "PaperTokens"). Comparten un solo service worker en la
raíz del sitio, cuyo scope cubre ambas, así que las dos funcionan sin
conexión con un único precache.

El archivo del Kindle se copia a mano de la Mac al dispositivo. No hay
backend, ni cuentas, ni sincronización entre las piezas.

**[CONTEXTO.md](CONTEXTO.md)** resume todo el diseño, las decisiones y el
inventario de funciones en un solo documento, para poner al día a alguien
—o a un chat— que no vio cómo se llegó hasta aquí.

## Flujo del generador

1. Pegar la decklist en el textarea. Botón **Analizar**.
2. Se resuelve contra Scryfall (lotes de 75, dedupe por `oracle_id`).
3. Pantalla de **revisión**: los tokens encontrados con su clave de icono,
   más las cartas que Scryfall no halló y las líneas que el parser ignoró.
   Los huecos se muestran, no se esconden. Es una revisión, **no una
   selección**: el archivo exporta todos los tokens; qué entra en juego se
   elige en el Kindle, en la mesa.
4. Campo para el nombre del mazo.
5. Botón para descargar el `.txt`.

## El archivo

Autosuficiente: el Kindle no tiene red y el plugin no sabe nada de Magic,
solo pinta lo que el archivo le dice.

```
PAPERTOKENS 1
# …comentarios que documentan el propio formato…

deck-id 5a8187f84690b6f8
deck-name Jund Wildfire

token
name Eldrazi Spawn
oracle-id 3aaf906a-e749-4e86-ac79-97650b92f271
type Token Creature — Eldrazi Spawn
pt 0/1
colors
icon eldrazi-spawn
rules Sacrifice this creature: Add {C}.
```

- **Primera línea, marcador de versión.** El plugin lo verifica y rechaza lo
  que no entienda. El formato va a cambiar varias veces.
- **Formato de líneas, no JSON**: Lua no trae parser de JSON de fábrica, y
  así el archivo se puede corregir a mano.
- **`deck-id` se deriva del contenido de la decklist**, no del nombre: el
  nombre puede cambiar y el dispositivo tiene que seguir reconociendo que es
  el mismo mazo. Reexportar la misma lista da el mismo id; dos listas
  distintas dan ids distintos. (FNV-1a de 64 bits sobre los nombres de carta
  normalizados y ordenados.)
- **Saltos de línea en las reglas**: se codifican como `\n`, y la barra
  invertida literal como `\\`. Se revierten en UNA pasada de izquierda a
  derecha; encadenar dos reemplazos rompe el caso `\\n`. El propio archivo
  lo documenta en sus comentarios.
- **UTF-8 con saltos LF explícitos**: la descarga se arma con `TextEncoder`
  y bytes, sin depender de lo que decida el navegador.
- `pt` solo aparece en criaturas.

## El mapeo de iconos

Vive en la web (`src/lib/icons.js`), no en el plugin. El plugin trae un set
finito de imágenes; la web decide qué clave le toca a cada token y la
escribe en el archivo. El plugin solo busca un archivo con ese nombre; si no
lo encuentra, pinta un `?` grande.

- Tabla explícita, pensada para editarse seguido: agregar una fila basta.
- Criaturas por **subtipo** (así los nombra Scryfall: Goblin, Cat, Soldier
  mapean directo). No criaturas (Blood, Clue, Treasure, Map, Food) por
  **nombre**.
- Sin coincidencia ⇒ **clave vacía**. No se inventa una clave ni se adivina
  por aproximación: el `?` del dispositivo es la señal de qué iconos faltan
  por dibujar, y ese dato tiene que llegar limpio.

El `?` es un fallback de **arte**, no de datos: ese token igual lleva
nombre, fuerza/resistencia y reglas completos en el archivo.

La pantalla de revisión muestra la imagen que le tocaría a cada token, y
avisa aparte de los que no tienen clave y de los que tienen clave pero el
plugin todavía no empaqueta.

### Una sola fuente de arte

`public/tokens/<clave>.svg` es el único origen. `npm run icons` rasteriza
esos SVG a los PNG que empaqueta el plugin (96/160/224 px, porque el
dispositivo nunca rasteriza SVG) y de paso actualiza la lista
`PACKAGED_IN_PLUGIN` y la hoja de contactos. Agregar un icono es soltar un
SVG y correr ese comando.

## Estructura

Compartido por las dos webs:

- `src/lib/deck.js` — parser de decklists. Puro, sin React.
- `src/lib/scryfall.js` — resolución de tokens vía `/cards/collection`.

Solo del generador (`/`):

- `src/lib/icons.js` — mapeo token → clave de icono.
- `src/lib/export.js` — formato del archivo, escapado, `deck-id`, descarga.
- `src/App.jsx`, `src/index.css` — las dos pantallas.

Solo de la app de mesa (`/jugar/`):

- `src/lib/session.js` — los dos contadores y sus transiciones. Puro.
- `src/lib/storage.js` — mazos guardados en el navegador.
- `src/jugar/` — pantallas, estilos y resolución de arte de esa app.

Y el dispositivo:

- `koreader/` — el plugin donde se juega en el Kindle.

## Correr

```
npm install
npm run dev -- --host
```

Pruebas sin navegador:

```
node scripts/test-parser.mjs    # el parser, contra formatos reales
node scripts/test-export.mjs    # formato de archivo, escapado, id, iconos
node scripts/test-session.mjs   # la lógica de partida de la app de mesa
```

## Publicación

`npm run build` genera `docs/` con las dos apps (rutas relativas, PWA con
service worker versionado). GitHub Pages sirve `docs/` desde `main`:

- https://vlady95.github.io/papertokens/ — generador
- https://vlady95.github.io/papertokens/jugar/ — app de mesa

Para publicar: `npm run build`, commit y push; esperar ~1 min a que Pages
reconstruya y abrir la app con conexión para que tome la versión nueva.
