# Карточка Ш3-Б — раскладки в сервере: узел живёт по `layout`, Фойе на node_00/01/02/07, стенд soak

Общие правила: `/private/tmp/claude-501/-Users-peachbite-Developer-megablock10/b5e593da-1b32-40c7-b757-4bc3f658fdd5/scratchpad/cards/rules-godot.md` (прочти первыми).
Рабочая копия и ветка: `/Users/peachbite/Developer/megablock10-wt/gd-w2-foyer`, `agent/gd-w2-foyer` (уже есть `LayoutData`, `LayoutCheck`, `legacy.json`, `foyer.json`, `foyer_tutorial.json`, `TickIce` с `wait/look`).
Источники: `docs/gamedesign/levels.md` 4.1, 7; `docs/netrun-tick-mode.md` (в ветке). Клиент (`netrun/client/`) — НЕ трогать, кроме поля сообщения (ниже): клиентская часть — следующая карточка.

**Цель:** сервер мира играет узел по раскладке: сетка, шарды-хранилища, порталы, вход, выход, площадка у хранилища, маршруты Стражей — из `LayoutData`; узлы без поля `layout` работают **ровно как сейчас** (раскладка `legacy`). В `graph.json` к `node_00`, `node_01`, `node_02`, `node_07` привязать Фойе.

**Зона записи:** `netrun/server/node/gray_node.gd`, `netrun/server/node/graph_world.gd`, `netrun/server/node/node_graph.gd`, `netrun/server/net_server.gd`, `netrun/shared/layout_data.gd`, `netrun/shared/node_layout.gd` (ТОЛЬКО добавлять функции с параметром-раскладкой; существующие константы и функции не менять), `netrun/shared/net/world_msg.gd`, `netrun/data/graph.json`, `netrun/tools/` (soak и стенд), `netrun/tests/`. Клиент не трогать.

## Досье
- Потребители констант `NodeLayout` на сервере: вход `SPAWN` — `net_server.gd`, `graph_world.gd`; порт прибытия `NodeLayout.arrival_for_slot` — `graph_world.gd`; слоты шардов `SHARD_SLOTS` и порталы `PORTAL_SLOTS` — `node_graph.gd`, `gray_node.gd` (`_build_slots`, `apply_def`); маршруты ICE `NodeLayout.ICE`/`BLACK_ICE` — `gray_node.gd` (`_add_ice`), `node_graph.gd`; выход `on_exit_pad` — `gray_node.gd`; площадка у хранилища `snap_to_vault_pad` / `vault_pad` — `net_server.gd`, `gray_node.gd` (`snap_teleport`).
- Сетка: `net_server.gd` `var grid` (общая на сервер — сделать по узлу сессии), `gray_node.gd` `ice_grid`.
- `LayoutData` (поля: `occupied`, `spawn`, `exit_pos`, `exit_cells`, `portals`, `vaults[{slot,pad,ring}]`, `sentries[{id,route}]`, `signs`, `sight_cells`, `grid()`), `LayoutData.load_named(name)`.
- `graph.json`: узлы `node_00…`; поле `"layout": "<имя>"` у узла. `GrayNode.apply_def(id, def, settings, graph)`.

## Что сделать (один коммит на шаг; после каждого `netrun/tools/dev.sh test <наборы>`)

1. **Узел знает раскладку.** `NodeGraph` читает `layout` узла (пустой/нет → "legacy"); `GrayNode.layout: LayoutData` (`apply_def` загружает; нет файла/ошибка разбора → журнал и `legacy`). Раскладки кэшируются (одна загрузка на имя). Новое `LayoutData` для `legacy` даёт те же значения, что константы (тест из предыдущей карточки это сверяет).
2. **Слоты, порталы, вход, выход по раскладке.** `GrayNode._build_slots`, порталы (`link i` → портал `i+1`), `snap_teleport` (площадка хранилища: клетка `pad` раскладки, лицом к хранилищу), `on_exit_pad` (центр `exit_pos`, радиус как сейчас), прибытие через портал (`arrival_for_slot` → точка у портала раскладки, как сейчас по `ARRIVE_DIST` в сторону центра комнаты) и вход игрока (`spawn` раскладки узла) — по раскладке узла.
   Шардов у узла столько, сколько указано (`shards`), берутся первые хранилища раскладки; хранилищ больше, чем шардов, — лишние пустые (не создавать слоты).
3. **Сетка по узлу.** `GrayNode.ice_grid = layout.grid()`; `NetServer.grid` заменить хуком `grid_of: Callable(session) -> NodeGrid` (не задан — `NodeGrid.for_layout()`, как сейчас); `GrayNode`/`GraphWorld` ставят его по узлу сессии. Проверка телепорта и «другой аватар в клетке» — по сетке узла.
4. **Стражи по раскладке.** В тактовом режиме `TickIce` строится из `layout.sentries` (маршрут с `wait/look`), дальность зрения — `layout.sight_cells`, если задана, иначе по тиру; в режиме `realtime` и для `legacy` — прежние маршруты. Black ICE — как сейчас (`NodeLayout.BLACK_ICE`).
5. **Сообщение о раскладке.** В событии входа в узел (то, что сервер шлёт клиенту про узел — найди `grep -n '"node"' server/node/gray_node.gd server/node/graph_world.gd`) добавить поле `layout` (имя); старые клиенты поле игнорируют. Тест: сообщение несёт имя.
6. **`graph.json`.** `node_00` → `foyer_tutorial`, `node_01`, `node_02`, `node_07` → `foyer`; остальные без поля. Число связей узлов не больше трёх; связи узла 1 и 2 идут в порталы `1`, `2`, `3` по порядку. Тест графа: у каждого узла с раскладкой число связей не больше числа порталов раскладки и число шардов не больше числа хранилищ.
   Тесты, привязанные к прежней комнате (`graph_world_test`, `outcomes_graph_test`, `breach_world_test`, `node_scene_test` и др.), правь минимально: проверять своё, не ослабляя; где нужна прежняя комната — узел без `layout` (legacy).
7. **Soak-стенд** (отдельным коммитом; `netrun/tools/soak.sh`, `soak_run.gd`, их фикстуры): боты стартуют на разных клетках входа узла (не все в одну клетку), у бота-вора в колоде Извлечение (а не только Призрак), чтобы забег проходил взлом; в `tick`-режиме после выброса локдаун не мешает следующему забегу (в стенде `node_lockdown_s` малый — как на копии прошлого прогона). Бот-прогон 10 минут в фоне: итог — число забегов, `clean`, причины FAIL; цель — нет FAIL из-за стенда.
8. **Полный прогон:** `netrun/tools/dev.sh test --all` в фоне — число тестов и падений.

## Приёмка
Затронутые наборы и `--all` — 0 ошибок; бот-прогон без FAIL из-за стенда; `git diff --stat origin/agent/gd-w2-tick` — только файлы из зоны. Коммиты на русском (что и почему), `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Не пушить.
**Отчёт** ≤ 15 строк: СТАТУС, коммиты (sha, тема), проверки (команда → вердикт), решения, вопросы (особенно: что в `legacy` не совпало с константами).
