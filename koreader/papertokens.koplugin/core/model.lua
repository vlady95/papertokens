-- core/model.lua — modelo de datos. Puro: sin KOReader, sin I/O.
--
-- TokenDef es estático y persiste con el Profile. El estado de partida es
-- efímero y vive en core/session.lua. Profile versionado desde v1.
--
-- Los campos replican el payload autosuficiente que produce la app web
-- (serializeDeck en src/lib/storage.js), para que un día un perfil pueda
-- viajar de la web a este dispositivo sin depender de Scryfall en la mesa.

local M = {}

function M.token_def(t)
  return {
    art_key = t.art_key,            -- clave de arte: assets/<hoja>-<talla>.png
    name = assert(t.name),
    type_line = t.type_line or "",  -- completa, con "Token"; la mini la recorta
    colors = t.colors or {},        -- LISTA: multicolor {"B","G"} e incoloro {}
    power = t.power,                -- nil si no es criatura
    toughness = t.toughness,
    abilities = t.abilities or "",  -- solo se ve en la vista expandida
  }
end

M.COUNT_MAX = 8 -- 0–8 cubre todo Pauper

-- Perfil hardcoded para esta fase: los seis tokens de Pauper.
function M.pauper_profile()
  return {
    version = 1,
    name = "Pauper básico",
    defs = {
      M.token_def{ art_key = "creature/eldrazi-spawn", name = "Eldrazi Spawn",
                   type_line = "Token Creature — Eldrazi Spawn",
                   colors = {}, power = 0, toughness = 1,
                   abilities = "Sacrifice this token: Add {C}." },
      M.token_def{ art_key = "artifact/blood", name = "Blood",
                   type_line = "Token Artifact — Blood", colors = {},
                   abilities = "{1}, {T}, Discard a card, Sacrifice this token: Draw a card." },
      M.token_def{ art_key = "artifact/map", name = "Map",
                   type_line = "Token Artifact — Map", colors = {},
                   abilities = "{1}, {T}, Sacrifice this token: Target creature you control explores." },
      M.token_def{ art_key = "creature/human-soldier", name = "Human Soldier",
                   type_line = "Token Creature — Human Soldier",
                   colors = { "R" }, power = 1, toughness = 1 },
      M.token_def{ art_key = "creature/cat", name = "Cat",
                   type_line = "Token Creature — Cat",
                   colors = { "W" }, power = 1, toughness = 1 },
      M.token_def{ art_key = "artifact/clue", name = "Clue",
                   type_line = "Token Artifact — Clue", colors = {},
                   abilities = "{2}, Sacrifice this token: Draw a card." },
    },
  }
end

return M
