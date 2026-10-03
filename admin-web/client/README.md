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

Экраны точек («Устройства», «Локации», точка в карточке узла) собраны из общих частей `src/screens/displays/` — новое
добавлять туда же, а не копировать в экран: загрузка точек, локаций, каналов и узлов — `useDeviceData`, форма точки и
показ секрета — `useDeviceEditor` (`detailProps(d)` — пропсы карточки), карточка точки — `DeviceDetail` (+ `DeviceFacts`),
значок связи и батарея — `DeviceStatus.tsx`, счётчики — `DeviceStats`. Звук точки — `audio/PointAudio.tsx`
(`PointAudioBlock`), «Громкая связь» — `audio/AnnouncePanel.tsx` с `AnnounceClips`, `AnnounceTargets`/`useAnnounceTargets`.
