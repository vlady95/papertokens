-- config/thresholds.lua — parámetros de calibración. Editar y reabrir el
-- plugin; no se recompila nada.
--
-- Todo en MILÍMETROS, no píxeles: un botón de 130 px es cómodo a 300 dpi e
-- inusable a 125. Las medidas físicas sobreviven al cambio de panel.

return {
  -- Franja superior: Reiniciar partida | UNTAP ALL | Salir
  header_mm = 22,

  -- Franja inferior: carrusel del catálogo, paginado por taps
  carousel_mm = 22,

  -- Orbes − / + montados sobre los bordes de la carta. 11 mm ≈ el target
  -- táctil de 48 px de la web en un teléfono.
  orb_mm = 11,

  -- Píldora de contadores sobre cada carta
  pill_mm = 11,

  -- Carpeta de mazos, hermana de koreader/ en la raíz de la partición: al
  -- montar el Kindle por USB queda a la vista, sin buscar entre carpetas
  -- del sistema.
  decks_folder = "papertokens",

  -- Subcarpeta a donde va lo archivado. Archivar es el "quitar de la
  -- biblioteca" reversible: mueve el archivo, no lo borra.
  archive_folder = "archivados",

  -- Presupuesto de ghosting: refrescos parciales por zona antes de forzar
  -- un refresco completo de esa zona.
  ghosting_budget = 10,

  -- Modo de refresco parcial por defecto: "fast" o "ui". Alternable desde
  -- el menú del plugin para compararlos en pantalla real.
  partial_mode = "fast",

  -- Nota verificada en el device: el gesto "hold" de la vista expandida
  -- dispara con HOLD_INTERVAL_MS = 500 de KOReader (setting global
  -- ges_hold_interval_ms), no con un valor propio del plugin.
}
