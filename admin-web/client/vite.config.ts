import react from '@vitejs/plugin-react'
import { defineConfig } from 'vitest/config'

// В проде фронт раздаёт тот же процесс Fastify (см. server/README) — прокси
// нужен только для npm run dev, чтобы бить в бэкенд на 2517 без CORS.
export default defineConfig({
  plugins: [react()],
  // Клиентские тесты (vitest + jsdom): чистая логика и ключевые экраны с подменённым api.
  test: {
    environment: 'jsdom',
    setupFiles: ['src/test/setup.ts'],
  },
  server: {
    proxy: {
      '/api': 'http://127.0.0.1:2517',
    },
  },
})
