-- core/registry.lua — registro interno de último uso de cada mazo.
--
-- MÓDULO PURO: sin require de KOReader, sin I/O. El caller lee y escribe el
-- archivo; aquí solo vive la lógica, para poder probarla en la Mac.
--
-- Por qué existe: el orden de la biblioteca NO puede salir de la fecha de
-- modificación del archivo. Copiar por USB reescribe los timestamps y todos
-- los mazos parecerían recién usados.
--
-- Se indexa por el IDENTIFICADOR ESTABLE del mazo, no por nombre ni por
-- ruta: renombrar el archivo o el mazo no rompe el historial.
--
-- Formato del archivo de registro, una línea por mazo:
--   <deck_id> <epoch>

local M = {}

M.SESSION_MARK_SECONDS = 10 * 60

function M.decode(text)
  local reg = {}
  if type(text) ~= "string" then return reg end
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local id, when = line:match("^(%S+)%s+(%d+)%s*$")
    if id then reg[id] = tonumber(when) end
  end
  return reg
end

function M.encode(reg)
  local ids = {}
  for id in pairs(reg) do ids[#ids + 1] = id end
  table.sort(ids)
  local out = {}
  for _, id in ipairs(ids) do
    out[#out + 1] = string.format("%s %d", id, reg[id])
  end
  out[#out + 1] = ""
  return table.concat(out, "\n")
end

-- La marca se escribe al CRUZAR los diez minutos de sesión, no al cerrarla:
-- una sesión más corta es una apertura accidental, y si solo se guardara al
-- salir nunca se guardaría.
function M.touch(reg, deck_id, when)
  reg[deck_id] = when
  return reg
end

-- Al reescanear se limpian las entradas que ya no corresponden a ningún
-- archivo presente. Devuelve el registro y cuántas se fueron.
function M.prune(reg, present_ids)
  local present = {}
  for _, id in ipairs(present_ids) do present[id] = true end
  local removed = 0
  for id in pairs(reg) do
    if not present[id] then
      reg[id] = nil
      removed = removed + 1
    end
  end
  return reg, removed
end

-- Mazos por uso reciente; los nunca usados van al final, por nombre.
function M.order(decks, reg)
  local sorted = {}
  for i, d in ipairs(decks) do sorted[i] = d end
  table.sort(sorted, function(a, b)
    local ta, tb = reg[a.id] or 0, reg[b.id] or 0
    if ta ~= tb then return ta > tb end
    return (a.name or "") < (b.name or "")
  end)
  return sorted
end

return M
