class_name ObstacleBody
extends RefCounted
## Корпус препятствия — один цельный объект по контуру области блоков «#» (П7-2, levels.md §2 п. 13): стены выдавлены по внешнему контуру,
## швов и рёбер между соседними блоками нет. Геометрия и свет вершин — как у `_cover_parts` в assets/src/env.py (пара П7-3, Blender):
## корпус отступает от границы модуля на INSET там, где соседа нет (между соседями отступа нет); полоса BAND у вертикальных рёбер и верха;
## основание подсвечено до RISE; рамка шириной BAND по внешнему контуру на высоте FRAME_Y. Материалы не задаются: их ставит NodeView
## (solid_dark из модуля `pillar`, чтобы AssetMaterials.apply и облако работали как у остальных колонн). Меш один на все области — вызовов отрисовки столько же,
## сколько у MultiMesh `pillar`.

const HEIGHT := 2.2  ## COVER_H
const INSET := 0.05  ## щель до границы модуля: корпус 1,9 из 2,0
const BAND := 0.03   ## полоса у рёбер и верха (шаг света)
const RISE := 0.3    ## высота подсвеченного основания
const FRAME_Y := 0.003
const CYAN := Color("18e6ff")
const VOID := Color("02050a")


## Корпус и рамка областей regions: {"body": ArrayMesh, "frame": ArrayMesh} (по одной поверхности без материала; пусто, если областей нет).
static func build(regions: Array) -> Dictionary:
	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	body.set_smooth_group(0)  # как smooth=True у pillar_block: нормали сглажены по сваренным вершинам (обводка силуэта, fringe.gdshader)
	var frame := SurfaceTool.new()
	frame.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r: ObstacleRegions.Region in regions:
		for loop in r.loops():
			_walls(body, loop)
			_band_and_frame(body, frame, loop)
		_cap(body, r)
	body.generate_normals()
	frame.generate_normals()
	return {"body": body.commit(), "frame": frame.commit()}


## Цвет света вершины стены: k = 1 у вертикального ребра и по контуру верха, у основания 0,6·(1 − y/RISE), иначе 0 (lit() в env.py).
static func light(k: float) -> Color:
	var lin_cyan := CYAN.srgb_to_linear()
	var lin_void := VOID.srgb_to_linear()
	return Color(lin_void.r + (lin_cyan.r - lin_void.r) * k, lin_void.g + (lin_cyan.g - lin_void.g) * k, lin_void.b + (lin_cyan.b - lin_void.b) * k, 1.0)


## Внутрь (вправо при обходе) от ребра с направлением d: вектор в плоскости (x, z).
static func _right(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x)


