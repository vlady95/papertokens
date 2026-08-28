-- ui/view.lua — la sesión de la app web corriendo en el Kindle.
-- DESECHABLE: todo lo portable vive en core/.
--
-- Pantalla vertical (como la web, mobile-first), toque directo sobre los
-- elementos, y las mismas tres zonas de arriba a abajo:
--   header  : Reiniciar partida | UNTAP ALL | Salir   (los dos con modal)
--   activa  : 1..4 cartas, proporción de carta, nunca estiradas
--   carrusel: catálogo completo, paginado por taps con chevrones negros
--
-- Gestos: tap en la carta = tapear un token; long-press = vista expandida
-- (solo lectura, se cierra con un tap en cualquier parte); orbe − destruye
-- (tapeados primero, bote de basura con el último); orbe + crea; botón de
-- la píldora destapa ese tipo; tap en una miniatura la pone en juego.
--
-- API verificada en KOReader v2026.07.1 (Kindle PW3):
--   UIManager:setDirty(widget, refreshtype, refreshregion, refreshdither)
--     refreshtype ∈ "full"|"flashpartial"|"flashui"|"partial"|"ui"|"fast"|"a2"
--   UIManager:nextTick(cb) corre tras el ciclo de repintado (instrumentación)
--   InputContainer:registerTouchZones{...} resuelve sus ratios AL REGISTRAR;
--     por eso aquí se registra una sola zona de pantalla completa y el
--     hit-test se hace a mano contra los rects vigentes: así el reflow no
--     obliga a re-registrar nada.
--   Las coordenadas táctiles ya llegan rotadas (adjustGesCoordinate).
--   El gesto "hold" dispara con HOLD_INTERVAL_MS = 500 global.

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local time = require("ui/time")

local Screen = Device.screen

local layout = require("core/layout")
local registry = require("core/registry")
local session = require("core/session")
local Render = require("ui/render")

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE

local CAROUSEL_PAGE = 4

local View = InputContainer:extend{
    name = "papertokens_view",
    covers_fullscreen = true,
}

local function hit(rect, x, y)
    return rect and x >= rect.x and x < rect.x + rect.w
        and y >= rect.y and y < rect.y + rect.h
end

function View:init()
    self.page = 0
    -- El mazo viene del archivo .txt; el catálogo completo va al carrusel y
    -- la zona activa arranca VACÍA: qué entra en juego se elige aquí, en la
    -- mesa, no en la computadora.
    self.mark_timer = nil
    self.expanded = nil     -- def mostrada en la vista expandida
    self.modal = nil        -- "reset" | "exit"
    self.partial_mode = self.partial_mode or "fast"
    self.log = {}

    self.saved_rotation = Screen:getRotationMode()
    Screen:setRotationMode(Screen.DEVICE_ROTATED_UPRIGHT) -- vertical, como la web

    self:computeGeometry()
    self:scheduleUsageMark()
    self:registerTouchZones({
        {
            id = "papertokens_tap",
            ges = "tap",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(ges) return self:onTap(ges) end,
        },
        {
            id = "papertokens_hold",
            ges = "hold",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(ges) return self:onHold(ges) end,
        },
    })
end

-- La marca de uso se escribe al CRUZAR los diez minutos, no al cerrar la
-- sesión: una sesión más corta es una apertura accidental, y si solo se
-- guardara al salir nunca se guardaría.
function View:scheduleUsageMark()
    if not self.on_used then return end
    self.mark_timer = function()
        self.on_used(self.session.profile.id, os.time())
        self.mark_timer = nil
    end
    UIManager:scheduleIn(registry.SESSION_MARK_SECONDS, self.mark_timer)
end

-- ---- geometría ----

