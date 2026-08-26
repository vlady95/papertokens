-- main.lua — integración con KOReader. DESECHABLE.
--
-- Patrón verificado contra plugins/hello.koplugin y readtimer.koplugin de
-- la instalación real (KOReader v2026.07.1): WidgetContainer:extend,
-- self.ui.menu:registerToMainMenu(self), addToMainMenu(menu_items) con
-- sorting_hint.
--
-- core/ NO hace require de nada de KOReader; esa dependencia solo vive aquí
-- y en ui/. El package.path se extiende para que `require("core/...")`
-- resuelva dentro del directorio del plugin.

local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local plugin_dir = debug.getinfo(1, "S").source:match("@?(.*)/[^/]*$")
package.path = plugin_dir .. "/?.lua;" .. package.path

local model = require("core/model")
local session = require("core/session")
local config = require("config/thresholds")
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

function PaperTokens:openSession(frozen)
    local profile = model.pauper_profile()
    local s = session.new(profile, {
        ghosting_budget = config.ghosting_budget,
        frozen = frozen or false,
    })
    self.view = View:new{
        session = s,
        config = config,
        plugin_dir = plugin_dir,
    }
    logger.info("PaperTokens: sesión abierta,",
        "frozen=" .. tostring(frozen), "ghosting=" .. tostring(config.ghosting_budget))
    UIManager:show(self.view)
end

function PaperTokens:onPaperTokensOpen()
    self:openSession(false)
    return true
end

function PaperTokens:addToMainMenu(menu_items)
    menu_items.papertokens = {
        text = _("PaperTokens"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Nueva sesión"),
                callback = function() self:openSession(false) end,
            },
            {
                text = _("Nueva sesión (layout fijo / torneo)"),
                callback = function() self:openSession(true) end,
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
            {
                text = _("Color: letra"),
                checked_func = function()
                    return self.view and self.view.color_mode == "letter"
                end,
                callback = function()
                    if self.view then self.view:setColorMode("letter") end
                end,
            },
            {
                text = _("Color: trama"),
                checked_func = function()
                    return self.view and self.view.color_mode == "hatch"
                end,
                callback = function()
                    if self.view then self.view:setColorMode("hatch") end
                end,
            },
        },
    }
end

return PaperTokens
