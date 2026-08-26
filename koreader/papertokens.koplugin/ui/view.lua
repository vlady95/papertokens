-- ui/view.lua — widget de sesión: input, política de refresco e
-- instrumentación. DESECHABLE: todo lo portable vive en core/.
--
-- API verificada en KOReader v2026.07.1 (Kindle PW3, /Volumes/Kindle):
--   UIManager:setDirty(widget, refreshtype, refreshregion, refreshdither)
--     refreshtype ∈ "full"|"flashpartial"|"flashui"|"partial"|"ui"|"fast"|"a2"
--     refreshregion es un Geom
--   UIManager:nextTick(cb) — corre tras el ciclo de repintado (instrumentación)
--   InputContainer:registerTouchZones{ {id, ges, screen_zone{ratio_*}, handler} }
--     Las ratios se resuelven contra Screen:getWidth/getHeight AL REGISTRAR,
--     así que hay que registrar DESPUÉS de rotar.
--   Screen:setRotationMode(Screen.DEVICE_ROTATED_CLOCKWISE) → landscape
--   Las coordenadas táctiles YA llegan rotadas (GestureDetector:adjustGesCoordinate),
--   no hay que traducirlas a mano.
--   El gesto "hold" dispara con HOLD_INTERVAL_MS = 500 global, NO con
--   config.long_press_ms (ver nota en config/thresholds.lua).

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText = require("ui/rendertext")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local time = require("ui/time")

local Screen = Device.screen

local layout = require("core/layout")
local session = require("core/session")
local Render = require("ui/render")

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE

local View = InputContainer:extend{
    name = "papertokens_view",
    covers_fullscreen = true,
}

function View:init()
    self.mode = "play"          -- "play" | "select"
    self.cursor = 1             -- índice sobre profile.defs en modo select
    self.color_mode = self.color_mode or "letter" -- "letter" | "hatch"
    -- Modo de refresco parcial: "fast" o "ui". Alternable para comparar.
    self.partial_mode = self.partial_mode or "fast"
    self.log = {}               -- instrumentación: últimas latencias

    self.saved_rotation = Screen:getRotationMode()
    Screen:setRotationMode(Screen.DEVICE_ROTATED_CLOCKWISE) -- landscape

    self:computeGeometry()
    self:registerButtons()
end

-- ---- geometría ----

function View:computeGeometry()
    local dpi = Screen:getDPI()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dpi, self.screen_w, self.screen_h = dpi, sw, sh

    self.bar_h = Render.mm_to_px(self.config.button_bar_mm or 0, dpi)
    self.status_h = Render.mm_to_px(self.config.status_bar_mm or 0, dpi)

    self.content = {
        x = 0,
        y = self.status_h,
        w = sw,
        h = sh - self.bar_h - self.status_h,
    }
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self:reflowLayout()
end

-- Rects del motor puro, desplazados al área de contenido.
function View:reflowLayout()
    local n = #self.session.declared
    self.rects = {}
    if n == 0 then return end
    local raw = layout.layout(self.content.w, self.content.h, self.dpi, n, self.config)
    for i, r in ipairs(raw) do
        self.rects[i] = {
            x = r.x + self.content.x,
            y = r.y + self.content.y,
            w = r.w, h = r.h, tier = r.tier,
        }
    end
end

function View:zoneGeom(zone_index)
    local r = self.rects[zone_index]
    if not r then return self.dimen end
    return Geom:new{ x = r.x, y = r.y, w = r.w, h = r.h }
end

-- ---- input: tres zonas táctiles fijas = BTN_A / BTN_B / BTN_C ----
--
-- NADA de touch directo sobre el elemento a modificar: falsearía la
-- validación de ergonomía de los tres botones físicos del hardware final.

function View:registerButtons()
    local bar_ratio_y = (self.screen_h - self.bar_h) / self.screen_h
    local bar_ratio_h = self.bar_h / self.screen_h
    local zones = {}
    local ids = { "A", "B", "C" }
    for i, id in ipairs(ids) do
        zones[#zones + 1] = {
            id = "papertokens_btn_" .. id .. "_tap",
            ges = "tap",
            screen_zone = {
                ratio_x = (i - 1) / 3, ratio_y = bar_ratio_y,
                ratio_w = 1 / 3, ratio_h = bar_ratio_h,
            },
            handler = function() return self:onButton(id, "tap") end,
        }
        zones[#zones + 1] = {
            id = "papertokens_btn_" .. id .. "_hold",
            ges = "hold",
            screen_zone = {
                ratio_x = (i - 1) / 3, ratio_y = bar_ratio_y,
                ratio_w = 1 / 3, ratio_h = bar_ratio_h,
            },
            handler = function() return self:onButton(id, "hold") end,
        }
    end
    self:registerTouchZones(zones)
