-- ui/render.lua — dibuja la carta de la app web sobre el blitbuffer.
-- DESECHABLE: depende de KOReader. La geometría viene de core/layout.lua.
--
-- API verificada en KOReader v2026.07.1 (Kindle PW3):
--   bb:paintRect(x, y, w, h, color)
--   bb:paintBorder(x, y, w, h, bw, color, radius)
--   bb:blitFrom(src, dx, dy, ox, oy, w, h)
--   RenderText:renderUtf8Text(bb, x, baseline, face, text, kerning, bold, fgcolor)
--   RenderText:sizeUtf8Text(x, width, face, text, kerning, bold) -> { x = ancho }
--   RenderImage:renderImageFile(path, want_frames, w, h) -> BlitBuffer
--   Font:getFace(name, size) escala su argumento con Screen:scaleBySize(),
--   por eso face_px() invierte esa escala para pedir píxeles reales.
--
-- Los círculos y rectángulos redondeados rellenos se dibujan por scanlines
-- con paintRect: primitivas verificadas, sin depender de helpers que
-- podrían no existir en otra versión.

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local RenderImage = require("ui/renderimage")
local RenderText = require("ui/rendertext")
local Screen = require("device").screen
local logger = require("logger")

local metrics = require("core/metrics")

local Render = {}

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE

-- ---- tallas físicas ----

local scale_probe = Screen:scaleBySize(1000) / 1000

-- El negrita se aplica al renderizar, no en la face: aquí solo la talla.
local face_cache = {}
local function face_px(px)
  local design = math.max(8, math.floor(px / scale_probe + 0.5))
  if not face_cache[design] then
    face_cache[design] = Font:getFace("cfont", design)
  end
  return face_cache[design]
end
Render.face_px = face_px

function Render.mm_to_px(mm, dpi)
  return math.floor(mm * dpi / 25.4 + 0.5)
end

-- ---- primitivas ----

local function fill_round_rect(bb, x, y, w, h, r, color)
  if w <= 0 or h <= 0 then return end
  r = math.min(r or 0, math.floor(math.min(w, h) / 2))
  for i = 0, h - 1 do
    local dy
    if i < r then dy = r - i - 1
    elseif i >= h - r then dy = i - (h - r) + 1
    else dy = 0 end
    local dx = 0
    if dy > 0 and dy <= r then
      dx = r - math.floor(math.sqrt(math.max(r * r - dy * dy, 0)) + 0.5)
    end
    bb:paintRect(x + dx, y + i, w - 2 * dx, 1, color)
  end
end
Render.fill_round_rect = fill_round_rect

local function fill_circle(bb, cx, cy, radius, color)
  fill_round_rect(bb, cx - radius, cy - radius, radius * 2, radius * 2, radius, color)
end

local function stroke_round_rect(bb, x, y, w, h, bw, r, color)
  if w <= 0 or h <= 0 then return end
  bb:paintBorder(x, y, w, h, bw, color or BLACK, r or 0)
end

