-- core/metrics.lua — proporciones de la carta, como fracciones de su ancho
-- o alto. MÓDULO PURO: lo usan tanto el render de KOReader como la
-- previsualización SVG del Mac, para que no puedan divergir.
--
-- Los valores salen del CSS de la app web, normalizados sobre el ancho de
-- carta de 315 px que tiene la vista n=1 en un teléfono de 375 px.

local M = {}

-- fracciones del ANCHO de la carta
M.pad = 0.032          -- padding interior del marco      (10/315)
M.gap = 0.025          -- separación entre bloques         (8/315)
M.frame_bw = 0.010     -- grosor del marco                 (3/315)
M.bar_bw = 0.008       -- grosor de las barras internas    (2.5/315)
M.frame_radius = 0.057 -- radio del marco                  (18/315)
M.bar_radius = 0.032   -- radio de las barras              (10/315)
M.art_radius = 0.038   -- radio de la caja de arte         (12/315)
M.text_pad = 0.028     -- padding horizontal del texto     (9/315)

-- fracciones del ALTO de la carta
M.title_h = 0.088      -- barra de título                  (39/440)
M.type_h = 0.070       -- barra de tipo                    (31/440)
M.pt_h = 0.072         -- badge de fuerza/resistencia      (32/440)
M.pt_font = 0.052      -- talla del texto de P/T           (23/440)

-- el badge de P/T se monta sobre el borde inferior del arte
M.pt_overhang = 0.45

-- proporciones internas de la píldora de contadores
M.pill_pad = 0.10          -- vertical, del alto de la píldora
M.pill_pad_x = 0.30        -- horizontal: libra las tapas redondas del óvalo
M.pill_badge_w = 0.78      -- del alto interior (badge destapados)
M.pill_tapped_w = 1.06     -- del alto interior (badge tapeados, apaisado)
M.pill_tapped_h = 0.74

-- Cuánto invade la orbe el interior de la carta.
--
-- La web la monta a media orbe sobre el borde, pero ahí la orbe mide un 15%
-- del ancho de la carta. Aquí el mínimo táctil físico puede ser la mitad de
-- una carta chica, y montarla taparía el arte. La regla: la orbe se corre
-- hacia afuera todo lo que permita el margen libre de su celda, tocando el
-- marco apenas; si el margen no alcanza, invade más, nunca más de media
-- orbe. En cartas grandes queda como en la web; en las chicas se sale al
-- espacio sobrante en vez de comerse el arte.
function M.orb_overlap(orb, margin)
  local touch = math.ceil(orb * 0.12)
  local needed = orb - (margin or 0)
  return math.max(0, math.min(math.floor(orb / 2), math.max(touch, needed)))
end

function M.card_boxes(card)
  local w, h = card.w, card.h
  local pad = math.max(4, math.floor(w * M.pad))
  local gap = math.max(3, math.floor(w * M.gap))
  local bw = math.max(2, math.floor(w * M.frame_bw))
  local ix = card.x + pad + bw
  local iy = card.y + pad + bw
  local iw = w - 2 * (pad + bw)
  local title_h = math.max(20, math.floor(h * M.title_h))
  local type_h = math.max(18, math.floor(h * M.type_h))
  local type_y = card.y + h - pad - bw - type_h
  local art_y = iy + title_h + gap
  return {
    pad = pad, gap = gap, bw = bw,
    bar_bw = math.max(2, math.floor(w * M.bar_bw)),
    text_pad = math.max(4, math.floor(w * M.text_pad)),
    title = { x = ix, y = iy, w = iw, h = title_h },
    art = { x = ix, y = art_y, w = iw, h = type_y - gap - art_y },
    type_bar = { x = ix, y = type_y, w = iw, h = type_h },
  }
end

return M