end

function View:onButton(id, press)
    if self.mode == "select" then
        return self:onSelectButton(id, press)
    end
    local s = self.session
    local ev
    if id == "A" then
        if press == "hold" then
            self.mode = "select"
            self:fullRefresh("entrar al selector")
            return true
        end
        ev = session.cycle_active(s, 1)
    elseif id == "B" then
        ev = (press == "hold") and session.tap_one(s) or session.inc(s)
    else -- C
        ev = (press == "hold") and session.untap_one(s) or session.dec(s)
    end
    self:applyRefresh(ev, id .. "/" .. press)
    return true
end

-- Selector operable con los MISMOS tres botones: el hardware final no
-- tiene más, así que el selector no puede inventarse entradas.
function View:onSelectButton(id, press)
    local defs = self.session.profile.defs
    if id == "A" then
        self.cursor = self.cursor % #defs + 1
        self:refreshRegion("ui", self.dimen, "selector/cursor")
    elseif id == "B" then
        local s = self.session
        local declared = nil
        for i, d in ipairs(s.declared) do
            if d == self.cursor then declared = i break end
        end
        local ev
        if declared then
            ev = session.undeclare(s, self.cursor)
        else
            ev = session.declare(s, self.cursor)
        end
        if ev.kind == "blocked" then
            self.blocked_reason = ev.reason
        else
            self.blocked_reason = nil
        end
        self:refreshRegion("ui", self.dimen, "selector/toggle")
    else -- C: cerrar. Aquí sí: cambió el set de tipos ⇒ reflow.
        self.mode = "play"
        self:reflowLayout()
        self:fullRefresh("salir del selector (reflow)")
    end
    return true
end

-- ---- política de refresco ----

function View:applyRefresh(ev, label)
    if ev.kind == "none" then
        return
    elseif ev.kind == "blocked" then
        self.blocked_reason = ev.reason
        self:refreshRegion("ui", self:statusGeom(), "blocked/" .. tostring(ev.reason))
    elseif ev.kind == "partial" then
        -- cantidad y tapped/untapped: parcial sobre el rect de la zona
        for _, z in ipairs(ev.zones) do
            self:refreshRegion(self.partial_mode, self:zoneGeom(z), label)
        end
    elseif ev.kind == "zone_full" then
        -- presupuesto de ghosting agotado: full sobre el rect de la zona
        for _, z in ipairs(ev.zones) do
            self:refreshRegion("full", self:zoneGeom(z), "ghosting/" .. label)
        end
    elseif ev.kind == "reflow" then
        self:reflowLayout()
        self:fullRefresh("reflow/" .. label)
    end
end

function View:statusGeom()
    return Geom:new{ x = 0, y = 0, w = self.screen_w, h = math.max(self.status_h, 1) }
end

function View:fullRefresh(label)
    self:refreshRegion("full", self.dimen, label)
end

-- Instrumentación: mide de la petición al final del ciclo de repintado de
-- KOReader (nextTick). NO es el tiempo de asentamiento físico del panel,
-- pero es la latencia que percibe la app y sirve para comparar modos.
function View:refreshRegion(mode, region, label)
    local start = time.now()
    UIManager:setDirty(self, mode, region)
    UIManager:nextTick(function()
        local ms = time.to_ms(time.since(start))
        local entry = string.format("%s %s %dms", label or "?", mode, ms)
        table.insert(self.log, 1, entry)
        if #self.log > 6 then table.remove(self.log) end
        logger.info("PaperTokens refresh:", entry,
            string.format("region=%dx%d@%d,%d", region.w, region.h, region.x, region.y))
        if self.status_h > 0 then
            UIManager:setDirty(self, "fast", self:statusGeom())
        end
    end)
end

-- ---- pintado ----

function View:paintTo(bb, x, y)
    if self.mode == "select" then
        return self:paintSelector(bb)
    end
    bb:paintRect(0, 0, self.screen_w, self.screen_h, WHITE)

    if #self.session.declared == 0 then
        local face = Render.face_px(math.floor(self.dpi * 0.10))
        local msg = "Mantén A para elegir tokens"
        local tw = RenderText:sizeUtf8Text(0, self.screen_w, face, msg, true, false).x
        RenderText:renderUtf8Text(bb, math.floor((self.screen_w - tw) / 2),
            math.floor(self.screen_h / 2), face, msg, true, false, BLACK)
    else
        for i, def_index in ipairs(self.session.declared) do
            local st = self.session.states[i]
            local zone = session.zone_of(self.session, i)
            local rect = self.rects[zone]
            if rect then
                Render.zone(bb, rect, self.session.profile.defs[def_index], st, {
                    active = (i == self.session.active),
                    color_mode = self.color_mode,
                    plugin_dir = self.plugin_dir,
                    dim = (st.count_a + st.count_b == 0),
                })
            end
        end
    end

    self:paintStatus(bb)
    self:paintButtonBar(bb, {
        "A  ciclar / ⌷ tipos",
        "B  +1 / ⌷ tapear",
        "C  −1 / ⌷ destapar",
    })
