extends GdUnitTestSuite
## Раскладка узла как данные (LayoutData): разбор Фойе и учебного узла, `legacy` = нынешние константы NodeLayout, битые данные не роняют.


func _foyer() -> LayoutData:
	var ld := LayoutData.load_named("foyer")
	assert_str(ld.error).is_empty()
	return ld


func _same_keys(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k):
			return false
	return true


func test_фойе_занятые_клетки_колонны_и_хранилища() -> void:
	var ld := _foyer()
	assert_int(ld.occupied.size()).is_equal(24)   # 4 колонны × 4 клетки + 2 хранилища × 4 клетки
	for c: Vector2i in [Vector2i(4, 2), Vector2i(5, 3), Vector2i(10, 2), Vector2i(11, 7), Vector2i(4, 6), Vector2i(0, 0), Vector2i(1, 1), Vector2i(15, 0), Vector2i(14, 1)]:
		assert_bool(ld.occupied.has(c)).is_true()
	for c: Vector2i in [Vector2i(0, 2), Vector2i(7, 13), Vector2i(3, 5), Vector2i(13, 9), Vector2i(2, 0)]:
		assert_bool(ld.occupied.has(c)).is_false()
	var g := ld.grid()
	assert_bool(g.is_occupied(Vector2i(4, 2))).is_true()
	assert_bool(g.is_occupied(Vector2i(7, 13))).is_false()


func test_фойе_вход_выход_порталы_и_хранилища() -> void:
	var ld := _foyer()
	assert_object(ld.spawn).is_equal(NodeLayout.SPAWN)
	assert_object(ld.exit_pos).is_equal(NodeLayout.EXIT_POS)
	assert_int(ld.exit_cells.size()).is_equal(4)
	assert_array(ld.exit_cells).contains_exactly(NodeLayout.exit_platform_cells())
	assert_array(ld.portals).is_equal([Vector3(-7, 0, -3), Vector3(7, 0, -3), Vector3(-1, 0, -13)])
	assert_int(ld.vaults.size()).is_equal(2)
	# хранилище и площадка — центры клеток 1 м (юго-восточная клетка блока хранилища и клетка площадки под ней), не углы блоков
	assert_object(ld.vaults[0]["slot"]).is_equal(Vector3(-6.5, 1.0, -12.5))
	assert_object(ld.vaults[1]["slot"]).is_equal(Vector3(7.5, 1.0, -12.5))
	assert_object(ld.vaults[0]["pad"]).is_equal(Vector3(-6.5, 0, -11.5))
	assert_object(ld.vaults[1]["pad"]).is_equal(Vector3(7.5, 0, -11.5))
	assert_object(ld.vaults[0]["cell1"]).is_equal(Vector2i(1, 1))
	assert_object(ld.vaults[0]["pad1"]).is_equal(Vector2i(1, 2))
	assert_object(ld.vaults[0]["pad_cell"]).is_equal(Vector2i(0, 1))
	assert_str(ld.vaults[0]["ring"]).is_equal("outer")
	assert_float(ld.sight_cells).is_equal(6.0)


func test_фойе_страж_маршрут_в_клетках_ожидание_и_взгляд() -> void:
	var ld := _foyer()
	assert_int(ld.sentries.size()).is_equal(1)
	assert_str(ld.sentries[0]["id"]).is_equal("g1")
	var route: Array = ld.sentries[0]["route"]
	assert_int(route.size()).is_equal(4)
	var cells: Array = []
	var waits: Array = []
	var looks: Array = []
	for p: Dictionary in route:
		cells.append(p["cell"])
		waits.append(p["wait"])
		looks.append(p["look"])
	assert_array(cells).is_equal([Vector2i(3, 5), Vector2i(13, 5), Vector2i(13, 9), Vector2i(3, 9)])   # юго-восточная клетка центра блока
	assert_array(waits).is_equal([1, 1, 1, 1])
	assert_array(looks).is_equal([Vector2i(0, 1), Vector2i(0, 1), Vector2i(0, -1), Vector2i(0, -1)])
	# Формат маршрута — тот, что принимает TickIce.
	var ice := TickIce.new({}, route, ld.grid())
	assert_object(ice.cell()).is_equal(Vector2i(3, 5))


