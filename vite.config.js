import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { resolve } from 'node:path'

// Dos apps en el mismo sitio:
//   /            generador — pega una decklist y descarga el .txt del Kindle
//   /jugar/      la app completa de mesa, para jugar desde el teléfono
//
// base './' = rutas relativas, para vivir bajo la subruta /papertokens/ de
// GitHub Pages y para que la página anidada resuelva sus propios assets.
// outDir 'docs' = la carpeta que Pages sirve desde la rama main.
export default defineConfig({
  plugins: [react()],
  base: './',
  build: {
    outDir: 'docs',
    rollupOptions: {
      input: {
        generador: resolve(__dirname, 'index.html'),
        jugar: resolve(__dirname, 'jugar/index.html'),
      },
    },
  },
})
