# Карточка Ш1-А — общий код клеток 1 м и взгляд ICE за колоннами

Общие правила: `/private/tmp/claude-501/-Users-peachbite-Developer-megablock10/b5e593da-1b32-40c7-b757-4bc3f658fdd5/scratchpad/cards/rules-godot.md` (прочти первыми).
Рабочая копия и ветка: `/Users/peachbite/Developer/megablock10-wt/gd-w2-cells`, `agent/gd-w2-cells`. Источник требований: `/Users/peachbite/Developer/megablock10-wt/gamedesign-2/docs/gamedesign/time-and-movement.md`
разделы 2.0–2.3 (читать только их).

**Цель:** клетка 1×1 м как общий код (один параметр размера), колонны — занятые клетки, ICE не видит сквозь занятые клетки в нынешнем непрерывном времени.

**Зона записи:** `netrun/shared/node_grid.gd` (новый), `netrun/server/ice/ice_brain.gd`, `netrun/server/ice/ice_node.gd`, `netrun/server/node/gray_node.gd` (только передача сетки ICE),
`netrun/tests/node_grid_test.gd` (новый), `netrun/tests/ice_brain_test.gd`, `docs/netrun-deck-design.md` НЕ трогать. Больше ничего.

## Досье
- Узел: `NodeLayout.ROOM_MIN/ROOM_MAX` (x −8…8, z −14…2), модульные ячейки 2 м (`NodeLayout.CELL`); колонны `NodeLayout.PILLARS` — центры модулей 2×2 м, то есть
  вершины клеток 1 м: колонна занимает блок из 4 клеток 1 м (центр ± 1 м).
- Видимость ICE: `ice_brain.gd` `_closest_visible` (строка ≈158) вызывает статическую `can_see` (расстояние + конус). IceBrain создаёт `IceNode.setup` (`ice_node.gd:24`);
  `gray_node.gd` вызывает `setup` — найди `grep -n "\.setup(" server/node/gray_node.gd`.
- ICE ходит по непрерывным позициям (не по клеткам): клетка ICE и цели — `floor((p − ROOM_MIN) / CELL_M)`; точка ровно на вершине клеток даёт юго-восточную клетку, это нормально.
- Существующие тесты ICE не передают сетку — без неё поведение прежнее (сетка по умолчанию `null`).

## Что сделать (один коммит на шаг)

1. **`netrun/shared/node_grid.gd`**, `class_name NodeGrid extends RefCounted`. Константы: `CELL_M := 1.0` (единственное место размера клетки), `REACH_M := 4.5` (центры клеток).
   Статические чистые функции и экземпляр:
   - `static func cols() -> int`, `rows() -> int` (из ROOM_MIN/MAX и CELL_M → 16×16);
   - `static func cell_of(p: Vector3) -> Vector2i` (floor, без зажима), `static func center(c: Vector2i) -> Vector3` (y = 0), `static func in_bounds(c) -> bool`;
   - экземпляр: `var occ: Dictionary` (множество Vector2i → true); `static func for_layout() -> NodeGrid` — занятость из `NodeLayout.PILLARS` (каждая колонна — 4 клетки);
     `func is_occupied(c) -> bool` (вне границ — занято); `func line_clear(a: Vector2i, b: Vector2i) -> bool` — supercover-линия между центрами клеток, промежуточные клетки (без концов)
     не должны быть заняты; **угол**: когда линия проходит ровно через вершину (диагональный шаг), она закрыта, только если заняты ОБЕ боковые клетки
     (целочисленный алгоритм: `decision = (1 + 2*ix)*ny − (1 + 2*iy)*nx`, ровно 0 — угол; <0 — шаг по x; >0 — шаг по y);
     `func can_see(from: Vector3, to: Vector3) -> bool` = `line_clear(cell_of(from), cell_of(to))`;
     `func reach_cells(from: Vector2i) -> Array[Vector2i]` — все клетки, центр которых не дальше REACH_M от центра `from`, не занятые, не сама `from`, `line_clear(from, c)`;
     `func hop_verdict(from: Vector3, to: Vector3) -> String` — "" если клетка `to` в `reach_cells(cell_of(from))`, иначе "occupied" (клетка занята или вне границ), "blocked" (линия закрыта), "range" (дальше REACH_M).
     Порядок проверок: bounds/occupied → range → blocked.
   - Тесты `node_grid_test.gd` (gdUnit, чистые функции): размеры 16×16; центры клеток (−7.5, −13.5 для клетки (0;0)); колонна = 4 занятые клетки, всего 16 у `for_layout()`;
     `line_clear`: прямая через колонну закрыта, мимо — открыта; диагональ между двумя клетками, где занята одна боковая — открыта, обе — закрыта; `reach_cells` с открытого места содержит
     клетки на 4,5 м по прямой (4 клетки) и не содержит 5 клеток по прямой, не содержит клеток за колонной; `hop_verdict` — три причины.
   Проверка: `netrun/tools/dev.sh test node_grid_test`.
2. **ICE не видит сквозь занятые клетки.** В `IceBrain`: `var grid: NodeGrid = null`; в `_closest_visible` цель видна, только если `can_see(...)` статическая И (`grid == null` или `grid.can_see(position, p)`).
   `IceNode.setup(settings, waypoints, grid = null)` передаёт сетку мозгу; `GrayNode` передаёт `NodeGrid.for_layout()` (одна на узел). Black ICE: охота по trace/позиции от взгляда не зависит (не менять).
   Тесты в `ice_brain_test.gd`: (а) ICE и цель на одной линии с колонной между ними (подбери координаты по `NodeLayout.PILLARS`, например колонна (3, −5), ICE (3, −8), цель (3, −2), ICE смотрит на +Z) —
   без сетки видит (осведомлённость растёт), с `NodeGrid.for_layout()` — не растёт; (б) цель сбоку от колонны на той же дистанции — видна и с сеткой; (в) после выхода цели из-за колонны осведомлённость
   падает как после потери из виду. Проверка: `dev.sh test ice_brain_test node_grid_test gray_node_test black_ice_test`.

## Приёмка
Все четыре набора зелёные; `git diff --stat origin/main` — только файлы из зоны. Коммиты на русском (что и почему), `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Не пушить.
**Отчёт** ≤ 15 строк: СТАТУС, коммиты (sha, тема), проверки (команда → вердикт), отклонения, вопросы.