func test_учебный_узел_та_же_карта_медленный_страж_и_подсказки() -> void:
	var f := _foyer()
	var t := LayoutData.load_named("foyer_tutorial")
	assert_str(t.error).is_empty()
	assert_array(t.blocks).is_equal(f.blocks)
	for p: Dictionary in t.sentries[0]["route"]:
		assert_int(p["wait"]).is_equal(2)
	assert_int(t.signs.size()).is_equal(4)
	for s: Dictionary in t.signs:
		assert_bool(not t.occupied.has(s["cell"])).is_true()   # подсказка лежит на свободной клетке
		assert_bool(not str(s["text"]).is_empty()).is_true()
	assert_str(t.signs[0]["text"]).is_equal("ЖДИ, ПОКА СТРАЖ ОТВЕРНЁТСЯ")
	assert_object(t.signs[0]["pos"]).is_equal(NodeLayout.cell_center(3, 5))   # cell [3, 5] — центр модуля


func test_legacy_даёт_те_же_занятые_клетки_и_позиции_что_константы_node_layout() -> void:
	var ld := LayoutData.load_named("legacy")
	assert_str(ld.error).is_empty()
	assert_bool(_same_keys(ld.occupied, NodeGrid.for_layout().occ)).is_true()
	assert_object(ld.spawn).is_equal(NodeLayout.SPAWN)
	assert_object(ld.exit_pos).is_equal(NodeLayout.EXIT_POS)
	assert_array(ld.exit_cells).is_equal(NodeLayout.exit_platform_cells())
	assert_array(ld.portals).is_equal(NodeLayout.PORTAL_SLOTS)
	var slots: Array = []
	for v: Dictionary in ld.vaults:
		slots.append(v["slot"])
	assert_array(slots).is_equal(NodeLayout.SHARD_SLOTS)


func test_legacy_маршруты_ice_и_black_ice_как_в_константах() -> void:
	var ld := LayoutData.load_named("legacy")
	assert_int(ld.sentries.size()).is_equal(NodeLayout.ICE.size())
	for i in NodeLayout.ICE.size():
		var want: Dictionary = NodeLayout.ICE[i]
		var got: Dictionary = ld.sentries[i]
		assert_str(got["id"]).is_equal(want["id"])
		var want_cells := TickIce.route_from_points(want["waypoints"])
		var got_route: Array = got["route"]
		assert_int(got_route.size()).is_equal(want_cells.size())
		for j in want_cells.size():
			assert_object(got_route[j]["cell"]).is_equal(want_cells[j])
			assert_int(got_route[j]["wait"]).is_equal(0)
	var bl: Dictionary = NodeLayout.BLACK_ICE[0]
	assert_str(ld.black["id"]).is_equal(bl["id"])
	var black_cells := TickIce.route_from_points(bl["waypoints"])
	for j in black_cells.size():
		assert_object(ld.black["route"][j]["cell"]).is_equal(black_cells[j])


