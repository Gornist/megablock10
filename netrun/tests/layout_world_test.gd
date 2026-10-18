extends GdUnitTestSuite
## Узел играет по раскладке (docs/gamedesign/levels.md, 7): слоты шардов, порталы, вход, выход, площадка хранилища, сетка, Стражи, сообщение узла.
## Раскладка test_alt кладётся в кэш LayoutData: всё в ней не там, где у legacy и Фойе, поэтому подмена на константы NodeLayout не пройдёт незамеченной.

static var _next_port := 18791
const ALT := "test_alt"

var _root: Node
var _server: NetServer
var _world: GraphWorld


func before_test() -> void:
	LayoutData._cache[ALT] = LayoutData.parse({
		"name": ALT,
		"cells": [
			"V.......",
			".2......",
			"........",
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
		"ice": [
			{"id": "t1", "kind": "sentry", "route": [
				{"cell": [1, 4], "wait": 2, "look": ["E"]},
				{"cell": [6, 4], "wait": 1, "look": ["N"]},
			]},
		],
		"signs": [{"cell": [3, 5], "text": "ВЫХОД СПРАВА"}],
		"meta": {"sight_cells": 4},
	})
	assert_str((LayoutData._cache[ALT] as LayoutData).error).is_empty()
	_root = Node.new()
	add_child(_root)


func after_test() -> void:
	if _server != null:
		_server.stop_net()
	_root.queue_free()
	LayoutData._cache.erase(ALT)


## Мир из двух узлов: x_alt (раскладка test_alt, шардов и Стражей по параметрам) и x_leg (без layout — legacy). Тактовый режим — по умолчанию.
func _build(alt_shards: int = 1, time_mode: String = "tick", layout_name: String = ALT) -> void:
	var d := {"default_entry": "x_alt", "entries": {}, "settings": {"time_mode": time_mode, "vault_requires_open": false}, "nodes": {
		"x_alt": {"title": "Альт", "tier": "BASE", "ice": 1, "shards": alt_shards, "layout": layout_name, "links": ["x_leg"], "signs": [{"p": [9.0, 9.0], "text": "НЕ ТА КОМНАТА"}]},
		"x_leg": {"title": "Старый", "tier": "BASE", "ice": 2, "shards": 3, "links": ["x_alt"], "signs": [{"p": [1.0, 2.0], "text": "СТАРАЯ"}]},
	}}
	var sroot := Node.new()
	sroot.name = "S"
	_root.add_child(sroot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), sroot.get_path())
	_server = NetServer.new()
	sroot.add_child(_server)
	var cfg := NetConfig.new()
	cfg.port = _next_port
	_next_port += 1
	assert_int(_server.start(cfg, DictTokenVerifier.new({}))).is_equal(OK)
	_world = GraphWorld.new()
	sroot.add_child(_world)
	_world.start(_server, null, NodeGraph.from_dict(d))


func _alt() -> GrayNode:
	return _world.node_of("x_alt")


func _leg() -> GrayNode:
	return _world.node_of("x_leg")


func test_слоты_шардов_стоят_в_первых_хранилищах_раскладки() -> void:
	_build(2)
	var ids := _alt().slot_ids()
	assert_int(ids.size()).is_equal(2)
	assert_object(_server.object_position(ids[0])).is_equal(Vector3(6.5, 1.0, -6.5))   # клетка (14; 7) — центр клетки 1 м
	assert_object(_server.object_position(ids[1])).is_equal(Vector3(-6.5, 1.0, -12.5))
	# legacy-узел — прежние SHARD_SLOTS
	var leg_ids := _leg().slot_ids()
	for k in 3:
		assert_object(_server.object_position(leg_ids[k])).is_equal(NodeLayout.SHARD_SLOTS[k])


func test_шардов_больше_хранилищ_раскладки_лишние_пустые() -> void:
	_build(3)
	assert_int(_alt().slot_ids().size()).is_equal(2)   # у раскладки два хранилища: третьего слота нет


func test_портал_узла_стоит_там_где_на_карте_цифра() -> void:
	_build()
	var pts := _alt().portals()
	assert_int(pts.size()).is_equal(1)
	assert_object(pts[0]["pos"]).is_equal(Vector3(3, 0, -3))   # клетка карты (5; 5)
	assert_object(_leg().portals()[0]["pos"]).is_equal(NodeLayout.PORTAL_SLOTS[0])


