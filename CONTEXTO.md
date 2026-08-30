# PaperTokens — contexto del proyecto

Documento para sincronizar la memoria de un chat con el estado real del
código. **El repositorio es la fuente de verdad**: lo que esté aquí describe
lo que existe y funciona hoy. Si en el chat se decidió algo que no aparece
en este documento, no está implementado.

Repo: `github.com/vlady95/papertokens` (público, rama `main`).
Última actualización de este documento: commit `987f999`.

---

## 1. Qué es

Registro de tokens de Magic: The Gathering para jugar con **cartas físicas**
en la mesa. El objetivo final es un dispositivo e-ink dedicado; hoy corre en
un Kindle Paperwhite 3 jailbrokeado con KOReader, más dos apps web.

**Son tres piezas:**

| Pieza | Dónde vive | Para qué |
|---|---|---|
| **Generador** (web) | `/`, `src/App.jsx` — https://vlady95.github.io/papertokens/ | Auxiliar del Kindle. Se pega una decklist, se resuelve contra Scryfall, se revisa, se nombra el mazo y se **descarga un `.txt`**. Aquí no se juega. |
| **Jugar** (web) | `/jugar/`, `src/jugar/` — https://vlady95.github.io/papertokens/jugar/ | La app completa de mesa desde el teléfono. Guarda mazos en `localStorage`. |
| **Plugin KOReader** | `koreader/papertokens.koplugin/` | Lo mismo que "Jugar" pero en el Kindle. Lee los `.txt` del generador. **Sin red.** |

Las dos webs son PWA instalables por separado ("PT Generador" y
"PaperTokens"), publicadas por GitHub Pages desde `docs/` en `main`.
Comparten **un solo service worker** en la raíz del sitio, cuyo scope
(`/papertokens/`) cubre ambas.

El `.txt` se copia **a mano por USB** de la Mac al Kindle. No hay backend,
cuentas, sincronización ni red entre las piezas.

---

## 2. El contrato: el archivo `.txt`

Es la única interfaz entre la web y el dispositivo. Autosuficiente: el
Kindle no tiene red y el plugin **no sabe nada de Magic** — no consulta
Scryfall, no deduce, no completa datos que falten. Solo lee y pinta.

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

Reglas del formato:

- **Primera línea = marcador de versión.** El plugin la verifica y rechaza
  lo que no entienda. El formato va a cambiar varias veces.
- **Formato de líneas, no JSON.** Lua no trae parser de JSON de fábrica, y
  así el archivo se corrige a mano en la Mac.
- **Bloques**: `token` abre un bloque, la línea en blanco lo cierra.
  Claves desconocidas se ignoran, para que el formato pueda crecer.
- `pt` solo aparece en criaturas. `colors` es lista de letras (vacío =
  incoloro). `icon` puede venir vacío.
- **Escapado**: saltos de línea → `\n`, barra invertida literal → `\\`. Se
  revierte en **UNA pasada de izquierda a derecha**; encadenar dos
  reemplazos rompe el caso `\\n` (barra literal seguida de ene). Está
  documentado dentro del propio archivo.
- **UTF-8 con saltos LF explícitos**: la descarga se arma con `TextEncoder`
  y bytes, sin depender del navegador.
- **`deck-id` se deriva del CONTENIDO de la decklist** (FNV-1a de 64 bits
  sobre los nombres de carta normalizados y ordenados), **no del nombre ni
  de un UUID**: el nombre puede cambiar y el dispositivo tiene que seguir
  reconociendo que es el mismo mazo. Reexportar la misma lista da el mismo
  id.

---

## 3. Decisiones de diseño que NO hay que re-litigar

Estas costaron trabajo o vienen de un requisito explícito. Un asistente sin
contexto tiende a deshacerlas.

**Interacción y visual**

- Los dos contadores (destapados / tapeados) **nunca se separan con `/`**:
  esa notación es fuerza/resistencia y confundirlas en combate es un error
  caro. Destapados = badge vertical sólido; tapeados = badge apaisado con
  contorno. El badge en 0 no se dibuja.
- **El texto de reglas solo existe en la vista expandida** (long-press). La
  ficha pequeña nunca lo muestra.
- En la ficha pequeña la línea de tipo **omite la palabra "Token"**
  (`Creature — Elemental`); la expandida la conserva completa.
- **La carta nunca se estira**: conserva la proporción física 63×88 mm.
- **Paleta de 4 grises** (blanco, gris claro, gris medio, negro). Sin color,
  gradientes ni sombras. En el dispositivo, además, sin transiciones.
