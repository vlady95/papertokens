-- ui/library.lua — la biblioteca de mazos. DESECHABLE.
--
-- Reescanea la carpeta CADA VEZ que se abre: nada se cachea entre
-- aperturas, porque los archivos cambian constantemente por USB.
--
-- El orden sale del registro interno de uso (core/registry.lua), NUNCA de
-- la fecha de modificación del archivo: copiar por USB reescribe los
-- timestamps y todos los mazos parecerían recién usados.
--
-- Un archivo que no valida no deja la biblioteca a medias: se lista aparte
-- con su motivo y los demás siguen disponibles.

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local Screen = Device.screen

local deckfile = require("core/deckfile")
local registry = require("core/registry")
local files = require("ui/files")
local Render = require("ui/render")

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE

local Library = InputContainer:extend{
    name = "papertokens_library",
    covers_fullscreen = true,
}

local function hit(r, x, y)
    return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

function Library:init()
    self.mode = "list"     -- "list" | "actions" | "confirm"
    self.target = nil      -- mazo sobre el que se abrió el menú
    self.scroll = 0

    self.saved_rotation = Screen:getRotationMode()
    Screen:setRotationMode(Screen.DEVICE_ROTATED_UPRIGHT)

    self.dpi = Screen:getDPI()
    self.screen_w, self.screen_h = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.screen_w, h = self.screen_h }
    self.header_h = Render.mm_to_px(self.config.header_mm or 22, self.dpi)
    self.row_h = Render.mm_to_px(16, self.dpi)

    self:rescan()

    self:registerTouchZones({
        {
            id = "papertokens_lib_tap", ges = "tap",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(ges) return self:onTap(ges) end,
        },
        {
            id = "papertokens_lib_hold", ges = "hold",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(ges) return self:onHold(ges) end,
        },
    })
end

-- ---- lectura de la carpeta ----

