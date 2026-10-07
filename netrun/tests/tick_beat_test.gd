extends GdUnitTestSuite
## Такт слышно и видно (TickBeat, TickAudio, TickRing): доля окна, смена такта один раз, момент и частота тиканья, звуковые параметры, кольцо на руке.
## Время подаёт тест, звук не играет (poll без _process).

const WIN := 5.0


func _tk(n: int, at: float = 10.0, inh: int = 0) -> Dictionary:
	return {"n": n, "at": at, "win": WIN, "inh": inh, "mv": 0}


func _it(c: Vector2i, nc: Variant = null, black: bool = false) -> Dictionary:
	return {"c": c, "d": Vector2i(1, 0), "st": 0, "nc": nc if nc != null else c, "nd": Vector2i(1, 0), "sc": 6.0, "black": black}


func test_доля_окна_от_at_до_at_плюс_win() -> void:
	assert_float(TickBeat.window_fraction(_tk(1, 10.0), 10.0)).is_equal(0.0)
	assert_float(TickBeat.window_fraction(_tk(1, 10.0), 12.5)).is_equal_approx(0.5, 0.0001)
	assert_float(TickBeat.window_fraction(_tk(1, 10.0), 15.0)).is_equal(1.0)
	assert_float(TickBeat.window_fraction(_tk(1, 10.0), 99.0)).is_equal(1.0)   # дольше окна — зажато
	assert_float(TickBeat.window_fraction(_tk(1, 10.0), 9.0)).is_equal(0.0)    # часы чуть отстали
	assert_float(TickBeat.window_fraction({}, 12.0)).is_equal(0.0)             # realtime: нет tk


func test_смена_такта_один_раз_без_повторов() -> void:
	var b := TickBeat.new()
	assert_bool(b.observe(_tk(4))).is_false()    # первый снимок такт не «начинает»
	assert_bool(b.observe(_tk(4))).is_false()    # 10 снимков в секунду с тем же n — не повтор
	assert_bool(b.observe(_tk(5))).is_true()
	assert_bool(b.observe(_tk(5))).is_false()
	assert_bool(b.observe(_tk(6))).is_true()
	assert_bool(b.observe({})).is_false()
	assert_bool(b.observe(_tk(6))).is_false()   # пустой tk прошлый такт не стёр


func test_сброс_забывает_такт() -> void:
	var b := TickBeat.new()
	b.observe(_tk(3))
	b.reset()
	assert_bool(b.observe(_tk(9))).is_false()   # снова первый снимок


func test_щелчки_по_частоте_с_переносом_фазы() -> void:
	var b := TickBeat.new()
	var total := 0
	for _i in 100:
		total += b.clicks(0.01, 4.0)   # 1 с при 4 Гц
	assert_int(total).is_equal(4)
	assert_int(b.clicks(0.5, 0.0)).is_equal(0)   # тишина
	assert_int(b.clicks(0.0, 4.0)).is_equal(0)


func test_ближайший_ICE_и_слышимость() -> void:
	var player := Vector2i(5, 5)
	var near := _it(Vector2i(7, 5), Vector2i(6, 5))
	var far := _it(Vector2i(30, 5), Vector2i(29, 5))
	assert_bool(TickBeat.ice_steps_soon([near], player)).is_true()
	assert_bool(TickBeat.ice_steps_soon([far], player)).is_false()   # дальше слышимости
	# Ближайший стоит, дальний идёт: тикает по ближайшему — тишина.
	assert_bool(TickBeat.ice_steps_soon([_it(Vector2i(6, 5)), _it(Vector2i(9, 5), Vector2i(8, 5))], player)).is_false()
	assert_bool(TickBeat.ice_steps_soon([_it(Vector2i(6, 5), Vector2i(7, 5), true)], player)).is_false()   # Black ICE шага не готовит
	assert_bool(TickBeat.ice_steps_soon([], player)).is_false()


func test_частота_тиканья_растёт_к_концу_окна() -> void:
	assert_float(TickBeat.click_rate(false, 0.9, false)).is_equal(0.0)           # ICE не шагнёт — тишина
	assert_float(TickBeat.click_rate(true, 0.1, false)).is_equal(0.0)            # начало окна — только пульс такта
	var early := TickBeat.click_rate(true, TickBeat.TICKING_FROM, false)
	var mid := TickBeat.click_rate(true, 0.7, false)
	var late := TickBeat.click_rate(true, 1.0, false)
	assert_float(early).is_equal_approx(TickBeat.CLICK_HZ_MIN, 0.0001)
	assert_float(late).is_equal_approx(TickBeat.CLICK_HZ_MAX, 0.0001)
	assert_float(mid).is_greater(early)
	assert_float(late).is_greater(mid)
	assert_float(TickBeat.click_rate(true, 0.1, true)).is_equal(TickBeat.CLICK_HZ_MAX)   # вдох: сразу часто


