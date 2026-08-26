-- core/model.lua — modelo de datos. Puro: sin KOReader, sin I/O.
--
-- TokenDef es estático y persiste con el Profile. TokenState es efímero y
-- se resetea al terminar la sesión. Profile versionado desde v1.

local M = {}

function M.token_def(t)
  return {
    art_key = t.art_key,          -- clave de arte, p. ej. "artifact/clue"
    name = assert(t.name),
    colors = t.colors or {},      -- LISTA: multicolor {"B","G"} e incoloro {} son reales
    power = t.power,              -- nil si no es criatura
    toughness = t.toughness,
    abilities = t.abilities or "",
  }
end

function M.token_state(def_index)
  return {
    def_index = def_index,
    count_a = 0, -- untapped
    count_b = 0, -- tapped
    counters = 0,
  }
end

M.COUNT_MAX = 8 -- 0–8 cubre todo Pauper

-- Perfil hardcoded para toda esta fase: los seis tokens de Pauper.
function M.pauper_profile()
  return {
    version = 1,
    name = "Pauper básico",
    defs = {
      M.token_def{ art_key = "creature/eldrazi-spawn", name = "Eldrazi Spawn",
                   colors = {}, power = 0, toughness = 1,
                   abilities = "Sacrifice: Add {C}." },
      M.token_def{ art_key = "artifact/blood", name = "Blood",
                   colors = {},
                   abilities = "{1}, {T}, Discard a card, Sacrifice: Draw a card." },
      M.token_def{ art_key = "artifact/map", name = "Map",
                   colors = {},
                   abilities = "{1}, {T}, Sacrifice: Target creature you control explores." },
      M.token_def{ art_key = "creature/human-soldier", name = "Human Soldier",
                   colors = { "R" }, power = 1, toughness = 1 },
      M.token_def{ art_key = "creature/cat", name = "Cat",
                   colors = { "W" }, power = 1, toughness = 1 },
      M.token_def{ art_key = "artifact/clue", name = "Clue",
                   colors = {},
                   abilities = "{2}, Sacrifice: Draw a card." },
    },
  }
end

return M
