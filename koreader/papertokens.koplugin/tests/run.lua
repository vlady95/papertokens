-- Tests de core/ en el Mac, sin KOReader:
--   luajit tests/run.lua       (desde koreader/papertokens.koplugin/)
--
-- Verifica que el motor de layout y la máquina de sesión se comporten como
-- la app web, contra las dimensiones reales del Kindle PW3 en vertical
-- (1072x1448 @ 300 dpi) y del panel objetivo.

package.path = "./?.lua;" .. package.path

local layout = require("core/layout")
local model = require("core/model")
local session = require("core/session")

local failures, checks = 0, 0
local function check(cond, label)
  checks = checks + 1
  if not cond then
    failures = failures + 1
    print("  FALLA: " .. label)
  end
end

local function overlap(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local DEVICES = {
  { name = "Kindle PW3 vertical", w = 1072, h = 1448 - 150 - 190, dpi = 300 },
  { name = "Panel objetivo",      w = 800,  h = 480 - 60 - 80,    dpi = 125 },
}
local OPTS = { pill_h = 90, gap = 12, orb = 96 }

for _, d in ipairs(DEVICES) do
  print("layout @ " .. d.name)
  for n = 1, layout.MAX_ACTIVE do
    local zones = layout.layout(d.w, d.h, n, OPTS)
    check(#zones == n, d.name .. " n=" .. n .. ": " .. n .. " zonas")

    for i, z in ipairs(zones) do
      -- la carta jamás se estira
      local ratio = z.card.w / z.card.h
      local want = layout.CARD_W / layout.CARD_H
      check(math.abs(ratio - want) < 0.02,
        string.format("%s n=%d carta %d proporción %.3f (esperada %.3f)",
          d.name, n, i, ratio, want))
      -- dentro de la celda y de pantalla
      check(z.card.x >= 0 and z.card.y >= 0
        and z.card.x + z.card.w <= d.w and z.card.y + z.card.h <= d.h,
        d.name .. " n=" .. n .. " carta " .. i .. " dentro de pantalla")
      check(z.card.y >= z.cell.y + OPTS.pill_h,
        d.name .. " n=" .. n .. " carta " .. i .. " debajo de su píldora")
      -- celdas sin traslape
      for j = i + 1, #zones do
        check(not overlap(z.cell, zones[j].cell),
          d.name .. " n=" .. n .. ": celdas " .. i .. " y " .. j .. " no se enciman")
      end
    end

    -- n=3: las tres cartas del mismo tamaño (regla de la web)
    if n == 3 then
      check(zones[1].card.w == zones[3].card.w and zones[1].card.h == zones[3].card.h,
        d.name .. " n=3: la carta de abajo mide igual que las de arriba")
    end
  end
end

-- Con la proporción del teléfono, la regla "maximiza la carta" debe elegir
-- exactamente las plantillas de la app web. Si esto falla, el port dejó de
-- ser fiel a la web y se volvió un rediseño.
print("fidelidad con la app web (375x616 @ 2x, medidas del CSS)")
local WEB = { pill_h = 48, gap = 8, orb = 48 }
local web_expected = {
  [1] = { 1, 1 },  -- una carta a pantalla
  [2] = { 1, 2 },  -- dos apiladas verticalmente
  [3] = { 2, 2 },  -- dos arriba y una abajo, centrada
  [4] = { 2, 2 },  -- cuadrícula 2x2
}
for n = 1, 4 do
  local cols, rows = layout.arrangement(375, 616, n, WEB)
  local want = web_expected[n]
  check(cols == want[1] and rows == want[2],
    string.format("web n=%d: %dx%d (esperado %dx%d)", n, cols, rows, want[1], want[2]))
end
-- Y en una pantalla más ancha la misma regla reparte distinto, en vez de
-- desperdiciar el ancho apilando.
local kcols, krows = layout.arrangement(1072, 928, 2, { pill_h = 130, gap = 24, orb = 130 })
check(kcols == 2 and krows == 1,
  string.format("Kindle n=2: %dx%d (dos columnas, no apiladas)", kcols, krows))

-- El layout depende solo de n, nunca de las cantidades.
print("layout estable")
local a = layout.layout(1072, 1108, 2, OPTS)
local b = layout.layout(1072, 1108, 2, OPTS)
check(a[1].card.w == b[1].card.w and a[2].card.y == b[2].card.y,
  "mismo n ⇒ mismo layout")

-- ---- sesión: el guion de la partida real ----
print("sesión (guion de la web)")
local s = session.new(require("tests/fixture"))
local A = 2 -- un token cualquiera del mazo de ejemplo

local function counts(i)
  local t = s.active[i]
  if not t then return "(fuera)" end
  return t.count_a .. " destapados, " .. t.count_b .. " tapeados"
end

check(session.create(s, A).kind == "reflow", "tipo nuevo ⇒ reflow")
check(session.create(s, A).kind == "partial", "misma cantidad ⇒ parcial, nunca reflow")
session.create(s, A)
check(counts(1) == "3 destapados, 0 tapeados", "creo 3: " .. counts(1))

session.tap(s, 1)
session.tap(s, 1)
check(counts(1) == "1 destapados, 2 tapeados", "ataco con 2: " .. counts(1))

session.destroy(s, 1)
check(counts(1) == "1 destapados, 1 tapeados", "uno muere bloqueando: " .. counts(1))

session.untap_all(s)
check(counts(1) == "2 destapados, 0 tapeados", "untap all: " .. counts(1))

-- destruir hasta cero saca el tipo (comportamiento de la web) ⇒ reflow
session.destroy(s, 1)
check(session.is_last(s, 1), "con 1 token el orbe − es bote de basura")
check(session.destroy(s, 1).kind == "reflow", "llegar a 0 saca el tipo ⇒ reflow")
check(#s.active == 0, "la zona activa queda vacía")

-- orden de inserción estable
for _, d in ipairs({ 1, 3, 5 }) do session.create(s, d) end
check(s.active[1].def_index == 1 and s.active[2].def_index == 3
  and s.active[3].def_index == 5, "orden de inserción")
session.create(s, 2)
check(s.active[4].def_index == 2 and s.active[1].def_index == 1,
  "un tipo nuevo nunca reordena los existentes")
check(session.create(s, 6).kind == "none", "tope de 4 tipos simultáneos")

-- untap por tipo: no toca a los demás
session.tap(s, 1)
session.tap(s, 2)
session.untap_type(s, 1)
check(s.active[1].count_b == 0 and s.active[2].count_b == 1,
  "untap de un tipo no destapa los otros")

-- tope de cantidad
for _ = 1, 12 do session.create(s, 1) end
check(s.active[1].count_a + s.active[1].count_b == model.COUNT_MAX,
  "cantidad topada en " .. model.COUNT_MAX)

-- reiniciar partida
check(session.reset(s).kind == "reflow", "reiniciar ⇒ reflow")
check(#s.active == 0, "reiniciar vacía la zona activa")

-- presupuesto de ghosting
local g = session.new(require("tests/fixture"), { ghosting_budget = 3 })
session.create(g, 1)
session.create(g, 1)
session.create(g, 1)
check(session.create(g, 1).kind == "zone_full",
  "al agotar el presupuesto la zona pide refresco completo")
check(session.create(g, 1).kind == "partial", "y el contador se reinicia")

print(string.format("\n%d checks, %d fallas", checks, failures))
os.exit(failures == 0 and 0 or 1)
