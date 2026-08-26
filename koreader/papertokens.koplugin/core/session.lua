-- core/session.lua — máquina de estados de la partida. Pura: sin KOReader.
--
-- Cada operación devuelve un EVENTO DE REFRESCO que el UI ejecuta tal cual;
-- la política vive aquí para poder probarla en el Mac:
--   { kind = "partial",   zones = {i, ...} }  refresco parcial de esas zonas
--   { kind = "zone_full", zones = {i, ...} }  se agotó el presupuesto de
--                                             ghosting: refresco completo de
--                                             esa(s) zona(s)
--   { kind = "reflow" }                       cambió el SET de tipos: full
--   { kind = "none" }                         nada que repintar
--   { kind = "blocked", reason = "frozen" }   modo layout fijo
--
-- Reglas duras que este módulo garantiza:
--   * La cantidad NUNCA dispara reflow. Llegar a 0 no elimina ni recoloca.
--   * Reflow solo cuando cambia el conjunto de tipos declarados.
--   * Orden estable: declarar agrega al final; nunca se reordena lo demás.

local model = require("core/model")

local M = {}

function M.new(profile, opts)
  opts = opts or {}
  return {
    profile = profile,
    declared = {},          -- lista de def_index, en orden de inserción
    states = {},            -- states[i] ↔ declared[i]
    active = 1,             -- índice sobre declared
    frozen = opts.frozen or false, -- modo "layout fijo" (default en torneo)
    ghosting_budget = opts.ghosting_budget or 10,
    partials = {},          -- refrescos parciales acumulados por zona
  }
end

function M.set_ghosting_budget(s, n)
  s.ghosting_budget = n
end

local function find_declared(s, def_index)
  for i, d in ipairs(s.declared) do
    if d == def_index then return i end
  end
  return nil
end

-- Zona (índice de rect del layout) donde vive el token declarado i.
-- Con 1–4 tipos el mapeo es directo. Con 5–6, el activo ocupa la zona
-- principal (rect 1) y el resto llena la franja en orden de inserción.
function M.zone_of(s, token_index)
  local n = #s.declared
  if n <= 4 then return token_index end
  if token_index == s.active then return 1 end
  local zone = 1
  for i = 1, n do
    if i ~= s.active then
      zone = zone + 1
      if i == token_index then return zone end
    end
  end
end

local function reset_partials(s)
  s.partials = {}
end

-- Consume presupuesto de ghosting de cada zona tocada. Si alguna llega al
-- umbral, esa zona pide refresco completo (y su contador se reinicia).
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

-- ---- Set de tipos (las únicas fuentes de reflow) ----

function M.declare(s, def_index)
  if s.frozen then return { kind = "blocked", reason = "frozen" } end
  if find_declared(s, def_index) then return { kind = "none" } end
  if #s.declared >= 6 then return { kind = "blocked", reason = "max_types" } end
  s.declared[#s.declared + 1] = def_index
  s.states[#s.states + 1] = model.token_state(def_index)
  if #s.declared == 1 then s.active = 1 end
  reset_partials(s)
  return { kind = "reflow" }
end

function M.undeclare(s, def_index)
  if s.frozen then return { kind = "blocked", reason = "frozen" } end
  local i = find_declared(s, def_index)
  if not i then return { kind = "none" } end
  table.remove(s.declared, i)
  table.remove(s.states, i)
  if s.active > #s.declared then s.active = math.max(1, #s.declared) end
  reset_partials(s)
  return { kind = "reflow" }
end

-- ---- Operaciones de partida (nunca reflow) ----

function M.cycle_active(s, dir)
  local n = #s.declared
  if n <= 1 then return { kind = "none" } end
  local old = s.active
  s.active = (s.active - 1 + (dir or 1)) % n + 1
  if n <= 4 then
    -- solo cambia el resaltado: repintar la zona vieja y la nueva
    return partial_event(s, { M.zone_of(s, old), M.zone_of(s, s.active) })
  end
  -- con franja lateral, el activo ocupa la zona principal: cambia el
  -- contenido de la principal y de la miniatura que recibe al anterior
  return partial_event(s, { 1, M.zone_of(s, old) })
end

local function active_state(s)
  return s.states[s.active]
end

function M.inc(s)
  local st = active_state(s)
  if not st then return { kind = "none" } end
  if st.count_a + st.count_b >= model.COUNT_MAX then return { kind = "none" } end
  st.count_a = st.count_a + 1
  return partial_event(s, { M.zone_of(s, s.active) })
end

-- Resta tapped primero (heurística validada en el prototipo web). Llegar a
-- 0 total solo atenúa la zona: JAMÁS reflow.
function M.dec(s)
  local st = active_state(s)
  if not st then return { kind = "none" } end
  if st.count_b > 0 then
    st.count_b = st.count_b - 1
  elseif st.count_a > 0 then
    st.count_a = st.count_a - 1
  else
    return { kind = "none" }
  end
  return partial_event(s, { M.zone_of(s, s.active) })
end

function M.tap_one(s)
  local st = active_state(s)
  if not st or st.count_a == 0 then return { kind = "none" } end
  st.count_a = st.count_a - 1
  st.count_b = st.count_b + 1
  return partial_event(s, { M.zone_of(s, s.active) })
end

function M.untap_one(s)
  local st = active_state(s)
  if not st or st.count_b == 0 then return { kind = "none" } end
  st.count_b = st.count_b - 1
  st.count_a = st.count_a + 1
  return partial_event(s, { M.zone_of(s, s.active) })
end

return M