end

function View:paintStatus(bb)
    if self.status_h <= 0 then return end
    bb:paintRect(0, 0, self.screen_w, self.status_h, WHITE)
    local face = Render.face_px(math.floor(self.status_h * 0.62))
    local txt = (self.log[1] or "listo")
        .. "  |  ghost " .. tostring(self.session.ghosting_budget)
        .. "  |  " .. self.partial_mode
        .. "  |  color " .. self.color_mode
    if self.blocked_reason then txt = txt .. "  |  " .. self.blocked_reason end
    RenderText:renderUtf8Text(bb, 6, math.floor(self.status_h * 0.78), face, txt,
        true, false, BLACK)
    bb:paintRect(0, self.status_h - 1, self.screen_w, 1, BLACK)
end

function View:paintButtonBar(bb, labels)
    if self.bar_h <= 0 then return end
    local by = self.screen_h - self.bar_h
    bb:paintRect(0, by, self.screen_w, self.bar_h, WHITE)
    bb:paintRect(0, by, self.screen_w, 2, BLACK)
    local face = Render.face_px(math.floor(self.bar_h * 0.38))
    for i = 1, 3 do
        local zx = math.floor(self.screen_w * (i - 1) / 3)
        local zw = math.floor(self.screen_w / 3)
        if i > 1 then bb:paintRect(zx, by, 2, self.bar_h, BLACK) end
        local label = labels[i]
        local tw = RenderText:sizeUtf8Text(0, zw, face, label, true, true).x
        RenderText:renderUtf8Text(bb, zx + math.floor((zw - tw) / 2),
            by + math.floor(self.bar_h * 0.66), face, label, true, true, BLACK)
    end
end

function View:paintSelector(bb)
    bb:paintRect(0, 0, self.screen_w, self.screen_h, WHITE)
    local defs = self.session.profile.defs
    local face = Render.face_px(math.floor(self.dpi * 0.055))
    local title_face = Render.face_px(math.floor(self.dpi * 0.045))
    RenderText:renderUtf8Text(bb, 20, self.status_h + 40, title_face,
        "Tipos en juego (" .. #self.session.declared .. "/6)", true, true, BLACK)

    local top = self.status_h + 70
    local avail = self.screen_h - self.bar_h - top - 10
    local row_h = math.floor(avail / #defs)
    for i, def in ipairs(defs) do
        local ry = top + (i - 1) * row_h
        local declared = false
        for _, d in ipairs(self.session.declared) do
            if d == i then declared = true break end
        end
        if i == self.cursor then
            bb:paintBorder(14, ry + 2, self.screen_w - 28, row_h - 6, 4, BLACK, 6)
        end
        local box = math.floor(row_h * 0.44)
        local bx, bby = 34, ry + math.floor((row_h - box) / 2)
        bb:paintBorder(bx, bby, box, box, 3, BLACK, 4)
        if declared then
            bb:paintRect(bx + 6, bby + 6, box - 12, box - 12, BLACK)
        end
        RenderText:renderUtf8Text(bb, bx + box + 24, ry + math.floor(row_h * 0.62),
            face, def.name, true, true, BLACK)
    end

    self:paintStatus(bb)
    self:paintButtonBar(bb, { "A  siguiente", "B  marcar", "C  jugar" })
end

-- ---- ciclo de vida ----

function View:onShow()
    self:fullRefresh("abrir")
    return true
end

function View:onCloseWidget()
    Screen:setRotationMode(self.saved_rotation)
    return true
end

function View:onClose()
    UIManager:close(self)
    return true
end

-- Ajustes en runtime (desde el menú del plugin)
function View:setPartialMode(mode)
    self.partial_mode = mode
    self:fullRefresh("modo parcial=" .. mode)
end

function View:setColorMode(mode)
    self.color_mode = mode
    self:fullRefresh("color=" .. mode)
end

function View:setGhostingBudget(n)
    session.set_ghosting_budget(self.session, n)
    self:fullRefresh("ghosting=" .. n)
end

return View
