extends GdUnitTestSuite
## RemoteTracks в тактовом режиме: намерения и tk из снимка, плавный шаг ICE между клетками за 0,4 с, realtime без новых полей.

func _ice(c: Array, nc: Array, st: int = 0, d: Array = [1, 0], b: int = 0) -> Dictionary:
	var p := NodeGrid.center(Vector2i(c[0], c[1]))
	return {"id": "ice_1", "p": [p.x, p.y, p.z], "f": [float(d[0]), float(d[1])], "s": 0, "b": b, "c": c, "d": d, "st": st, "nc": nc, "nd": d, "aw": 0, "sc": 6}


func _state(k: float, ice: Dictionary, tk: Variant = null) -> Dictionary:
	var s := {"k": k, "ice": [ice]}
	if tk != null:
		s["tk"] = tk
	return s


func test_намерения_и_tk_из_снимка() -> void:
	var tr := RemoteTracks.new()
	tr.on_state(_state(1.0, _ice([4, 8], [6, 8], 2), {"n": 3, "at": 0.5, "win": 5.0, "inh": 1, "mv": 0}), 1.0)
	assert_int(tr.intents().size()).is_equal(1)
	assert_that(tr.intents()[0]["nc"]).is_equal(Vector2i(6, 8))
	assert_int(tr.intents()[0]["st"]).is_equal(2)
	assert_int(int(tr.tick_info()["n"])).is_equal(3)
	assert_int(int(tr.tick_info()["inh"])).is_equal(1)


func test_realtime_без_намерений_и_tk() -> void:
	var tr := RemoteTracks.new()
	tr.on_state({"k": 1.0, "ice": [{"id": "ice_1", "p": [1.0, 0.0, -6.0], "f": [0.0, -1.0], "s": 0, "b": 0}]}, 1.0)
	assert_array(tr.intents()).is_empty()
	assert_bool(tr.tick_info().is_empty()).is_true()
	assert_int(tr.window_left(1.0)).is_equal(0)
	assert_vector(tr.ice_pose("ice_1", 5.0)["p"]).is_equal(Vector3(1.0, 0.0, -6.0))   # по буферу, как раньше


func test_первое_появление_без_шага() -> void:
	var tr := RemoteTracks.new()
	tr.on_state(_state(1.0, _ice([4, 8], [6, 8])), 10.0)
	assert_vector(tr.ice_pose("ice_1", 10.0)["p"]).is_equal(NodeGrid.center(Vector2i(4, 8)))
	assert_vector(tr.ice_pose("ice_1", 10.3)["p"]).is_equal(NodeGrid.center(Vector2i(4, 8)))


func test_шаг_идёт_плавно_ровно_0_4_секунды() -> void:
	var tr := RemoteTracks.new()
	tr.on_state(_state(1.0, _ice([4, 8], [6, 8])), 10.0)
	var a := NodeGrid.center(Vector2i(4, 8))
	var b := NodeGrid.center(Vector2i(6, 8))   # на 2 м дальше
	tr.on_state(_state(1.1, _ice([6, 8], [8, 8])), 10.1)
	assert_vector(tr.ice_pose("ice_1", 10.1)["p"]).is_equal(a)   # шаг только начался
	assert_float((tr.ice_pose("ice_1", 10.3)["p"] as Vector3).x).is_equal_approx(a.x + 1.0, 0.001)   # середина (0,2 с из 0,4)
	assert_vector(tr.ice_pose("ice_1", 10.5)["p"]).is_equal(b)
	assert_vector(tr.ice_pose("ice_1", 12.0)["p"]).is_equal(b)   # дальше стоит