- Orbe `−` con el último token se vuelve **bote de basura**.
- Llegar a 0 saca el tipo de la zona activa y lo devuelve al carrusel.
- Máximo **4 tipos simultáneos** en juego.

**El motor de layout (lo único pensado para sobrevivir al port)**

- `core/layout.lua` es **puro**: sin `require` de KOReader, sin I/O, sin
  estado global. Corre bajo LuaJIT pelón. La regla es: `core/` no importa
  nada de KOReader; si lo hace, está mal.
- Lo que se portó de la web **es la regla, no las coordenadas**: "elegir la
  disposición que hace las cartas lo más grandes posible". Con la proporción
  de un teléfono reproduce exactamente las plantillas de la web (n=2
  apiladas, n=3 dos arriba y una abajo, n=4 en 2×2) — **hay un test que lo
  verifica**. En el Kindle, relativamente más ancho, n=2 sale en dos
  columnas en vez de desperdiciar el ancho.
- Las medidas de los controles van en **milímetros**, no en píxeles: un orbe
  de 130 px es cómodo a 300 dpi e inusable a 125.

**Iconos**

- **La web decide la clave, el plugin solo la usa.** El mapeo vive en
  `src/lib/icons.js`, en tablas explícitas pensadas para editarse seguido:
  criaturas por **subtipo** (así los nombra Scryfall), no-criaturas por
  **nombre**.
- **Sin coincidencia ⇒ clave vacía.** No se inventa ni se aproxima. El `?`
  del dispositivo es la señal limpia de qué iconos faltan por dibujar.
- El `?` es fallback de **arte, no de datos**: ese token igual muestra
  nombre y contadores en la ficha, y P/T y reglas en la expandida.

**Biblioteca del dispositivo**

- **Reescanea la carpeta en cada apertura.** Nada se cachea al arrancar.
- Un archivo que no valida **se rechaza entero** y se lista aparte con su
  motivo; los demás siguen disponibles. Media biblioteca en la mesa es peor
  que un mazo de menos.
- El orden **no** sale de la fecha de modificación del archivo: copiar por
  USB reescribe los timestamps. Hay un **registro propio** indexado por el
  id estable (no por nombre ni ruta), guardado aparte de los `.txt`.
- La marca de uso se escribe **al cruzar los diez minutos de sesión**, no al
  cerrarla: una sesión más corta es una apertura accidental, y si solo se
  guardara al salir nunca se guardaría.
- **Borrar** elimina archivo y entrada del registro en la misma operación
  (nunca queda huérfana); va detrás de long-press **y** confirmación
  explícita, porque es irreversible y el archivo puede ser la única copia.
  **Archivar** mueve a una subcarpeta: es el "quitar" reversible.
- La **selección de tokens se hace en la mesa**, no en la computadora: el
  archivo trae todos, la zona activa arranca vacía y el carrusel ofrece el
  catálogo completo.

**Fuera de alcance (decidido, no pendiente)**

Sin red en el dispositivo. Sin sincronización. Sin edición ni creación de
mazos en el Kindle. Sin backend, autenticación ni cuentas. La sesión de
juego es efímera: recargar o salir la descarta, sin recuperación.

---

## 4. Inventario de archivos y funciones

### Web — compartido por las dos apps

- **`src/lib/deck.js`** — parser de decklists. Puro.
  - `parseDecklist(text) → { cards: [{name, qty, sideboard, lines}], skipped: [{line, lineNumber, reason}] }`
  - Acepta `4 Name`, `4x Name`, `Name (SET) 123`, `SB:`, comentarios `//` y
    `#`, encabezados de sección, cartas partidas `//`. `reason` ∈ `blank` |
    `comment` | `header` | `unrecognized`.
- **`src/lib/scryfall.js`** — resolución de tokens.
  - `fetchCollection(identifiers, onBatch)` — lotes de 75, ~100 ms de pausa.
  - `deriveTokens(cardNames, onProgress) → { tokens, notFound, suspects, foundCount }`
  - Dedupe por `oracle_id`. `suspects` = cartas cuyo texto menciona crear
    tokens pero sin entrada en `all_parts`.
  - **Scryfall rechaza User-Agents genéricos**: el módulo manda uno propio.

### Web — solo el generador (`/`)

- **`src/lib/icons.js`** — el mapeo.
  - `ICON_BY_SUBTYPE`, `ICON_BY_NAME`, `PACKAGED_IN_PLUGIN`
  - `subtypeCandidates(typeLine)`, `iconKey(token) → clave | ''`, `isPackaged(key)`
