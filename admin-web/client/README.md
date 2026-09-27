# Клиент коллектора (React + Vite)

Фронт мастерского дашборда. Запуск, сборка, оформление и экраны — [../README.md](../README.md).

```bash
npm install
npm run dev     # Vite с прокси /api → :2517 (сервер — ../server, npm run dev)
npm test        # vitest + jsdom; подмена сети — src/test/mockApi.ts
npm run lint    # oxlint
npm run build   # → dist/, его раздаёт сервер
```

Меню — `src/nav.ts` (группы «Игра» и «Мир», прежние адреса), адрес → экран — `src/routes.tsx`, типы ответов API — из
`../server/src/apiTypes.ts` (реэкспорт в `src/api/types.ts`, не дублировать).