func test_повторный_снимок_той_же_клетки_шаг_не_сбрасывает() -> void:
	var tr := RemoteTracks.new()
	tr.on_state(_state(1.0, _ice([4, 8], [6, 8])), 10.0)
	tr.on_state(_state(1.1, _ice([6, 8], [8, 8])), 10.1)
	tr.on_state(_state(1.2, _ice([6, 8], [8, 8])), 10.2)   # 10 снимков в секунду, клетка та же
	tr.on_state(_state(1.3, _ice([6, 8], [8, 8])), 10.3)
	assert_vector(tr.ice_pose("ice_1", 10.5)["p"]).is_equal(NodeGrid.center(Vector2i(6, 8)))


func test_поворот_плавный_по_кратчайшей_дуге() -> void:
	var tr := RemoteTracks.new()
	tr.on_state(_state(1.0, _ice([4, 8], [4, 8], 0, [1, 0])), 10.0)
	var y0: float = tr.ice_pose("ice_1", 10.0)["yaw"]
	tr.on_state(_state(1.1, _ice([4, 8], [4, 8], 0, [0, 1])), 10.1)   # восток -> юг (+z)
	var y1: float = tr.ice_pose("ice_1", 10.5)["yaw"]
	var mid: float = tr.ice_pose("ice_1", 10.3)["yaw"]
	assert_float(absf(angle_difference(y0, y1))).is_equal_approx(PI / 2.0, 0.001)
	assert_float(absf(angle_difference(y0, mid))).is_equal_approx(PI / 4.0, 0.001)


func test_новый_шаг_посреди_старого_идёт_от_текущего_места() -> void:
	var tr := RemoteTracks.new()
	tr.on_state(_state(1.0, _ice([4, 8], [6, 8])), 10.0)
	tr.on_state(_state(1.1, _ice([6, 8], [8, 8])), 10.1)
	var mid: Vector3 = tr.ice_pose("ice_1", 10.3)["p"]
	tr.on_state(_state(1.3, _ice([8, 8], [10, 8])), 10.3)
	assert_vector(tr.ice_pose("ice_1", 10.3)["p"]).is_equal(mid)   # без рывка
	assert_vector(tr.ice_pose("ice_1", 10.7)["p"]).is_equal(NodeGrid.center(Vector2i(8, 8)))


func test_Black_ICE_идёт_по_буферу_а_не_шагами() -> void:
	var tr := RemoteTracks.new()
	tr.on_state(_state(1.0, _ice([4, 8], [4, 8], 3, [1, 0], 1)), 10.0)
	tr.on_state(_state(1.1, _ice([6, 8], [6, 8], 3, [1, 0], 1)), 10.1)
	# Показывается момент в прошлом (ICE_DELAY): сервер 1,15 − 0,15 = 1,0 — ещё первая точка; шагов 0,4 с у Black ICE нет.
	var pose: Dictionary = tr.ice_pose("ice_1", 10.15)
	assert_vector(pose["p"]).is_equal(NodeGrid.center(Vector2i(4, 8)))


func test_окно_до_такта_округляется_вверх() -> void:
	var tr := RemoteTracks.new()
	# Часы сервера: k = 100 пришёл в местное 100 (смещение 0). Такт был в 99, окно 5 с: до такта 4 с ровно.
	tr.on_state(_state(100.0, _ice([4, 8], [6, 8]), {"n": 1, "at": 99.0, "win": 5.0, "inh": 0, "mv": 0}), 100.0)
	assert_int(tr.window_left(100.0)).is_equal(4)
	assert_int(tr.window_left(100.2)).is_equal(4)   # 3,8 -> 4
	assert_int(tr.window_left(101.5)).is_equal(3)   # 2,5 -> 3
	assert_int(tr.window_left(104.5)).is_equal(0)   # окно вышло
	assert_int(tr.window_left(120.0)).is_equal(0)


func test_ICE_исчез_забыть_шаг() -> void:
	var tr := RemoteTracks.new()
	tr.on_state(_state(1.0, _ice([4, 8], [6, 8])), 10.0)
	tr.forget_ice("ice_1")
	assert_bool(tr.ice_pose("ice_1", 10.0).is_empty()).is_true()
