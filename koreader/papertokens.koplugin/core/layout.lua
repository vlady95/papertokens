-- core/layout.lua — motor de layout de PaperTokens.
--
-- MÓDULO PURO. Sin require de KOReader, sin I/O, sin estado global.
-- Entra geometría, salen rectángulos. Corre bajo Lua pelón (tests en el Mac)
-- y está escrito para portarse a C mecánicamente: aritmética entera sobre
-- píxeles, decisiones sobre milímetros.
--
-- Firma:
--   layout(w_px, h_px, dpi, n[, thresholds])
--     w_px, h_px : dimensiones de pantalla en píxeles
--     dpi        : densidad física reportada por el dispositivo
--     n          : número de tipos de token activos (1..6)
--     thresholds : umbrales de tier en mm (default: config/thresholds.lua,
--                  inyectado por el caller; aquí hay un fallback idéntico)
--   devuelve: lista de n rects { x, y, w, h, tier }, en el orden estable de
--   inserción de los tokens (rect[i] ↔ token declarado i). En n=5,6 el
--   rect[1] es la zona principal; el caller decide qué token va ahí.
--
-- Los umbrales están en MILÍMETROS, no píxeles: un rect de 200x150 px es
-- ilegible a 300 dpi y cómodo a 125 dpi. mm = px / dpi * 25.4.

local M = {}

M.TIER_FULL = "FULL"
M.TIER_COMPACT = "COMPACT"
M.TIER_MINIMAL = "MINIMAL"

-- Fallback si el caller no inyecta config/thresholds.lua. Mantener idéntico.
local DEFAULT_THRESHOLDS = {
  full = { w_mm = 45, h_mm = 35 },
  compact = { w_mm = 25, h_mm = 20 },
}

local function px_to_mm(px, dpi)
  return px / dpi * 25.4
end

local function tier_for(w_px, h_px, dpi, th)
  local w_mm = px_to_mm(w_px, dpi)
  local h_mm = px_to_mm(h_px, dpi)
  if w_mm >= th.full.w_mm and h_mm >= th.full.h_mm then
    return M.TIER_FULL
  end
  if w_mm >= th.compact.w_mm and h_mm >= th.compact.h_mm then
    return M.TIER_COMPACT
  end
  return M.TIER_MINIMAL
end

-- Frontera proporcional entera: sin huecos ni traslapes acumulados.
local function boundary(total, i, parts)
  return math.floor(total * i / parts + 0.5)
end

local function rect(x, y, w, h)
  return { x = x, y = y, w = w, h = h }
end

-- Rejilla de cols x rows sobre la región (x0,y0,w,h), en orden de lectura.
local function grid(x0, y0, w, h, cols, rows, out)
  for r = 0, rows - 1 do
    local ry0 = y0 + boundary(h, r, rows)
    local ry1 = y0 + boundary(h, r + 1, rows)
    for c = 0, cols - 1 do
      local cx0 = x0 + boundary(w, c, cols)
      local cx1 = x0 + boundary(w, c + 1, cols)
      out[#out + 1] = rect(cx0, ry0, cx1 - cx0, ry1 - ry0)
    end
  end
  return out
end

-- Proporción de la franja lateral de miniaturas en n=5,6.
local SIDE_STRIP_FRACTION = 0.28

function M.layout(w_px, h_px, dpi, n, thresholds)
  assert(n >= 1 and n <= 6, "layout: n fuera de rango (1..6)")
  local th = thresholds or DEFAULT_THRESHOLDS
  local rects = {}

  if n == 1 then
    -- zona única, pantalla completa
    rects[1] = rect(0, 0, w_px, h_px)
  elseif n == 2 then
    -- dos columnas iguales
    grid(0, 0, w_px, h_px, 2, 1, rects)
  elseif n == 3 then
    -- franja superior completa + dos columnas abajo
    local split = boundary(h_px, 1, 2)
    rects[1] = rect(0, 0, w_px, split)
    grid(0, split, w_px, h_px - split, 2, 1, rects)
  elseif n == 4 then
    -- cuadrícula 2x2
    grid(0, 0, w_px, h_px, 2, 2, rects)
  else
    -- n=5,6: zona principal grande + franja lateral de miniaturas
    local strip_w = math.floor(w_px * SIDE_STRIP_FRACTION + 0.5)
    local main_w = w_px - strip_w
    rects[1] = rect(0, 0, main_w, h_px)
    grid(main_w, 0, strip_w, h_px, 1, n - 1, rects)
  end

  for i = 1, #rects do
    rects[i].tier = tier_for(rects[i].w, rects[i].h, dpi, th)
  end
  return rects
end

M.px_to_mm = px_to_mm

return M
