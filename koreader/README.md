# PaperTokens — plugin de KOReader (Kindle PW3)

Port del prototipo web a hardware e-ink real. **Objetivo de esta fase:
validar función, no fidelidad visual** — motor de layout, máquina de estados
de sesión, modelo de refresco y presupuesto de ghosting. Código de prueba,
desechable salvo `core/layout.lua`.

Dispositivo: Kindle Paperwhite 3 (PQ94WIF), 1072x1448 @ 300 dpi, jailbreak +
KOReader, orientación horizontal, dimensiones nativas sin escalar.

## Estado

Hecho y probado en la Mac (sin KOReader):

- `core/layout.lua` — **módulo puro, portable**. Umbrales en mm (no px),
  plantillas proporcionales n=1..6, tiers FULL/COMPACT/MINIMAL, orden
  estable. `luajit tests/run.lua` → 195 checks contra las dimensiones del
  Kindle horizontal y del panel objetivo (800x480 @ 125 dpi): tiers
  esperados, sin traslapes, sin salirse de pantalla.
- `core/session.lua` — máquina de sesión pura. Cada operación devuelve el
  evento de refresco (`partial` / `zone_full` / `reflow` / `none` /
  `blocked`): la cantidad jamás dispara reflow (llegar a 0 no elimina la
  zona), reflow solo al cambiar el set declarado, presupuesto de ghosting
  por zona con umbral ajustable, modo "layout fijo" que bloquea declarar.
- `core/model.lua` — TokenDef/TokenState/Profile v1 + perfil Pauper
  hardcoded con los seis tokens.
- `config/thresholds.lua` — umbrales de tier en mm, presupuesto de ghosting
  y ms de pulsación larga. Editable sin recompilar.
- `assets/` — seis siluetas negras (Eldrazi Spawn, Blood, Map, Human
  Soldier, Cat, Clue) pre-rasterizadas en la Mac a 224/160/96 px (fuentes
  SVG en `assets/src/`). El nombre de archivo es el último segmento del
  `art_key` + tamaño (`creature/cat` → `cat-224.png`).
- `deploy.sh` — rsync por SSH + reinicio (rutas pendientes de verificar).

- `main.lua`, `_meta.lua`, `ui/render.lua`, `ui/view.lua` — escritos contra
  la API **verificada en la instalación real**, ver abajo.

## API verificada (KOReader v2026.07.1, PW3)

Consultada en el device antes de escribir una línea que dependiera de ella:

| Punto | Hallazgo |
|---|---|
| `UIManager:setDirty` | `(widget, refreshtype, refreshregion, refreshdither)`; modos `full`, `flashpartial`, `flashui`, `partial`, `ui`, `fast`, `a2`. `refreshregion` es un `Geom` |
| DPI | `Screen:getDPI()` devuelve `display_dpi` = **300 físico** para PW3 (solo lo altera `EMULATE_READER_DPI`) |
| Tallas de fuente | `Font:getFace(name, size)` escala su argumento con `Screen:scaleBySize()`. `ui/render.lua` **invierte** esa escala para pedir píxeles físicos reales |
| Rotación | `Screen:setRotationMode(Screen.DEVICE_ROTATED_CLOCKWISE)` (=1) |
| Táctil rotado | `GestureDetector:adjustGesCoordinate` **ya traduce** las coordenadas en landscape: no hay que corregirlas a mano |
| Pulsación larga | `HOLD_INTERVAL_MS = 500` **global** (setting `ges_hold_interval_ms`), no los 600 ms del spec — el gesto `hold` dispara con ese valor |
| Zonas táctiles | `InputContainer:registerTouchZones{...}` con `screen_zone` en ratios, resueltas contra `Screen:getWidth/getHeight` **al registrar** ⇒ registrar después de rotar |
| Plugin | `_meta.lua` con `fullname`/`description`; `WidgetContainer:extend`, `self.ui.menu:registerToMainMenu(self)`, `addToMainMenu(menu_items)` con `sorting_hint` |
| PNG | `RenderImage:renderImageFile(path, want_frames, w, h)` → BlitBuffer |
| Dibujo | `bb:paintRect/paintBorder/invertRect/blitFrom`; `RenderText:renderUtf8Text/sizeUtf8Text` |
| Ruta de plugins | `koreader/plugins/` en la raíz de la unidad (`/mnt/us/koreader/plugins`) |
| Ciclo de vida | `Widget:new` llama `_init()` y luego `init()` |

## Mapeo de botones (3 zonas táctiles fijas)

Franja inferior dividida en tres, nada de touch sobre el elemento a
modificar. El selector de tipos se opera con **los mismos tres botones**,
porque el hardware final no tiene más:

| Botón | Corta (juego) | Larga (juego) | En el selector |
|---|---|---|---|
| BTN_A | ciclar token activo | abrir selector de tipos | siguiente |
| BTN_B | +1 cantidad | tapear uno (untapped→tapped) | marcar/desmarcar |
| BTN_C | −1 cantidad (tapped primero) | destapar uno | jugar (cierra ⇒ reflow) |

## Dato de calibración (`luajit tests/report.lua`)

Con las franjas de botones (12 mm) y estado (5 mm) descontadas:

```
Kindle PW3 landscape — contenido 122.6 x 73.7 mm
  n=1..4  todas las zonas FULL (mínima 61x37 mm)
  n=5     principal 88x74 FULL | tira 34x18 mm MINIMAL
  n=6     principal 88x74 FULL | tira 34x15 mm MINIMAL

Panel objetivo — contenido 162.6 x 80.5 mm
  n=5     principal 117x80 FULL | tira 46x20 mm COMPACT
```

**Hallazgo:** en el Kindle la tira lateral cae a MINIMAL por 2 mm de alto
(18 vs el umbral 20). El panel objetivo sí llega a COMPACT. Decisión abierta
para calibrar contra hardware: bajar `compact.h_mm`, subir
`SIDE_STRIP_FRACTION`, o aceptar que en el caso más restrictivo la tira solo
muestre cantidades.

## Correr los tests

```
cd papertokens.koplugin && luajit tests/run.lua
cd papertokens.koplugin && luajit tests/report.lua
```

## Deploy

```
./deploy.sh                    # Kindle montado por USB en /Volumes/Kindle
./deploy.sh 192.168.15.244     # USBNetwork por SSH
```

En modo USB mass storage KOReader no está corriendo: tras copiar hay que
expulsar la unidad (`diskutil eject /Volumes/Kindle`) y abrir KOReader.

El plugin aparece en **☰ → herramientas → PaperTokens**. Los errores de Lua
van a `koreader/crash.log`, junto con las latencias de refresco que loguea
la instrumentación (`PaperTokens refresh: <acción> <modo> <ms>`).
