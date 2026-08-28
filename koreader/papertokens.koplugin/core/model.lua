-- core/model.lua — constantes del modelo de partida. Puro.
--
-- Ya no hay catálogo hardcoded: los mazos salen exclusivamente de los
-- archivos .txt que genera la webapp y se copian por USB. Ver
-- core/deckfile.lua para la forma de un token leído del archivo:
--   { name, oracle_id, type_line, power, toughness, colors = {}, rules,
--     icon, is_creature }

local M = {}

M.COUNT_MAX = 8 -- 0–8 cubre todo Pauper

return M