function View:computeGeometry()
    local dpi = Screen:getDPI()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dpi, self.screen_w, self.screen_h = dpi, sw, sh
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }

    local mm = function(v) return Render.mm_to_px(v, dpi) end
    self.header_h = mm(self.config.header_mm or 22)
    self.carousel_h = mm(self.config.carousel_mm or 22)
    self.orb_d = mm(self.config.orb_mm or 11)
    self.pill_h = mm(self.config.pill_mm or 11)
    self.gap = mm(2)

    self.content = {
        x = 0, y = self.header_h, w = sw,
        h = sh - self.header_h - self.carousel_h,
    }
    self:reflowLayout()
end

function View:reflowLayout()
    local n = #self.session.active
    self.zones = {}
    if n == 0 then return end
    local raw = layout.layout(self.content.w, self.content.h, n, {
        pill_h = self.pill_h, gap = self.gap, orb = self.orb_d,
    })
    for i, z in ipairs(raw) do
        local function shift(r)
            return { x = r.x + self.content.x, y = r.y + self.content.y,
                     w = r.w, h = r.h }
        end
        self.zones[i] = { cell = shift(z.cell), pill = shift(z.pill), card = shift(z.card) }
    end
end

function View:zoneGeom(i)
    local z = self.zones[i]
    if not z then return self.dimen end
    -- el rect a refrescar incluye píldora y orbes, no solo la carta
    local pad = math.floor(self.orb_d / 2) + 4
    return Geom:new{
        x = math.max(0, z.cell.x - pad), y = z.cell.y,
        w = math.min(self.screen_w, z.cell.w + 2 * pad), h = z.cell.h,
    }
end

-- ---- input ----

function View:onTap(ges)
    local x, y = ges.pos.x, ges.pos.y

    -- la vista expandida se cierra con un tap en cualquier parte
    if self.expanded then
        self.expanded = nil
        self:refresh("full", self.dimen, "cerrar expandida")
        return true
    end

    if self.modal then return self:onModalTap(x, y) end

    -- header
    if y < self.header_h then
        if hit(self.hit_reset, x, y) then
            self.modal = "reset"
            self:refresh("full", self.dimen, "modal reiniciar")
        elseif hit(self.hit_exit, x, y) then
            self.modal = "exit"
            self:refresh("full", self.dimen, "modal salir")
        elseif hit(self.hit_untap_all, x, y) then
            self:apply(session.untap_all(self.session), "untap all")
        end
        return true
    end

    -- carrusel
    if y >= self.screen_h - self.carousel_h then
        if hit(self.hit_prev, x, y) then
            self.page = (self.page - 1) % self:pageCount()
            self:refresh(self.partial_mode, self:carouselGeom(), "carrusel <")
        elseif hit(self.hit_next, x, y) then
            self.page = (self.page + 1) % self:pageCount()
            self:refresh(self.partial_mode, self:carouselGeom(), "carrusel >")
        else
            for _, m in ipairs(self.hit_minis or {}) do
                if hit(m, x, y) then
                    self:apply(session.create(self.session, m.def_index),
                        "crear " .. m.def_index)
                    break
                end
            end
        end
        return true
    end

    -- zona activa: orbes, píldora y carta
    for i, z in ipairs(self.zones) do
        if hit(z.hit_minus, x, y) then
            self:apply(session.destroy(self.session, i), "destruir " .. i)
            return true
        elseif hit(z.hit_plus, x, y) then
            self:apply(session.create(self.session, self.session.active[i].def_index),
                "crear " .. i)
            return true
        elseif hit(z.hit_untap, x, y) then
            self:apply(session.untap_type(self.session, i), "untap tipo " .. i)
            return true
        elseif hit(z.card, x, y) then
            self:apply(session.tap(self.session, i), "tapear " .. i)
            return true
        end
    end
    return true
end

function View:onHold(ges)
    if self.expanded or self.modal then return true end
    local x, y = ges.pos.x, ges.pos.y
    for i, z in ipairs(self.zones) do
        if hit(z.card, x, y) then
            local def_index = self.session.active[i].def_index
            self.expanded = self.session.profile.defs[def_index]
            self:refresh("full", self.dimen, "vista expandida")
            return true
        end
    end
    return true
