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


# ---------- Black ICE (P4) ----------

func _meter_at(value: float) -> TraceMeter:
	var m := TraceMeter.new()
	m.tick(0.0)
	m.add_action("door_forced", 0.0, value / 10.0)
	return m


func test_black_ice_caught_is_black_caught_not_eject() -> void:
	var b := _brain({"black": true})
	_run(b, 0.0, 10.0, func(_t): return {"a": Vector3(0, 0, -2)} if _ejects.is_empty() else {})
	assert_array(_ejects).is_equal([["a", "black_caught"]])


func test_soft_ice_never_hunts() -> void:
	var b := _brain()
	_run(b, 0.0, 1.0, func(_t): return {"a": Vector3(0, 0, 10)}, {"a": _meter_at(60.0)})  # trace 60, но цель за спиной
	assert_int(b.state()).is_equal(S.PATROL)
	assert_bool(b.is_hunting("a")).is_false()


func test_black_ice_hunts_from_trace_level_without_sight() -> void:
	var b := _brain({"black": true})
	var meter := _meter_at(55.0)  # уровень TRACE
	_run(b, 0.0, 0.5, func(_t): return {"a": Vector3(0, 0, 10)}, {"a": meter})  # за спиной: зрение не видит
	assert_int(b.state()).is_equal(S.HUNT)
	assert_bool(b.is_hunting("a")).is_true()
	assert_float(b.position.z).is_greater(0.0)  # пошёл к цели, а не по патрулю (он стоит без маршрута)


func test_black_ice_does_not_hunt_below_trace_level() -> void:
	var b := _brain({"black": true})
	_run(b, 0.0, 1.0, func(_t): return {"a": Vector3(0, 0, 10)}, {"a": _meter_at(30.0)})
	assert_int(b.state()).is_equal(S.PATROL)


func test_hunt_catches_target_with_black_caught() -> void:
	var b := _brain({"black": true, "hunt_speed": 5.0})
	var meter := _meter_at(55.0)
	_run(b, 0.0, 6.0, func(_t): return {"a": Vector3(0, 0, 8)} if _ejects.is_empty() else {}, {"a": meter})
	assert_array(_ejects).is_equal([["a", "black_caught"]])
	assert_int(b.state()).is_equal(S.PATROL)


func test_hunt_is_slower_than_walking_player() -> void:
	var b := _brain({"black": true})  # hunt_speed 2.0 < 2.5 м/с игрока
	var meter := _meter_at(55.0)
	var t := 0.0
	var player := Vector3(0, 0, 10)
	while t < 8.0:
		t += 0.1
		player.z += 2.5 * 0.1  # игрок уходит прочь со скоростью ходьбы
		b.step(t, {"a": player}, {"a": meter})
	assert_array(_ejects).is_empty()
	assert_bool(b.is_hunting("a")).is_true()


func test_hunt_stops_when_target_is_ghost_or_trace_drops() -> void:
	var b := _brain({"black": true})
	var meter := _meter_at(55.0)
	var t := _run(b, 0.0, 0.5, func(_t): return {"a": Vector3(0, 0, 10)}, {"a": meter})
	assert_bool(b.is_hunting("a")).is_true()
	# GHOST: цели нет в targets — охота забыта.
	_run(b, t, 0.3, func(_t): return {}, {"a": meter})
	assert_bool(b.is_hunting("a")).is_false()
	assert_int(b.state()).is_equal(S.PATROL)


## Тревога после «!» (карточка 1б, шаг 2): catch_grace_sec секунд поиска ICE стоит и смотрит, не ловит; потом поиск как раньше.
## Прогон: игрок стоит в 2 м перед ICE (тот смотрит вдоль -Z); возвращает {search_t, eject_t, moved} — время входа в SEARCH, выброса (-1 — нет)
## и на сколько метров ICE сдвинулся за первую секунду поиска.
func _alarm_run(settings: Dictionary, leave_at_search: bool = false, limit: float = 30.0) -> Dictionary:
	var b := _brain(settings)
	var res := {"search_t": -1.0, "eject_t": -1.0, "moved": -1.0}
	var t := 0.0
	var start_pos := Vector3.ZERO
	var player := Vector3(0, 0, -2)
	while t < limit and res["eject_t"] < 0.0:
		t += 0.1
		var st0 := b.state()
		b.step(t, {"a": player} if _ejects.is_empty() else {}, {})
		if st0 != S.SEARCH and b.state() == S.SEARCH:
			res["search_t"] = t
			start_pos = b.position
			if leave_at_search:
				player = Vector3(0, 0, 5)  # ушёл за спину ICE
		if res["search_t"] >= 0.0 and absf(t - res["search_t"] - 1.0) < 0.05:
			res["moved"] = b.position.distance_to(start_pos)
		if not _ejects.is_empty():
			res["eject_t"] = t
	return res


func test_grace_is_off_by_default() -> void:
	var r := _alarm_run({"catch_range": 1.0})
	assert_float(r["eject_t"] - r["search_t"]).is_less(1.0)  # старое поведение: бежит и хватает сразу (2 м при 2,5 м/с)


func test_grace_holds_ice_in_place_and_delays_the_catch() -> void:
	var r := _alarm_run({"catch_range": 1.0, "catch_grace_sec": 2.0})
	assert_float(r["search_t"]).is_greater(0.0)
	assert_float(r["moved"]).is_less(0.01)  # первую секунду тревоги ICE стоит
	assert_float(r["eject_t"] - r["search_t"]).is_greater_equal(2.0 - 0.001)  # касание не раньше 2 с после «!»
	assert_array(_ejects).is_equal([["a", "caught"]])


func test_player_leaving_the_cone_during_grace_is_not_caught() -> void:
	var r := _alarm_run({"catch_range": 1.0, "catch_grace_sec": 2.0}, true, 30.0)
	assert_float(r["search_t"]).is_greater(0.0)
	assert_array(_ejects).is_empty()


func test_flatline_ejects_even_during_grace() -> void:
	var b := _brain({"catch_grace_sec": 2.0})
	var meter := TraceMeter.new()
	meter.tick(0.0)
	var seen := func(_t: float) -> Dictionary: return {"a": Vector3(0, 0, -3)} if _ejects.is_empty() else {}
	var t := _run(b, 0.0, 2.3, seen, {"a": meter})
	assert_int(b.state()).is_equal(S.SEARCH)  # «!» только что: идёт тревога
	meter.add_action("door_forced", t, 12.0)  # trace 100 посреди тревоги
	_run(b, t, 0.5, seen, {"a": meter})
	assert_array(_ejects).is_equal([["a", "flatline"]])