local function fill_triangle(bb, x1, y1, x2, y2, x3, y3, color)
  local ymin = math.min(y1, y2, y3)
  local ymax = math.max(y1, y2, y3)
  for y = ymin, ymax do
    local xs = {}
    local pts = { { x1, y1 }, { x2, y2 }, { x3, y3 } }
    for i = 1, 3 do
      local ax, ay = pts[i][1], pts[i][2]
      local bx, by = pts[i % 3 + 1][1], pts[i % 3 + 1][2]
      if (ay <= y and by > y) or (by <= y and ay > y) then
        xs[#xs + 1] = ax + (y - ay) / (by - ay) * (bx - ax)
      end
    end
    if #xs >= 2 then
      local lo, hi = math.min(xs[1], xs[2]), math.max(xs[1], xs[2])
      bb:paintRect(math.floor(lo), y, math.max(1, math.floor(hi - lo)), 1, color)
    end
  end
end

-- Flecha circular de "untap", dibujada a mano: la fuente del sistema no
-- garantiza el glifo ↺ y una caja vacía sería peor que no ponerlo.
local function untap_glyph(bb, cx, cy, radius, color, bg)
  local r_out = radius
  local r_in = math.floor(radius * 0.58)
  fill_circle(bb, cx, cy, r_out, color)
  fill_circle(bb, cx, cy, r_in, bg)
  -- corte del anillo, arriba a la derecha
  bb:paintRect(cx, cy - r_out - 1, r_out + 2, math.floor(radius * 0.55), bg)
  -- punta de flecha
  local a = math.floor(radius * 0.62)
  fill_triangle(bb,
    cx + math.floor(radius * 0.18), cy - r_out - 1,
    cx + a + math.floor(radius * 0.45), cy - r_out - 1,
    cx + a, cy - r_out + math.floor(radius * 0.62), color)
end

-- Bote de basura: el orbe − cuando queda el último token.
local function trash_glyph(bb, cx, cy, size, color)
  local w = size
  local h = math.floor(size * 1.1)
  local x, y = cx - math.floor(w / 2), cy - math.floor(h / 2)
  local lid = math.max(2, math.floor(h * 0.14))
  bb:paintRect(x, y + lid, w, lid, color)                                  -- tapa
  bb:paintRect(cx - math.floor(w * 0.18), y, math.floor(w * 0.36), lid, color) -- asa
  local bx, bw = x + math.floor(w * 0.14), math.floor(w * 0.72)
  bb:paintRect(bx, y + 2 * lid + 1, bw, h - 2 * lid - 1, color)            -- cuerpo
  local slot = math.max(1, math.floor(w * 0.08))
  for _, fx in ipairs({ 0.28, 0.5, 0.72 }) do
    bb:paintRect(x + math.floor(w * fx) - math.floor(slot / 2),
      y + 3 * lid, slot, h - 4 * lid, WHITE)
  end
end

-- ---- texto ----

local function text_w(face, s, bold)
  return RenderText:sizeUtf8Text(0, 100000, face, s, true, bold and true or false).x
end

local function ellipsize(face, s, max_w, bold)
  if text_w(face, s, bold) <= max_w then return s end
  local out = s
  while #out > 1 do
    out = out:sub(1, #out - 1)
    if text_w(face, out .. "…", bold) <= max_w then return out .. "…" end
  end
  return out
end

-- Talla más grande que hace caber `s` en `max_w`. Sin esto, una etiqueta
-- como "UNTAP ALL" se sale del círculo en cuanto cambia el dpi o la fuente.
local function fit_face(s, max_w, start_px, min_px, bold)
  local size = start_px
  while size > min_px do
    local f = face_px(size)
    if RenderText:sizeUtf8Text(0, 100000, f, s, true, bold and true or false).x <= max_w then
      return f
    end
    size = size - 1
  end
  return face_px(min_px)
end

local function draw_text(bb, x, baseline, face, s, bold, color)
  RenderText:renderUtf8Text(bb, x, baseline, face, s, true, bold and true or false,
    color or BLACK)
end

local function draw_text_centered(bb, x, w, baseline, face, s, bold, color)
  local tw = text_w(face, s, bold)
  draw_text(bb, x + math.floor((w - tw) / 2), baseline, face, s, bold, color)
end

-- ---- íconos ----

local ICON_SIZES = { 96, 160, 224 }
local icon_cache = {}

local function best_size(target)
  local pick = ICON_SIZES[1]
  for _, s in ipairs(ICON_SIZES) do
    if s <= target then pick = s end
  end
  return pick
end

-- Devuelve BlitBuffer o nil. El plugin NO decide qué imagen va con cada
-- token: usa la clave que trae el archivo y busca esa imagen. Si la clave
-- viene vacía o no hay imagen, devuelve nil y el caller pinta un "?".
local function load_icon(plugin_dir, icon_key, target_px)
  if not icon_key or icon_key == "" or not plugin_dir then return nil end
  local size = best_size(target_px)
  local leaf = icon_key
  local key = leaf .. "@" .. size
  if icon_cache[key] ~= nil then return icon_cache[key] or nil end
  local path = plugin_dir .. "/assets/" .. leaf .. "-" .. size .. ".png"
  local ok, bb = pcall(function()
    return RenderImage:renderImageFile(path, false, target_px, target_px)
  end)
  if not ok or not bb then
    logger.warn("PaperTokens: no hay imagen para la clave", icon_key, "(" .. path .. ")")
    icon_cache[key] = false
    return nil
  end
  icon_cache[key] = bb
  return bb
end

-- Sin imagen se pinta un "?" grande, del mismo tamaño que tendría la
-- silueta. Nada de imagen genérica ni de aproximar por nombre: el "?" es
-- una señal deliberada de qué iconos faltan por dibujar.
--
-- Es un fallback de ARTE, no de datos: el token igual muestra su nombre y
-- sus contadores en la ficha, y su P/T y reglas en la vista expandida.
local function draw_icon(bb, box, def, plugin_dir)
  local side = math.floor(math.min(box.w, box.h) * 0.82)
  local icon = load_icon(plugin_dir, def.icon, side)
  if icon then
    bb:blitFrom(icon, box.x + math.floor((box.w - side) / 2),
      box.y + math.floor((box.h - side) / 2), 0, 0, side, side)
  else
    local face = face_px(math.max(16, math.floor(side * 0.86)))
    draw_text_centered(bb, box.x, box.w,
      box.y + math.floor(box.h / 2) + math.floor(side * 0.32), face, "?", true, BLACK)
  end
end

-- ---- píldora de contadores ----
-- Sin barra "/": esa notación es fuerza/resistencia. Destapados = badge
-- vertical sólido; tapeados = badge apaisado con contorno. El badge en 0
-- no se dibuja, igual que en la web.

function Render.pill(bb, rect, state, opts)
  local h = rect.h
  local pad = math.max(3, math.floor(h * metrics.pill_pad))
  local pad_x = math.max(pad, math.floor(h * metrics.pill_pad_x))
  local inner_h = h - 2 * pad
  local circle_d = inner_h
  local gap = math.max(4, math.floor(h * 0.09))

  local badges = {}
  if state.count_a > 0 then
    badges[#badges + 1] = { n = state.count_a, tapped = false,
      w = math.max(math.floor(inner_h * 0.78), 1), h = inner_h }
  end
  if state.count_b > 0 then
    badges[#badges + 1] = { n = state.count_b, tapped = true,
      w = math.floor(inner_h * 1.06), h = math.floor(inner_h * 0.74) }
  end

  local content_w = circle_d
  for _, b in ipairs(badges) do content_w = content_w + b.w + gap end
  local w = content_w + 2 * pad_x
  local x = rect.x + math.floor((rect.w - w) / 2)
  local y = rect.y

  fill_round_rect(bb, x, y, w, h, math.floor(h / 2), WHITE)
  stroke_round_rect(bb, x, y, w, h, math.max(2, math.floor(h * 0.06)),
    math.floor(h / 2), BLACK)

  local cx = x + pad_x
  for _, b in ipairs(badges) do
    local by = y + pad + math.floor((inner_h - b.h) / 2)
    local face = face_px(math.floor(b.h * 0.66))
    if b.tapped then
      fill_round_rect(bb, cx, by, b.w, b.h, math.floor(b.h * 0.28), WHITE)
      stroke_round_rect(bb, cx, by, b.w, b.h, math.max(2, math.floor(b.h * 0.10)),
        math.floor(b.h * 0.28), BLACK)
      draw_text_centered(bb, cx, b.w, by + math.floor(b.h * 0.76), face,
        tostring(b.n), true, BLACK)
    else
      fill_round_rect(bb, cx, by, b.w, b.h, math.floor(b.h * 0.22), BLACK)
      draw_text_centered(bb, cx, b.w, by + math.floor(b.h * 0.76), face,
        tostring(b.n), true, WHITE)
    end
    cx = cx + b.w + gap
  end

  -- botón de untap de ESTE tipo
  local ccx = cx + math.floor(circle_d / 2)
  local ccy = y + pad + math.floor(inner_h / 2)
  fill_circle(bb, ccx, ccy, math.floor(circle_d / 2), BLACK)
  untap_glyph(bb, ccx, ccy, math.floor(circle_d * 0.30), WHITE, BLACK)

  -- rect táctil del botón, para el hit-test del caller
  local d = circle_d
  return { x = ccx - math.floor(d / 2), y = ccy - math.floor(d / 2), w = d, h = d }
end

-- ---- carta ----

local function color_letter(def)
  if def.colors and #def.colors > 0 then
    return table.concat(def.colors)
  end
  return "C"
end
Render.color_letter = color_letter

-- En la vista mini sobra la palabra "Token": todo lo que está en la mesa lo
-- es. La expandida conserva la línea de tipo completa.
local function short_type(def)
  return (def.type_line or ""):gsub("Token%s+", "")
end
Render.short_type = short_type

function Render.card(bb, rect, def, opts)
  opts = opts or {}
  local w, h = rect.w, rect.h
  local m = metrics.card_boxes(rect)

  fill_round_rect(bb, rect.x, rect.y, w, h,
    math.floor(w * metrics.frame_radius), WHITE)
  stroke_round_rect(bb, rect.x, rect.y, w, h, m.bw,
    math.floor(w * metrics.frame_radius), BLACK)

  local bar_r = math.floor(w * metrics.bar_radius)
  local tpad = m.text_pad

  -- barra de título: nombre + letra de color
  local t = m.title
  local face_title = face_px(math.floor(t.h * 0.60))
  stroke_round_rect(bb, t.x, t.y, t.w, t.h, m.bar_bw, bar_r, BLACK)
  local letter = color_letter(def)
  local lw = text_w(face_title, letter, true)
  draw_text(bb, t.x + tpad, t.y + math.floor(t.h * 0.72), face_title,
    ellipsize(face_title, def.name, t.w - lw - 3 * tpad, true), true, BLACK)
  draw_text(bb, t.x + t.w - lw - tpad, t.y + math.floor(t.h * 0.72), face_title,
    letter, true, BLACK)

  -- barra de tipo (abajo), sin la palabra "Token"
  local tb = m.type_bar
  local face_type = face_px(math.floor(tb.h * 0.58))
  stroke_round_rect(bb, tb.x, tb.y, tb.w, tb.h, m.bar_bw, bar_r, BLACK)
  -- el badge de P/T se monta sobre esta barra por la derecha: el tipo se
  -- recorta antes de llegar ahí, en vez de pasar por debajo
  local type_room = tb.w - 2 * tpad
  if def.power ~= nil then
    type_room = type_room - math.floor(rect.w * 0.22)
  end
  draw_text(bb, tb.x + tpad, tb.y + math.floor(tb.h * 0.72), face_type,
    ellipsize(face_type, short_type(def), type_room, true), true, BLACK)

  -- caja de arte
  local art = m.art
  if art.h > 8 then
    stroke_round_rect(bb, art.x, art.y, art.w, art.h, m.bar_bw,
      math.floor(w * metrics.art_radius), BLACK)
    draw_icon(bb, art, def, opts.plugin_dir)

    -- badge de fuerza/resistencia, montado sobre el borde inferior del arte
    if def.power ~= nil then
      local pt = tostring(def.power) .. "/" .. tostring(def.toughness)
      local face_pt = face_px(math.floor(h * metrics.pt_font))
      local bwid = text_w(face_pt, pt, true) + 2 * tpad
      local bhei = math.floor(h * metrics.pt_h)
      local bx = art.x + art.w - bwid - math.floor(w * 0.025)
      local by = art.y + art.h - math.floor(bhei * metrics.pt_overhang)
      fill_round_rect(bb, bx - m.bar_bw, by - m.bar_bw, bwid + 2 * m.bar_bw,
        bhei + 2 * m.bar_bw, math.floor(w * 0.030), WHITE)
      fill_round_rect(bb, bx, by, bwid, bhei, math.floor(w * 0.028), BLACK)
      draw_text_centered(bb, bx, bwid, by + math.floor(bhei * 0.74), face_pt,
        pt, true, WHITE)
    end
  end
end

-- Orbes ± a los lados de la carta, montadas sobre el borde cuando la carta
-- es grande (como en la web) y corridas hacia afuera cuando es chica, para
-- no tapar el arte. Devuelve los rects táctiles { minus, plus }.
function Render.orbs(bb, card, diameter, is_last, cell_w)
  local r = math.floor(diameter / 2)
  local cy = card.y + math.floor(card.h / 2)
  local margin = math.max(0, math.floor((cell_w - card.w) / 2))
  local over = metrics.orb_overlap(diameter, margin)
  local lx = card.x - r + over
  local rx = card.x + card.w + r - over

  fill_circle(bb, lx, cy, r, BLACK)
  if is_last then
    trash_glyph(bb, lx, cy, math.floor(diameter * 0.42), WHITE)
  else
    bb:paintRect(lx - math.floor(r * 0.5), cy - math.max(2, math.floor(r * 0.09)),
      r, math.max(4, math.floor(r * 0.18)), WHITE)
  end

  fill_circle(bb, rx, cy, r, BLACK)
  local t = math.max(4, math.floor(r * 0.18))
  bb:paintRect(rx - math.floor(r * 0.5), cy - math.floor(t / 2), r, t, WHITE)
  bb:paintRect(rx - math.floor(t / 2), cy - math.floor(r * 0.5), t, r, WHITE)

  return
    { x = lx - r, y = cy - r, w = diameter, h = diameter },
    { x = rx - r, y = cy - r, w = diameter, h = diameter }
end

-- ---- vista expandida (long-press): solo lectura ----

function Render.expanded(bb, rect, def, opts)
  opts = opts or {}
  local w, h = rect.w, rect.h
  bb:paintRect(rect.x, rect.y, w, h, WHITE)

  local pad = math.max(8, math.floor(w * 0.045))
  local bw = math.max(3, math.floor(w * 0.008))
  local cx, cy = rect.x + pad, rect.y + pad
  local cw, ch = w - 2 * pad, h - 2 * pad
  stroke_round_rect(bb, cx, cy, cw, ch, bw, math.floor(w * 0.045), BLACK)

  local ipad = math.max(6, math.floor(cw * 0.030))
  local ix, iw = cx + ipad + bw, cw - 2 * (ipad + bw)
  local iy = cy + ipad + bw

  local title_h = math.max(30, math.floor(ch * 0.070))
  local face_title = face_px(math.floor(title_h * 0.60))
  stroke_round_rect(bb, ix, iy, iw, title_h, bw, math.floor(cw * 0.028), BLACK)
  local letter = color_letter(def)
  local lw = text_w(face_title, letter, true)
  draw_text(bb, ix + ipad, iy + math.floor(title_h * 0.72), face_title,
    ellipsize(face_title, def.name, iw - lw - 3 * ipad, true), true, BLACK)
  draw_text(bb, ix + iw - lw - ipad, iy + math.floor(title_h * 0.72), face_title,
    letter, true, BLACK)

  -- caja de reglas (abajo). Solo aquí se ve el texto de reglas.
  local rules_size = math.max(16, math.floor(ch * 0.030))
  local face_rules = face_px(rules_size)
  local rules = def.rules
  if not rules or rules == "" then rules = "Sin texto de reglas." end
  local line_h = math.floor(rules_size * 1.35)
  local lines = {}
  local cur = ""
  for word in rules:gmatch("%S+") do
    local try = (cur == "") and word or (cur .. " " .. word)
    if text_w(face_rules, try, false) <= iw - 2 * ipad then
      cur = try
    else
      lines[#lines + 1] = cur
      cur = word
    end
  end
  if cur ~= "" then lines[#lines + 1] = cur end
  local rules_h = #lines * line_h + 2 * ipad

  -- línea de tipo COMPLETA (con "Token"), encima de las reglas
  local type_h = math.max(24, math.floor(ch * 0.052))
  local face_type = face_px(math.floor(type_h * 0.55))
  local rules_y = cy + ch - ipad - bw - rules_h
  local type_y = rules_y - type_h - ipad

  local art_y = iy + title_h + ipad
  local art_h = type_y - ipad - art_y
  if art_h > 20 then
    local art = { x = ix, y = art_y, w = iw, h = art_h }
    stroke_round_rect(bb, art.x, art.y, art.w, art.h, bw,
      math.floor(cw * 0.035), BLACK)
    draw_icon(bb, art, def, opts.plugin_dir)
    if def.power ~= nil then
      local pt = tostring(def.power) .. "/" .. tostring(def.toughness)
      local face_pt = face_px(math.floor(ch * 0.045))
      local bwid = text_w(face_pt, pt, true) + 2 * ipad
      local bhei = math.floor(ch * 0.058)
      local bx = ix + iw - bwid - ipad
      local by = art.y + art.h - math.floor(bhei * 0.45)
      fill_round_rect(bb, bx - bw, by - bw, bwid + 2 * bw, bhei + 2 * bw,
        math.floor(cw * 0.028), WHITE)
      fill_round_rect(bb, bx, by, bwid, bhei, math.floor(cw * 0.026), BLACK)
      draw_text_centered(bb, bx, bwid, by + math.floor(bhei * 0.74), face_pt,
        pt, true, WHITE)
    end
  end

  stroke_round_rect(bb, ix, type_y, iw, type_h, bw, math.floor(cw * 0.028), BLACK)
  draw_text(bb, ix + ipad, type_y + math.floor(type_h * 0.70), face_type,
    ellipsize(face_type, def.type_line or "", iw - 2 * ipad, true), true, BLACK)

  stroke_round_rect(bb, ix, rules_y, iw, rules_h, bw, math.floor(cw * 0.030), BLACK)
  for i, line in ipairs(lines) do
    draw_text(bb, ix + ipad, rules_y + ipad + i * line_h - math.floor(line_h * 0.25),
      face_rules, line, false, BLACK)
  end

  local face_hint = face_px(math.max(13, math.floor(ch * 0.024)))
  draw_text_centered(bb, rect.x, w, rect.y + h - math.floor(pad * 0.35), face_hint,
    "Tap en cualquier parte para cerrar", false, BLACK)
end

Render.draw_text = draw_text
Render.draw_text_centered = draw_text_centered
Render.text_w = text_w
Render.ellipsize = ellipsize
Render.fill_circle = fill_circle
Render.stroke_round_rect = stroke_round_rect
Render.untap_glyph = untap_glyph
Render.draw_icon = draw_icon
Render.fit_face = fit_face

return Render
