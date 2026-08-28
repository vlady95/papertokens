-- core/deckfile.lua — lector del archivo .txt de mazo.
--
-- MÓDULO PURO: sin require de KOReader, sin I/O. Recibe el texto completo
-- del archivo y devuelve el mazo, o nil y el motivo del rechazo.
--
-- El plugin no tiene red y no sabe nada de Magic: no consulta nada, no
-- deduce, no completa datos que falten. Solo lee y valida.
--
-- Un archivo truncado o editado a mano NO debe dejar la biblioteca a
-- medias: si un token no valida, se rechaza el archivo ENTERO y el caller
-- reporta cuál falló y sigue con los demás. Media biblioteca en la mesa es
-- peor que un mazo de menos.

local M = {}

M.FORMAT = "PAPERTOKENS"
M.VERSION = 1

-- Los valores traen los saltos de línea codificados como \n y la barra
-- invertida literal como \\. Se revierte en UNA pasada de izquierda a
-- derecha: encadenar dos reemplazos rompería "\\n" (barra literal seguida
-- de ene), que es exactamente el caso que el escapado protege.
function M.decode_value(s)
  local out = {}
  local i = 1
  local n = #s
  while i <= n do
    local c = s:sub(i, i)
    if c == "\\" and i < n then
      local nxt = s:sub(i + 1, i + 1)
      if nxt == "\\" then
        out[#out + 1] = "\\"
        i = i + 2
      elseif nxt == "n" then
        out[#out + 1] = "\n"
        i = i + 2
      else
        out[#out + 1] = c
        i = i + 1
      end
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

local REQUIRED = { "name", "oracle_id", "type_line" }

local function finish_token(tok, index)
  for _, field in ipairs(REQUIRED) do
    if not tok[field] or tok[field] == "" then
      return nil, string.format("token %d sin campo \"%s\"", index, field)
    end
  end
  tok.colors = tok.colors or {}
  tok.rules = tok.rules or ""
  tok.icon = tok.icon or ""
  tok.is_creature = tok.power ~= nil
  return tok
end

-- text: contenido completo del archivo.
-- Devuelve { id, name, tokens = { ... } } o nil, motivo.
function M.parse(text)
  if type(text) ~= "string" or text == "" then
    return nil, "archivo vacío"
  end

  local lines = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = (line:gsub("\r$", ""))
  end

  -- Marcador de versión en la primera línea. El formato va a cambiar
  -- varias veces; lo que no se reconozca se rechaza, no se adivina.
  local fmt, ver = (lines[1] or ""):match("^(%S+)%s+(%d+)%s*$")
  if fmt ~= M.FORMAT then
    return nil, "no es un archivo de PaperTokens"
  end
  if tonumber(ver) ~= M.VERSION then
    return nil, string.format("versión de formato %s, este plugin lee %d", ver, M.VERSION)
  end

  local deck = { id = nil, name = nil, tokens = {} }
  local tok = nil
  local tok_index = 0

  for i = 2, #lines do
    local line = lines[i]
    if line:sub(1, 1) == "#" then
      -- comentario
    elseif line == "" then
      if tok then
        local ok, err = finish_token(tok, tok_index)
        if not ok then return nil, err end
        deck.tokens[#deck.tokens + 1] = ok
        tok = nil
      end
    elseif line == "token" then
      if tok then
        local ok, err = finish_token(tok, tok_index)
        if not ok then return nil, err end
        deck.tokens[#deck.tokens + 1] = ok
      end
      tok_index = tok_index + 1
      tok = {}
    else
      local key, value = line:match("^(%S+)%s?(.*)$")
      if not key then
        return nil, string.format("línea %d ilegible", i)
      end
      if tok then
        if key == "name" then tok.name = M.decode_value(value)
        elseif key == "oracle-id" then tok.oracle_id = value
        elseif key == "type" then tok.type_line = M.decode_value(value)
        elseif key == "icon" then tok.icon = value
        elseif key == "rules" then tok.rules = M.decode_value(value)
        elseif key == "colors" then
          local colors = {}
          for c in value:gmatch("[A-Z]") do colors[#colors + 1] = c end
          tok.colors = colors
        elseif key == "pt" then
          local p, t = value:match("^(-?%w+)/(-?%w+)$")
          if not p then
            return nil, string.format("token %d con pt ilegible: %q", tok_index, value)
          end
          tok.power, tok.toughness = p, t
        end
        -- claves desconocidas: se ignoran, para que el formato pueda crecer
      else
        if key == "deck-id" then deck.id = value
        elseif key == "deck-name" then deck.name = M.decode_value(value) end
      end
    end
  end

  if tok then
    local ok, err = finish_token(tok, tok_index)
    if not ok then return nil, err end
    deck.tokens[#deck.tokens + 1] = ok
  end

  if not deck.id or deck.id == "" then return nil, "sin deck-id" end
  if not deck.name or deck.name == "" then return nil, "sin deck-name" end
  if #deck.tokens == 0 then return nil, "sin tokens" end

  return deck
end

return M