end

function View:onModalTap(x, y)
    if hit(self.hit_modal_ok, x, y) then
        local which = self.modal
        self.modal = nil
        if which == "reset" then
            self:apply(session.reset(self.session), "reiniciar")
        else
            UIManager:close(self)
        end
    elseif hit(self.hit_modal_cancel, x, y) then
        self.modal = nil
        self:refresh("full", self.dimen, "cancelar modal")
    end
    return true
end

-- ---- política de refresco ----

function View:apply(ev, label)
    if ev.kind == "none" then
        return
    elseif ev.kind == "partial" then
        for _, z in ipairs(ev.zones) do
            self:refresh(self.partial_mode, self:zoneGeom(z), label)
        end
    elseif ev.kind == "zone_full" then
        for _, z in ipairs(ev.zones) do
            self:refresh("full", self:zoneGeom(z), "ghosting/" .. label)
        end
    elseif ev.kind == "reflow" then
        self:reflowLayout()
        self:refresh("full", self.dimen, "reflow/" .. label)
    end
end

-- Instrumentación: mide de la petición al fin del ciclo de repintado. No es
-- el asentamiento físico del panel, pero es la latencia que percibe la app.
function View:refresh(mode, region, label)
    local start = time.now()
    UIManager:setDirty(self, mode, region)
    UIManager:nextTick(function()
        local ms = time.to_ms(time.since(start))
        table.insert(self.log, 1, string.format("%s %s %dms", label, mode, ms))
        if #self.log > 8 then table.remove(self.log) end
        logger.info("PaperTokens refresh:", label, mode, ms .. "ms",
            string.format("region=%dx%d@%d,%d", region.w, region.h, region.x, region.y))
    end)
end

-- ---- pintado ----

function View:paintTo(bb, x, y)
    if self.expanded then
        Render.expanded(bb, { x = 0, y = 0, w = self.screen_w, h = self.screen_h },
            self.expanded, { plugin_dir = self.plugin_dir })
        return
    end

    bb:paintRect(0, 0, self.screen_w, self.screen_h, WHITE)
    self:paintHeader(bb)
    self:paintActive(bb)
    self:paintCarousel(bb)
    if self.modal then self:paintModal(bb) end
end

function View:paintHeader(bb)
    local h = self.header_h
    local pad = math.floor(h * 0.12)
    bb:paintRect(0, 0, self.screen_w, h, WHITE)
    bb:paintRect(0, h - 3, self.screen_w, 3, BLACK)

    -- botón circular central: untap all
    local d = h - 2 * pad
    local cx, cy = math.floor(self.screen_w / 2), math.floor(h / 2)
    Render.fill_circle(bb, cx, cy, math.floor(d / 2), BLACK)
    local face_u = Render.fit_face("UNTAP ALL", math.floor(d * 0.84),
        math.floor(d * 0.17), 8, true)
    Render.untap_glyph(bb, cx, cy - math.floor(d * 0.12), math.floor(d * 0.20),
        WHITE, BLACK)
    Render.draw_text_centered(bb, cx - math.floor(d / 2), d,
        cy + math.floor(d * 0.36), face_u, "UNTAP ALL", true, WHITE)
    self.hit_untap_all = { x = cx - d, y = 0, w = 2 * d, h = h }

    local bw = math.floor(self.screen_w * 0.24)
    local face = Render.fit_face("Reiniciar", bw - 12, math.floor(h * 0.17), 8, true)
    local bh = h - 2 * pad
    local by = pad

    Render.stroke_round_rect(bb, pad, by, bw, bh, 3, math.floor(bh * 0.22), BLACK)
    Render.draw_text_centered(bb, pad, bw, by + math.floor(bh * 0.42), face,
        "Reiniciar", true, BLACK)
    Render.draw_text_centered(bb, pad, bw, by + math.floor(bh * 0.78), face,
        "partida", true, BLACK)
    self.hit_reset = { x = pad, y = by, w = bw, h = bh }

    local ex = self.screen_w - pad - bw
    Render.stroke_round_rect(bb, ex, by, bw, bh, 3, math.floor(bh * 0.22), BLACK)
    Render.draw_text_centered(bb, ex, bw, by + math.floor(bh * 0.62), face,
        "Salir", true, BLACK)
    self.hit_exit = { x = ex, y = by, w = bw, h = bh }
