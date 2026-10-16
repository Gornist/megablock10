class_name ObstacleRegions
extends RefCounted
## Препятствия карты: соседние по стороне блоки «#» (2×2 м) — один объект произвольной формы (levels.md §2 п. 13, владелец 16.10 после П7:
## «препятствия склеены из двух-трёх колонн — так не должно быть»). Касание по диагонали — два объекта. Хранилище, тумба Маяка, барьер и логово
## (V, O, B, L) — свои объекты и с колоннами не сливаются: сюда попадает только «#».
## Чистый расчёт без сцены: клиент строит по контуру один корпус (ObstacleBody), тесты и LayoutCheck считают области.

const SYMBOL := "#"


## Одна область: блоки карты (в порядке обхода) и контуры в метрах мира (x, z): внешние (по часовой на виде сверху, x вправо, z вниз) и дырки
## (против часовой; внутри кольца из блоков есть незанятый блок). Углы только настоящие: точки на прямой убраны.
class Region:
	extends RefCounted
	var blocks: Array[Vector2i] = []
	var outlines: Array[PackedVector2Array] = []
	var holes: Array[PackedVector2Array] = []

	## Площадь по блокам, м².
	func area_m2() -> float:
		return blocks.size() * NodeLayout.CELL * NodeLayout.CELL

	## Все контуры подряд (внешние, потом дырки): по ним рисуются стены и рёбра.
	func loops() -> Array[PackedVector2Array]:
		var out: Array[PackedVector2Array] = []
		out.append_array(outlines)
		out.append_array(holes)
		return out


## Области раскладки `blocks` (строки по SIZE символов, как LayoutData.blocks). Порядок — по первому блоку области в обходе строка за строкой.
static func from_blocks(blocks: Array[String]) -> Array[Region]:
	var out: Array[Region] = []
	var seen := {}
	for sz in blocks.size():
		for sx in blocks[sz].length():
			var start := Vector2i(sx, sz)
			if seen.has(start) or not _occupied(blocks, start):
				continue
			var r := Region.new()
			var queue: Array[Vector2i] = [start]
			seen[start] = true
			while not queue.is_empty():
				var b: Vector2i = queue.pop_front()
				r.blocks.append(b)
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n := b + d
					if not seen.has(n) and _occupied(blocks, n):
						seen[n] = true
						queue.append(n)
			_trace(blocks, r)
			out.append(r)
	return out


## Область, в которую входит блок, или null (блок не «#»).
static func region_of(regions: Array[Region], b: Vector2i) -> Region:
	for r in regions:
		if r.blocks.has(b):
			return r
	return null


static func _occupied(blocks: Array[String], b: Vector2i) -> bool:
	return b.y >= 0 and b.y < blocks.size() and b.x >= 0 and b.x < blocks[b.y].length() and blocks[b.y][b.x] == SYMBOL


## Контуры области: рёбра блоков, у которых с той стороны нет «#», с внутренностью справа при обходе (x вправо, z вниз — по часовой на виде сверху).
## В вершине, где выходит несколько рёбер (два блока касаются углом), берём правый поворот: каждый блок обходится своим углом, контуры не пересекаются.
static func _trace(blocks: Array[String], r: Region) -> void:
	var from := {}  # Vector2i (угол сетки) → Array[Vector2i] концы рёбер, ещё не пройденных
	for b in r.blocks:
		var x := b.x
		var z := b.y
		if not _occupied(blocks, Vector2i(x, z - 1)):
			_add_edge(from, Vector2i(x, z), Vector2i(x + 1, z))
		if not _occupied(blocks, Vector2i(x + 1, z)):
			_add_edge(from, Vector2i(x + 1, z), Vector2i(x + 1, z + 1))
		if not _occupied(blocks, Vector2i(x, z + 1)):
			_add_edge(from, Vector2i(x + 1, z + 1), Vector2i(x, z + 1))
		if not _occupied(blocks, Vector2i(x - 1, z)):
			_add_edge(from, Vector2i(x, z + 1), Vector2i(x, z))
	var starts: Array = from.keys()
	starts.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for s: Vector2i in starts:
		while not (from[s] as Array).is_empty():
			var loop := _walk(from, s)
			var pts := _to_meters(_straighten(loop))
			if _signed_area(pts) > 0.0:
				r.outlines.append(pts)
			else:
				r.holes.append(pts)


static func _add_edge(from: Dictionary, a: Vector2i, b: Vector2i) -> void:
	if not from.has(a):
		from[a] = []
	(from[a] as Array).append(b)


static func _walk(from: Dictionary, start: Vector2i) -> Array[Vector2i]:
	var loop: Array[Vector2i] = [start]
	var cur: Vector2i = (from[start] as Array).pop_back()
	var dir := cur - start
	while cur != start:
		loop.append(cur)
		var next_list: Array = from[cur]
		var pick := 0
		if next_list.size() > 1:
			var right := Vector2i(-dir.y, dir.x)
			for i in next_list.size():
				if (next_list[i] as Vector2i) - cur == right:
					pick = i
					break
		var nxt: Vector2i = next_list[pick]
		next_list.remove_at(pick)
		dir = nxt - cur
		cur = nxt
	return loop


## Убирает точки, лежащие на прямой между соседями: стена из трёх блоков в ряд — одно ребро, а не три.
static func _straighten(loop: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var n := loop.size()
	for i in n:
		var prev := loop[(i + n - 1) % n]
		var cur := loop[i]
		var nxt := loop[(i + 1) % n]
		if (cur - prev).sign() != (nxt - cur).sign():
			out.append(cur)
	return out


static func _to_meters(loop: Array[Vector2i]) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in loop:
		out.append(Vector2(NodeLayout.ROOM_MIN.x + NodeLayout.CELL * p.x, NodeLayout.ROOM_MIN.y + NodeLayout.CELL * p.y))
	return out


## Знаковая площадь (шнурок): > 0 — по часовой на виде сверху (x вправо, z вниз).
static func _signed_area(pts: PackedVector2Array) -> float:
	var s := 0.0
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5