func test_битые_данные_дают_error_и_не_падают() -> void:
	assert_bool(LayoutData.parse({}).error != "").is_true()
	assert_bool(LayoutData.load_named("нет_такой_раскладки").error != "").is_true()
	var ok_cells := ["V..3...V", "..#..#..", "........", "..#..#..", "........", "1......2", "...S.EE.", ".....EE."]
	var base := {"name": "x", "cells": ok_cells, "vaults": [], "ice": []}
	assert_str(LayoutData.parse(base).error).is_empty()
	var short := base.duplicate(true)
	short["cells"] = ok_cells.slice(0, 7)
	assert_bool(LayoutData.parse(short).error != "").is_true()
	var wide := base.duplicate(true)
	wide["cells"] = ok_cells.duplicate()
	wide["cells"][2] = "........."
	assert_bool(LayoutData.parse(wide).error != "").is_true()
	var unknown := base.duplicate(true)
	unknown["cells"] = ok_cells.duplicate()
	unknown["cells"][2] = "...?...."
	assert_bool(LayoutData.parse(unknown).error != "").is_true()
	var no_spawn := base.duplicate(true)
	no_spawn["cells"] = ok_cells.duplicate()
	no_spawn["cells"][6] = ".....EE."
	assert_bool(LayoutData.parse(no_spawn).error != "").is_true()
	var no_exit := base.duplicate(true)
	no_exit["cells"] = ok_cells.duplicate()
	no_exit["cells"][6] = "...S...."
	no_exit["cells"][7] = "........"
	assert_bool(LayoutData.parse(no_exit).error != "").is_true()
	var bad_route := base.duplicate(true)
	bad_route["ice"] = [{"id": "g", "kind": "sentry", "route": [{"cell": [9, 0]}]}]
	assert_bool(LayoutData.parse(bad_route).error != "").is_true()
	var bad_vault := base.duplicate(true)
	bad_vault["vaults"] = [{"cell": "0,0", "pad": [0, 1]}]
	assert_bool(LayoutData.parse(bad_vault).error != "").is_true()
	var bad_cells := base.duplicate(true)
	bad_cells["cells"] = "не массив"
	assert_bool(LayoutData.parse(bad_cells).error != "").is_true()


func test_cached_одна_загрузка_на_имя_пусто_значит_legacy() -> void:
	var a := LayoutData.cached("foyer")
	assert_bool(a == LayoutData.cached("foyer")).is_true()
	assert_str(a.name).is_equal("foyer")
	assert_bool(LayoutData.cached("").is_legacy()).is_true()
	assert_bool(a.is_legacy()).is_false()
	assert_bool(LayoutData.cached("нет_такой").error != "").is_true()


func test_дальность_зрения_задана_только_если_есть_в_файле() -> void:
	assert_bool(LayoutData.cached("foyer").has_sight).is_true()
	assert_float(LayoutData.cached("foyer").sight_cells).is_equal(6.0)
	assert_bool(LayoutData.cached("legacy").has_sight).is_false()


func test_клетки_хранилища_ведут_на_площадку_а_в_legacy_нет() -> void:
	var ld := _foyer()
	var g := ld.grid()
	# хранилище [0, 0] — блок клеток (0..1; 0..1), площадка — клетка (1; 2): прыжок на любую клетку блока приземляется на неё
	for c in LayoutData.block_cells(Vector2i(0, 0)):
		assert_object(g.landing_of(c)).is_equal(Vector2i(1, 2))
		assert_bool(g.is_occupied(c)).is_true()   # сами клетки по-прежнему заняты
	assert_object(g.landing_of(Vector2i(8, 8))).is_equal(Vector2i(8, 8))   # прочие клетки — как есть
	assert_bool(LayoutData.load_named("legacy").grid().landing.is_empty()).is_true()


func test_площадка_с_западной_стороны_хранилища_рядом_с_ним() -> void:
	# хранилище [7, 3] у восточного края, площадка [6, 3] левее: хранилище — клетка западной половины его блока, не угол в двух клетках от площадки
	var d := {"name": "x", "cells": ["........", "........", "........", ".......V", "........", "........", "S.......", "......EE"],
		"vaults": [{"cell": [7, 3], "pad": [6, 3]}], "ice": []}
	var ld := LayoutData.parse(d)
	assert_str(ld.error).is_empty()
	var v: Dictionary = ld.vaults[0]
	assert_int(maxi(absi(v["cell1"].x - v["pad1"].x), absi(v["cell1"].y - v["pad1"].y))).is_equal(1)
	assert_bool(LayoutCheck.check_vault_grid(ld)["ok"]).is_true()