- **`src/lib/export.js`** — el formato del archivo.
  - `FORMAT`, `FORMAT_VERSION`
  - `encodeValue(s)` / `decodeValue(s)` — el escapado y su inverso de referencia
  - `deckId(cardNames)` — FNV-1a 64 bits, hex de 16
  - `buildFile({ deckName, cards, tokens })`, `fileName(deckName)`, `downloadFile(deckName, content)`
- **`src/lib/art.js`** — `iconCandidates(key)`, solo para la vista previa.
- **`src/App.jsx`**, **`src/index.css`** — dos pantallas: pegar y revisión.

### Web — solo la app de mesa (`/jugar/`)

- **`src/lib/session.js`** — la lógica de partida. Pura, probable con node.
  - `MAX_ACTIVE_TYPES` (=4), `createSession()`
  - `createToken(state, oracleId)`, `tapToken(...)`, `destroyToken(...)`,
    `untapType(...)`, `untapAll(state)`
  - Estado inmutable: cada operación devuelve uno nuevo.
- **`src/lib/storage.js`** — mazos en `localStorage`.
  - `PAYLOAD_VERSION`, `serializeDeck(deck)`, `deserializeDeck(payload)`
  - `listDecks`, `saveDeck`, `touchDeck`, `newDeckId`, `corruptBackup`
  - Un almacén ilegible se aparta a una clave de respaldo **antes** de
    cualquier escritura, y el inicio avisa. No se sobrescribe en silencio.
- **`src/jugar/`** — `App.jsx`, `index.css`, `main.jsx`, `art.js`
  (`artSlug`, `artCandidates(token)`; busca el arte en `../tokens/` porque
  la app vive un nivel abajo).

### Plugin KOReader — `core/` (puro, probable en la Mac)

- **`core/layout.lua`** — `MAX_ACTIVE` (=4), `CARD_W`/`CARD_H` (63/88),
  `arrangement(w,h,n,opts) → cols,rows`, `cells(...)`,
  `split_cell(cell, pill_h, gap, orb) → pill, card`, `layout(w,h,n,opts)`
- **`core/metrics.lua`** — proporciones de la carta como fracciones.
  `orb_overlap(orb, margin)`, `card_boxes(card)`. Lo comparten el render del
  dispositivo y la previsualización SVG, para que no diverjan.
- **`core/session.lua`** — `new(deck, opts)`, `create`, `tap`, `destroy`,
  `untap_type`, `untap_all`, `reset`, `is_last`, `index_of`,
  `set_ghosting_budget`. Cada operación devuelve un **evento de refresco**:
  `partial` | `zone_full` | `reflow` | `none`.
- **`core/deckfile.lua`** — `FORMAT`, `VERSION`, `decode_value(s)`,
  `parse(text) → deck | nil, motivo`
- **`core/registry.lua`** — `SESSION_MARK_SECONDS` (=600), `decode`,
  `encode`, `touch`, `prune(reg, present_ids)`, `order(decks, reg)`
- **`core/model.lua`** — solo `COUNT_MAX` (=8). Ya no hay catálogo hardcoded.

### Plugin KOReader — `ui/` (desechable, depende de KOReader)

- **`ui/files.lua`** — todo el acceso a disco vive aquí y en ningún otro
  lado. `decks_dir`, `archive_dir`, `exists`, `mkdir`, `list_txt`, `read`,
  `write`, `remove`, `move_to`, `registry_path`
- **`ui/library.lua`** — la biblioteca: lista, abrir, archivar, borrar.
- **`ui/view.lua`** — la sesión: header, zona activa, carrusel, modales,
  vista expandida, instrumentación de refrescos.
- **`ui/render.lua`** — dibuja la carta web sobre el blitbuffer. Círculos y
  rectángulos redondeados por scanlines, sin helpers no verificados.
- **`main.lua`**, **`_meta.lua`**, **`config/thresholds.lua`** (toda la
  configuración: medidas en mm, carpetas, presupuesto de ghosting, modo de
  refresco parcial).

### Pruebas

```
node scripts/test-parser.mjs     # parser contra formatos reales
node scripts/test-export.mjs     # 38 checks: formato, escapado, id, iconos
node scripts/test-session.mjs    # guion de partida de la app de mesa

cd koreader/papertokens.koplugin
luajit tests/run.lua             # 114 checks: layout, fidelidad web, sesión
luajit tests/test-library.lua    #  30 checks: lectura de archivos y registro
luajit tests/report.lua          # tamaño de carta real por dispositivo
luajit tests/preview.lua > /tmp/preview.svg   # cómo se ve la pantalla
```

Las pruebas del plugin corren contra `tests/fixtures/jund-wildfire.txt`, un
archivo **generado de verdad por la webapp contra Scryfall**, no un objeto
inventado en el test.

