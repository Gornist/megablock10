class_name TickVision
extends RefCounted
## Зрение ICE на клетках (docs/gamedesign/ice.md, 1): чистые функции без сцены и сети — один расчёт для сервера и клиента (свет на полу).
## Конус: центр клетки не дальше `sight_cells` клеток от центра клетки ICE и под углом не больше `half_deg` от направления (одно из 8).
## Фокус — угол не больше `focus_deg`, остальное — периферия. Своя клетка, клетки позади и закрытые линией взгляда (NodeGrid.line_clear) не видны.

const NONE := 0
const PERIPHERY := 1
const FOCUS := 2

const _EPS := 0.001


## Как ICE видит клетку `target`: NONE (0) — не видна, PERIPHERY (1), FOCUS (2). Занятая клетка (колонна, вне комнаты) не видна: в ней никого нет.
static func classify(grid: NodeGrid, ice_cell: Vector2i, dir: Vector2i, target: Vector2i, sight_cells: float, half_deg: float, focus_deg: float) -> int:
	if target == ice_cell or dir == Vector2i.ZERO or grid.is_occupied(target):
		return NONE
	if Vector2(target - ice_cell).length() > sight_cells + _EPS:
		return NONE
	var angle := NodeGrid.angle_deg(dir, ice_cell, target)
	if angle > half_deg + _EPS:
		return NONE
	if not grid.line_clear(ice_cell, target):
		return NONE
	return FOCUS if angle <= focus_deg + _EPS else PERIPHERY


## Все видимые клетки: клетка → 1 (периферия) | 2 (фокус). Для света на полу и для расчёта «кого видно».
static func visible_cells(grid: NodeGrid, ice_cell: Vector2i, dir: Vector2i, sight_cells: float, half_deg: float, focus_deg: float) -> Dictionary:
	var out: Dictionary = {}
	var r := ceili(sight_cells)
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var c := Vector2i(ice_cell.x + dx, ice_cell.y + dy)
			var k := classify(grid, ice_cell, dir, c, sight_cells, half_deg, focus_deg)
			if k != NONE:
				out[c] = k
	return out
