# Карточка Ш3-В — клиент играет узел по раскладке: Фойе в 3D, сетка узла у рига и света, таблички, кадр сверху

Общие правила: `/private/tmp/claude-501/-Users-peachbite-Developer-megablock10/b5e593da-1b32-40c7-b757-4bc3f658fdd5/scratchpad/cards/rules-godot.md` (прочти первыми).
Рабочая копия и ветка: `/Users/peachbite/Developer/megablock10-wt/gd-w2-foyer`, `agent/gd-w2-foyer` (сервер уже играет узлы по раскладке; в событии входа в узел есть поле `layout` — имя; `NodeGrid.look_dir`, `LayoutData` общий).
Источники: `docs/gamedesign/levels.md` 3, 4.1, 7; `docs/netrun-tick-mode.md`.

**Цель:** на очках и в плоской сборке узел с раскладкой выглядит и работает как Фойе: колонны, хранилища, порталы, вход и выход стоят по раскладке; рамка прицела, свет зрения и «ИИ-прогноз» считаются по сетке узла; таблички учебного узла — из раскладки. Узлы без `layout` — как сейчас.

**Зона записи:** `netrun/client/` (КРОМЕ вида тела и рук: `avatar_view.gd`, `hand_view.gd`, `avatar_body.gd`, `head_*.gd` — не трогать), `netrun/shared/layout_data.gd`, `netrun/shared/node_layout.gd` (только добавлять), `netrun/server/node/gray_node.gd` (ТОЛЬКО формирование событийного поля `signs` из раскладки), `netrun/export_presets.cfg` (включить `data/layouts/*.json` в клиентский экспорт), `netrun/tests/`. Больше ничего.

## Досье
- `rig_test_scene.gd` `apply_node(info)` (≈655): шарды, порталы, `_build_signs(info["signs"])` (≈885), место входа. `NodeView` (`client/node_view.gd`): комната и модули строятся из констант `NodeLayout` — колонны `PILLARS` (`_room_transforms`, ≈192), площадка выхода `exit_platform_cells()`, туннель выхода `EXIT_POS`, кресло входа `SPAWN` (≈94), датчик `SENSOR_POS`; хранилища и порталы — по данным сервера (`set_vaults`, `set_portals`); площадка взлома — `NodeLayout.vault_pad` (≈329).
- Сетка клиента: `XRRig.grid` (`xr_rig.gd` ≈69), `TickFloor` (`client/tick_floor.gd`, `_grid`), плоский стенд — тот же `rig_test_scene`.
- `LayoutData`: `occupied`, `spawn`, `exit_pos`, `exit_cells`, `portals`, `vaults[{slot,pad,ring}]`, `signs`, `grid()`, `load_named(name)`, `cached(name)`.
- Тест `client_export_test` следит, чтобы клиентский код не брал классы из `server/`.
- Сервер: событие узла несёт `layout`, `signs` у `node_00` в `graph.json` остались в координатах старой комнаты — теперь для узла с раскладкой сервер должен отдавать `signs` из `layout.signs`.

## Что сделать (один коммит на шаг; после каждого — `netrun/tools/dev.sh test <наборы>`)

1. **Сервер: таблички из раскладки.** В событии узла `signs` для узла с `layout` берётся из `layout.signs` (перевод клетки карты в позицию модуля), `graph.json signs` используется только без раскладки. Тест.
2. **Клиент: раскладка узла.** `NodeView.set_layout(layout: LayoutData)` (null — прежнее): колонны ставятся по занятым блокам карты `#` (центры модулей, как `PILLARS`; хранилища `V` рисует `set_vaults`), площадка и туннель выхода — по `exit_cells`/`exit_pos`, кресло — по `spawn`, датчик — только без раскладки; площадка взлома — по `pad` раскладки (клетка карты → позиция), а не по `NodeLayout.vault_pad`, если раскладка не legacy. Модули пересобираются при смене раскладки (переход между узлами).
   `rig_test_scene.apply_node` читает `info.layout` → `LayoutData.cached` → `view.set_layout`, `rig.grid`, `TickFloor` grid и клиентскую привязку к площадке — по раскладке; нет поля — legacy. Клиентский экспорт: `export_presets.cfg` включает `data/layouts/*.json` (проверь `include_filter`); `client_export_test` зелёный.
3. **Место входа.** Риг при входе и после тоннеля встаёт на `spawn` раскладки узла (или то, что присылает сервер — найди, где сейчас берётся место входа, и согласуй с `NetServer.spawn_of`); тест на чистой логике.
4. **Кадр Фойе сверху.** Расширь `tests/tick_demo_preview` (или сделай `tests/foyer_preview.gd/.tscn`): Фойе с колоннами, хранилищами и площадками, порталами, входом `S`, выходом `E`, Стражем с светом зрения (фокус/периферия) и стрелкой, рамка прицела. `netrun/tools/dev.sh shot` — одна сетка ≤ 1024 px (вид сверху + вид от входа). Отдай кадр агенту `visual-reviewer` с чек-листом:
   «колонны видны (4 штуки); два хранилища у северной стены; три портала; вход и выход различимы; свет Стража двух яркостей; стрелка; рамка цветная; кадр не чёрный». PASS/FAIL по строкам — в отчёт; провалы чини.
5. **Полный прогон:** `netrun/tools/dev.sh test --all` в фоне; итог — число тестов и падений.

## Приёмка
Затронутые наборы и `--all` — 0 ошибок; кадр прошёл чек-лист; `git diff --stat origin/agent/gd-w2-tick` — только файлы из зоны. Коммиты на русском (что и почему), `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Не пушить.
**Отчёт** ≤ 15 строк: СТАТУС, коммиты (sha, тема), проверки (команда → вердикт), результат `visual-reviewer`, решения, вопросы.
