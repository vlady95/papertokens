-- Pruebas del lector de archivos de mazo y del registro de uso.
--   luajit tests/test-library.lua

package.path = "./?.lua;" .. package.path

local deckfile = require("core/deckfile")
local registry = require("core/registry")

local fails, checks = 0, 0
local function check(cond, label)
  checks = checks + 1
  if not cond then fails = fails + 1; print("  FALLA: " .. label) end
end

-- ---- archivo real, tal como lo genera la webapp ----
print("lectura de archivo")
local FILE = table.concat({
  "PAPERTOKENS 1",
  "# comentario que documenta el formato",
  "# los saltos van como \\n y la barra literal como \\\\",
  "",
  "deck-id 5a8187f84690b6f8",
  "deck-name Jund Wildfire",
  "",
  "token",
  "name Eldrazi Spawn",
  "oracle-id 3aaf906a-e749-4e86-ac79-97650b92f271",
  "type Token Creature — Eldrazi Spawn",
  "pt 0/1",
  "colors ",
  "icon eldrazi-spawn",
  "rules Sacrifice this creature: Add {C}.",
  "",
  "token",
  "name Angel",
  "oracle-id aaaa",
  "type Token Creature — Angel",
  "pt 4/4",
  "colors WB",
  "icon ",
  "rules Flying\\n//\\nVigilance",
  "",
  "token",
  "name Map",
  "oracle-id bbbb",
  "type Token Artifact — Map",
  "colors ",
  "icon map",
  "rules {1}, {T}: explora.",
  "",
}, "\n")

local deck, err = deckfile.parse(FILE)
check(deck ~= nil, "el archivo se lee: " .. tostring(err))
check(deck.id == "5a8187f84690b6f8", "deck-id")
check(deck.name == "Jund Wildfire", "deck-name")
check(#deck.tokens == 3, "tres tokens (leyó " .. #deck.tokens .. ")")

local spawn, angel, map = deck.tokens[1], deck.tokens[2], deck.tokens[3]
check(spawn.name == "Eldrazi Spawn" and spawn.power == "0" and spawn.toughness == "1",
  "nombre y fuerza/resistencia")
check(spawn.is_creature and not map.is_creature, "criatura se distingue de artefacto")
check(spawn.icon == "eldrazi-spawn" and angel.icon == "", "clave de icono, vacía incluida")
check(#angel.colors == 2 and angel.colors[1] == "W" and angel.colors[2] == "B",
  "colores como lista")
check(#spawn.colors == 0, "incoloro es lista vacía")
check(angel.rules == "Flying\n//\nVigilance",
  "saltos de línea revertidos: " .. string.format("%q", angel.rules))
check(deck.tokens[3].type_line == "Token Artifact — Map", "acentos y guion largo intactos")

-- el caso feo del escapado: barra literal seguida de ene
check(deckfile.decode_value("a\\\\nb") == "a\\nb",
  "\\\\n es barra literal + ene, no un salto")
check(deckfile.decode_value("a\\nb") == "a\nb", "\\n sí es un salto")

-- ---- rechazos ----
print("validación")
local bad = {
  { "", "archivo vacío" },
  { "OTRACOSA 1\ndeck-id x\n", "marcador desconocido" },
  { "PAPERTOKENS 99\ndeck-id x\ndeck-name y\n\ntoken\nname a\noracle-id b\ntype c\n",
    "versión futura" },
  { "PAPERTOKENS 1\ndeck-name y\n\ntoken\nname a\noracle-id b\ntype c\n", "sin deck-id" },
  { "PAPERTOKENS 1\ndeck-id x\ndeck-name y\n", "sin tokens" },
  { "PAPERTOKENS 1\ndeck-id x\ndeck-name y\n\ntoken\nname a\ntype c\n",
    "token sin oracle-id (archivo truncado)" },
  { "PAPERTOKENS 1\ndeck-id x\ndeck-name y\n\ntoken\nname a\noracle-id b\ntype c\npt abc\n",
    "pt ilegible" },
}
for _, caso in ipairs(bad) do
  local d, e = deckfile.parse(caso[1])
  check(d == nil and e ~= nil, "rechaza: " .. caso[2] .. " (motivo: " .. tostring(e) .. ")")
end

-- un archivo malo no debe dejar tokens a medias
local truncado = "PAPERTOKENS 1\ndeck-id x\ndeck-name y\n\ntoken\nname A\noracle-id 1\ntype T\n\ntoken\nname B\n"
check(deckfile.parse(truncado) == nil, "un token roto invalida el archivo entero")

-- claves desconocidas no rompen: el formato puede crecer
local futuro = FILE:gsub("icon map", "icon map\nfuturo algo-nuevo")
check(deckfile.parse(futuro) ~= nil, "una clave desconocida se ignora, no rompe")

-- ---- registro de uso ----
print("registro de uso")
local reg = registry.decode("aaa 1000\nbbb 2000\nbasura\n")
check(reg.aaa == 1000 and reg.bbb == 2000, "decodifica")
check(registry.decode(registry.encode(reg)).bbb == 2000, "viaje redondo")

registry.touch(reg, "ccc", 3000)
check(reg.ccc == 3000, "marca de uso")

local decks = {
  { id = "aaa", name = "Zurg" }, { id = "bbb", name = "Alfa" },
  { id = "ccc", name = "Medio" }, { id = "ddd", name = "Nunca usado" },
}
local ordered = registry.order(decks, reg)
check(ordered[1].id == "ccc" and ordered[2].id == "bbb" and ordered[3].id == "aaa",
  "orden por uso reciente")
check(ordered[4].id == "ddd", "los nunca usados van al final")

local _, removed = registry.prune(reg, { "aaa", "ccc" })
check(removed == 1 and reg.bbb == nil and reg.aaa == 1000,
  "se limpian las entradas sin archivo presente")

-- el historial sobrevive a renombrar: el índice es el id, no el nombre
local renamed = { { id = "aaa", name = "Otro nombre completamente" } }
check(registry.order(renamed, reg)[1].id == "aaa" and reg.aaa == 1000,
  "renombrar el mazo no pierde su historial")

check(registry.SESSION_MARK_SECONDS == 600, "la marca se cruza a los diez minutos")

print(string.format("\n%d checks, %d fallas", checks, fails))
os.exit(fails == 0 and 0 or 1)
