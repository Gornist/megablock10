# Карточка Ш1-Б — телепорт на клетку (клиент и сервер)

Общие правила: `/private/tmp/claude-501/-Users-peachbite-Developer-megablock10/b5e593da-1b32-40c7-b757-4bc3f658fdd5/scratchpad/cards/rules-godot.md` (прочти первыми).
Рабочая копия и ветка: `/Users/peachbite/Developer/megablock10-wt/gd-w2-cells`, `agent/gd-w2-cells` (в ней уже лежит `netrun/shared/node_grid.gd` — класс `NodeGrid`, коммиты Ш1-А).
Источник требований: `docs/gamedesign/time-and-movement.md (в твоей worktree, main уже влит)` разделы 2.2 и 2.3 (только они; про такт, цвета «зелёный/жёлтый/красный»
и «залипание» — НЕ делать, это Ш2).

**Цель:** телепорт идёт на клетку 1 м: прицел притягивается к достижимой клетке, на полу рамка клетки вместо кольца, сервер проверяет клетку. Режим времени не меняется.

**Зона записи:** `netrun/shared/rig_math.gd`, `netrun/shared/net/world_msg.gd`, `netrun/server/net_server.gd`, `netrun/server/node/gray_node.gd` (только если нужно для привязки площадки),
`netrun/client/xr_rig.gd`, `netrun/client/ui/teleport_aim.gd`, `netrun/client/proto_client.gd` (только журнал телепорта), `netrun/client/rig_test_scene.gd` (только привязка телепорта),
`netrun/shared/node_grid.gd` (можно ДОБАВЛЯТЬ функции, не менять существующие), `netrun/tests/` (адаптация старых и новые тесты), `netrun/tools/` и `netrun/tests/bot*` (боты, которые телепортируются — под новые правила).
Больше ничего.

## Досье
- API `NodeGrid` (Ш1-А): `CELL_M`, `REACH_M = 4.5`, `cell_of(p)`, `center(c)`, `in_bounds`, `for_layout()`, `is_occupied`, `line_clear`, `reach_cells(from_cell)`, `hop_verdict(from, to) -> ""|"occupied"|"blocked"|"range"`.
- Клиент: `xr_rig.gd` `_show_aim` (≈360: `RigMath.teleport_aim` даёт сырую точку, `aim_visual.show_at(arc_from, p, ok, charge)`), `_fire_teleport` (≈385: `RigMath.teleport_verdict`, потом `teleport_snap` — привязка к площадке хранилища, `_start_blink`).
  `client/ui/teleport_aim.gd` (`TeleportAim`: тор `_ring`, диск `_disc`, стрелка `_arrow`, `show_at`).
- Сервер: `net_server.gd` `_handle_teleport` (≈412): `RigMath.teleport_verdict` с пределами и допусками, потом `teleport_snap` (площадка у хранилища, `GrayNode.snap_teleport`), `teleport()`, `teleported`.
  Причины отказа — `WorldMsg.REASON_*` (`world_msg.gd` ≈104–113), ответ `encode_teleport_denied`; клиент возвращает риг (`xr_rig.apply_teleport_denial`).
- Журнал клиента: `proto_client.gd` ≈320 `rig.teleport`, ≈323/340 `teleport.denied`; сервер печатает `teleport ok/denied` в stdout.
- Старые тесты, которые телепортируют в произвольные точки и ждут точных координат: `teleport_test`, `teleport_proto_test`, `teleport_client_test`, `decrypt_world_test` (≈248), `gray_node_test` (≈150, бот-прыжки), `node_scene_test` (≈264), `avatar_net_test`, `rig_math_test`.
  Новое поведение сервера: точка прыжка привязывается к центру своей клетки (`NodeGrid.center(cell_of(to))`), затем идёт проверка клетки; тесты поправить на центры клеток (у вершин сетки `floor` даёт юго-восточную клетку: (1, −2) → центр (1.5, −1.5)).

## Что сделать (один коммит на шаг; после каждого — `dev.sh test` затронутых наборов)