end

function View:paintActive(bb)
    if #self.session.active == 0 then
        local face = Render.face_px(math.floor(self.dpi * 0.085))
        Render.draw_text_centered(bb, 0, self.screen_w,
            self.content.y + math.floor(self.content.h / 2), face,
            "Toca un token de abajo", false, BLACK)
        return
    end
    for i, t in ipairs(self.session.active) do
        local z = self.zones[i]
        if z then
            local def = self.session.profile.defs[t.def_index]
            z.hit_untap = Render.pill(bb, z.pill, t)
            Render.card(bb, z.card, def, { plugin_dir = self.plugin_dir })
            z.hit_minus, z.hit_plus =
                Render.orbs(bb, z.card, self.orb_d, session.is_last(self.session, i), z.cell.w)
        end
    end
end

function View:pageCount()
    local n = #self.session.profile.defs
    return math.max(1, math.ceil(n / CAROUSEL_PAGE))
end

function View:carouselGeom()
    return Geom:new{ x = 0, y = self.screen_h - self.carousel_h,
                     w = self.screen_w, h = self.carousel_h }
end

function View:paintCarousel(bb)
    local h = self.carousel_h
    local y0 = self.screen_h - h
    bb:paintRect(0, y0, self.screen_w, h, WHITE)
    bb:paintRect(0, y0, self.screen_w, 3, BLACK)

    local defs = self.session.profile.defs
    local pages = self:pageCount()
    local paginated = pages > 1
    local chevron_w = paginated and math.floor(h * 0.62) or 0

    self.hit_prev, self.hit_next = nil, nil
    if paginated then
        -- bloque negro sólido con chevron blanco, a la altura de la banda
        local face = Render.face_px(math.floor(h * 0.42))
        bb:paintRect(0, y0 + 3, chevron_w, h - 3, BLACK)
        Render.draw_text_centered(bb, 0, chevron_w, y0 + math.floor(h * 0.64),
            face, "<", true, WHITE)
        self.hit_prev = { x = 0, y = y0, w = chevron_w, h = h }

        local nx = self.screen_w - chevron_w
        bb:paintRect(nx, y0 + 3, chevron_w, h - 3, BLACK)
        Render.draw_text_centered(bb, nx, chevron_w, y0 + math.floor(h * 0.64),
            face, ">", true, WHITE)
        self.hit_next = { x = nx, y = y0, w = chevron_w, h = h }
    end

    local page = self.page % pages
    local first = page * CAROUSEL_PAGE + 1
    local last = math.min(first + CAROUSEL_PAGE - 1, #defs)
    local count = last - first + 1
    local band_x = chevron_w
    local band_w = self.screen_w - 2 * chevron_w
    local slot_w = math.floor(band_w / math.max(count, 1))
    local side = math.min(math.floor(h * 0.58), slot_w - 8)
    local face = Render.face_px(math.floor(h * 0.11))

    self.hit_minis = {}
    for k = 0, count - 1 do
        local def_index = first + k
        local def = defs[def_index]
        local sx = band_x + k * slot_w
        local ix = sx + math.floor((slot_w - side) / 2)
        local iy = y0 + math.floor(h * 0.10)

        Render.stroke_round_rect(bb, ix, iy, side, side, 3,
            math.floor(side * 0.22), BLACK)
        Render.draw_icon(bb, { x = ix, y = iy, w = side, h = side }, def,
            self.plugin_dir)
        -- En juego: se invierte la miniatura. Solo blanco y negro, sin grises
        -- intermedios que el panel tendría que tramar.
        if session.index_of(self.session, def_index) ~= nil then
            bb:invertRect(ix, iy, side, side)
        end
        Render.draw_text_centered(bb, sx, slot_w, y0 + h - math.floor(h * 0.08),
            face, Render.ellipsize(face, def.name, slot_w - 6, false), false, BLACK)

        self.hit_minis[#self.hit_minis + 1] =
            { x = sx, y = y0, w = slot_w, h = h, def_index = def_index }
    end
end

function View:paintModal(bb)
    -- Fondo sólido, sin transparencias ni grises: el panel es monocromo.
    bb:paintRect(0, 0, self.screen_w, self.screen_h, WHITE)

    local w = math.floor(self.screen_w * 0.78)
    local pad = math.floor(w * 0.07)
    local face_size = math.floor(w * 0.055)
    local face = Render.face_px(face_size)
    local text = (self.modal == "reset")
        and "¿Seguro que deseas reiniciar? Se eliminan todos los tokens en juego."
        or "¿Seguro que deseas salir? La sesión no se guarda."

    -- ajuste de línea
    local lines, cur = {}, ""
    for word in text:gmatch("%S+") do
        local try = (cur == "") and word or (cur .. " " .. word)
        if Render.text_w(face, try, true) <= w - 2 * pad then
            cur = try
        else
            lines[#lines + 1] = cur; cur = word
        end
    end
    if cur ~= "" then lines[#lines + 1] = cur end

    local line_h = math.floor(face_size * 1.4)
    local btn_h = math.floor(w * 0.17)
    local h = 2 * pad + #lines * line_h + pad + 2 * btn_h + pad
    local x = math.floor((self.screen_w - w) / 2)
    local y = math.floor((self.screen_h - h) / 2)

    Render.fill_round_rect(bb, x, y, w, h, math.floor(w * 0.055), WHITE)
    Render.stroke_round_rect(bb, x, y, w, h, 4, math.floor(w * 0.055), BLACK)

    for i, line in ipairs(lines) do
        Render.draw_text_centered(bb, x, w, y + pad + i * line_h, face, line, true, BLACK)
    end

    local by = y + 2 * pad + #lines * line_h
    local bx, bw = x + pad, w - 2 * pad
    Render.fill_round_rect(bb, bx, by, bw, btn_h, math.floor(btn_h * 0.28), BLACK)
    Render.draw_text_centered(bb, bx, bw, by + math.floor(btn_h * 0.66), face,
        (self.modal == "reset") and "Reiniciar" or "Salir", true, WHITE)
    self.hit_modal_ok = { x = bx, y = by, w = bw, h = btn_h }

    local cy = by + btn_h + math.floor(pad * 0.5)
    Render.stroke_round_rect(bb, bx, cy, bw, btn_h, 3, math.floor(btn_h * 0.28), BLACK)
    Render.draw_text_centered(bb, bx, bw, cy + math.floor(btn_h * 0.66), face,
        "Cancelar", true, BLACK)
    self.hit_modal_cancel = { x = bx, y = cy, w = bw, h = btn_h }
end

-- ---- ciclo de vida ----

function View:onShow()
    self:refresh("full", self.dimen, "abrir")
    return true
end

function View:onCloseWidget()
    if self.mark_timer then
        UIManager:unschedule(self.mark_timer)
        self.mark_timer = nil
    end
    Screen:setRotationMode(self.saved_rotation)
    return true
end

function View:onClose()
    UIManager:close(self)
    return true
end

function View:setPartialMode(mode)
    self.partial_mode = mode
    self:refresh("full", self.dimen, "modo parcial=" .. mode)
end

return View