func test_вход_игрока_по_раскладке_узла_сессии() -> void:
	_build()
	_server.set_node("s1", "x_alt")
	_server.set_node("s2", "x_leg")
	assert_object(_server.spawn_of.call("s1")).is_equal(Vector3(-7, 0, -1))   # S в клетке карты (0; 6)
	assert_object(_server.spawn_of.call("s2")).is_equal(NodeLayout.SPAWN)
	assert_object(_alt().layout.spawn).is_equal(Vector3(-7, 0, -1))


func test_площадка_хранилища_раскладки_это_клетка_pad_лицом_к_хранилищу() -> void:
	_build()
	# хранилище [7, 3] — клетка (14; 7) его блока, ближайшая к площадке [6, 3]: центр (6,5; -6,5); площадка — клетка (13; 7)
	var snap := _alt().snap_teleport(Vector3(6.5, 0, -6.2))   # в клетке хранилища: ближе 0,75 м (П5)
	assert_object(snap["p"]).is_equal(Vector3(5.5, 0, -6.5))
	assert_object(snap["look"]).is_equal(Vector3(6.5, 0, -6.5))
	assert_object(_alt().snap_teleport(Vector3(6.5, 0, -5.5))["look"]).is_null()   # соседняя клетка (1 м) не привязывается
	assert_object(_alt().snap_teleport(Vector3(0, 0, -3))["look"]).is_null()   # далеко от хранилищ — без привязки
	# legacy: прежнее правило (cardinal_yaw), не клетка pad
	var slot: Vector3 = NodeLayout.SHARD_SLOTS[0]
	var near := Vector3(slot.x + 0.5, 0, slot.z + 0.5)
	assert_object(_leg().snap_teleport(near)).is_equal(NodeLayout.snap_to_vault_pad(near, NodeLayout.SHARD_SLOTS))


func test_выход_и_прибытие_по_раскладке() -> void:
	var alt: LayoutData = LayoutData.cached(ALT)
	assert_object(alt.exit_pos).is_equal(Vector3(6, 0, 1))
	assert_bool(NodeLayout.on_exit_pad_in(alt, Vector3(6, 0, 0))).is_true()
	assert_bool(NodeLayout.on_exit_pad_in(alt, NodeLayout.EXIT_POS)).is_false()
	var arrive := NodeLayout.arrival_in(alt, 0)
	assert_float(NodeLayout.flat_distance(arrive, alt.portals[0])).is_equal_approx(NodeLayout.ARRIVE_DIST, 0.001)
	assert_object(NodeLayout.arrival_in(alt, 2)).is_equal(alt.spawn)    # портала 3 на карте нет — вход
	assert_object(NodeLayout.arrival_in(alt, -1)).is_equal(alt.spawn)


func test_legacy_раскладка_даёт_прежние_прибытие_выход_и_площадку() -> void:
	var leg := LayoutData.cached("legacy")
	for slot in NodeLayout.PORTAL_SLOTS.size():
		assert_object(NodeLayout.arrival_in(leg, slot)).is_equal(NodeLayout.arrival_for_slot(slot))
	for p: Vector3 in [Vector3(4, 0, 0), Vector3(6, 0, 0), Vector3(2, 0, 0), Vector3(6.1, 0, 0), Vector3(0, 0, -6)]:
		assert_bool(NodeLayout.on_exit_pad_in(leg, p)).is_equal(NodeLayout.on_exit_pad(p))
	for k in leg.vaults.size():
		assert_object(leg.vaults[k]["slot"]).is_equal(NodeLayout.SHARD_SLOTS[k])


# ---------------------------------------------------------------- сетка узла

func test_сетка_узла_своя_колонна_раскладки_не_колонна_legacy() -> void:
	_build()
	var column := Vector2i(4, 6)   # колонна карты (2; 3) → клетки 4..5 × 6..7
	assert_bool(_alt().ice_grid.is_occupied(column)).is_true()
	assert_bool(_leg().ice_grid.is_occupied(column)).is_false()
	assert_bool(_alt().ice_grid.is_occupied(Vector2i(5, 9))).is_false()   # колонна legacy в раскладке test_alt не стоит
	assert_bool(_leg().ice_grid.is_occupied(Vector2i(5, 9))).is_true()


