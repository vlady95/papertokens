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

  -- Detección de pulsación larga, en ms. VERIFICADO en el device: KOReader
  -- v2026.07.1 usa HOLD_INTERVAL_MS = 500 global (ajustable con el setting
  -- ges_hold_interval_ms). El gesto "hold" que consume este plugin dispara
  -- con ESE valor, no con el de aquí; este queda como referencia del target.
  long_press_ms = 600,

  -- Franja inferior con las tres zonas táctiles que simulan BTN_A/B/C.
  -- El hardware final tiene botones físicos fuera del panel; aquí roban
  -- alto, lo que hace el caso aún más restrictivo. 0 = sin franja (las
  -- zonas táctiles quedarían encima del contenido).
  button_bar_mm = 12,

  -- Alto de la franja de estado (instrumentación de refrescos). 0 = sin
  -- franja; el log sigue yendo a crash.log de cualquier forma.
  status_bar_mm = 5,
}
