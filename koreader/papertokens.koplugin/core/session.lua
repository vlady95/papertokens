-- core/session.lua — máquina de estados de la partida. Pura: sin KOReader.
--
-- Semántica IDÉNTICA a la app web (src/lib/session.js):
--   * create  : tap en el carrusel. Crea un token; entra destapado. Si el
--               tipo no estaba en juego, entra a la zona activa (máx 4).
--   * tap     : tap en la carta. Mueve un token de destapado a tapeado.
--   * destroy : orbe −. Resta de tapeados primero; si no hay, de destapados.
--               Cuando ambos contadores llegan a cero el tipo SALE de la
--               zona activa y vuelve al carrusel.
--   * untap_type : botón de la píldora. Destapa todo ese tipo.
--   * untap_all  : botón central del header. Destapa todos los tipos.
--   * reset      : reiniciar partida. Vacía la zona activa.
--
-- Cada operación devuelve el evento de refresco que el UI ejecuta:
--   { kind = "partial", zones = {i,...} }  parcial de esas zonas
--   { kind = "zone_full", zones = {i,...} } presupuesto de ghosting agotado
--   { kind = "reflow" }                     cambió el conjunto de tipos
--   { kind = "none" }                       nada que repintar
--
-- Entra o sale un tipo ⇒ reflow. Cambia una cantidad ⇒ parcial. El orden es
-- de inserción: agregar un tipo nuevo nunca reordena los existentes.

local model = require("core/model")
local layout = require("core/layout")

local M = {}

function M.new(profile, opts)
  opts = opts or {}
  return {
    profile = profile,
    active = {},   -- lista de { def_index, count_a, count_b }, orden de inserción
    ghosting_budget = opts.ghosting_budget or 10,
    partials = {},
  }
end

function M.set_ghosting_budget(s, n)
  s.ghosting_budget = n
end

local function index_of(s, def_index)
  for i, t in ipairs(s.active) do
    if t.def_index == def_index then return i end
  end
  return nil
end

M.index_of = index_of

local function reset_partials(s)
  s.partials = {}
end

-- Consume presupuesto de ghosting de cada zona tocada. Al llegar al umbral,
-- esa zona pide refresco completo y su contador se reinicia.
local function partial_event(s, zones)
  local exhausted = {}
  for _, z in ipairs(zones) do
    s.partials[z] = (s.partials[z] or 0) + 1
    if s.partials[z] >= s.ghosting_budget then
      s.partials[z] = 0
      exhausted[#exhausted + 1] = z
    end
  end
  if #exhausted > 0 then
    return { kind = "zone_full", zones = exhausted }
  end
  return { kind = "partial", zones = zones }
end

function M.create(s, def_index)
  local i = index_of(s, def_index)
  if i then
    local t = s.active[i]
    if t.count_a + t.count_b >= model.COUNT_MAX then return { kind = "none" } end
    t.count_a = t.count_a + 1
    return partial_event(s, { i })
  end
  if #s.active >= layout.MAX_ACTIVE then
    return { kind = "none" }
  end
  s.active[#s.active + 1] = { def_index = def_index, count_a = 1, count_b = 0 }
  reset_partials(s)
  return { kind = "reflow" }
end

function M.tap(s, i)
  local t = s.active[i]
  if not t or t.count_a == 0 then return { kind = "none" } end
  t.count_a = t.count_a - 1
  t.count_b = t.count_b + 1
  return partial_event(s, { i })
end

function M.destroy(s, i)
  local t = s.active[i]
  if not t then return { kind = "none" } end
  if t.count_b > 0 then
    t.count_b = t.count_b - 1
  elseif t.count_a > 0 then
    t.count_a = t.count_a - 1
  else
    return { kind = "none" }
  end
  if t.count_a == 0 and t.count_b == 0 then
    table.remove(s.active, i)
    reset_partials(s)
    return { kind = "reflow" }
  end
  return partial_event(s, { i })
end

function M.untap_type(s, i)
  local t = s.active[i]
  if not t or t.count_b == 0 then return { kind = "none" } end
  t.count_a = t.count_a + t.count_b
  t.count_b = 0
  return partial_event(s, { i })
end

function M.untap_all(s)
  local touched = {}
  for i, t in ipairs(s.active) do
    if t.count_b > 0 then
      t.count_a = t.count_a + t.count_b
      t.count_b = 0
      touched[#touched + 1] = i
    end
  end
  if #touched == 0 then return { kind = "none" } end
  return partial_event(s, touched)
end

function M.reset(s)
  if #s.active == 0 then return { kind = "none" } end
  s.active = {}
  reset_partials(s)
  return { kind = "reflow" }
end

-- ¿Es el último token de ese tipo? El orbe − se vuelve bote de basura.
function M.is_last(s, i)
  local t = s.active[i]
  return t ~= nil and (t.count_a + t.count_b) == 1
end

return M
