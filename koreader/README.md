# PaperTokens — plugin de KOReader (Kindle PW3)

La **sesión de la app web** corriendo en hardware e-ink. Mismo modelo de
interacción, mismo diseño de carta, mismas reglas: lo que cambia es el
dispositivo.

Kindle Paperwhite 3 (PQ94WIF), 1072x1448 @ 300 dpi, jailbreak + KOReader
v2026.07.1. Orientación **vertical**, como la web (mobile-first).

## Qué hay en pantalla

Las mismas tres zonas de la web, de arriba a abajo:

- **Header** — `Reiniciar partida` | círculo `UNTAP ALL` | `Salir`. Los dos
  botones laterales abren modal de confirmación; el central destapa todo sin
  preguntar.
- **Zona activa** — 1 a 4 tipos de token. Cada uno lleva su píldora de
  contadores con botón de untap propio, la carta, y los orbes `−` / `+` a los
  lados. La carta **nunca se estira**: conserva la proporción 63x88 de una
  carta física.
- **Carrusel** — el catálogo completo abajo, paginado por taps con bloques
  negros de chevron. Las miniaturas en juego se ven invertidas.

**Gestos** (toque directo, como la web):

| Acción | Resultado |
|---|---|
| tap en la carta | tapea un token (destapado → tapeado) |
| long-press en la carta | vista expandida: nombre, tipo completo, P/T y texto de reglas. Solo lectura, se cierra con un tap en cualquier parte |
| orbe `+` | crea un token, entra destapado |
| orbe `−` | destruye: resta de tapeados primero. Con el último token se vuelve bote de basura, y al llegar a 0 el tipo vuelve al carrusel |
| botón de la píldora | destapa todos los de ese tipo |
| tap en una miniatura | pone ese tipo en juego |

Los contadores nunca usan `/` (esa notación es fuerza/resistencia):
destapados en badge vertical sólido, tapeados en badge apaisado con
contorno. El badge en 0 no se dibuja. El texto de reglas solo existe en la
vista expandida.

## El motor de layout

`core/layout.lua` es puro (sin `require` de KOReader, sin I/O) y corre bajo
Lua pelón. La web elige la disposición que hace las cartas lo más grandes
posible en su pantalla angosta —n=2 apiladas, n=3 dos arriba y una abajo,
n=4 en 2x2— y **esa regla es lo que se porta**, no las coordenadas: aquí se
aplica al panel real. Con la proporción de un teléfono reproduce exactamente
las plantillas de la web (hay un test que lo verifica); en el Kindle, que es
relativamente más ancho, n=2 sale en dos columnas en vez de desperdiciar el
ancho.

Las medidas de los controles van en **milímetros** (`config/thresholds.lua`),
no en píxeles: un orbe de 130 px es cómodo a 300 dpi e inusable a 125.

## Ver el layout sin el Kindle

```
cd papertokens.koplugin
luajit tests/run.lua           # 114 checks: layout, fidelidad con la web, sesión
luajit tests/test-library.lua  # 30 checks: lectura de archivos y registro de uso
luajit tests/report.lua        # tamaño de carta real por dispositivo
luajit tests/preview.lua > /tmp/preview.svg   # cómo se ve la pantalla
```

Las pruebas corren contra `tests/fixtures/jund-wildfire.txt`, un archivo
generado de verdad por la webapp contra Scryfall, no un objeto inventado.

`preview.lua` usa los mismos `core/layout.lua` y `core/metrics.lua` que el
render del dispositivo, así que la geometría que muestra es la real.

## API verificada (KOReader v2026.07.1, PW3)

Consultada en la instalación real antes de escribir código que dependiera
de ella:

| Punto | Hallazgo |
|---|---|
| `UIManager:setDirty` | `(widget, refreshtype, refreshregion, refreshdither)`; modos `full`, `flashpartial`, `flashui`, `partial`, `ui`, `fast`, `a2`. `refreshregion` es un `Geom` |
| DPI | `Screen:getDPI()` devuelve `display_dpi` = **300 físico** para PW3 |
| Tallas de fuente | `Font:getFace(name, size)` escala su argumento con `Screen:scaleBySize()`; `ui/render.lua` **invierte** esa escala para pedir píxeles reales |
| Táctil rotado | `GestureDetector:adjustGesCoordinate` ya traduce las coordenadas: no hay que corregirlas a mano |
| Pulsación larga | `HOLD_INTERVAL_MS = 500` **global** (setting `ges_hold_interval_ms`) |
| Zonas táctiles | `registerTouchZones` fija sus ratios al registrar ⇒ aquí se registra una sola zona de pantalla completa y el hit-test se hace a mano, para que el reflow no obligue a re-registrar |
| Plugin | `_meta.lua` con `fullname`/`description`; `WidgetContainer:extend` + `registerToMainMenu` + `addToMainMenu` con `sorting_hint` |
| PNG | `RenderImage:renderImageFile(path, want_frames, w, h)` → BlitBuffer |
| Dibujo | `bb:paintRect/paintBorder/invertRect/blitFrom`; `RenderText:renderUtf8Text/sizeUtf8Text`. Círculos y rectángulos redondeados rellenos se dibujan por scanlines, sin depender de helpers no verificados |
| Ruta de plugins | `koreader/plugins/` en la raíz de la unidad (`/mnt/us/koreader/plugins`) |

