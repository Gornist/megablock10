import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// В проде фронт раздаёт тот же процесс Fastify (см. server/README) — прокси
// нужен только для npm run dev, чтобы бить в бэкенд на 2517 без CORS.
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': 'http://127.0.0.1:2517',
    },
  },
})