func test_звуковые_параметры_пульса_и_щелчка_гаснут() -> void:
	var p0 := AudioParams.tick_params("pulse", 0.0)
	assert_bool(p0["active"]).is_true()
	assert_float(p0["gain"]).is_equal_approx(1.0, 0.0001)
	var p1 := AudioParams.tick_params("pulse", 0.08)
	assert_float(p1["gain"]).is_less(p0["gain"])
	assert_bool(AudioParams.tick_params("pulse", 1.0)["active"]).is_false()
	var click := AudioParams.tick_params("click", 0.0)
	assert_float(click["volume_db"]).is_greater(p0["volume_db"])   # щелчок чуть громче пульса
	assert_float(click["hz"]).is_greater(p0["hz"])
	assert_bool(AudioParams.tick_params("click", 0.05)["active"]).is_false()
	assert_bool(AudioParams.tick_params("нет", 0.0)["active"]).is_false()


func _audio(tk: Dictionary, ice: Array, local_now: float) -> Array:
	var remote := RemoteTracks.new()
	var rig := Node3D.new()
	add_child(auto_free(rig))
	rig.global_position = NodeGrid.center(Vector2i(5, 5))
	var a := TickAudio.new()
	a.bind(remote, rig)
	auto_free(a)
	remote.on_state({"k": local_now, "ice": ice, "tk": tk}, local_now)
	return [a, remote]


func _ice_entry(c: Vector2i, nc: Vector2i) -> Dictionary:
	var p := NodeGrid.center(c)
	return {"id": "i1", "p": [p.x, 0.0, p.z], "f": [1.0, 0.0], "s": 0, "b": 0, "c": [c.x, c.y], "d": [1, 0], "st": 0, "nc": [nc.x, nc.y], "nd": [1, 0], "aw": 0, "sc": 6.0}


func test_TickAudio_пульс_один_раз_на_смену_такта() -> void:
	var r := _audio(_tk(1, 100.0), [], 100.0)
	var a: TickAudio = r[0]
	var remote: RemoteTracks = r[1]
	a.poll(0.1, 100.1)
	assert_int(a.pulses).is_equal(0)   # первый снимок
	remote.on_state({"k": 100.2, "ice": [], "tk": _tk(1, 100.0)}, 100.2)
	a.poll(0.1, 100.2)
	assert_int(a.pulses).is_equal(0)
	remote.on_state({"k": 105.0, "ice": [], "tk": _tk(2, 105.0)}, 105.0)
	a.poll(0.1, 105.0)
	assert_int(a.pulses).is_equal(1)
	a.poll(0.1, 105.1)
	assert_int(a.pulses).is_equal(1)
	assert_str(a.kind).is_equal("pulse")


func test_TickAudio_щелчки_только_когда_ближайший_ICE_шагнёт_и_окно_к_концу() -> void:
	var step := _ice_entry(Vector2i(7, 5), Vector2i(6, 5))
	var r := _audio(_tk(1, 100.0), [step], 100.0)
	var a: TickAudio = r[0]
	for i in 20:   # первые секунды окна (доля < TICKING_FROM) — тишина
		a.poll(0.05, 100.0 + 0.05 * i)
	assert_int(a.clicks_made).is_equal(0)
	var t := 103.9   # доля 0,78: тикает, частота выше минимальной
	var remote: RemoteTracks = r[1]
	remote.on_state({"k": t, "ice": [step], "tk": _tk(1, 100.0)}, t)
	for _i in 20:
		t += 0.05
		a.poll(0.05, t)
	assert_int(a.clicks_made).is_greater(2)
	# Стоящий ICE — щелчков нет.
	var r2 := _audio(_tk(1, 100.0), [_ice_entry(Vector2i(7, 5), Vector2i(7, 5))], 104.0)
	var a2: TickAudio = r2[0]
	for i in 20:
		a2.poll(0.05, 104.0 + 0.04 * i)
	assert_int(a2.clicks_made).is_equal(0)


func test_кольцо_заполняется_и_вспыхивает_на_такте() -> void:
	var remote := RemoteTracks.new()
	var ring := TickRing.new()
	add_child(auto_free(ring))
	ring.bind(remote)
	ring.poll(0.016, 100.0)
	assert_bool(ring.visible).is_false()   # realtime: нет tk — нет кольца
	remote.on_state({"k": 100.0, "ice": [], "tk": _tk(1, 100.0)}, 100.0)
	ring.poll(0.016, 100.0)
	assert_bool(ring.visible).is_true()
	assert_int(ring.filled_segments()).is_equal(0)
	remote.on_state({"k": 102.5, "ice": [], "tk": _tk(1, 100.0)}, 102.5)
	ring.poll(0.016, 102.5)
	assert_int(ring.filled_segments()).is_equal(TickRing.SEGMENTS / 2)
	assert_float(ring.brightness()).is_equal(1.0)
	remote.on_state({"k": 105.0, "ice": [], "tk": _tk(2, 105.0)}, 105.0)
	ring.poll(0.016, 105.0)
	assert_float(ring.brightness()).is_greater(1.5)   # вспышка на новом такте
	assert_int(ring.filled_segments()).is_equal(0)    # и окно началось заново
	ring.apply(0.5, TickRing.FLASH_SEC)
	assert_float(ring.brightness()).is_equal(1.0)
	ring.apply(0.9, 0.0)
	assert_object(ring.fill_color()).is_equal(TickRing.COLOR_WARN)   # последняя треть — жёлтое