function Library:rescan()
    self.decks = {}
    self.broken = {}
    self.scan_error = nil

    local dir = files.decks_dir(self.plugin_dir, self.config.decks_folder)
    self.dir = dir
    files.mkdir(dir)

    local paths, err = files.list_txt(dir)
    if not paths then
        self.scan_error = err
        self.registry = {}
        return
    end

    for _, path in ipairs(paths) do
        local text = files.read(path)
        local deck, why
        if text then
            deck, why = deckfile.parse(text)
        else
            why = "no se pudo abrir el archivo"
        end
        if deck then
            deck.path = path
            self.decks[#self.decks + 1] = deck
        else
            self.broken[#self.broken + 1] = {
                file = path:match("([^/]+)$"),
                why = why or "no se pudo leer",
            }
        end
    end

    -- registro de uso: cargar, limpiar lo que ya no existe, guardar
    self.registry_path = files.registry_path(self.plugin_dir)
    self.registry = registry.decode(files.read(self.registry_path))
    local ids = {}
    for i, d in ipairs(self.decks) do ids[i] = d.id end
    local _, removed = registry.prune(self.registry, ids)
    if removed > 0 then
        files.write(self.registry_path, registry.encode(self.registry))
        logger.info("PaperTokens: registro limpiado,", removed, "entradas huérfanas")
    end

    self.decks = registry.order(self.decks, self.registry)
end

-- Llamado por la sesión al cruzar los diez minutos.
function Library:markUsed(deck_id, when)
    registry.touch(self.registry, deck_id, when)
    files.write(self.registry_path, registry.encode(self.registry))
    -- reordenar ya, para que al volver de la sesión la lista esté al día
    self.decks = registry.order(self.decks, self.registry)
    logger.info("PaperTokens: mazo", deck_id, "marcado como usado")
end

-- ---- input ----

function Library:rowRects()
    local rects = {}
    local y = self.header_h + 8
    for i, d in ipairs(self.decks) do
        rects[i] = { x = 12, y = y, w = self.screen_w - 24, h = self.row_h, deck = d }
        y = y + self.row_h + 8
    end
    return rects
end

function Library:onTap(ges)
    local x, y = ges.pos.x, ges.pos.y

    if self.mode == "confirm" then
        if hit(self.hit_ok, x, y) then
            self:deleteTarget()
        elseif hit(self.hit_cancel, x, y) then
            self.mode = "list"
            self:refresh("volver de la confirmación")
        end
        return true
    end

    if self.mode == "actions" then
        if hit(self.hit_archive, x, y) then
            self:archiveTarget()
        elseif hit(self.hit_delete, x, y) then
            self.mode = "confirm"
            self:refresh("confirmar borrado")
        elseif hit(self.hit_cancel, x, y) then
            self.mode = "list"
            self:refresh("cerrar acciones")
        end
        return true
    end

    if y < self.header_h then
        if hit(self.hit_exit, x, y) then UIManager:close(self) end
        return true
    end

    for _, r in ipairs(self:rowRects()) do
        if hit(r, x, y) then
            self.on_open(r.deck)
            return true
        end
    end
    return true
end

-- Borrar y archivar viven detrás de long-press: el archivo puede ser la
-- única copia y borrar es irreversible.
function Library:onHold(ges)
    if self.mode ~= "list" then return true end
    local x, y = ges.pos.x, ges.pos.y
    for _, r in ipairs(self:rowRects()) do
        if hit(r, x, y) then
            self.target = r.deck
            self.mode = "actions"
            self:refresh("acciones de mazo")
            return true
        end
    end
    return true
end

function Library:archiveTarget()
    local dest = files.archive_dir(self.dir, self.config.archive_folder)
    local ok = files.move_to(self.target.path, dest)
    logger.info("PaperTokens: archivar", self.target.path, "→", dest, ok and "ok" or "falló")
    self.mode = "list"
    self.target = nil
    self:rescan()
    self:refresh("archivado")
end

-- El archivo y su entrada del registro se van en la MISMA operación, para
-- que nunca quede una entrada huérfana apuntando a nada.
function Library:deleteTarget()
    local id = self.target.id
    local removed = files.remove(self.target.path)
    self.registry[id] = nil
    files.write(self.registry_path, registry.encode(self.registry))
    logger.info("PaperTokens: borrado", self.target.path, removed and "ok" or "falló")
    self.mode = "list"
    self.target = nil
    self:rescan()
    self:refresh("borrado")
end

function Library:refresh(label)
    UIManager:setDirty(self, "full", self.dimen)
    logger.info("PaperTokens biblioteca:", label)
end

-- ---- pintado ----

function Library:paintTo(bb, x, y)
    bb:paintRect(0, 0, self.screen_w, self.screen_h, WHITE)
    self:paintHeader(bb)

    if self.scan_error then
        local face = Render.face_px(math.floor(self.dpi * 0.055))
        Render.draw_text_centered(bb, 0, self.screen_w,
            self.header_h + math.floor(self.dpi * 0.6), face,
            "No se pudo leer la carpeta", false, BLACK)
        local small = Render.face_px(math.floor(self.dpi * 0.042))
        Render.draw_text_centered(bb, 0, self.screen_w,
            self.header_h + math.floor(self.dpi * 0.8), small,
            Render.ellipsize(small, self.scan_error, self.screen_w - 40, false), false, BLACK)
    elseif #self.decks == 0 then
        self:paintEmpty(bb)
    else
        self:paintRows(bb)
    end

    self:paintBroken(bb)

    if self.mode == "actions" then self:paintActions(bb) end
    if self.mode == "confirm" then self:paintConfirm(bb) end
end

function Library:paintHeader(bb)
    local h = self.header_h
    local pad = math.floor(h * 0.12)
    bb:paintRect(0, h - 3, self.screen_w, 3, BLACK)
    local face = Render.face_px(math.floor(h * 0.30))
    Render.draw_text(bb, 16, math.floor(h * 0.62), face, "Mazos", true, BLACK)

    local bw = math.floor(self.screen_w * 0.22)
    local bh = h - 2 * pad
    local bx = self.screen_w - pad - bw
    Render.stroke_round_rect(bb, bx, pad, bw, bh, 3, math.floor(bh * 0.22), BLACK)
    local f = Render.fit_face("Salir", bw - 12, math.floor(h * 0.17), 8, true)
    Render.draw_text_centered(bb, bx, bw, pad + math.floor(bh * 0.62), f, "Salir", true, BLACK)
    self.hit_exit = { x = bx, y = pad, w = bw, h = bh }
end

function Library:paintEmpty(bb)
    local face = Render.face_px(math.floor(self.dpi * 0.050))
    local small = Render.face_px(math.floor(self.dpi * 0.040))
    local cy = self.header_h + math.floor(self.dpi * 0.9)
    Render.draw_text_centered(bb, 0, self.screen_w, cy, face,
        "No hay mazos todavía", false, BLACK)
    Render.draw_text_centered(bb, 0, self.screen_w, cy + math.floor(self.dpi * 0.28), small,
        "Copia archivos .txt por USB a:", false, BLACK)
    local path = self.dir:match("([^/]+/[^/]+)$") or self.dir
    Render.draw_text_centered(bb, 0, self.screen_w, cy + math.floor(self.dpi * 0.48), small,
        Render.ellipsize(small, path, self.screen_w - 40, false), true, BLACK)
end

function Library:paintRows(bb)
    local name_face = Render.face_px(math.floor(self.row_h * 0.34))
    local sub_face = Render.face_px(math.floor(self.row_h * 0.22))
    for _, r in ipairs(self:rowRects()) do
        if r.y + r.h < self.screen_h then
            Render.stroke_round_rect(bb, r.x, r.y, r.w, r.h, 3,
                math.floor(r.h * 0.16), BLACK)
            Render.draw_text(bb, r.x + 16, r.y + math.floor(r.h * 0.44), name_face,
                Render.ellipsize(name_face, r.deck.name, r.w - 32, true), true, BLACK)
            local used = self.registry[r.deck.id]
            local sub = #r.deck.tokens .. " tokens"
            if used then sub = sub .. "  ·  usado " .. os.date("%Y-%m-%d", used) end
            Render.draw_text(bb, r.x + 16, r.y + math.floor(r.h * 0.78), sub_face,
                sub, false, BLACK)
        end
    end
end

function Library:paintBroken(bb)
    if #self.broken == 0 then return end
    local face = Render.face_px(math.floor(self.dpi * 0.038))
    local title = Render.face_px(math.floor(self.dpi * 0.042))
    local y = self.screen_h - 24 - #self.broken * math.floor(self.dpi * 0.30)
        - math.floor(self.dpi * 0.28)
    bb:paintRect(16, y - math.floor(self.dpi * 0.10), self.screen_w - 32, 2, BLACK)
    Render.draw_text(bb, 16, y + math.floor(self.dpi * 0.10), title,
        "Archivos rechazados", true, BLACK)
    for i, b in ipairs(self.broken) do
        local ry = y + math.floor(self.dpi * (0.10 + 0.30 * i))
        Render.draw_text(bb, 16, ry, face,
            Render.ellipsize(face, b.file, self.screen_w - 32, true), true, BLACK)
        Render.draw_text(bb, 16, ry + math.floor(self.dpi * 0.13), face,
            Render.ellipsize(face, b.why, self.screen_w - 32, false), false, BLACK)
    end
end

-- Hoja de acciones sobre un mazo.
function Library:paintActions(bb)
    local w = math.floor(self.screen_w * 0.80)
    local pad = math.floor(w * 0.06)
    local face = Render.face_px(math.floor(w * 0.055))
    local bh = math.floor(w * 0.17)
    local h = pad + math.floor(w * 0.09) + pad + 3 * bh + 2 * math.floor(pad * 0.5) + pad
    local x = math.floor((self.screen_w - w) / 2)
    local y = math.floor((self.screen_h - h) / 2)

    bb:paintRect(0, 0, self.screen_w, self.screen_h, WHITE)
    Render.fill_round_rect(bb, x, y, w, h, math.floor(w * 0.055), WHITE)
    Render.stroke_round_rect(bb, x, y, w, h, 4, math.floor(w * 0.055), BLACK)
    Render.draw_text_centered(bb, x, w, y + pad + math.floor(w * 0.06), face,
        Render.ellipsize(face, self.target.name, w - 2 * pad, true), true, BLACK)

    local bx, bw = x + pad, w - 2 * pad
    local by = y + pad + math.floor(w * 0.09) + pad
    Render.stroke_round_rect(bb, bx, by, bw, bh, 3, math.floor(bh * 0.28), BLACK)
    Render.draw_text_centered(bb, bx, bw, by + math.floor(bh * 0.66), face,
        "Archivar", true, BLACK)
    self.hit_archive = { x = bx, y = by, w = bw, h = bh }

    local dy = by + bh + math.floor(pad * 0.5)
    Render.fill_round_rect(bb, bx, dy, bw, bh, math.floor(bh * 0.28), BLACK)
    Render.draw_text_centered(bb, bx, bw, dy + math.floor(bh * 0.66), face,
        "Borrar", true, WHITE)
    self.hit_delete = { x = bx, y = dy, w = bw, h = bh }

    local cy = dy + bh + math.floor(pad * 0.5)
    Render.stroke_round_rect(bb, bx, cy, bw, bh, 3, math.floor(bh * 0.28), BLACK)
    Render.draw_text_centered(bb, bx, bw, cy + math.floor(bh * 0.66), face,
        "Cancelar", true, BLACK)
    self.hit_cancel = { x = bx, y = cy, w = bw, h = bh }
end

-- Borrar es irreversible y el archivo puede ser la única copia.
function Library:paintConfirm(bb)
    local w = math.floor(self.screen_w * 0.80)
    local pad = math.floor(w * 0.06)
    local size = math.floor(w * 0.052)
    local face = Render.face_px(size)
    local bh = math.floor(w * 0.17)

    local text = "Se borra el archivo del disco. Puede ser la única copia y no hay vuelta atrás."
    local lines, cur = {}, ""
    for word in text:gmatch("%S+") do
        local try = (cur == "") and word or (cur .. " " .. word)
        if Render.text_w(face, try, false) <= w - 2 * pad then cur = try
        else lines[#lines + 1] = cur; cur = word end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    local line_h = math.floor(size * 1.4)

    local h = pad + math.floor(size * 1.5) + #lines * line_h + pad + 2 * bh
        + math.floor(pad * 0.5) + pad
    local x = math.floor((self.screen_w - w) / 2)
    local y = math.floor((self.screen_h - h) / 2)

    bb:paintRect(0, 0, self.screen_w, self.screen_h, WHITE)
    Render.fill_round_rect(bb, x, y, w, h, math.floor(w * 0.055), WHITE)
    Render.stroke_round_rect(bb, x, y, w, h, 4, math.floor(w * 0.055), BLACK)

    Render.draw_text_centered(bb, x, w, y + pad + size, face,
        Render.ellipsize(face, "¿Borrar " .. self.target.name .. "?", w - 2 * pad, true),
        true, BLACK)
    for i, l in ipairs(lines) do
        Render.draw_text_centered(bb, x, w,
            y + pad + math.floor(size * 1.5) + i * line_h, face, l, false, BLACK)
    end

    local bx, bw = x + pad, w - 2 * pad
    local by = y + pad + math.floor(size * 1.5) + #lines * line_h + pad
    Render.fill_round_rect(bb, bx, by, bw, bh, math.floor(bh * 0.28), BLACK)
    Render.draw_text_centered(bb, bx, bw, by + math.floor(bh * 0.66), face,
        "Borrar definitivamente", true, WHITE)
    self.hit_ok = { x = bx, y = by, w = bw, h = bh }

    local cy = by + bh + math.floor(pad * 0.5)
    Render.stroke_round_rect(bb, bx, cy, bw, bh, 3, math.floor(bh * 0.28), BLACK)
    Render.draw_text_centered(bb, bx, bw, cy + math.floor(bh * 0.66), face,
        "Cancelar", true, BLACK)
    self.hit_cancel = { x = bx, y = cy, w = bw, h = bh }
end

function Library:onShow()
    self:refresh("abrir biblioteca")
    return true
end

function Library:onCloseWidget()
    Screen:setRotationMode(self.saved_rotation)
    return true
end

function Library:onClose()
    UIManager:close(self)
    return true
end

return Library
