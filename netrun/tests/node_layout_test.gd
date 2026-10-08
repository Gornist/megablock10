extends GdUnitTestSuite
## Геометрия узла на сетке модулей окружения (assets/models/MANIFEST.md): комната 16x16 м — 8x8 ячеек 2x2 м, центры ячеек в нечётных
## координатах. Спавн и порталы стоят в центрах ячеек 2×2, не ближе 1 м к стене (площадка портала r=1,5 м целиком в комнате),
## площадка выхода — на вершине между четырьмя ячейками (четыре помоста 2x2 вписывают круг r=2). Хранилища шардов — в центре клетки 1 м
## (П4: не на вершине блока), см. test_хранилища_и_их_площадки_в_центрах_клеток. Сервер читает те же константы.


func _all_slots() -> Array:
	var out: Array = [NodeLayout.SPAWN]
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


func test_хранилища_и_их_площадки_в_центрах_клеток_а_не_на_вершинах() -> void:
	# владелец на очках (П4): хранилище стояло на пересечении 4 клеток; теперь слот и площадка — центр клетки 1 м (допуск 5 см)
	for p: Vector3 in NodeLayout.SHARD_SLOTS:
		for q: Vector3 in [Vector3(p.x, 0.0, p.z), NodeLayout.vault_pad(p)]:
			var c := NodeGrid.center(NodeGrid.cell_of(q))
			assert_float(Vector2(q.x - c.x, q.z - c.z).length()).override_failure_message("не центр клетки 1 м: %s" % [q]).is_less(0.05)
		assert_bool(NodeLayout.in_room(p)).is_true()
		assert_float(NodeLayout.wall_gap(p)).is_greater_equal(1.0)


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


## Маршруты ICE (карточка 1б, шаг 3). Расстояние от точки до ближайшей точки маршрута (ломаная, по кругу: последняя точка → первая), плоскость XZ.
func _route_distance(p: Vector3, waypoints: Array) -> float:
	var best := INF
	for i in waypoints.size():
		var a: Vector3 = waypoints[i]
		var b: Vector3 = waypoints[(i + 1) % waypoints.size()]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var t := 0.0
		if ab.length_squared() > 0.0:
			t = clampf(Vector2(p.x - a.x, p.z - a.z).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var q := Vector2(a.x, a.z) + ab * t
		best = minf(best, Vector2(p.x, p.z).distance_to(q))
	return best


func _all_routes() -> Array:
	var out: Array = []
	for d in NodeLayout.ICE:
		out.append(d)
	for d in NodeLayout.BLACK_ICE:
		out.append(d)
	return out


func test_ice_routes_stay_on_even_coordinates_inside_the_room() -> void:
	for d in _all_routes():
		for w in d["waypoints"]:
			assert_bool(NodeLayout.in_room(w)).override_failure_message("%s: точка маршрута вне комнаты: %s" % [d["id"], w]).is_true()
			assert_bool(is_equal_approx(fposmod(w.x, 2.0), 0.0) and is_equal_approx(fposmod(w.z, 2.0), 0.0)).override_failure_message("%s: точка не на ребре ячеек: %s" % [d["id"], w]).is_true()


## Стоя у хранилища, игрок не на маршруте Стража: слот шарда — не ближе MIN_VAULT_TO_ROUTE к любой точке маршрута любого ICE.
func test_every_vault_slot_is_far_from_every_ice_route() -> void:
	var rows: Array[String] = []
	for slot in NodeLayout.SHARD_SLOTS:
		var nearest := INF
		for d in _all_routes():
			nearest = minf(nearest, _route_distance(slot, d["waypoints"]))
		rows.append("(%d;%d): %.1f м" % [slot.x, slot.z, nearest])
		assert_float(nearest).override_failure_message("слот %s ближе %.1f м к маршруту ICE: %.2f" % [slot, NodeLayout.MIN_VAULT_TO_ROUTE, nearest]).is_greater_equal(NodeLayout.MIN_VAULT_TO_ROUTE)
	print("[w1b-раскладка] слот → мин. расстояние до маршрута ICE: ", "; ".join(rows))


## Спавн и порталы — вне конуса ICE на первой точке патруля (ICE смотрит на вторую) с запасом по зрению узла: каждый узел графа со своими числами
## (sight_range узла × тревога, Black ICE — settings.black_ice). И маршрут не заходит ближе 3 м к спавну и порталам.
func test_spawn_and_portals_are_outside_the_ice_cone_at_patrol_start_in_every_graph_node() -> void:
	var g := NodeGraph.load_file()
	var boost := 1.0 + float(g.settings["alert_boost"])
	var half := float(IceBrain.DEFAULT_SETTINGS["sight_half_angle_deg"])
	for id in g.nodes:
		var def: Dictionary = g.nodes[id]
		var sight := float(def.get("ice_settings", {}).get("sight_range", IceBrain.DEFAULT_SETTINGS["sight_range"])) * boost
		var checks: Array = []
		for i in int(def["ice"]):
			checks.append([NodeLayout.ICE[i], sight])
		if def["tier"] == NodeGraph.TIER_BLACK:
			checks.append([NodeLayout.BLACK_ICE[0], float(g.settings["black_ice"]["sight_range"]) * boost])
		var watched: Array = [NodeLayout.SPAWN]
		for i in (def["links"] as Array).size():
			watched.append(NodeLayout.PORTAL_SLOTS[i])
		for c in checks:
			var wps: Array[Vector3] = []
			for w in c[0]["waypoints"]:
				wps.append(w)
			var brain := IceBrain.new({}, wps[0], wps)
			for p in watched:
				assert_bool(IceBrain.can_see(wps[0], brain.facing, p, c[1], half)).override_failure_message("%s: %s на старте видит %s (зрение %.1f м)" % [id, c[0]["id"], p, c[1]]).is_false()
				assert_float(_route_distance(p, wps)).override_failure_message("%s: маршрут %s ближе 3 м к %s" % [c[0]["id"], id, p]).is_greater_equal(3.0)
