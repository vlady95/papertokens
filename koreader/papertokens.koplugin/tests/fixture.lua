-- Carga el mazo de ejemplo: un archivo generado de verdad por la webapp
-- contra Scryfall, no un objeto inventado en el test.
local deckfile = require("core/deckfile")

local f = assert(io.open("tests/fixtures/jund-wildfire.txt", "r"),
  "falta tests/fixtures/jund-wildfire.txt")
local text = f:read("*a")
f:close()

local deck, err = deckfile.parse(text)
assert(deck, "el mazo de ejemplo no valida: " .. tostring(err))
return deck
