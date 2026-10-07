extends GdUnitTestSuite
## Клиент играет узел по раскладке (NodeView.set_layout, RigTestScene.apply_node): колонны, выход, кресло, площадки хранилищ, сетка прицела и света зрения,
## место входа. Раскладка test_alt_view кладётся в кэш LayoutData: у неё всё не там, где у legacy и Фойе, поэтому подмена константами NodeLayout не пройдёт.

const ALT := "test_alt_view"

var _alt: LayoutData


func before_test() -> void:
	_alt = LayoutData.parse({
		"name": ALT,
		"cells": [
			"V.......",
			".2......",
			"....#...",
			"..#....V",
			"........",
			".....1..",
			"S.......",
			"......EE",
		],
		"vaults": [
			{"cell": [7, 3], "pad": [6, 3], "ring": "outer"},
			{"cell": [0, 0], "pad": [0, 1], "ring": "outer"},
		],
		"ice": [],
	})
	assert_str(_alt.error).is_empty()
	LayoutData._cache[ALT] = _alt


func after_test() -> void:
	LayoutData._cache.erase(ALT)


func _scene() -> Node3D:
	var scene: Node3D = auto_free(preload("res://client/rig_test_scene.gd").new())
	add_child(scene)
	return scene


func _info(layout_name: String, ld: LayoutData) -> Dictionary:
	var shards: Array = []
	for k in ld.vaults.size():
		var p: Vector3 = ld.vaults[k]["slot"]
		shards.append({"id": "x_pk%d" % k, "p": [p.x, p.y, p.z], "ready": true})
	var info := {"kind": "node", "node": "node_x", "title": "Тест", "tier": "BASE", "r": NodeLayout.PORTAL_RADIUS, "shards": shards, "portals": []}
	if not layout_name.is_empty():
		info["layout"] = layout_name
	return info


# ---------------------------------------------------------------- комната и мебель

func test_колонны_ставятся_по_блокам_карты() -> void:
	var scene := _scene()
	scene.apply_node(_info(ALT, _alt))
	var got: Array = scene.view.pillar_positions()
	assert_int(got.size()).is_equal(2)
	assert_array(got).contains_exactly([NodeLayout.cell_center(4, 2), NodeLayout.cell_center(2, 3)])
	assert_int(int(scene.view.module_counts()["pillar"])).is_equal(2)


func test_фойе_четыре_колонны_по_карте_и_четыре_помоста_выхода() -> void:
	var scene := _scene()
	var foyer := LayoutData.cached("foyer")
	scene.apply_node(_info("foyer", foyer))
	assert_int(scene.view.pillar_positions().size()).is_equal(4)
	assert_int(int(scene.view.module_counts()["pillar"])).is_equal(4)
	assert_int(int(scene.view.module_counts()["platform"])).is_equal(4)
	assert_int(int(scene.view.module_counts()["tunnel_ring"])).is_equal(NodeLayout.EXIT_TUNNEL_SEGMENTS)


func test_укрытия_блока_хранилища_три_клетки_на_каждое_хранилище_фойе() -> void:
	var scene := _scene()
	var foyer := LayoutData.cached("foyer")
	scene.apply_node(_info("foyer", foyer))
	var got: Array[Vector3] = scene.view.cover_positions()
	assert_int(got.size()).is_equal(3 * foyer.vaults.size())
	assert_int(int(scene.view.module_counts()["cover"])).is_equal(3 * foyer.vaults.size())
	for v: Dictionary in foyer.vaults:
		var vault_cell: Vector2i = v["cell1"]
		var in_block := 0
		for p in got:
			var c := NodeGrid.cell_of(p)
			assert_vector(p).is_equal_approx(NodeGrid.center(c), Vector3.ONE * 0.001)  # центр клетки, y = 0
			assert_that(c).is_not_equal(vault_cell)                                    # не на клетке самого хранилища
			if LayoutData.block_of(c) == v["cell"]:
				in_block += 1
		assert_int(in_block).is_equal(3)


func test_укрытий_нет_без_раскладки_и_в_legacy() -> void:
	var scene := _scene()
	scene.apply_node(_info("", _alt))
	assert_int(scene.view.cover_positions().size()).is_equal(0)
	assert_int(int(scene.view.module_counts()["cover"])).is_equal(0)


