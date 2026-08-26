-- config/thresholds.lua — parámetros de calibración de los tiers, en mm.
--
-- NO son constantes: el punto de esta fase es ajustarlos contra hardware
-- real. Editar este archivo y reiniciar KOReader; nada se recompila.
--
--   FULL    : ícono + nombre + P/T + cantidad + indicador de color
--   COMPACT : ícono + cantidad + indicador de color
--   MINIMAL : cantidad sola

return {
  full = { w_mm = 45, h_mm = 35 },
  compact = { w_mm = 25, h_mm = 20 },

  -- Presupuesto de ghosting: refrescos parciales por zona antes de forzar
  -- un refresco completo de esa zona. Ajustable también en runtime.
  ghosting_budget = 10,

  -- Detección de pulsación larga, en ms.
  long_press_ms = 600,
}