func test_проверка_телепорта_идёт_по_сетке_узла_сессии() -> void:
	_build()
	_server.set_node("s1", "x_alt")
	_server.set_node("s2", "x_leg")
	assert_bool(_server.grid_for("s1") == _alt().ice_grid).is_true()
	assert_bool(_server.grid_for("s2") == _leg().ice_grid).is_true()
	var from := NodeGrid.center(Vector2i(4, 8))
	var to := NodeGrid.center(Vector2i(4, 6))   # колонна test_alt
	assert_str(_server._cell_verdict("s1", from, to)).is_equal(WorldMsg.REASON_CELL)
	assert_str(_server._cell_verdict("s2", from, to)).is_empty()   # в legacy-узле клетка свободна
	# сессия без узла графа — общая сетка сервера
	assert_bool(_server.grid_for("s_none") == _server.grid).is_true()


# ---------------------------------------------------------------- Стражи

func _tick_of(gn: GrayNode) -> TickIce:
	return gn._tick_ices.values()[0]


func test_тактовый_страж_раскладки_идёт_по_её_маршруту_с_ожиданием_и_дальностью() -> void:
	_build()
	assert_int(_alt().ices().size()).is_equal(1)   # узел просит 1, в раскладке 1
	var ice := _alt().ices()[0]
	assert_str(str(ice.name)).is_equal("t1")
	var ti := _tick_of(_alt())
	assert_object(ti.cell()).is_equal(Vector2i(3, 9))              # точка маршрута [1, 4] → юго-восточная клетка центра блока
	assert_object(ice.position).is_equal(NodeGrid.center(Vector2i(3, 9)))
	assert_array(ti._waits).is_equal([2, 1])
	assert_array(ti._looks).is_equal([Vector2i(1, 0), Vector2i(0, -1)])
	assert_float(float(ti._s["sight_cells"])).is_equal(4.0)         # meta.sight_cells раскладки главнее тира (BASE — 6)


func test_стражей_не_больше_чем_в_раскладке_и_legacy_идёт_по_старым_маршрутам() -> void:
	_build()
	assert_int(_leg().ices().size()).is_equal(2)
	var first: Vector3 = NodeLayout.ICE[0]["waypoints"][0]
	assert_object(_leg()._tick_ices.values()[0].cell()).is_equal(NodeGrid.cell_of(first))
	assert_float(float(_leg()._tick_ices.values()[0]._s["sight_cells"])).is_equal(6.0)   # по тиру, раскладка legacy дальности не задаёт


# ---------------------------------------------------------------- сообщение узла

func test_сообщение_о_входе_в_узел_несёт_имя_раскладки() -> void:
	_build()
	assert_str(str(_world.node_event("x_alt")["layout"])).is_equal(ALT)
	assert_str(str(_world.node_event("x_leg")["layout"])).is_equal("legacy")


func test_таблички_узла_с_раскладкой_берутся_из_неё_а_не_из_graph_json() -> void:
	_build()
	var signs: Array = _world.node_event("x_alt")["signs"]
	assert_int(signs.size()).is_equal(1)   # graph.json-таблички x_alt (координаты старой комнаты) не попадают в событие
	var c := NodeLayout.cell_center(3, 5)
	assert_array(signs[0]["p"]).is_equal([c.x, c.z])
	assert_str(signs[0]["text"]).is_equal("ВЫХОД СПРАВА")
	# узел без раскладки — таблички из graph.json как были
	var legacy_signs: Array = _world.node_event("x_leg")["signs"]
	assert_int(legacy_signs.size()).is_equal(1)
	assert_str(legacy_signs[0]["text"]).is_equal("СТАРАЯ")


# ---------------------------------------------------------------- стенд: стартовые клетки ботов

func test_боты_стенда_берут_разные_свободные_клетки_у_входа() -> void:
	var alt: LayoutData = LayoutData.cached(ALT)
	var cells := {}
	for slot in 6:
		var bot := BotClient.new()
		bot._grid = alt.grid()
		bot.position = alt.spawn
		bot.start_slot = slot
		var c := NodeGrid.cell_of(bot._start_cell_center())
		assert_bool(bot._grid.is_occupied(c)).is_false()
		assert_str(bot._grid.hop_verdict(alt.spawn, NodeGrid.center(c))).is_empty()
		assert_bool(c != NodeGrid.cell_of(alt.spawn)).is_true()
		cells[c] = true
		bot.free()
	assert_int(cells.size()).is_equal(6)   # шесть ботов — шесть разных клеток


