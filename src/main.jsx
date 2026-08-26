import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.jsx'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <App />
  </StrictMode>,
)

// PWA: el service worker solo existe en el build publicado (docs/sw.js,
// generado por scripts/build-sw.mjs). Ruta relativa para funcionar bajo la
// subruta /papertokens/ de GitHub Pages.
if ('serviceWorker' in navigator && import.meta.env.PROD) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('sw.js').catch((err) => {
      console.error('Service worker no registrado:', err)
    })
  })
}
