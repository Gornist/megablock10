extends GdUnitTestSuite
## Корпус препятствия по контуру области (ObstacleBody): одна оболочка без швов между соседними блоками, свет вершин как у lit() в env.py.

const EMPTY := "........"


func _rows(marks: Array) -> Array[String]:
	var rows: Array[String] = []
	for i in LayoutData.SIZE:
		rows.append(EMPTY)
	for m: Vector2i in marks:
		rows[m.y] = rows[m.y].substr(0, m.x) + "#" + rows[m.y].substr(m.x + 1)
	return rows


func _build(marks: Array) -> Dictionary:
	return ObstacleBody.build(ObstacleRegions.from_blocks(_rows(marks)))


func _arrays(mesh: ArrayMesh) -> Array:
	return mesh.surface_get_arrays(0)


func test_two_blocks_make_one_body_of_the_union_width() -> void:
	var m := _build([Vector2i(2, 2), Vector2i(3, 2)])
	var box: AABB = (m["body"] as ArrayMesh).get_aabb()
	assert_float(box.size.x).is_equal_approx(4.0 - 2.0 * ObstacleBody.INSET, 0.001)  # 3,9 м: между блоками отступа нет
	assert_float(box.size.z).is_equal_approx(2.0 - 2.0 * ObstacleBody.INSET, 0.001)
	assert_float(box.size.y).is_equal_approx(ObstacleBody.HEIGHT, 0.001)


func test_no_wall_vertex_on_the_joint_between_blocks() -> void:
	var m := _build([Vector2i(2, 2), Vector2i(3, 2)])
	var joint_x: float = NodeLayout.ROOM_MIN.x + NodeLayout.CELL * 3
	var verts: PackedVector3Array = _arrays(m["body"])[Mesh.ARRAY_VERTEX]
	var hits := 0
	for v in verts:
		# Стена идёт по внешней границе (z у краёв блока); на стыке блоков по x стен нет. Крышка может иметь точки на стыке, но не ниже верха.
		if absf(v.x - joint_x) < 0.001 and v.y < ObstacleBody.HEIGHT - 0.001:
			hits += 1
	assert_int(hits).is_equal(0)


func test_normals_point_outward_on_walls_and_up_on_the_cap() -> void:
	var m := _build([Vector2i(2, 2)])
	var arr := _arrays(m["body"])
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var cx: float = NodeLayout.ROOM_MIN.x + NodeLayout.CELL * 2.5
	var cz: float = NodeLayout.ROOM_MIN.y + NodeLayout.CELL * 2.5
	var wall_ok := 0
	var cap_ok := 0
	for i in verts.size():
		var v := verts[i]
		var out := Vector3(v.x - cx, 0.0, v.z - cz)
		if v.y > 0.25 and v.y < 2.19 and out.length() > 0.5:  # ряды стены — на 0,3 и 2,17 м
			assert_float(normals[i].dot(out.normalized())).is_greater(0.5)
			wall_ok += 1
		if v.y > ObstacleBody.HEIGHT - 0.001 and maxf(absf(out.x), absf(out.z)) < 0.94:  # внутренний край полосы верха, дальше — только крышка
			assert_float(normals[i].y).is_greater(0.9)
			cap_ok += 1
	assert_int(wall_ok).is_greater(0)
	assert_int(cap_ok).is_greater(0)


func test_corner_is_lit_and_flat_wall_middle_is_dark() -> void:
	var m := _build([Vector2i(2, 2), Vector2i(3, 2)])
	var arr := _arrays(m["body"])
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var x0: float = NodeLayout.ROOM_MIN.x + NodeLayout.CELL * 2 + ObstacleBody.INSET
	var z0: float = NodeLayout.ROOM_MIN.y + NodeLayout.CELL * 2 + ObstacleBody.INSET
	var lit := ObstacleBody.light(1.0)
	var dark := ObstacleBody.light(0.0)
	var corner_seen := false
	var dark_seen := false
	for i in verts.size():
		var v := verts[i]
		if absf(v.x - x0) < 0.001 and absf(v.z - z0) < 0.001 and v.y > 0.25 and v.y < 2.19:
			assert_float(colors[i].g).is_equal_approx(lit.g, 0.01)  # вертикальное ребро на любой высоте (цвета вершин в меше — 8 бит)
			corner_seen = true
		if absf(v.z - z0) < 0.001 and absf(v.x - (x0 + ObstacleBody.BAND)) < 0.001 and v.y > 0.25 and v.y < 2.19:  # в трёх сантиметрах от ребра свет уже погас
			assert_float(colors[i].g).is_equal_approx(dark.g, 0.01)  # на прямой стене рёбер нет
			dark_seen = true
	assert_bool(corner_seen).is_true()
	assert_bool(dark_seen).is_true()


func test_l_shape_reflex_corner_gets_an_edge() -> void:
	var m := _build([Vector2i(2, 2), Vector2i(2, 3), Vector2i(3, 3)])
	var verts: PackedVector3Array = _arrays(m["body"])[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = _arrays(m["body"])[Mesh.ARRAY_COLOR]
	# Вогнутый угол Г (пусто — блок (3, 2)): точка границы (x = столбец 3, z = строка 3); стены отступают от неё на INSET каждая внутрь своего блока.
	var rx: float = NodeLayout.ROOM_MIN.x + NodeLayout.CELL * 3 - ObstacleBody.INSET
	var rz: float = NodeLayout.ROOM_MIN.y + NodeLayout.CELL * 3 + ObstacleBody.INSET
	var lit := ObstacleBody.light(1.0)
	var found := false
	for i in verts.size():
		if absf(verts[i].x - rx) < 0.001 and absf(verts[i].z - rz) < 0.001 and verts[i].y > 0.25 and verts[i].y < 2.19:
			assert_float(colors[i].g).is_equal_approx(lit.g, 0.01)
			found = true
	assert_bool(found).is_true()


func test_frame_lies_on_the_outer_contour_only() -> void:
	var m := _build([Vector2i(2, 2), Vector2i(3, 2)])
	var joint_x: float = NodeLayout.ROOM_MIN.x + NodeLayout.CELL * 3
	var verts: PackedVector3Array = _arrays(m["frame"])[Mesh.ARRAY_VERTEX]
	for v in verts:
		assert_float(v.y).is_equal_approx(ObstacleBody.FRAME_Y, 0.0001)
		assert_float(absf(v.x - joint_x)).is_greater(0.5)  # рамки на стыке блоков нет
	assert_int(verts.size()).is_equal(4 * 6)  # четыре ребра внешнего контура, по два треугольника


func test_hole_region_builds_without_error() -> void:
	var marks: Array = []
	for x in 3:
		for z in 3:
			if x != 1 or z != 1:
				marks.append(Vector2i(2 + x, 2 + z))
	var m := _build(marks)
	var frame_verts: PackedVector3Array = _arrays(m["frame"])[Mesh.ARRAY_VERTEX]
	assert_int(frame_verts.size()).is_equal(8 * 6)  # внешний и внутренний контуры


func test_empty_regions_give_empty_meshes() -> void:
	var m := ObstacleBody.build([])
	assert_int((m["body"] as ArrayMesh).get_surface_count()).is_equal(0)
