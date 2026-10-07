class_name NodeGrid
extends RefCounted
## Сетка клеток 1×1 м поверх комнаты узла (NodeLayout.ROOM_MIN/ROOM_MAX): общий код клиента и сервера.
## Колонны — занятые клетки (блок 2×2 м = 4 клетки). Взгляд и прыжок считаются по клеткам: линия между центрами,
## через занятую клетку не проходит; диагональный шаг ровно через вершину закрыт, только если заняты обе боковые клетки.
## Размер клетки — единственная константа CELL_M: поменять её здесь значит поменять сетку везде.

const CELL_M := 1.0
## Дальность прыжка между центрами клеток, м.
const REACH_M := 4.5
const _EPS := 0.0001
## Половина стороны колонны (модуль 2×2 м вокруг NodeLayout.PILLARS), м.
const PILLAR_HALF_M := 1.0

## Занятые клетки: Vector2i → true.
var occ: Dictionary = {}


static func cols() -> int:
	return roundi((NodeLayout.ROOM_MAX.x - NodeLayout.ROOM_MIN.x) / CELL_M)


static func rows() -> int:
	return roundi((NodeLayout.ROOM_MAX.y - NodeLayout.ROOM_MIN.y) / CELL_M)


## Клетка, в которой лежит точка (без зажима: вне комнаты индексы выходят за границы). Точка на вершине — юго-восточная клетка.
static func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori((p.x - NodeLayout.ROOM_MIN.x) / CELL_M), floori((p.z - NodeLayout.ROOM_MIN.y) / CELL_M))


static func center(c: Vector2i) -> Vector3:
	return Vector3(NodeLayout.ROOM_MIN.x + CELL_M * (c.x + 0.5), 0.0, NodeLayout.ROOM_MIN.y + CELL_M * (c.y + 0.5))


static func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < cols() and c.y < rows()


## Занятость по колоннам узла: каждая колонна закрывает все клетки своего блока 2×2 м.
static func for_layout() -> NodeGrid:
	var g := NodeGrid.new()
	for pillar: Vector3 in NodeLayout.PILLARS:
		var x0 := ceili((pillar.x - PILLAR_HALF_M - NodeLayout.ROOM_MIN.x) / CELL_M - _EPS)
		var x1 := floori((pillar.x + PILLAR_HALF_M - NodeLayout.ROOM_MIN.x) / CELL_M + _EPS) - 1
		var z0 := ceili((pillar.z - PILLAR_HALF_M - NodeLayout.ROOM_MIN.y) / CELL_M - _EPS)
		var z1 := floori((pillar.z + PILLAR_HALF_M - NodeLayout.ROOM_MIN.y) / CELL_M + _EPS) - 1
		for ix in range(x0, x1 + 1):
			for iz in range(z0, z1 + 1):
				g.occ[Vector2i(ix, iz)] = true
	return g


## Вне комнаты — занято: за стену не прыгнуть и не заглянуть.
func is_occupied(c: Vector2i) -> bool:
	return not in_bounds(c) or occ.has(c)


## Линия между центрами клеток свободна: промежуточные клетки (без концов) не заняты.
## Целочисленная supercover-линия; decision == 0 — линия ровно через вершину (диагональный шаг).
func line_clear(a: Vector2i, b: Vector2i) -> bool:
	var nx := absi(b.x - a.x)
	var ny := absi(b.y - a.y)
	var sx := 1 if b.x > a.x else -1
	var sy := 1 if b.y > a.y else -1
	var p := a
	var ix := 0
	var iy := 0
	while ix < nx or iy < ny:
		var decision := (1 + 2 * ix) * ny - (1 + 2 * iy) * nx
		if decision == 0:
			# Угол: пройти можно, если свободна хотя бы одна из двух боковых клеток.
			if is_occupied(Vector2i(p.x + sx, p.y)) and is_occupied(Vector2i(p.x, p.y + sy)):
				return false
			p = Vector2i(p.x + sx, p.y + sy)
			ix += 1
			iy += 1
		elif decision < 0:
			p = Vector2i(p.x + sx, p.y)
			ix += 1
		else:
			p = Vector2i(p.x, p.y + sy)
			iy += 1
		if p != b and is_occupied(p):
			return false
	return true


func can_see(from: Vector3, to: Vector3) -> bool:
	return line_clear(cell_of(from), cell_of(to))


## Клетки, куда можно прыгнуть из `from`: центр не дальше REACH_M, клетка свободна, линия открыта.
func reach_cells(from: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := ceili(REACH_M / CELL_M)
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var c := Vector2i(from.x + dx, from.y + dy)
			if c == from or is_occupied(c):
				continue
			if _dist_m(from, c) > REACH_M + _EPS:
				continue
			if line_clear(from, c):
				out.append(c)
	return out


## Почему прыжок не разрешён: "" — можно; "occupied" (клетка занята или вне границ), "range" (дальше REACH_M), "blocked" (линия закрыта).
func hop_verdict(from: Vector3, to: Vector3) -> String:
	var a := cell_of(from)
	var b := cell_of(to)
	if is_occupied(b):
		return "occupied"
	if _dist_m(a, b) > REACH_M + _EPS:
		return "range"
	if not line_clear(a, b):
		return "blocked"
	return ""


static func _dist_m(a: Vector2i, b: Vector2i) -> float:
	return Vector2(b - a).length() * CELL_M


## Прицел на клетку: куда на самом деле ляжет прыжок при прицеле в точку `aim`. Возвращает {cell, p (центр клетки), kind, reason}.
## kind: "hop" — можно прыгнуть; "wait" — цель в своей клетке (остаться); "denied" — нельзя, reason: "occupied" / "blocked" / "range" / "room".
## Вне комнаты клетка зажимается в границы ("room" — только если зажатая клетка занята). Слишком далёкая клетка заменяется ближайшей
## к `aim` из достижимых; занятую или закрытую линией клетку к соседней не притягиваем — игрок должен видеть, что она закрыта.
func pick(from: Vector3, aim: Vector3) -> Dictionary:
	var raw := cell_of(aim)
	var c := Vector2i(clampi(raw.x, 0, cols() - 1), clampi(raw.y, 0, rows() - 1))
	if c != raw and is_occupied(c):
		return _pick_result(c, "denied", "room")
	var start := cell_of(from)
	if c == start:
		return _pick_result(c, "wait", "")
	var verdict := hop_verdict(from, center(c))
	if verdict.is_empty():
		return _pick_result(c, "hop", "")
	if verdict == "range":
		var best := start
		var best_d := INF
		for r: Vector2i in reach_cells(start):
			var d := Vector2(center(r).x - aim.x, center(r).z - aim.z).length()
			if d < best_d:
				best_d = d
				best = r
		if best == start:
			return _pick_result(c, "denied", "range")
		return _pick_result(best, "hop", "")
	return _pick_result(c, "denied", verdict)


func _pick_result(c: Vector2i, kind: String, reason: String) -> Dictionary:
	return {"cell": c, "p": center(c), "kind": kind, "reason": reason}
