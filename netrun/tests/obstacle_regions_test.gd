extends GdUnitTestSuite
## Препятствие — один цельный объект (levels.md §2 п. 13): соседние по стороне блоки «#» — одна область, диагональ — две; контур — только настоящие углы.

const EMPTY := "........"


func _rows(marks: Array) -> Array[String]:
	var rows: Array[String] = []
	for i in LayoutData.SIZE:
		rows.append(EMPTY)
	for m: Vector2i in marks:
		rows[m.y] = rows[m.y].substr(0, m.x) + "#" + rows[m.y].substr(m.x + 1)
	return rows


func _area(pts: PackedVector2Array) -> float:
	return absf(ObstacleRegions._signed_area(pts))


func test_one_block_is_one_region_with_four_corners() -> void:
	var rs := ObstacleRegions.from_blocks(_rows([Vector2i(3, 3)]))
	assert_int(rs.size()).is_equal(1)
	assert_int(rs[0].outlines.size()).is_equal(1)
	assert_int(rs[0].outlines[0].size()).is_equal(4)
	assert_float(_area(rs[0].outlines[0])).is_equal_approx(4.0, 0.001)
	assert_int(rs[0].holes.size()).is_equal(0)


func test_side_neighbours_merge_into_one_straight_wall() -> void:
	var rs := ObstacleRegions.from_blocks(_rows([Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)]))
	assert_int(rs.size()).is_equal(1)
	assert_int(rs[0].blocks.size()).is_equal(3)
	assert_int(rs[0].outlines[0].size()).is_equal(4)  # три ребра на сторону слиты в одно: точек на прямой нет
	assert_float(_area(rs[0].outlines[0])).is_equal_approx(12.0, 0.001)


func test_diagonal_touch_is_two_objects() -> void:
	var rs := ObstacleRegions.from_blocks(_rows([Vector2i(2, 2), Vector2i(3, 3)]))
	assert_int(rs.size()).is_equal(2)


func test_l_shape_has_six_corners_and_area_of_its_blocks() -> void:
	var rs := ObstacleRegions.from_blocks(_rows([Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2)]))
	assert_int(rs.size()).is_equal(1)
	assert_int(rs[0].outlines[0].size()).is_equal(6)
	assert_float(_area(rs[0].outlines[0])).is_equal_approx(12.0, 0.001)


func test_ring_of_blocks_has_a_hole() -> void:
	var marks: Array = []
	for x in 3:
		for z in 3:
			if x != 1 or z != 1:
				marks.append(Vector2i(2 + x, 2 + z))
	var rs := ObstacleRegions.from_blocks(_rows(marks))
	assert_int(rs.size()).is_equal(1)
	assert_int(rs[0].outlines.size()).is_equal(1)
	assert_int(rs[0].holes.size()).is_equal(1)
	assert_float(_area(rs[0].outlines[0])).is_equal_approx(36.0, 0.001)
	assert_float(_area(rs[0].holes[0])).is_equal_approx(4.0, 0.001)


func test_outline_is_clockwise_from_above() -> void:
	var rs := ObstacleRegions.from_blocks(_rows([Vector2i(0, 0), Vector2i(1, 0)]))
	assert_float(ObstacleRegions._signed_area(rs[0].outlines[0])).is_greater(0.0)


func test_contour_points_sit_on_block_corners_in_world_metres() -> void:
	var rs := ObstacleRegions.from_blocks(_rows([Vector2i(0, 0)]))
	var pts := rs[0].outlines[0]
	assert_bool(pts.has(Vector2(NodeLayout.ROOM_MIN.x, NodeLayout.ROOM_MIN.y))).is_true()
	assert_bool(pts.has(Vector2(NodeLayout.ROOM_MIN.x + NodeLayout.CELL, NodeLayout.ROOM_MIN.y + NodeLayout.CELL))).is_true()


func test_other_symbols_are_not_obstacles() -> void:
	var rows := _rows([Vector2i(2, 2)])
	rows[2] = rows[2].substr(0, 3) + "V" + rows[2].substr(4)  # хранилище рядом с колонной не сливается с ней
	var rs := ObstacleRegions.from_blocks(rows)
	assert_int(rs.size()).is_equal(1)
	assert_int(rs[0].blocks.size()).is_equal(1)


func test_region_of_finds_the_region_of_a_block() -> void:
	var rs := ObstacleRegions.from_blocks(_rows([Vector2i(1, 1), Vector2i(2, 1), Vector2i(5, 5)]))
	assert_object(ObstacleRegions.region_of(rs, Vector2i(2, 1))).is_same(rs[0])
	assert_object(ObstacleRegions.region_of(rs, Vector2i(5, 5))).is_same(rs[1])
	assert_object(ObstacleRegions.region_of(rs, Vector2i(0, 0))).is_null()
