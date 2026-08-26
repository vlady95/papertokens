-- Tests de core/ corriendo en el Mac, sin KOReader:
--   luajit tests/run.lua        (desde koreader/papertokens.koplugin/)
--
-- Verifica el motor de layout contra las dimensiones del Kindle PW3 en
-- horizontal (1448x1072 @ 300 dpi) y contra el panel objetivo (800x480 @
-- 125 dpi), y las reglas duras de la máquina de sesión.

package.path = "./?.lua;" .. package.path

local layout = require("core/layout")
local model = require("core/model")
local session = require("core/session")

local failures = 0
local checks = 0

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

local function verify_geometry(rects, w, h, label)
  for i, r in ipairs(rects) do
    check(r.x >= 0 and r.y >= 0 and r.x + r.w <= w and r.y + r.h <= h,
      label .. ": rect " .. i .. " dentro de pantalla")
    check(r.w > 0 and r.h > 0, label .. ": rect " .. i .. " con área")
    for j = i + 1, #rects do
      check(not overlap(r, rects[j]),
        label .. ": rects " .. i .. " y " .. j .. " no se enciman")
    end
  end
end

local function tiers_of(rects)
  local t = {}
  for i, r in ipairs(rects) do t[i] = r.tier end
  return table.concat(t, ",")
end

-- ---- layout: Kindle PW3 horizontal ----
print("layout @ Kindle PW3 (1448x1072, 300 dpi, horizontal)")
local expected_kindle = {
  [1] = "FULL",
  [2] = "FULL,FULL",
  [3] = "FULL,FULL,FULL",
  [4] = "FULL,FULL,FULL,FULL",
  [5] = "FULL,COMPACT,COMPACT,COMPACT,COMPACT",
  [6] = "FULL,MINIMAL,MINIMAL,MINIMAL,MINIMAL,MINIMAL",
}
for n = 1, 6 do
  local rects = layout.layout(1448, 1072, 300, n)
  check(#rects == n, "kindle n=" .. n .. ": " .. n .. " rects")
  verify_geometry(rects, 1448, 1072, "kindle n=" .. n)
  check(tiers_of(rects) == expected_kindle[n],
    "kindle n=" .. n .. ": tiers " .. expected_kindle[n] .. " (obtuvo " .. tiers_of(rects) .. ")")
end

-- ---- layout: panel objetivo ----
print("layout @ panel objetivo (800x480, 125 dpi)")
local expected_target = {
  [1] = "FULL",
  [2] = "FULL,FULL",
  [3] = "FULL,FULL,FULL",
  [4] = "FULL,FULL,FULL,FULL",
  [5] = "FULL,COMPACT,COMPACT,COMPACT,COMPACT",
  [6] = "FULL,MINIMAL,MINIMAL,MINIMAL,MINIMAL,MINIMAL",
}
for n = 1, 6 do
  local rects = layout.layout(800, 480, 125, n)
  check(#rects == n, "target n=" .. n .. ": " .. n .. " rects")
  verify_geometry(rects, 800, 480, "target n=" .. n)
  check(tiers_of(rects) == expected_target[n],
    "target n=" .. n .. ": tiers " .. expected_target[n] .. " (obtuvo " .. tiers_of(rects) .. ")")
end

-- ---- umbral en mm, no en píxeles: mismo px, distinto dpi ----
print("umbrales físicos (mismos px, distinto dpi)")
local hi = layout.layout(1448, 1072, 300, 6)
local lo = layout.layout(1448, 1072, 125, 6)
check(hi[2].tier == "MINIMAL" and lo[2].tier == "FULL",
  "el mismo rect en px cambia de tier con el dpi")

-- ---- sesión: orden estable y reglas de reflow ----
print("sesión")
local profile = model.pauper_profile()
local s = session.new(profile)

check(session.declare(s, 1).kind == "reflow", "declarar dispara reflow")
session.declare(s, 3)
session.declare(s, 5)
check(s.declared[1] == 1 and s.declared[2] == 3 and s.declared[3] == 5,
  "orden de inserción")
session.declare(s, 2)
check(s.declared[1] == 1 and s.declared[2] == 3 and s.declared[3] == 5 and s.declared[4] == 2,
  "declarar nuevo NUNCA reordena los existentes")
check(session.declare(s, 2).kind == "none", "declarar duplicado no hace nada")

-- la cantidad nunca dispara reflow, ni al llegar a 0
local ev = session.inc(s)
check(ev.kind == "partial", "inc → partial")
session.inc(s)
ev = session.tap_one(s)
check(ev.kind == "partial", "tap_one → partial")
ev = session.dec(s) -- resta tapped primero
check(s.states[1].count_b == 0 and s.states[1].count_a == 1, "dec resta tapped primero")
session.dec(s)
ev = session.dec(s) -- ya en 0
check(ev.kind == "none", "dec en 0 no hace nada (y jamás reflow)")
check(#s.declared == 4, "llegar a 0 no elimina el tipo")

-- tope de cantidad
for _ = 1, 12 do session.inc(s) end
check(s.states[1].count_a == model.COUNT_MAX, "cantidad topada en " .. model.COUNT_MAX)

-- ciclado
local old_active = s.active
ev = session.cycle_active(s, 1)
check(s.active == old_active + 1 and ev.kind == "partial" and #ev.zones == 2,
  "ciclar repinta dos zonas, sin reflow")

-- presupuesto de ghosting
local s2 = session.new(profile, { ghosting_budget = 3 })
session.declare(s2, 1)
session.inc(s2); session.inc(s2)
ev = session.inc(s2)
check(ev.kind == "zone_full" and ev.zones[1] == 1,
  "al agotar presupuesto la zona pide refresco completo")
ev = session.inc(s2)
check(ev.kind == "partial", "tras el refresco completo el contador se reinicia")

-- modo layout fijo
local s3 = session.new(profile, { frozen = true })
check(session.declare(s3, 1).kind == "blocked", "layout fijo bloquea declarar")

-- zonas en n=5: el activo ocupa la principal
local s5 = session.new(profile)
for i = 1, 5 do session.declare(s5, i) end
s5.active = 3
check(session.zone_of(s5, 3) == 1, "n=5: el activo vive en la zona principal")
check(session.zone_of(s5, 1) == 2 and session.zone_of(s5, 2) == 3 and
      session.zone_of(s5, 4) == 4 and session.zone_of(s5, 5) == 5,
  "n=5: los demás llenan la franja en orden de inserción")

print(string.format("\n%d checks, %d fallas", checks, failures))
os.exit(failures == 0 and 0 or 1)
