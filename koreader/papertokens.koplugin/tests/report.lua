-- Reporte de calibración: qué tiers salen con la geometría REAL del
-- dispositivo, ya descontadas la franja de botones y la de estado.
--   luajit tests/report.lua
--
-- Es el dato que esta fase debe producir para ajustar config/thresholds.lua.

package.path = "./?.lua;" .. package.path

local layout = require("core/layout")
local config = require("config/thresholds")

local function mm(px, dpi) return px / dpi * 25.4 end
local function px(mm_, dpi) return math.floor(mm_ * dpi / 25.4 + 0.5) end

local devices = {
  { name = "Kindle PW3 landscape", w = 1448, h = 1072, dpi = 300 },
  { name = "Panel objetivo",       w = 800,  h = 480,  dpi = 125 },
}

for _, d in ipairs(devices) do
  local bar = px(config.button_bar_mm or 0, d.dpi)
  local status = px(config.status_bar_mm or 0, d.dpi)
  local cw, ch = d.w, d.h - bar - status
  print(string.format("\n=== %s ===", d.name))
  print(string.format("pantalla %dx%d px = %.1f x %.1f mm @ %d dpi",
    d.w, d.h, mm(d.w, d.dpi), mm(d.h, d.dpi), d.dpi))
  print(string.format("contenido %dx%d px = %.1f x %.1f mm (botones %d px, estado %d px)",
    cw, ch, mm(cw, d.dpi), mm(ch, d.dpi), bar, status))
  for n = 1, 6 do
    local rects = layout.layout(cw, ch, d.dpi, n, config)
    local parts = {}
    for i, r in ipairs(rects) do
      parts[i] = string.format("%.0fx%.0fmm %s", mm(r.w, d.dpi), mm(r.h, d.dpi), r.tier)
    end
    print(string.format("  n=%d  %s", n, table.concat(parts, " | ")))
  end
end
print("")
