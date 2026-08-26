-- Reporte de geometría: qué tamaño tiene la carta con la geometría REAL del
-- dispositivo, ya descontadas las franjas de header y carrusel.
--   luajit tests/report.lua

package.path = "./?.lua;" .. package.path

local layout = require("core/layout")
local config = require("config/thresholds")

local function mm(px, dpi) return px / dpi * 25.4 end
local function px(v, dpi) return math.floor(v * dpi / 25.4 + 0.5) end

local devices = {
  { name = "Kindle PW3 vertical", w = 1072, h = 1448, dpi = 300 },
  { name = "Panel objetivo",      w = 480,  h = 800,  dpi = 125 },
}

for _, d in ipairs(devices) do
  local header = px(config.header_mm, d.dpi)
  local carousel = px(config.carousel_mm, d.dpi)
  local opts = {
    pill_h = px(config.pill_mm, d.dpi),
    gap = px(2, d.dpi),
    orb = px(config.orb_mm, d.dpi),
  }
  local cw, ch = d.w, d.h - header - carousel
  print(string.format("\n=== %s ===", d.name))
  print(string.format("pantalla %dx%d px = %.1f x %.1f mm @ %d dpi",
    d.w, d.h, mm(d.w, d.dpi), mm(d.h, d.dpi), d.dpi))
  print(string.format("zona activa %dx%d px = %.1f x %.1f mm",
    cw, ch, mm(cw, d.dpi), mm(ch, d.dpi)))
  for n = 1, layout.MAX_ACTIVE do
    local zones = layout.layout(cw, ch, n, opts)
    local c = zones[1].card
    print(string.format("  n=%d  carta %dx%d px = %.0f x %.0f mm  (carta real: 63 x 88 mm)",
      n, c.w, c.h, mm(c.w, d.dpi), mm(c.h, d.dpi)))
  end
end
print("")
