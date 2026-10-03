extends GdUnitTestSuite
## Геометрия узла на сетке модулей окружения (assets/models/MANIFEST.md): комната 16x16 м — 8x8 ячеек 2x2 м, центры ячеек в нечётных
## координатах. Спавн, хранилища шардов и порталы стоят в центрах ячеек, не ближе 1 м к стене (площадка портала r=1,5 м целиком в комнате),
## площадка выхода — на вершине между четырьмя ячейками (четыре помоста 2x2 вписывают круг r=2). Сервер читает те же константы.


func _all_slots() -> Array:
	var out: Array = [NodeLayout.SPAWN]
	out.append_array(NodeLayout.SHARD_SLOTS)
	out.append_array(NodeLayout.PORTAL_SLOTS)
	return out


func test_room_is_an_8x8_grid_of_2m_cells() -> void:
	assert_float(NodeLayout.ROOM_MAX.x - NodeLayout.ROOM_MIN.x).is_equal(NodeLayout.CELL * NodeLayout.GRID)
	assert_float(NodeLayout.ROOM_MAX.y - NodeLayout.ROOM_MIN.y).is_equal(NodeLayout.CELL * NodeLayout.GRID)
	assert_vector(NodeLayout.cell_center(0, 0)).is_equal(Vector3(-7, 0, -13))
	assert_vector(NodeLayout.cell_center(7, 7)).is_equal(Vector3(7, 0, 1))


func test_slots_stand_at_cell_centers() -> void:
	for p in _all_slots():
		assert_bool(NodeLayout.is_cell_center(p)).override_failure_message("не центр ячейки: %s" % [p]).is_true()
		assert_bool(NodeLayout.in_room(p)).is_true()


func test_slots_keep_one_meter_from_walls() -> void:
	for p in _all_slots():
		assert_float(NodeLayout.wall_gap(p)).override_failure_message("слот у стены: %s" % [p]).is_greater_equal(1.0)


func test_portal_pad_stays_inside_the_walls() -> void:
	# площадка r=1,5 м + толщина стены: раньше слоты (-7;-6) и (4;-13) выпускали её за стену на ~0,7 м
	for p in NodeLayout.PORTAL_SLOTS:
		assert_float(NodeLayout.wall_gap(p)).override_failure_message("площадка за стеной: %s" % [p]).is_greater_equal(NodeLayout.PORTAL_RADIUS + NodeLayout.WALL_THICKNESS)


func test_exit_pad_sits_on_a_cell_vertex_inside_the_room() -> void:
	var e := NodeLayout.EXIT_POS
	assert_bool(NodeLayout.is_cell_vertex(e)).is_true()
	assert_float(NodeLayout.wall_gap(e)).is_greater_equal(NodeLayout.EXIT_RADIUS)
	assert_array(NodeLayout.exit_platform_cells()).has_size(4)
	for c in NodeLayout.exit_platform_cells():
		assert_bool(NodeLayout.is_cell_center(c)).is_true()
		assert_float(NodeLayout.flat_distance(c, e)).is_equal_approx(sqrt(2.0), 0.001)


func test_exit_doors_are_south_wall_cells_behind_the_pad() -> void:
	for d in NodeLayout.EXIT_DOORS:
		assert_bool(NodeLayout.is_cell_center(d)).is_true()
		assert_float(d.z).is_equal(NodeLayout.ROOM_MAX.y - NodeLayout.CELL * 0.5)  # южный ряд
		assert_bool(NodeLayout.on_exit_pad(d)).is_true()


func test_spawn_is_outside_every_portal_and_the_exit() -> void:
	assert_bool(NodeLayout.on_exit_pad(NodeLayout.SPAWN)).is_false()
	for p in NodeLayout.PORTAL_SLOTS:
		assert_float(NodeLayout.flat_distance(NodeLayout.SPAWN, p)).is_greater(NodeLayout.PORTAL_RADIUS)


func test_shard_pos_is_the_first_slot() -> void:
	assert_vector(NodeLayout.SHARD_POS).is_equal(NodeLayout.SHARD_SLOTS[0])


func test_props_do_not_overlap() -> void:
	# хранилища, порталы и колонны не стоят друг на друге (круг портала r=1,5, хранилище и колонна ~0,7 м)
	var solids: Array = []
	for p in NodeLayout.SHARD_SLOTS:
		solids.append([Vector3(p.x, 0, p.z), 0.75])
	for p in NodeLayout.PORTAL_SLOTS:
		solids.append([p, NodeLayout.PORTAL_RADIUS])
	for p in NodeLayout.PILLARS:
		solids.append([p, 0.45])
	solids.append([NodeLayout.EXIT_POS, NodeLayout.EXIT_RADIUS])
	for i in solids.size():
		for j in range(i + 1, solids.size()):
			var need: float = solids[i][1] + solids[j][1]
			assert_float(NodeLayout.flat_distance(solids[i][0], solids[j][0])).override_failure_message("пересекаются %s и %s" % [solids[i][0], solids[j][0]]).is_greater_equal(need)


func test_pillars_stand_at_cell_centers() -> void:
	for p in NodeLayout.PILLARS:
		assert_bool(NodeLayout.is_cell_center(p)).is_true()


func test_yaw_turns_local_forward_to_the_target() -> void:
	# лицо предмета смотрит в +Z (MANIFEST): поворот вокруг Y направляет +Z на цель
	var yaw := NodeLayout.yaw_facing(Vector3(0, 0, 0), Vector3(5, 0, 0))
	assert_vector(Basis(Vector3.UP, yaw) * Vector3(0, 0, 1)).is_equal_approx(Vector3(1, 0, 0), Vector3.ONE * 0.001)
	var back := NodeLayout.yaw_facing(Vector3(0, 0, -3), Vector3(0, 0, -9))
	assert_vector(Basis(Vector3.UP, back) * Vector3(0, 0, 1)).is_equal_approx(Vector3(0, 0, -1), Vector3.ONE * 0.001)


func test_cardinal_yaw_snaps_to_the_nearest_wall_direction() -> void:
	# хранилище у северной стены смотрит на юг (+Z), у западной — на восток (+X)
	assert_float(NodeLayout.cardinal_yaw(Vector3(-5, 0, -13))).is_equal_approx(0.0, 0.001)
	assert_float(NodeLayout.cardinal_yaw(Vector3(-7, 0, -5))).is_equal_approx(PI / 2.0, 0.001)
	assert_float(absf(NodeLayout.cardinal_yaw(Vector3(5, 0, 1)))).is_equal_approx(PI, 0.001)
	assert_float(NodeLayout.cardinal_yaw(Vector3(7, 0, -5))).is_equal_approx(-PI / 2.0, 0.001)
