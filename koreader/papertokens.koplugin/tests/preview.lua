-- Previsualización SVG de la sesión, para ver el layout sin el Kindle.
--   luajit tests/preview.lua > /tmp/preview.svg
--
-- Usa los MISMOS core/layout.lua y core/metrics.lua que el render del
-- dispositivo, así que lo que se ve aquí es la geometría real. Lo único que
-- no reproduce es el arte de los íconos (aquí van como iniciales).

package.path = "./?.lua;" .. package.path

local layout = require("core/layout")
local metrics = require("core/metrics")
local config = require("config/thresholds")

local W, H, DPI = 1072, 1448, 300
local function px(mm) return math.floor(mm * DPI / 25.4 + 0.5) end

local HEADER = px(config.header_mm)
local CAROUSEL = px(config.carousel_mm)
local ORB = px(config.orb_mm)
local PILL = px(config.pill_mm)
local GAP = px(2)

local defs = require("tests/fixture").tokens
-- Estado de ejemplo: cuatro tipos con cantidades distintas.
local active = {
  { def = defs[1], a = 2, b = 1 },
  { def = defs[4], a = 3, b = 0 },
  { def = defs[6], a = 1, b = 0 },
  { def = defs[5], a = 0, b = 2 },
}

local out = {}
local function emit(s) out[#out + 1] = s end
local function esc(s) return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end

local function rrect(x, y, w, h, r, fill, stroke, sw)
  emit(string.format(
    '<rect x="%d" y="%d" width="%d" height="%d" rx="%d" fill="%s" stroke="%s" stroke-width="%d"/>',
    x, y, w, h, r, fill or "none", stroke or "none", sw or 0))
end
local function circle(cx, cy, r, fill)
  emit(string.format('<circle cx="%d" cy="%d" r="%d" fill="%s"/>', cx, cy, r, fill))
end
local function text(x, y, size, s, anchor, fill, weight)
  emit(string.format(
    '<text x="%d" y="%d" font-family="Helvetica,Arial,sans-serif" font-size="%d" ' ..
    'font-weight="%s" fill="%s" text-anchor="%s">%s</text>',
    x, y, size, weight or "bold", fill or "#000", anchor or "start", esc(s)))
end

local PAD = math.floor((H - W) / 2)
emit(string.format('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">', H, H, H, H))
emit(string.format('<rect width="%d" height="%d" fill="#f2f2f2"/>', H, H))
emit(string.format('<g transform="translate(%d,0)">', PAD))
emit(string.format('<rect width="%d" height="%d" fill="#fff"/>', W, H))

-- ---- header ----
local hpad = math.floor(HEADER * 0.12)
local bh = HEADER - 2 * hpad
local bwid = math.floor(W * 0.24)
rrect(hpad, hpad, bwid, bh, math.floor(bh * 0.22), "none", "#000", 3)
text(hpad + math.floor(bwid / 2), hpad + math.floor(bh * 0.42), math.floor(HEADER * 0.17), "Reiniciar", "middle")
text(hpad + math.floor(bwid / 2), hpad + math.floor(bh * 0.78), math.floor(HEADER * 0.17), "partida", "middle")
local ex = W - hpad - bwid
rrect(ex, hpad, bwid, bh, math.floor(bh * 0.22), "none", "#000", 3)
text(ex + math.floor(bwid / 2), hpad + math.floor(bh * 0.62), math.floor(HEADER * 0.17), "Salir", "middle")
local ccx, ccy, cd = math.floor(W / 2), math.floor(HEADER / 2), bh
circle(ccx, ccy, math.floor(cd / 2), "#000")
text(ccx, ccy - math.floor(cd * 0.02), math.floor(cd * 0.30), "↺", "middle", "#fff")
text(ccx, ccy + math.floor(cd * 0.36), math.floor(cd * 0.13), "UNTAP ALL", "middle", "#fff")
emit(string.format('<rect x="0" y="%d" width="%d" height="3" fill="#000"/>', HEADER - 3, W))

-- ---- zona activa ----
local content = { x = 0, y = HEADER, w = W, h = H - HEADER - CAROUSEL }
local zones = layout.layout(content.w, content.h, #active,
  { pill_h = PILL, gap = GAP, orb = ORB })

for i, t in ipairs(active) do
  local z = zones[i]
  local card = { x = z.card.x, y = z.card.y + content.y, w = z.card.w, h = z.card.h }
  local pill = { x = z.pill.x, y = z.pill.y + content.y, w = z.pill.w, h = z.pill.h }
  local m = metrics.card_boxes(card)
  local cw, chh = card.w, card.h

  -- píldora: badges + botón de untap del tipo
  local ppad = math.max(3, math.floor(pill.h * metrics.pill_pad))
  local ppad_x = math.max(ppad, math.floor(pill.h * metrics.pill_pad_x))
  local inner = pill.h - 2 * ppad
  local pgap = math.max(4, math.floor(pill.h * 0.09))
  local badges = {}
  if t.a > 0 then badges[#badges + 1] = { n = t.a, w = math.floor(inner * metrics.pill_badge_w), h = inner, tapped = false } end
  if t.b > 0 then badges[#badges + 1] = { n = t.b, w = math.floor(inner * metrics.pill_tapped_w), h = math.floor(inner * metrics.pill_tapped_h), tapped = true } end
  local cwid = inner
  for _, b in ipairs(badges) do cwid = cwid + b.w + pgap end
  local pw = cwid + 2 * ppad_x
  local pxx = card.x + math.floor((cw - pw) / 2)
  rrect(pxx, pill.y, pw, pill.h, math.floor(pill.h / 2), "#fff", "#000", math.max(2, math.floor(pill.h * 0.06)))
  local bxx = pxx + ppad_x
  for _, b in ipairs(badges) do
    local byy = pill.y + ppad + math.floor((inner - b.h) / 2)
    if b.tapped then
      rrect(bxx, byy, b.w, b.h, math.floor(b.h * 0.28), "#fff", "#000", math.max(2, math.floor(b.h * 0.10)))
      text(bxx + math.floor(b.w / 2), byy + math.floor(b.h * 0.76), math.floor(b.h * 0.66), tostring(b.n), "middle", "#000")
    else
      rrect(bxx, byy, b.w, b.h, math.floor(b.h * 0.22), "#000")
      text(bxx + math.floor(b.w / 2), byy + math.floor(b.h * 0.76), math.floor(b.h * 0.66), tostring(b.n), "middle", "#fff")
    end
    bxx = bxx + b.w + pgap
  end
  circle(bxx + math.floor(inner / 2), pill.y + ppad + math.floor(inner / 2), math.floor(inner / 2), "#000")
  text(bxx + math.floor(inner / 2), pill.y + ppad + math.floor(inner * 0.70), math.floor(inner * 0.62), "↺", "middle", "#fff")

  -- marco de la carta
  rrect(card.x, card.y, cw, chh, math.floor(cw * metrics.frame_radius), "#fff", "#000", m.bw)
  local bar_r = math.floor(cw * metrics.bar_radius)
  rrect(m.title.x, m.title.y, m.title.w, m.title.h, bar_r, "none", "#000", m.bar_bw)
  text(m.title.x + m.text_pad, m.title.y + math.floor(m.title.h * 0.72),
    math.floor(m.title.h * 0.60), t.def.name)
  local letter = (#t.def.colors > 0) and table.concat(t.def.colors) or "C"
  text(m.title.x + m.title.w - m.text_pad, m.title.y + math.floor(m.title.h * 0.72),
    math.floor(m.title.h * 0.60), letter, "end")

  rrect(m.art.x, m.art.y, m.art.w, m.art.h, math.floor(cw * metrics.art_radius), "none", "#000", m.bar_bw)
  -- sin clave de icono el dispositivo pinta un "?"; aquí se refleja igual
  local leaf = (t.def.icon ~= "") and t.def.icon:sub(1, 2):upper() or "?"
  text(m.art.x + math.floor(m.art.w / 2), m.art.y + math.floor(m.art.h * 0.60),
    math.floor(m.art.h * 0.45), leaf, "middle", "#d9d9d9")

  rrect(m.type_bar.x, m.type_bar.y, m.type_bar.w, m.type_bar.h, bar_r, "none", "#000", m.bar_bw)
  local tl = (t.def.type_line:gsub("Token%s+", ""))
  if t.def.power then
    local room = m.type_bar.w - 2 * m.text_pad - math.floor(cw * 0.22)
    local maxch = math.max(4, math.floor(room / (m.type_bar.h * 0.32)))
    if #tl > maxch then tl = tl:sub(1, maxch) .. "…" end
  end
  text(m.type_bar.x + m.text_pad, m.type_bar.y + math.floor(m.type_bar.h * 0.72),
    math.floor(m.type_bar.h * 0.58), tl)

  if t.def.power then
    local pt = t.def.power .. "/" .. t.def.toughness
    local fs = math.floor(chh * metrics.pt_font)
    local pwid = math.floor(fs * 2.2) + 2 * m.text_pad
    local phei = math.floor(chh * metrics.pt_h)
    local pbx = m.art.x + m.art.w - pwid - math.floor(cw * 0.025)
    local pby = m.art.y + m.art.h - math.floor(phei * metrics.pt_overhang)
    rrect(pbx - m.bar_bw, pby - m.bar_bw, pwid + 2 * m.bar_bw, phei + 2 * m.bar_bw, math.floor(cw * 0.030), "#fff")
    rrect(pbx, pby, pwid, phei, math.floor(cw * 0.028), "#000")
    text(pbx + math.floor(pwid / 2), pby + math.floor(phei * 0.74), fs, pt, "middle", "#fff")
  end

  -- orbes: misma regla de invasión que el render del dispositivo
  local ocy = card.y + math.floor(chh / 2)
  local margin = math.max(0, math.floor((z.cell.w - cw) / 2))
  local over = metrics.orb_overlap(ORB, margin)
  local olx = card.x - math.floor(ORB / 2) + over
  local orx = card.x + cw + math.floor(ORB / 2) - over
  circle(olx, ocy, math.floor(ORB / 2), "#000")
  circle(orx, ocy, math.floor(ORB / 2), "#000")
  local last = (t.a + t.b) == 1
  text(olx, ocy + math.floor(ORB * 0.18), math.floor(ORB * 0.55), last and "🗑" or "−", "middle", "#fff")
  text(orx, ocy + math.floor(ORB * 0.18), math.floor(ORB * 0.55), "+", "middle", "#fff")
end

-- ---- carrusel ----
local y0 = H - CAROUSEL
emit(string.format('<rect x="0" y="%d" width="%d" height="3" fill="#000"/>', y0, W))
local chev = math.floor(CAROUSEL * 0.62)
emit(string.format('<rect x="0" y="%d" width="%d" height="%d" fill="#000"/>', y0 + 3, chev, CAROUSEL - 3))
text(math.floor(chev / 2), y0 + math.floor(CAROUSEL * 0.64), math.floor(CAROUSEL * 0.42), "<", "middle", "#fff")
emit(string.format('<rect x="%d" y="%d" width="%d" height="%d" fill="#000"/>', W - chev, y0 + 3, chev, CAROUSEL - 3))
text(W - math.floor(chev / 2), y0 + math.floor(CAROUSEL * 0.64), math.floor(CAROUSEL * 0.42), ">", "middle", "#fff")

local band_x, band_w = chev, W - 2 * chev
local slot = math.floor(band_w / 4)
local side = math.min(math.floor(CAROUSEL * 0.58), slot - 8)
for k = 0, 3 do
  local def = defs[k + 1]
  local sx = band_x + k * slot
  local ix = sx + math.floor((slot - side) / 2)
  local iy = y0 + math.floor(CAROUSEL * 0.10)
  local in_play = (k == 0 or k == 3)
  rrect(ix, iy, side, side, math.floor(side * 0.22), in_play and "#000" or "#fff", "#000", 3)
  text(ix + math.floor(side / 2), iy + math.floor(side * 0.66), math.floor(side * 0.42),
    ((def.icon ~= "") and def.icon:sub(1,2):upper() or "?"), "middle", in_play and "#fff" or "#d9d9d9")
  local lbl = def.name
  local maxch = math.max(4, math.floor((slot - 6) / (CAROUSEL * 0.062)))
  if #lbl > maxch then lbl = lbl:sub(1, maxch) .. "…" end
  text(sx + math.floor(slot / 2), y0 + CAROUSEL - math.floor(CAROUSEL * 0.08),
    math.floor(CAROUSEL * 0.11), lbl, "middle", "#000", "normal")
end

emit("</g></svg>")
print(table.concat(out, "\n"))