## Modelo de refresco

| Evento | Modo | Alcance |
|---|---|---|
| cambio de cantidad o de tapeado | `fast` (o `ui`, alternable en el menú) | rect de la zona |
| entra o sale un tipo | `full` | pantalla completa |
| presupuesto de ghosting agotado | `full` | rect de la zona |

Cada refresco se loguea a `koreader/crash.log` como
`PaperTokens refresh: <acción> <modo> <ms>`.

## Deploy

```
./deploy.sh                    # Kindle montado por USB en /Volumes/Kindle
./deploy.sh 192.168.15.244     # USBNetwork por SSH
```

En modo USB mass storage KOReader no está corriendo: tras copiar hay que
expulsar la unidad (`diskutil eject /Volumes/Kindle`) y abrir KOReader. El
plugin aparece en **☰ → herramientas → PaperTokens → Mazos**.

## De dónde salen los mazos

De una carpeta de archivos `.txt`, uno por mazo, colocados a mano por USB en
`papertokens/` en la raíz de la partición del Kindle — hermana de
`koreader/`, para que se vea al montar el dispositivo. Cada archivo lo
genera la webapp y es autosuficiente.

El plugin **no tiene red y no sabe nada de Magic**: no consulta Scryfall, no
deduce, no completa datos que falten. Solo lee y pinta.

- **Reescanea en cada apertura.** Nada se cachea al arrancar: los archivos
  cambian constantemente.
- **Verifica el marcador de versión** de la primera línea. Lo que no
  reconoce, lo rechaza.
- **Valida cada token al leerlo.** Un archivo truncado o editado a mano no
  deja la biblioteca a medias: se rechaza ese archivo entero, se lista
  aparte con su motivo, y los demás siguen disponibles.
- **Revierte los saltos de línea** codificados del texto de reglas, en una
  sola pasada de izquierda a derecha.

## El registro interno de uso

El orden de la biblioteca **no** puede salir de la fecha de modificación del
archivo: copiar por USB reescribe los timestamps y todos los mazos
parecerían recién usados.

El plugin lleva su propio registro, guardado aparte de los `.txt` e indexado
por el **identificador estable** del mazo, no por nombre ni por ruta: así
renombrar el archivo o el mazo no rompe el historial.

La marca se escribe **al cruzar los diez minutos de sesión**, no al
cerrarla: una sesión más corta es una apertura accidental, y si solo se
guardara al salir nunca se guardaría. Al reescanear se limpian las entradas
que ya no corresponden a ningún archivo presente.

## Selección de tokens

El archivo trae **todos** los tokens del mazo. Al abrirlo, el catálogo
completo aparece en el carrusel y la zona activa arranca vacía: qué entra en
juego se elige aquí, en la mesa. Tap en una miniatura mete ese tipo en
juego.

## Iconos y el `?`

El plugin trae empaquetado un set finito de imágenes y **no decide** cuál va
con cada token: usa la clave que viene en el archivo y busca la imagen con
ese nombre.

Si la clave viene vacía, o no existe imagen para esa clave, pinta un `?`
grande ocupando el mismo espacio que tendría la silueta. Nada de imagen
genérica ni de aproximar: el `?` es una señal deliberada de qué iconos
faltan por dibujar.

Es un fallback de **arte**, no de datos: ese token igual muestra su nombre y
sus contadores en la ficha, y su fuerza/resistencia y texto de reglas
completos en la vista expandida.

## Borrar y archivar

Desde la biblioteca, long-press sobre un mazo:

- **Archivar** — mueve el archivo a `papertokens/archivados/`. Es el "quitar
  de la biblioteca" reversible.
- **Borrar** — elimina el archivo del disco y su entrada del registro en la
  misma operación, para que nunca quede huérfana. Es irreversible y el
  archivo puede ser la única copia, así que va detrás de long-press **y** de
  una confirmación explícita.

## Pendiente de verificar en el device

El Kindle estaba desconectado al escribir la biblioteca. Todo lo demás se
comprobó contra la instalación real; estas dos llamadas no, y viven
aisladas en `ui/files.lua`, envueltas en `pcall` para que un fallo se vea en
pantalla en vez de reventar:

- `require("libs/libkoreader-lfs")` — listar el directorio.
- `require("datastorage"):getSettingsDir()` — dónde guardar el registro de
  uso (hay respaldo si el método no existe).

También quedan por confirmar `UIManager:scheduleIn` / `unschedule`, que usa
la marca de los diez minutos.