## Контур, сдвинутый внутрь на depth: у прямоугольных углов сдвиг по обеим осям ровно depth (сумма правых нормалей двух рёбер).
static func inset_loop(loop: PackedVector2Array, depth: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := loop.size()
	for i in n:
		var d_in := (loop[i] - loop[(i + n - 1) % n]).normalized()
		var d_out := (loop[(i + 1) % n] - loop[i]).normalized()
		out.append(loop[i] + (_right(d_in) + _right(d_out)) * depth)
	return out


static func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


## Стены по рёбрам контура, отступившего на INSET: сетка 3×3 по длине (полоса, середина, полоса) и по высоте (основание, середина, верхняя полоса).
static func _walls(st: SurfaceTool, loop: PackedVector2Array) -> void:
	var pts := inset_loop(loop, INSET)
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var len := a.distance_to(b)
		var d := (b - a) / len
		var ts := [0.0, BAND, len - BAND, len]
		var ys := [0.0, RISE, HEIGHT - BAND, HEIGHT]
		for ti in 3:
			for yi in 3:
				var t0: float = ts[ti]
				var t1: float = ts[ti + 1]
				var y0: float = ys[yi]
				var y1: float = ys[yi + 1]
				# Порядок обхода — по часовой при взгляде снаружи (передняя грань Godot).
				_quad(st, a + d * t0, y0, a + d * t1, y0, a + d * t1, y1, a + d * t0, y1, t0, t1, y0, y1, len)


## Четырёхугольник стены (p, y) ×4 в порядке «низ-слева, низ-справа, верх-справа, верх-слева» при взгляде снаружи; свет вершин — по правилу lit().
static func _quad(st: SurfaceTool, p0: Vector2, y0: float, p1: Vector2, y1: float, p2: Vector2, y2: float, p3: Vector2, y3: float,
		t0: float, t1: float, ya: float, yb: float, len: float) -> void:
	var c0 := light(_wall_k(t0, ya, len))
	var c1 := light(_wall_k(t1, ya, len))
	var c2 := light(_wall_k(t1, yb, len))
	var c3 := light(_wall_k(t0, yb, len))
	var v0 := _v3(p0, y0)
	var v1 := _v3(p1, y1)
	var v2 := _v3(p2, y2)
	var v3 := _v3(p3, y3)
	for tri in [[v0, c0, v2, c2, v3, c3], [v0, c0, v1, c1, v2, c2]]:
		for i in 3:
			st.set_color(tri[i * 2 + 1])
			st.add_vertex(tri[i * 2])


## Свет точки стены: t — расстояние от начала ребра, y — высота.
static func _wall_k(t: float, y: float, len: float) -> float:
	if t < 1e-4 or t > len - 1e-4:
		return 1.0  # вертикальное ребро (выпуклый и вогнутый угол); на прямой стене рёбер нет — точки на прямой убраны из контура
	if y > HEIGHT - 1e-4:
		return 1.0  # контур верха
	if y < RISE:
		return 0.6 * (1.0 - y / RISE)  # основание
	return 0.0


## Верх: полоса BAND по контуру (от INSET до INSET+BAND: у стены свет 1, внутри 0) и крышка из блоков за вычетом полос у границ.
static func _band_and_frame(body: SurfaceTool, frame: SurfaceTool, loop: PackedVector2Array) -> void:
	var outer := inset_loop(loop, INSET)
	var inner := inset_loop(loop, INSET + BAND)
	var n := outer.size()
	for i in n:
		var j := (i + 1) % n
		var lit := light(1.0)
		var dark := light(0.0)
		# Полоса верха: по часовой при взгляде сверху (+Y), как передняя грань.
		var q := [[outer[i], lit], [inner[j], dark], [inner[i], dark], [outer[i], lit], [outer[j], lit], [inner[j], dark]]
		for e in q:
			body.set_color(e[1])
			body.add_vertex(_v3(e[0], HEIGHT))
	# Рамка на полу: от границы модуля внутрь на BAND (цвет рамки — полный свет, как cyan у pillar_base).
	var f_in := inset_loop(loop, BAND)
	for i in n:
		var j := (i + 1) % n
		var q := [loop[i], f_in[j], f_in[i], loop[i], loop[j], f_in[j]]
		for p: Vector2 in q:
			frame.set_color(CYAN.srgb_to_linear())
			frame.add_vertex(_v3(p, FRAME_Y))


## Крышка: квадрат каждого блока минус полосы шириной INSET+BAND вдоль внешних рёбер контура (концы продлены на ту же ширину — вогнутый угол срезается).
static func _cap(st: SurfaceTool, r: ObstacleRegions.Region) -> void:
	var strips: Array[PackedVector2Array] = []
	var w := INSET + BAND
	for loop in r.loops():
		var n := loop.size()
		for i in n:
			var a := loop[i]
			var b := loop[(i + 1) % n]
			var d := (b - a).normalized()
			var rt := _right(d)
			strips.append(PackedVector2Array([a - d * w, b + d * w, b + d * w + rt * w, a - d * w + rt * w]))
	var dark := light(0.0)
	for b in r.blocks:
		var x0 := NodeLayout.ROOM_MIN.x + NodeLayout.CELL * b.x
		var z0 := NodeLayout.ROOM_MIN.y + NodeLayout.CELL * b.y
		var pieces: Array[PackedVector2Array] = [PackedVector2Array([Vector2(x0, z0), Vector2(x0 + NodeLayout.CELL, z0), Vector2(x0 + NodeLayout.CELL, z0 + NodeLayout.CELL), Vector2(x0, z0 + NodeLayout.CELL)])]
		for s in strips:
			var next: Array[PackedVector2Array] = []
			for p in pieces:
				next.append_array(Geometry2D.clip_polygons(p, s))
			pieces = next
		for p in pieces:
			var idx := Geometry2D.triangulate_polygon(p)
			for k in range(0, idx.size(), 3):
				var tri := [p[idx[k]], p[idx[k + 1]], p[idx[k + 2]]]
				if ObstacleRegions._signed_area(PackedVector2Array(tri)) < 0.0:
					tri = [tri[0], tri[2], tri[1]]  # передняя грань крышки смотрит в +Y: по часовой на виде сверху
				for q: Vector2 in tri:
					st.set_color(dark)
					st.add_vertex(_v3(q, HEIGHT))