func test_выход_и_кресло_по_раскладке_датчика_нет() -> void:
	var scene := _scene()
	scene.apply_node(_info(ALT, _alt))
	assert_vector(scene.view.exit_pos()).is_equal(_alt.exit_pos)
	assert_array(scene.view.exit_cells()).is_equal(_alt.exit_cells)
	assert_vector(scene.view.seat_node().position).is_equal_approx(_alt.spawn, Vector3.ONE * 0.001)
	assert_array(scene.view.used_assets()).not_contains(["res://assets/models/props/sensor.glb"])
	assert_array(scene.view.used_assets()).contains(["res://assets/models/props/seat.glb"])


func test_без_поля_layout_комната_прежняя_и_датчик_на_месте() -> void:
	var scene := _scene()
	scene.apply_node(_info("", _alt))
	assert_int(scene.view.pillar_positions().size()).is_equal(NodeLayout.PILLARS.size())
	assert_vector(scene.view.seat_node().position).is_equal_approx(NodeLayout.SPAWN, Vector3.ONE * 0.001)
	assert_array(scene.view.used_assets()).contains(["res://assets/models/props/sensor.glb"])
	assert_vector(scene.view.exit_pos()).is_equal(NodeLayout.EXIT_POS)


func test_переход_между_узлами_пересобирает_комнату() -> void:
	var scene := _scene()
	scene.apply_node(_info(ALT, _alt))
	assert_int(scene.view.pillar_positions().size()).is_equal(2)
	scene.apply_node(_info("", _alt))   # узел без раскладки
	assert_int(int(scene.view.module_counts()["pillar"])).is_equal(NodeLayout.PILLARS.size())
	assert_vector(scene.view.seat_node().position).is_equal_approx(NodeLayout.SPAWN, Vector3.ONE * 0.001)
	scene.apply_node(_info(ALT, _alt))
	assert_int(int(scene.view.module_counts()["pillar"])).is_equal(2)
	assert_vector(scene.view.seat_node().position).is_equal_approx(_alt.spawn, Vector3.ONE * 0.001)


func test_площадка_взлома_по_клетке_pad_раскладки() -> void:
	var scene := _scene()
	scene.apply_node(_info(ALT, _alt))
	# площадка — центр клетки 1 м блока pad (не угол блока): [6, 3] → клетка (13; 7), [0, 1] → клетка (1; 2)
	assert_vector(scene.view.pad_node("x_pk0").position).is_equal_approx(Vector3(5.5, 0, -6.5), Vector3.ONE * 0.001)
	assert_vector(scene.view.pad_node("x_pk1").position).is_equal_approx(Vector3(-6.5, 0, -11.5), Vector3.ONE * 0.001)


func test_площадка_без_раскладки_по_прежнему_правилу() -> void:
	var scene := _scene()
	scene.apply_node(_info("", _alt))
	var slot: Vector3 = _alt.vaults[0]["slot"]
	var base := Vector3(slot.x, 0.0, slot.z)
	assert_vector(scene.view.pad_node("x_pk0").position).is_equal_approx(NodeLayout.vault_pad(base), Vector3.ONE * 0.001)


func test_хранилище_смотрит_на_площадку() -> void:
	var base := NodeLayout.cell_center(7, 3)
	for pad_cell in [Vector2i(6, 3), Vector2i(7, 4), Vector2i(8 - 1, 2), Vector2i(7, 3)]:
		var pad := NodeLayout.cell_center(pad_cell.x, pad_cell.y)
		var yaw := NodeView.vault_yaw_to(base, pad, 1.25)
		var face := Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)   # лицо vault.glb — локальный −Z
		if pad_cell == Vector2i(7, 3):
			assert_float(yaw).is_equal(1.25)   # площадка в той же клетке — прежний поворот
		else:
			assert_float(face.dot((pad - base).normalized())).is_equal_approx(1.0, 0.001)


# ---------------------------------------------------------------- сетка и привязка

