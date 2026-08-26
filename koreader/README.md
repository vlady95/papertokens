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

Pendiente, **bloqueado en verificar contra la instalación real** (regla del
spec: ante ambigüedad, preguntar en vez de adivinar):

- `main.lua`, `_meta.lua`, `ui/` — necesitan confirmar en el device:
  firmas de `UIManager:setDirty` y nombres de modo de refresco vigentes;
  `Device.screen` y si `getDPI()` reporta el valor físico; rotación a
  horizontal y coordenadas táctiles; estructura de `_meta.lua` y registro en
  menú; carga de PNG; ruta real del directorio de plugins.

## Mapeo de botones propuesto (3 zonas táctiles fijas)

El hardware final tiene tres botones físicos; el prototipo mapea tres zonas
táctiles fijas (nada de touch sobre el elemento) con pulsación larga ~600 ms:

| Botón | Corta | Larga |
|---|---|---|
| BTN_A | ciclar token activo | abrir selector agregar/quitar tipo (reflow) |
| BTN_B | +1 cantidad | mover 1 untapped → tapped |
| BTN_C | −1 cantidad (tapped primero) | mover 1 tapped → untapped |

## Correr los tests

```
cd papertokens.koplugin && luajit tests/run.lua
```

## Deploy

```
./deploy.sh [ip-del-kindle]
```

Requiere USBNetwork activo y SSH como root.