func test_маяк_раскладки_стоит_на_узле_вращается_и_виден_в_state() -> void:
	const BEACON := "test_beacon"
	LayoutData._cache[BEACON] = LayoutData.parse({
		"name": BEACON,
		"cells": ["V.......", ".2......", "........", "........", "........", ".....1..", "S.......", "......EE"],
		"vaults": [{"cell": [0, 0], "pad": [0, 1], "ring": "outer"}],
		"ice": [{"id": "o1", "kind": "beacon", "cell": [4, 4], "start": "N"}],
	})
	assert_str((LayoutData._cache[BEACON] as LayoutData).error).is_empty()
	_build(1, "tick", BEACON)
	var beacons := _alt().beacons()
	assert_int(beacons.size()).is_equal(1)
	assert_int(_alt().ices().size()).is_equal(0)   # Стражей у раскладки нет, а Маяк — не IceNode
	assert_object(beacons[0].cell()).is_equal(LayoutData.block_center_cell(Vector2i(4, 4)))
	var view := _alt().beacon_view()
	assert_str(str(view[0]["id"])).is_equal("o1")
	assert_array(view[0]["d"]).is_equal([0, -1])    # смотрит на север
	assert_array(view[0]["nd"]).is_equal([1, -1])   # следующим тактом — на северо-восток
	assert_float(float(view[0]["r"])).is_equal(10.0)   # 5 клеток карты по 2 м
	LayoutData._cache.erase(BEACON)


func test_датчик_раскладки_стоит_на_узле_и_сработав_будит_стража_и_тревогу() -> void:
	const SENSOR := "test_sensor"
	LayoutData._cache[SENSOR] = LayoutData.parse({
		"name": SENSOR,
		"cells": ["V.......", ".2......", "........", "........", "........", ".....1..", "S.......", "......EE"],
		"vaults": [{"cell": [0, 0], "pad": [0, 1], "ring": "outer"}],
		"ice": [
			{"id": "g1", "kind": "sentry", "route": [{"cell": [1, 4], "wait": 2, "look": ["E"]}, {"cell": [6, 4], "wait": 1, "look": ["N"]}]},
			{"id": "d1", "kind": "sensor", "cell": [4, 2], "dir": "E", "len": 3},
		],
	})
	assert_str((LayoutData._cache[SENSOR] as LayoutData).error).is_empty()
	_build(1, "tick", SENSOR)
	var sensors := _alt().sensors()
	assert_int(sensors.size()).is_equal(1)
	assert_object(sensors[0].program()).is_equal(TickSensor.program_of("BASE"))   # узел BASE: 3/3
	var view := _alt().sensor_view()
	assert_str(str(view[0]["id"])).is_equal("d1")
	assert_int((view[0]["c"] as Array).size()).is_equal(3)
	assert_int(int(view[0]["on"])).override_failure_message("П6-4: вход в узел застаёт луч выключенным").is_equal(0)
	assert_int(int(view[0]["l"])).is_equal(3)   # BASE: три выключенных такта впереди
	for i in 3:
		sensors[0].tick()
	assert_int(int(_alt().sensor_view()[0]["on"])).is_equal(1)   # потом включается
	# Срабатывание: тревога узла +5 и ближайший Страж — в Проверку к клетке луча (сессии в узле нет — trace не считаем).
	var cell: Vector2i = sensors[0].cells()[1]
	var before := _alt().alarm
	_alt()._sensor_fire(sensors[0], "s1", cell)
	assert_float(_alt().alarm - before).is_equal_approx(5.0, 0.001)
	assert_int(_tick_of(_alt()).awareness_of("s1")).is_equal(TickIce.CHECK_CEILING)
	assert_int(int(_alt().sensor_view()[0]["al"])).is_equal(5)   # прицел клиента пишет «ЛУЧ → ТРЕВОГА +5» до прыжка
	_alt()._sensor_fire(sensors[0], "s1", cell)   # второй раз за то же включение — молчит
	assert_float(_alt().alarm - before).is_equal_approx(5.0, 0.001)
	# Игроку о срабатывании скажет поле sf ближайшего state (раз): вспышка луча, звук и метка в центре зрения.
	assert_array(_alt().take_sensor_fired("s1")).is_equal([{"id": "d1", "a": 5}])
	assert_array(_alt().take_sensor_fired("s1")).is_empty()
	assert_array(_alt().take_sensor_fired("s2")).is_empty()   # другому игроку не говорят
	LayoutData._cache.erase(SENSOR)
