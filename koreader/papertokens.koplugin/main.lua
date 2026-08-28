-- main.lua — integración con KOReader. DESECHABLE.
--
-- Patrón verificado contra plugins/hello.koplugin y readtimer.koplugin de
-- la instalación real (v2026.07.1): WidgetContainer:extend,
-- self.ui.menu:registerToMainMenu(self), addToMainMenu con sorting_hint.
--
-- core/ NO hace require de nada de KOReader; esa dependencia vive solo aquí
-- y en ui/. El package.path se extiende para que require("core/...")
-- resuelva dentro del directorio del plugin.

local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local plugin_dir = debug.getinfo(1, "S").source:match("@?(.*)/[^/]*$")
package.path = plugin_dir .. "/?.lua;" .. package.path

local session = require("core/session")
local config = require("config/thresholds")
local Library = require("ui/library")
local View = require("ui/view")

local PaperTokens = WidgetContainer:extend{
    name = "papertokens",
    is_doc_only = false,
}

function PaperTokens:onDispatcherRegisterActions()
    Dispatcher:registerAction("papertokens_open", {
        category = "none", event = "PaperTokensOpen",
        title = _("PaperTokens"), general = true,
    })
end

function PaperTokens:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

-- La biblioteca reescanea la carpeta en cada apertura: nada se cachea entre
-- aperturas porque los archivos cambian constantemente por USB.
function PaperTokens:openLibrary()
    self.library = Library:new{
        config = config,
        plugin_dir = plugin_dir,
        on_open = function(deck) self:openSession(deck) end,
    }
    logger.info("PaperTokens: biblioteca abierta")
    UIManager:show(self.library)
end

function PaperTokens:openSession(deck)
    local s = session.new(deck, { ghosting_budget = config.ghosting_budget })
    self.view = View:new{
        session = s,
        config = config,
        plugin_dir = plugin_dir,
        partial_mode = config.partial_mode,
        -- la marca de uso la escribe la biblioteca, dueña del registro
        on_used = function(deck_id, when)
            if self.library then self.library:markUsed(deck_id, when) end
        end,
    }
    logger.info("PaperTokens: sesión de", deck.name, "con", #deck.tokens, "tokens")
    UIManager:show(self.view)
end

function PaperTokens:onPaperTokensOpen()
    self:openLibrary()
    return true
end

function PaperTokens:addToMainMenu(menu_items)
    menu_items.papertokens = {
        text = _("PaperTokens"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Mazos"),
                callback = function() self:openLibrary() end,
            },
            {
                text = _("Refresco parcial: fast"),
                checked_func = function()
                    return self.view and self.view.partial_mode == "fast"
                end,
                callback = function()
                    if self.view then self.view:setPartialMode("fast") end
                end,
            },
            {
                text = _("Refresco parcial: ui"),
                checked_func = function()
                    return self.view and self.view.partial_mode == "ui"
                end,
                callback = function()
                    if self.view then self.view:setPartialMode("ui") end
                end,
            },
        },
    }
end

return PaperTokens
