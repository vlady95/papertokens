import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// base './' = rutas relativas en el build, para vivir bajo la subruta
// /papertokens/ de GitHub Pages. outDir 'docs' = la carpeta que Pages sirve
// desde la rama main.
export default defineConfig({
  plugins: [react()],
  base: './',
  build: { outDir: 'docs' },
})
