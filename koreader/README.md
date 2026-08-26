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
luajit tests/run.lua       # 114 checks: layout, fidelidad con la web, sesión
luajit tests/report.lua    # tamaño de carta real por dispositivo
luajit tests/preview.lua > /tmp/preview.svg   # cómo se ve la pantalla
```

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
plugin aparece en **☰ → herramientas → PaperTokens → Nueva sesión**.

## Fuera de alcance en esta fase

Sin red: el catálogo son los seis tokens de Pauper hardcoded en
`core/model.lua`. Crear un deck pegando una decklist vive en la app web; los
campos de `TokenDef` ya replican el payload autosuficiente que produce
`serializeDeck` allá, para que un perfil pueda viajar de la web al
dispositivo sin depender de Scryfall en la mesa.
