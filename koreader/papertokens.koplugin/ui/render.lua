-- ui/render.lua — dibujo de una zona sobre el blitbuffer. DESECHABLE:
-- depende de KOReader. La geometría ya viene resuelta por core/layout.lua.
--
-- API verificada en KOReader v2026.07.1 (Kindle PW3):
--   bb:paintRect(x, y, w, h, color)
--   bb:paintBorder(x, y, w, h, bw, color, radius)
--   bb:invertRect(x, y, w, h)
--   bb:blitFrom(src, dx, dy, ox, oy, w, h)
--   RenderText:renderUtf8Text(bb, x, baseline, face, text, kerning, bold, fgcolor)
--   RenderText:sizeUtf8Text(x, width, face, text, kerning, bold) -> { x = ancho }
--   RenderImage:renderImageFile(path, want_frames, width, height) -> BlitBuffer
--   Font:getFace(name, size)  ← size se escala internamente con
--   Screen:scaleBySize(), por eso aquí se invierte esa escala para poder
--   pedir tallas en píxeles físicos reales.

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local RenderImage = require("ui/renderimage")
local RenderText = require("ui/rendertext")
local Screen = require("device").screen
local logger = require("logger")

local Render = {}

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE

-- ---- tallas físicas ----

-- Font:getFace escala su argumento con Screen:scaleBySize(). Para pedir una
-- talla en píxeles reales hay que invertir esa escala. Se mide con una
-- sonda grande en vez de leer internals, así sobrevive a cambios de versión.
local scale_probe = Screen:scaleBySize(1000) / 1000

local face_cache = {}
local function face_px(px, bold)
    local design = math.max(8, math.floor(px / scale_probe + 0.5))
    local key = design .. (bold and "b" or "r")
    if not face_cache[key] then
        face_cache[key] = Font:getFace(bold and "cfont" or "cfont", design)
    end
    return face_cache[key]
end

function Render.mm_to_px(mm, dpi)
    return math.floor(mm * dpi / 25.4 + 0.5)
end

-- ---- íconos ----

