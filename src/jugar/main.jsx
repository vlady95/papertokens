import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.jsx'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <App />
  </StrictMode>,
)

// PWA: un solo service worker para las dos apps, en la raíz del sitio.
// Su scope (/papertokens/) cubre también esta página anidada, así que las
// dos funcionan sin conexión con un único precache.
if ('serviceWorker' in navigator && import.meta.env.PROD) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('../sw.js').catch((err) => {
      console.error('Service worker no registrado:', err)
    })
  })
}
