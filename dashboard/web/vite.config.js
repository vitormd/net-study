import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// Endpoints servidos pelo backend Sinatra (dashboard/app.rb). Em dev, o Vite
// faz proxy deles pro container do dashboard em :8080. Em prod, o build vai
// pra dashboard/public e é servido pelo próprio Sinatra (mesma origem).
const BACKEND = process.env.BACKEND_URL || 'http://localhost:8080'
const API_PATHS = [
  '/stream', '/events', '/packet',
  '/topology', '/client-certs', '/trigger', '/probe-from',
  '/api', '/ca', '/identity'
]

export default defineConfig({
  plugins: [vue()],
  build: {
    outDir: 'dist',
    emptyOutDir: true
  },
  server: {
    port: 5173,
    // changeOrigin:false mantém o Host original (localhost) — o host
    // authorization do Sinatra 4 rejeitaria host.docker.internal.
    proxy: Object.fromEntries(
      API_PATHS.map((p) => [p, { target: BACKEND, changeOrigin: false }])
    )
  }
})