-- Pre-rasterizados en el Mac (assets/*.png). Nunca se rasteriza SVG aquí.
local ICON_SIZES = { 96, 160, 224 }
local icon_cache = {}

local function icon_path(plugin_dir, art_key, size)
    local leaf = art_key:match("([^/]+)$") or art_key
    return plugin_dir .. "/assets/" .. leaf .. "-" .. size .. ".png"
end

-- Mayor tamaño pre-rasterizado que quepa en `target` px; si ninguno cabe,
-- el más chico (KOReader lo escala al vuelo al blitear).
local function best_size(target)
    local pick = ICON_SIZES[1]
    for _, s in ipairs(ICON_SIZES) do
        if s <= target then pick = s end
    end
    return pick
end

-- Devuelve un BlitBuffer o nil. nil ⇒ el caller DEBE caer al nombre en
-- tipografía: jamás una caja vacía.
local function load_icon(plugin_dir, art_key, target_px)
    if not art_key then return nil end
    local size = best_size(target_px)
    local key = art_key .. "@" .. size
    if icon_cache[key] ~= nil then
        return icon_cache[key] or nil
    end
    local path = icon_path(plugin_dir, art_key, size)
    local ok, bb = pcall(function()
        return RenderImage:renderImageFile(path, false, target_px, target_px)
    end)
    if not ok or not bb then
        logger.warn("PaperTokens: falta el asset", path, "— fallback tipográfico")
        icon_cache[key] = false
        return nil
    end
    icon_cache[key] = bb
    return bb
end

-- ---- indicadores de color ----
-- Dos mecanismos alternables para poder compararlos en pantalla real.

local COLOR_LETTER = { W = "W", U = "U", B = "B", R = "R", G = "G" }

-- Tramas distinguibles en monocromo: paso y orientación distintos por color.
local HATCH = {
    W = { kind = "empty" },
    U = { kind = "vertical", step = 4 },
    B = { kind = "solid" },
    R = { kind = "diagonal", step = 5 },
    G = { kind = "horizontal", step = 4 },
    C = { kind = "checker", step = 5 },
}

local function paint_hatch(bb, x, y, w, h, spec)
    bb:paintBorder(x, y, w, h, 2, BLACK, 3)
    local ix, iy, iw, ih = x + 2, y + 2, w - 4, h - 4
    if iw <= 0 or ih <= 0 then return end
    if spec.kind == "solid" then
        bb:paintRect(ix, iy, iw, ih, BLACK)
    elseif spec.kind == "vertical" then
        for px = ix, ix + iw - 1, spec.step do
            bb:paintRect(px, iy, 2, ih, BLACK)
        end
    elseif spec.kind == "horizontal" then
        for py = iy, iy + ih - 1, spec.step do
            bb:paintRect(ix, py, iw, 2, BLACK)
        end
    elseif spec.kind == "diagonal" then
        for off = 0, iw + ih, spec.step do
            for t = 0, math.min(off, ih - 1) do
                local px = ix + off - t
                if px >= ix and px < ix + iw then
                    bb:paintRect(px, iy + t, 2, 1, BLACK)
                end
            end
        end
    elseif spec.kind == "checker" then
        local on = false
        for py = iy, iy + ih - 1, spec.step do
            local row = on
            for px = ix, ix + iw - 1, spec.step do
                if row then bb:paintRect(px, py, spec.step, spec.step, BLACK) end
                row = not row
            end
            on = not on
        end
    end
end

-- colors es LISTA: multicolor {"B","G"} e incoloro {} son casos reales.
-- Se reserva espacio para hasta 3 indicadores.
local function paint_colors(bb, x, y, size, colors, mode)
    local list = colors
    if not list or #list == 0 then list = { "C" } end
    local n = math.min(#list, 3)
    local gap = math.max(2, math.floor(size / 6))
    for i = 1, n do
        local cx = x + (i - 1) * (size + gap)
        local c = list[i]
        if mode == "hatch" then
            paint_hatch(bb, cx, y, size, size, HATCH[c] or HATCH.C)
        else
            bb:paintBorder(cx, y, size, size, 2, BLACK, 3)
            local face = face_px(math.floor(size * 0.66), true)
            local letter = COLOR_LETTER[c] or "C"
            local tw = RenderText:sizeUtf8Text(0, size, face, letter, true, true).x
            local baseline = y + math.floor(size * 0.75)
            RenderText:renderUtf8Text(bb, cx + math.floor((size - tw) / 2), baseline,
                face, letter, true, true, BLACK)
        end
    end
    return n * size + (n - 1) * gap
end

-- ---- contadores ----
-- Sin barra "/": esa notación es fuerza/resistencia y confundirlas en
-- combate es un error caro. Destapados = caja sólida; tapeados = caja
-- apaisada con contorno (el eco de girar la carta).

local function paint_counts(bb, x, y, h, count_a, count_b)
    local face = face_px(math.floor(h * 0.72), true)
    local w_a = math.floor(h * 0.72)
    bb:paintRect(x, y, w_a, h, BLACK)
    local ta = tostring(count_a)
    local tw = RenderText:sizeUtf8Text(0, w_a, face, ta, true, true).x
    RenderText:renderUtf8Text(bb, x + math.floor((w_a - tw) / 2),
        y + math.floor(h * 0.78), face, ta, true, true, WHITE)

    local gap = math.max(3, math.floor(h * 0.16))
    local bx = x + w_a + gap
    local bh = math.floor(h * 0.74)
    local bw = math.floor(h * 0.95)
    local by = y + math.floor((h - bh) / 2)
    bb:paintBorder(bx, by, bw, bh, 2, BLACK, 3)
    local tb = tostring(count_b)
    local face_b = face_px(math.floor(bh * 0.68), true)
    local twb = RenderText:sizeUtf8Text(0, bw, face_b, tb, true, true).x
    RenderText:renderUtf8Text(bb, bx + math.floor((bw - twb) / 2),
        by + math.floor(bh * 0.76), face_b, tb, true, true, BLACK)

    return w_a + gap + bw
end

local function ellipsize(face, text, max_w)
    if RenderText:sizeUtf8Text(0, max_w, face, text, true, false).x <= max_w then
        return text
    end
    local s = text
    while #s > 1 do
        s = s:sub(1, #s - 1)
        if RenderText:sizeUtf8Text(0, max_w, face, s .. "…", true, false).x <= max_w then
            return s .. "…"
        end
    end
    return s
end

-- ---- zona completa ----

-- rect: { x, y, w, h, tier } de core/layout.lua
-- def/state: core/model.lua
-- opts: { active, color_mode = "letter"|"hatch", plugin_dir, dim }
function Render.zone(bb, rect, def, state, opts)
    opts = opts or {}
    local x, y, w, h = rect.x, rect.y, rect.w, rect.h
    local pad = math.max(4, math.floor(math.min(w, h) * 0.05))

    bb:paintRect(x, y, w, h, WHITE)
    local bw = opts.active and 5 or 2
    bb:paintBorder(x + 1, y + 1, w - 2, h - 2, bw, BLACK, 8)

    local ix = x + pad + bw
    local iy = y + pad + bw
    local iw = w - 2 * (pad + bw)
    local ih = h - 2 * (pad + bw)
    if iw <= 0 or ih <= 0 then return end

    if rect.tier == "MINIMAL" then
        -- cantidad sola
        local ch = math.min(ih, math.floor(iw * 0.5))
        paint_counts(bb, ix, iy + math.floor((ih - ch) / 2), ch, state.count_a, state.count_b)
    elseif rect.tier == "COMPACT" then
        -- ícono + cantidad + indicador de color
        local ch = math.max(16, math.floor(ih * 0.34))
        local icon_side = math.min(iw, ih - ch - pad)
        if icon_side > 12 then
            local icon = load_icon(opts.plugin_dir, def.art_key, icon_side)
            if icon then
                bb:blitFrom(icon, ix + math.floor((iw - icon_side) / 2), iy, 0, 0,
                    icon_side, icon_side)
            else
                local face = face_px(math.floor(icon_side * 0.3), true)
                local name = ellipsize(face, def.name, iw)
                RenderText:renderUtf8Text(bb, ix, iy + math.floor(icon_side * 0.5),
                    face, name, true, true, BLACK)
            end
        end
        local row_y = iy + ih - ch
        local used = paint_counts(bb, ix, row_y, ch, state.count_a, state.count_b)
        paint_colors(bb, ix + used + pad, row_y + math.floor(ch * 0.15),
            math.floor(ch * 0.7), def.colors, opts.color_mode)
    else
        -- FULL: ícono + nombre + P/T + cantidad + indicador de color
        local name_h = math.max(18, math.floor(ih * 0.13))
        local face_name = face_px(name_h, true)
        RenderText:renderUtf8Text(bb, ix, iy + name_h,
            face_name, ellipsize(face_name, def.name, iw), true, true, BLACK)

        local ch = math.max(22, math.floor(ih * 0.22))
        local body_y = iy + name_h + pad
        local body_h = ih - (name_h + pad) - (ch + pad)
        local icon_side = math.min(iw, body_h)
        if icon_side > 16 then
            local icon = load_icon(opts.plugin_dir, def.art_key, icon_side)
            if icon then
                bb:blitFrom(icon, ix + math.floor((iw - icon_side) / 2), body_y, 0, 0,
                    icon_side, icon_side)
            else
                local face = face_px(math.floor(body_h * 0.22), false)
                RenderText:renderUtf8Text(bb, ix, body_y + math.floor(body_h * 0.5),
                    face, ellipsize(face, def.name, iw), true, false, BLACK)
            end
        end

        -- P/T: solo criaturas
        if def.power ~= nil then
            local pt = tostring(def.power) .. "/" .. tostring(def.toughness)
            local face_pt = face_px(math.floor(ch * 0.62), true)
            local tw = RenderText:sizeUtf8Text(0, iw, face_pt, pt, true, true).x
            local px = ix + iw - tw - pad
            local py = body_y + body_h - math.floor(ch * 0.7)
            bb:paintRect(px - pad, py - math.floor(ch * 0.6), tw + 2 * pad,
                math.floor(ch * 0.8), BLACK)
            RenderText:renderUtf8Text(bb, px, py, face_pt, pt, true, true, WHITE)
        end

        local row_y = iy + ih - ch
        local used = paint_counts(bb, ix, row_y, ch, state.count_a, state.count_b)
        paint_colors(bb, ix + used + pad, row_y + math.floor(ch * 0.15),
            math.floor(ch * 0.7), def.colors, opts.color_mode)
    end

    -- Cantidad total en 0: se ATENÚA, no se elimina ni recoloca (regla dura).
    if opts.dim then
        local step = 3
        for py = y + 2, y + h - 3, step do
            bb:paintRect(x + 2, py, w - 4, 1, WHITE)
        end
    end
end

Render.face_px = face_px

return Render