1. **Прицел на клетку (общий код).** В `NodeGrid` добавь `func pick(from: Vector3, aim: Vector3) -> Dictionary`: `{cell: Vector2i, p: Vector3 (центр), kind: String, reason: String}`;
   `kind`: `"hop"` (можно прыгать), `"wait"` (цель — своя клетка), `"denied"` (нельзя; `reason` = "occupied"/"blocked"/"range"/"room"). Правила: `c = cell_of(aim)`; вне границ → клетка зажимается в границы, `reason` "room" только если зажатая клетка занята;
   `c == cell_of(from)` → `wait`; `hop_verdict(from, center(c)) == ""` → `hop`; причина "range" → клетка заменяется ближайшей по расстоянию до точки `aim` из `reach_cells(cell_of(from))` и тогда `hop`
   (если `reach_cells` пуст — `denied` "range"); "occupied"/"blocked" → `denied` на исходной клетке с этой причиной (притягивать к соседней нельзя — игрок должен видеть, что клетка закрыта).
   Тесты в `node_grid_test.gd`: каждый вид и причина. Константу `RigMath.TELEPORT_RANGE` поднять до 4.5 (дальность прицела = досягаемость клеток); поправить тесты, где она сравнивается числом.
2. **Клиент.** `xr_rig.gd`: `var grid: NodeGrid = NodeGrid.for_layout()`; `_show_aim` считает `pick(global_position, info["p"])`; `ok` = (`kind == "hop"` и перезарядка готова); `_fire_teleport` — только при `kind == "hop"`, цель = центр клетки, дальше как было
   (verdict по перезарядке/тоннелю, привязка к площадке хранилища, моргание). `TeleportAim.show_at` принимает `kind` и `reason`: вместо тора — **рамка клетки 1×1 м** (тонкая квадратная рамка из четырёх узких полос на полу, размер из `NodeGrid.CELL_M`);
   цвета: `hop` — как сейчас «ok»-цвет кольца, `wait` — нейтральный (рамка своей клетки), `denied` — серый, над серой рамкой `Label3D` с короткой причиной («ЗАНЯТО», «ЗА УКРЫТИЕМ», «ДАЛЬНО»). Диск и стрелка поворота остаются, стрелка — над рамкой.
   Тесты на чистой логике (`teleport_client_test`/`rig_math_test`): выбор клетки; рамка скрыта/показана; серая при denied.
3. **Сервер.** В `NetServer`: `var grid := NodeGrid.for_layout()`; `_handle_teleport` после `RigMath.teleport_verdict` (тоннель/перезарядка/комната/дальность 6 м остаются) привязывает `to` к центру его клетки и проверяет
   `grid.hop_verdict(a.position, to)` → при отказе `REASON_CELL = "cell"` (занято/вне границ), `REASON_BLOCKED = "blocked"` (линия закрыта), `REASON_RANGE` (дальше 4,5 м; допуск: считать от центра своей клетки + 0,5 м запаса — аватар после площадки стоит не в центре);
   плюс отказ `REASON_CELL`, если в этой клетке уже стоит другой аватар в том же узле (`node_of`). Привязка к площадке хранилища (`teleport_snap`) — ПОСЛЕ проверки клетки, как раньше. Клиент (`proto_client`/`xr_rig.apply_teleport_denial`) принимает новые причины без падения.
   Журналы: клиент `rig.teleport … cell=ix,iz ok=…` (добавить поля к существующей строке, старые не удалять), сервер `teleport ok/denied … cell=ix,iz`. Боты и тесты — на центры клеток. Старый клиент не должен падать на новых `reason`.
   Тесты: сервер отказывает в колонне (`cell`), через колонну (`blocked`), слишком далеко (`range`), в клетку другого игрока (`cell`), принимает центр клетки, привязывает произвольную точку к центру клетки; площадка хранилища работает.
4. **Полный прогон:** `netrun/tools/dev.sh test --all` — ТОЛЬКО в фоне (Bash `run_in_background`), итог — число тестов и падений. Падения, не связанные с телепортом и клетками, — в отчёт, не чинить.

## Приёмка
Затронутые наборы зелёные, `--all` — 0 ошибок; `git diff --stat origin/main` — только файлы из зоны. Коммиты на русском (что и почему), `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Не пушить.
**Отчёт** ≤ 15 строк: СТАТУС, коммиты (sha, тема), проверки (команда → вердикт), отклонения, вопросы (особенно: где в коде клиент и сервер могут разойтись по клетке).
