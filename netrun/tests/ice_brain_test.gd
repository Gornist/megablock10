extends GdUnitTestSuite

const S := IceBrain.State

var _ejects: Array = []


func _brain(settings: Dictionary = {}) -> IceBrain:
	# ICE в нуле, смотрит вдоль -Z (Vector3.FORWARD).
	var b := IceBrain.new(settings)
	b.ejected.connect(func(s: String, r: String) -> void: _ejects.append([s, r]))
	return b


## Прогон по сценарию: seconds секунд с шагом 0.1; pos_at(t) -> Dictionary целей.
func _run(b: IceBrain, from_t: float, seconds: float, targets: Callable, meters: Dictionary = {}) -> float:
	var t := from_t
	var end := from_t + seconds
	while t < end - 0.0001:
		t += 0.1
		b.step(t, targets.call(t), meters)
	return t


func before_test() -> void:
	_ejects = []


func test_visibility_cone_and_range() -> void:
	var f := Vector3.FORWARD
	assert_bool(IceBrain.can_see(Vector3.ZERO, f, Vector3(0, 0, -5), 12.0, 50.0)).is_true()
	assert_bool(IceBrain.can_see(Vector3.ZERO, f, Vector3(0, 0, 5), 12.0, 50.0)).is_false()  # сзади
	assert_bool(IceBrain.can_see(Vector3.ZERO, f, Vector3(5, 0, -5), 12.0, 50.0)).is_true()  # 45°
	assert_bool(IceBrain.can_see(Vector3.ZERO, f, Vector3(5, 0, -2), 12.0, 50.0)).is_false()  # ~68°
	assert_bool(IceBrain.can_see(Vector3.ZERO, f, Vector3(0, 0, -13), 12.0, 50.0)).is_false()  # далеко
	assert_bool(IceBrain.can_see(Vector3.ZERO, f, Vector3(0, 9, -5), 12.0, 50.0)).is_true()  # высота не важна


func test_patrol_ignores_unseen_target() -> void:
	var b := _brain()
	_run(b, 0.0, 3.0, func(_t): return {"a": Vector3(0, 0, 5)})
	assert_int(b.state()).is_equal(S.PATROL)


func test_seen_target_raises_suspicion() -> void:
	var b := _brain()
	_run(b, 0.0, 0.5, func(_t): return {"a": Vector3(0, 0, -10)})
	assert_int(b.state()).is_equal(S.SUSPICIOUS)
	assert_str(b.target()).is_equal("a")
	assert_float(b.awareness()).is_between(0.0, 1.0)


func test_suspicion_decays_when_target_gone() -> void:
	var b := _brain()
	var t := _run(b, 0.0, 0.5, func(_t): return {"a": Vector3(0, 0, -10)})
	assert_int(b.state()).is_equal(S.SUSPICIOUS)
	# Цель ушла за спину; осведомлённость ~0.25 спадает по 0.25/с — за пару секунд патруль.
	_run(b, t, 3.0, func(_t): return {"a": Vector3(0, 0, 10)})
	assert_int(b.state()).is_equal(S.PATROL)
	assert_float(b.awareness()).is_equal(0.0)
	assert_array(_ejects).is_empty()


func test_continuous_sighting_goes_to_search() -> void:
	var b := _brain()
	_run(b, 0.0, 2.5, func(_t): return {"a": Vector3(0, 0, -10)})
	assert_int(b.state()).is_equal(S.SEARCH)


func test_search_ends_in_ejection_when_caught() -> void:
	var b := _brain()
	# Бот стоит на месте на 10 м: ICE замечает, идёт и хватает.
	# После выброса владелец узла убирает аватар из целей.
	_run(b, 0.0, 10.0, func(_t): return {} if not _ejects.is_empty() else {"a": Vector3(0, 0, -10)})
	assert_array(_ejects).is_equal([["a", "caught"]])
	assert_int(b.state()).is_equal(S.PATROL)


func test_search_gives_up_when_target_hides() -> void:
	var b := _brain({"sight_range": 12.0})
	var t := _run(b, 0.0, 2.5, func(_t): return {"a": Vector3(0, 0, -10)})
	assert_int(b.state()).is_equal(S.SEARCH)
	# Бот спрятался (вне радиуса) — ICE дойдёт до последней точки, постоит и вернётся.
	_run(b, t, 20.0, func(_t): return {"a": Vector3(100, 0, 100)})
	assert_int(b.state()).is_equal(S.PATROL)
	assert_array(_ejects).is_empty()


func test_moving_bot_scenario_is_caught() -> void:
	var b := _brain()
	# Бот идёт поперёк по дуге вдали, затем замирает на виду.
	var path := func(t: float) -> Dictionary:
		var x := clampf(-6.0 + t, -6.0, 0.0)
		return {"a": Vector3(x, 0, -8)}
	_run(b, 0.0, 15.0, func(t): return {} if not _ejects.is_empty() else path.call(t))
	assert_array(_ejects).is_equal([["a", "caught"]])


func test_seen_raises_trace_via_settings_action() -> void:
	var b := _brain({"trace_action": "seen_by_ice"})
	var meter := TraceMeter.new({"weights": {"seen_by_ice": 10.0}})
	meter.tick(0.0)
	_run(b, 0.0, 1.0, func(_t): return {"a": Vector3(0, 0, -10)}, {"a": meter})
	# 10 шагов по 0.1 с × вес 10 ≈ 10 (первый шаг без dt).
	assert_float(meter.value()).is_between(8.0, 11.0)
	var meter2 := TraceMeter.new()
	meter2.tick(0.0)
	_run(_brain(), 0.0, 1.0, func(_t): return {"a": Vector3(0, 0, 10)}, {"a": meter2})
	assert_float(meter2.value()).is_equal(0.0)


func test_flatline_trace_ejects() -> void:
	var b := _brain()
	var meter := TraceMeter.new({"weights": {"seen_by_ice": 200.0}})
	meter.tick(0.0)
	_run(b, 0.0, 1.0, func(_t): return {} if not _ejects.is_empty() else {"a": Vector3(0, 0, -10)}, {"a": meter})
	assert_array(_ejects).is_equal([["a", "flatline"]])


func test_forget_when_target_leaves_node() -> void:
	var b := _brain()
	var t := _run(b, 0.0, 0.5, func(_t): return {"a": Vector3(0, 0, -10)})
	assert_int(b.state()).is_equal(S.SUSPICIOUS)
	_run(b, t, 0.2, func(_t): return {})
	assert_int(b.state()).is_equal(S.PATROL)


func test_patrol_follows_waypoints() -> void:
	var wps: Array[Vector3] = [Vector3(5, 0, 0), Vector3(5, 0, 5)]
	var b := IceBrain.new({}, Vector3.ZERO, wps)
	_run(b, 0.0, 6.0, func(_t): return {})
	assert_float(b.position.x).is_greater(3.0)


func test_node_sleeps_without_netrunners() -> void:
	var n: IceNode = auto_free(IceNode.new())
	var wps: Array[Vector3] = [Vector3(50, 0, 0)]
	n.setup({}, wps)
	add_child(n)
	n._physics_process(1.0)
	assert_float(n.position.x).is_equal(0.0)
	n.netrunner_count = 1
	n._physics_process(1.0)
	assert_float(n.position.x).is_greater(0.5)
