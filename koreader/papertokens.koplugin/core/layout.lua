-- core/layout.lua — motor de layout de PaperTokens.
--
-- MÓDULO PURO. Sin require de KOReader, sin I/O, sin estado global.
-- Entra geometría, salen rectángulos. Corre bajo Lua pelón (tests en el Mac).
--
-- Replica el layout de la app web:
--   n=1  una carta grande, centrada
--   n=2  dos apiladas verticalmente
--   n=3  dos arriba y una abajo, TODAS del mismo tamaño
--   n=4  cuadrícula 2x2
--   máximo 4 tipos simultáneos
--
-- La carta NUNCA se estira: conserva la proporción física 63x88 de una
-- carta de Magic. El tamaño lo manda el eje que limite, igual que el
-- `min(100cqw - orbes, 100cqh * 63/88)` del CSS de la web.
--
-- Cada celda contiene, de arriba a abajo:
--   [píldora de contadores]  [carta, con los orbes ± montados en sus bordes]

local M = {}

M.MAX_ACTIVE = 4
M.CARD_W, M.CARD_H = 63, 88 -- proporción de carta física

local function rect(x, y, w, h)
  return { x = x, y = y, w = w, h = h }
end

-- Frontera proporcional entera: sin huecos ni traslapes acumulados.
local function boundary(total, i, parts)
  return math.floor(total * i / parts + 0.5)
end

-- Ancho de carta que cabe en una celda de wxh, sin romper la proporción.
-- Se reserva media orbe por lado, como la web. El margen que sobre lo usa
-- M.orb_overlap para correr la orbe hacia afuera y no tapar el arte.
local function card_width_in(cell_w, cell_h, pill_h, gap, orb)
  local avail_h = cell_h - pill_h - gap
  local avail_w = cell_w - orb
  if avail_h < 1 or avail_w < 1 then return 0 end
  return math.min(avail_w, math.floor(avail_h * M.CARD_W / M.CARD_H))
end

-- Cuánto invade la orbe el interior de la carta. En la web la orbe se monta
-- a medias sobre el borde, pero ahí mide un 15% del ancho de la carta; aquí
-- el mínimo táctil físico puede ser la mitad de una carta chica, y montarla
-- taparía el arte. La invasión se limita al 8% del ancho de la carta: en
-- cartas grandes queda centrada en el borde, como en la web, y en las
-- chicas la orbe se sale hacia afuera, donde hay sitio de sobra.
M.orb_overlap = require("core/metrics").orb_overlap

-- Disposiciones candidatas para n cartas: columnas x filas.
local ARRANGEMENTS = {
  [1] = { { 1, 1 } },
  [2] = { { 1, 2 }, { 2, 1 } },
  [3] = { { 2, 2 }, { 3, 1 }, { 1, 3 } },
  [4] = { { 2, 2 }, { 4, 1 }, { 1, 4 } },
}

-- La app web elige la disposición que hace las cartas lo más grandes
-- posible en su pantalla angosta: n=2 apiladas, n=3 dos arriba y una
-- abajo, n=4 en 2x2. Esa es la regla, no las coordenadas: aquí se aplica
-- al panel real, de modo que en una pantalla más ancha n=2 salga en dos
-- columnas en vez de desperdiciar el ancho. Con la proporción del teléfono
-- reproduce exactamente las plantillas de la web.
function M.arrangement(w_px, h_px, n, opts)
  opts = opts or {}
  local pill_h, gap, orb = opts.pill_h or 0, opts.gap or 0, opts.orb or 0
  local best, best_w = nil, -1
  for _, cand in ipairs(ARRANGEMENTS[n]) do
    local cols, rows = cand[1], cand[2]
    local cw = card_width_in(math.floor(w_px / cols), math.floor(h_px / rows),
      pill_h, gap, orb)
    if cw > best_w then
      best, best_w = cand, cw
    end
  end
  return best[1], best[2]
end

-- Celdas de la disposición elegida, en orden de lectura. Una última fila
-- incompleta va centrada, para que ninguna carta quede descolgada.
function M.cells(w_px, h_px, n, opts)
  assert(n >= 1 and n <= M.MAX_ACTIVE, "layout: n fuera de rango (1..4)")
  local cols, rows = M.arrangement(w_px, h_px, n, opts)
  local cells = {}
  local placed = 0
  for r = 0, rows - 1 do
    local remaining = n - placed
    if remaining <= 0 then break end
    local in_row = math.min(cols, remaining)
    local y0 = boundary(h_px, r, rows)
    local y1 = boundary(h_px, r + 1, rows)
    local row_w = math.floor(w_px * in_row / cols)
    local x_off = math.floor((w_px - row_w) / 2) -- centra la fila incompleta
    for c = 0, in_row - 1 do
      local x0 = x_off + boundary(row_w, c, in_row)
      local x1 = x_off + boundary(row_w, c + 1, in_row)
      cells[#cells + 1] = rect(x0, y0, x1 - x0, y1 - y0)
      placed = placed + 1
    end
  end
  return cells
end

-- Reparto interno de una celda. Devuelve:
--   pill : rect de la píldora de contadores (arriba, centrada)
--   card : rect de la carta, con proporción 63x88 garantizada
-- `orb` es el diámetro de los botones ± ; se reserva la mitad de cada lado
-- porque van montados sobre el borde de la carta, como en la web.
function M.split_cell(cell, pill_h, gap, orb)
  local avail_h = cell.h - pill_h - gap
  local avail_w = cell.w - orb
  if avail_h < 1 or avail_w < 1 then
    return rect(cell.x, cell.y, cell.w, pill_h), rect(cell.x, cell.y, 1, 1)
  end

  -- El eje que limite manda; la proporción nunca se rompe.
  local card_w = math.min(avail_w, math.floor(avail_h * M.CARD_W / M.CARD_H))
  local card_h = math.floor(card_w * M.CARD_H / M.CARD_W)

  local card_x = cell.x + math.floor((cell.w - card_w) / 2)
  local card_y = cell.y + pill_h + gap + math.floor((avail_h - card_h) / 2)

  local pill_w = math.max(math.floor(card_w * 0.62), 1)
  local pill = rect(cell.x + math.floor((cell.w - pill_w) / 2), cell.y, pill_w, pill_h)

  return pill, rect(card_x, card_y, card_w, card_h)
end

-- Conveniencia: celdas ya divididas en píldora + carta.
function M.layout(w_px, h_px, n, opts)
  opts = opts or {}
  local pill_h = opts.pill_h or 0
  local gap = opts.gap or 0
  local orb = opts.orb or 0
  local out = {}
  for i, cell in ipairs(M.cells(w_px, h_px, n, opts)) do
    local pill, card = M.split_cell(cell, pill_h, gap, orb)
    out[i] = { cell = cell, pill = pill, card = card }
  end
  return out
end

M.px_to_mm = function(px, dpi) return px / dpi * 25.4 end

return M