---

## 5. API de KOReader verificada contra la instalación real

KOReader **v2026.07.1** en Kindle PW3 (1072×1448 @ 300 dpi). Consultado en
el dispositivo antes de escribir código que dependiera de ello:

| Punto | Hallazgo |
|---|---|
| `UIManager:setDirty` | `(widget, refreshtype, refreshregion, refreshdither)`; modos `full`, `flashpartial`, `flashui`, `partial`, `ui`, `fast`, `a2`. `refreshregion` es un `Geom` |
| DPI | `Screen:getDPI()` devuelve `display_dpi` = **300 físico** |
| Fuentes | `Font:getFace(name, size)` **escala su argumento** con `Screen:scaleBySize()`; `ui/render.lua` invierte esa escala para pedir píxeles reales |
| Táctil rotado | `GestureDetector:adjustGesCoordinate` **ya traduce** las coordenadas; no hay que corregirlas a mano |
| Long-press | `HOLD_INTERVAL_MS = 500` **global** (setting `ges_hold_interval_ms`), no configurable por plugin |
| Zonas táctiles | `registerTouchZones` fija sus ratios **al registrar** ⇒ se registra una sola zona de pantalla completa y el hit-test se hace a mano |
| Plugin | `_meta.lua` con `fullname`/`description`; `WidgetContainer:extend` + `registerToMainMenu` + `addToMainMenu` con `sorting_hint` |
| Ciclo de vida | `Widget:new` llama `_init()` y luego `init()` |
| PNG | `RenderImage:renderImageFile(path, want_frames, w, h)` → BlitBuffer |
| Dibujo | `bb:paintRect/paintBorder/invertRect/blitFrom`; `RenderText:renderUtf8Text/sizeUtf8Text` |
| Ruta de plugins | `koreader/plugins/` en la raíz de la unidad (`/mnt/us/koreader/plugins`) |

**Pendiente de verificar** (el Kindle estaba desconectado al escribir la
biblioteca). Aisladas en `ui/files.lua`, envueltas en `pcall` para que un
fallo se vea en pantalla en vez de reventar:

- `require("libs/libkoreader-lfs")` — listar el directorio
- `require("datastorage"):getSettingsDir()` — dónde va el registro de uso
  (hay respaldo si el método no existe)
- `UIManager:scheduleIn` / `unschedule` — la marca de los diez minutos

---

## 6. Estado del arte de iconos (disparidad conocida)

El mapeo puede emitir **14 claves**, pero los tres sets de imágenes no
coinciden:

| Set | Cuántos | Cuáles |
|---|---|---|
| Web `public/tokens/*.svg` | 12 | bird, clue, eldrazi-spawn, elemental, food, goblin, human-soldier, map, plant, spirit, squirrel, treasure |
| Plugin `assets/*.png` (96/160/224) | 6 | blood, cat, clue, eldrazi-spawn, human-soldier, map |
| **En ambos** | **4** | clue, eldrazi-spawn, human-soldier, map |

- Solo en la web (**el Kindle pintará `?`**): bird, elemental, food, goblin,
  plant, spirit, squirrel, treasure.
- Solo en el plugin (**la web previsualiza `?`**): blood, cat.

La pantalla de revisión ya avisa "el plugin aún no lo trae" usando
`PACKAGED_IN_PLUGIN`, que sí está correcto. Falta rasterizar los 8 SVG de la
web a PNG del plugin, y dibujar blood/cat para la web.

Archivos huérfanos detectados, sin referencias: `src/assets/hero.png`,
`src/assets/vite.svg`, `public/icons.svg`, `decks/sample-pauper.txt`
(lo usa a mano `scripts/common-pauper-tokens.mjs`), `public/tokens-preview.html`
(hoja de contactos que se abre a mano, lista desactualizada sin blood/cat).

---

## 7. Publicación

```
npm run build      # genera docs/ con las dos apps + sw.js versionado
git add -A && git commit && git push
```

Esperar ~1 min a que Pages reconstruya y abrir la app **con conexión** una o
dos veces para que tome la versión nueva.

Deploy al Kindle:

```
cd koreader && ./deploy.sh          # Kindle montado por USB en /Volumes/Kindle
cd koreader && ./deploy.sh <ip>     # USBNetwork por SSH
```

En modo USB mass storage KOReader no está corriendo: tras copiar hay que
expulsar la unidad y abrir KOReader. El plugin aparece en
**☰ → herramientas → PaperTokens → Mazos**. Los `.txt` van en
`papertokens/` en la raíz de la partición.