func test_сетка_прицела_по_раскладке() -> void:
	var scene := _scene()
	scene.apply_node(_info(ALT, _alt))
	assert_dict(scene.rig.grid.occ).is_equal(_alt.occupied)
	assert_bool(scene.rig.grid.is_occupied(LayoutData.block_cells(Vector2i(4, 2))[0])).is_true()   # колонна раскладки
	assert_bool(scene.rig.grid.is_occupied(NodeGrid.cell_of(NodeLayout.PILLARS[0]))).is_false()   # колонны прежней комнаты здесь нет
	scene.apply_node(_info("", _alt))
	assert_dict(scene.rig.grid.occ).is_equal(NodeGrid.for_layout().occ)


func test_свет_зрения_берёт_сетку_нового_узла() -> void:
	var floor := TickFloor.new(NodeGrid.for_layout())
	auto_free(floor)
	var g := _alt.grid()
	floor.set_grid(g)
	assert_object(floor._grid).is_same(g)
	floor.set_grid(null)
	assert_dict(floor._grid.occ).is_equal(NodeGrid.for_layout().occ)


func test_привязка_телепорта_к_площадке_раскладки() -> void:
	var scene := _scene()
	scene.apply_node(_info(ALT, _alt))
	var slot: Vector3 = _alt.vaults[0]["slot"]
	var near := Vector3(slot.x - 1.0, 0.0, slot.z)
	var snapped: Dictionary = scene.snap_teleport(near)
	var pad := Vector3(5.5, 0, -6.5)   # клетка (13; 7)
	assert_float((snapped["p"] as Vector3).x).is_equal_approx(pad.x, 0.001)
	assert_float((snapped["p"] as Vector3).z).is_equal_approx(pad.z, 0.001)
	assert_object(snapped["look"]).is_not_null()


# ---------------------------------------------------------------- место входа

func test_первый_узел_ставит_риг_на_вход_раскладки() -> void:
	var scene := _scene()
	assert_float(scene.rig.global_position.x).is_equal_approx(NodeLayout.SPAWN.x, 0.001)
	scene.apply_node(_info(ALT, _alt))
	assert_float(scene.rig.global_position.x).is_equal_approx(_alt.spawn.x, 0.001)
	assert_float(scene.rig.global_position.z).is_equal_approx(_alt.spawn.z, 0.001)


func test_повторное_событие_узла_риг_не_двигает() -> void:
	var scene := _scene()
	scene.apply_node(_info(ALT, _alt))
	scene.rig.global_position = Vector3(3.0, scene.rig.global_position.y, -7.0)
	scene.apply_node(_info(ALT, _alt))   # то же событие без arrive (переподключение): игрок остаётся где был
	assert_float(scene.rig.global_position.x).is_equal_approx(3.0, 0.001)
	assert_float(scene.rig.global_position.z).is_equal_approx(-7.0, 0.001)


func test_после_тоннеля_риг_в_точке_arrive() -> void:
	var scene := _scene()
	scene.apply_node(_info(ALT, _alt))
	var info := _info(ALT, _alt)
	info["arrive"] = [1.0, -2.0]
	scene.apply_node(info)
	assert_float(scene.rig.global_position.x).is_equal_approx(1.0, 0.001)
	assert_float(scene.rig.global_position.z).is_equal_approx(-2.0, 0.001)


func test_точка_входа_раскладки_и_запасная() -> void:
	var cls := preload("res://client/rig_test_scene.gd")
	assert_vector(cls.entry_point(_alt)).is_equal(_alt.spawn)
	assert_vector(cls.entry_point(null)).is_equal(NodeLayout.SPAWN)
	assert_vector(cls.entry_point(LayoutData.load_named("нет_такой"))).is_equal(NodeLayout.SPAWN)


# ---------------------------------------------------------------- клиентский экспорт

func test_экспорт_клиента_включает_раскладки() -> void:
	var cfg := ConfigFile.new()
	assert_int(cfg.load("res://export_presets.cfg")).is_equal(OK)
	var found := false
	for section in cfg.get_sections():
		if str(cfg.get_value(section, "name", "")) != "Client Pico 4 (Android)":
			continue
		found = true
		var include := str(cfg.get_value(section, "include_filter", ""))
		var ok := false
		for pat in include.split(",", false):
			if "data/layouts/foyer.json".match(pat.strip_edges()):
				ok = true
		assert_bool(ok).is_true()
		for pat in str(cfg.get_value(section, "exclude_filter", "")).split(",", false):
			assert_bool("data/layouts/foyer.json".match(pat.strip_edges())).is_false()
	assert_bool(found).is_true()
