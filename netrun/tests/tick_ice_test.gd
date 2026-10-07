extends GdUnitTestSuite
## Тактовый мозг ICE (TickIce): осведомлённость по тактам, состояния, патруль, «наткнулся», возврат, намерение, события.
## Детерминированно, без сцены. Поле 16×16 клеток, пустое, если не сказано иное; дальность 6, конус ±50°, фокус ±25° (настройки по умолчанию).
## Ряд 8 — «восточный» маршрут от (1;8); цель "s" неподвижна, если тест не двигает её сам.

const EAST := Vector2i(1, 0)


func _route(cells: Array) -> Array[Vector2i]:
	var r: Array[Vector2i] = []
	for c: Vector2i in cells:
		r.append(c)
	return r


func _east_ice(g: NodeGrid) -> TickIce:
	return TickIce.new({}, _route([Vector2i(1, 8), Vector2i(14, 8)]), g)


## ICE, который стоит на месте (маршрут из одной точки), смотрит на восток.
func _still_ice(g: NodeGrid, at: Vector2i) -> TickIce:
	return TickIce.new({}, _route([at]), g)


func _at(c: Vector2i) -> Dictionary:
	return {"s": NodeGrid.center(c)}


func _kinds(ev: Array, kind: String) -> int:
	var n := 0
	for e: Dictionary in ev:
		if e["kind"] == kind:
			n += 1
	return n


## Клетка, которую ICE (из клетки `from` с направлением `dir`) видит как `cls` (1 периферия, 2 фокус) на расстоянии [dmin, dmax] клеток.
func _cell_seen_as(g: NodeGrid, from: Vector2i, dir: Vector2i, cls: int, dmin: float, dmax: float) -> Vector2i:
	for dx in range(-6, 7):
		for dy in range(-6, 7):
			var c := Vector2i(from.x + dx, from.y + dy)
			var d := Vector2(c - from).length()
			if d < dmin or d > dmax or not NodeGrid.in_bounds(c):
				continue
			if TickVision.classify(g, from, dir, c, 6.0, 50.0, 25.0) == cls:
				return c
	return Vector2i(-99, -99)


func test_а_цель_в_фокусе_два_четыре_шесть_и_захват_на_четвёртом_такте() -> void:
	var g := NodeGrid.new()
	var ice := _east_ice(g)
	var tg := _at(Vector2i(9, 8))
	var aws: Array = []
	var states: Array = []
	var caps: Array = []
	for _i in 4:
		var ev := ice.tick(tg)
		aws.append(ice.awareness_of("s"))
		states.append(ice.state())
		caps.append(_kinds(ev, "capture"))
	assert_array(aws).is_equal([2, 4, 6, 6])   # на 4-м ICE встаёт перед клеткой цели (в неё не входит): сосед в фокусе
	assert_array(states).is_equal([1, 2, 3, 3])   # Взгляд, Проверка, Поиск
	assert_array(caps).is_equal([0, 0, 0, 1])   # ICE ещё идёт; захват — на такте, целиком проведённом в Поиске
	assert_object(ice.cell()).is_equal(Vector2i(8, 8))


func test_б_цель_на_периферии_поиск_не_раньше_пятого_такта() -> void:
	var g := NodeGrid.new()
	var ice := _east_ice(g)
	var aws: Array = []
	var states: Array = []
	for _i in 5:
		# Цель всякий раз на периферии относительно того, где ICE окажется после шага: берём из намерения.
		var it := ice.intent()
		var c := _cell_seen_as(g, it["next_cell"], it["next_dir"], 1, 4.0, 5.5)
		assert_bool(NodeGrid.in_bounds(c)).is_true()
		ice.tick(_at(c))
		aws.append(ice.awareness_of("s"))
		states.append(ice.state())
	assert_array(aws).is_equal([1, 2, 3, 4, 5])
	assert_array(states).is_equal([1, 1, 2, 2, 3])


func test_в_цель_ушла_за_колонну_из_взгляда_через_два_такта_патруль() -> void:
	var g := NodeGrid.new()
	for c in [Vector2i(6, 9), Vector2i(7, 9), Vector2i(6, 10), Vector2i(7, 10)]:
		g.occ[c] = true
	var ice := _east_ice(g)
	ice.tick(_at(Vector2i(9, 8)))   # ICE у (3;8): цель прямо впереди, 6 клеток
	assert_int(ice.awareness_of("s")).is_equal(2)
	assert_int(ice.state()).is_equal(1)
	ice.tick(_at(Vector2i(8, 10)))   # линия к (8;10) идёт через колонну
	assert_int(ice.awareness_of("s")).is_equal(1)
	assert_int(ice.state()).is_equal(1)
	ice.tick(_at(Vector2i(8, 10)))
	assert_int(ice.awareness_of("s")).is_equal(0)
	assert_int(ice.state()).is_equal(0)   # без захвата и без поиска
	var ev := ice.tick(_at(Vector2i(8, 10)))
	assert_int(_kinds(ev, "capture")).is_equal(0)


func test_г_патруль_две_клетки_за_такт_развороты_и_перенос_остатка() -> void:
	var g := NodeGrid.new()
	var ice := TickIce.new({}, _route([Vector2i(2, 4), Vector2i(5, 4), Vector2i(5, 8)]), g)
	assert_object(ice.cell()).is_equal(Vector2i(2, 4))
	assert_object(ice.dir()).is_equal(EAST)   # смотрит на вторую точку
	ice.tick({})
	assert_object(ice.cell()).is_equal(Vector2i(4, 4))
	ice.tick({})   # шаг до угла (5;4) и остаток 1 — уже на юг
	assert_object(ice.cell()).is_equal(Vector2i(5, 5))
	assert_object(ice.dir()).is_equal(Vector2i(0, 1))
	ice.tick({})
	assert_object(ice.cell()).is_equal(Vector2i(5, 7))
	ice.tick({})   # (5;8) — конец маршрута, остаток 1 — уже к первой точке (2;4), по диагонали
	assert_object(ice.cell()).is_equal(Vector2i(4, 7))
	assert_object(ice.dir()).is_equal(Vector2i(-1, -1))
	assert_int(ice.state()).is_equal(0)


func test_д_наткнулся_цель_на_пути_патруля() -> void:
	var g := NodeGrid.new()
	var ice := TickIce.new({}, _route([Vector2i(2, 8), Vector2i(14, 8)]), g)
	var tg := _at(Vector2i(4, 8))
	var ev := ice.tick(tg)
	assert_object(ice.cell()).is_equal(Vector2i(3, 8))   # остановился перед ней
	assert_int(ice.awareness_of("s")).is_equal(6)
	assert_int(ice.state()).is_equal(3)
	assert_int(_kinds(ev, "search_started")).is_equal(1)
	assert_int(_kinds(ev, "capture")).is_equal(0)   # такт начат в Патруле
	ev = ice.tick(tg)   # следующий такт — Поиск
	assert_int(_kinds(ev, "capture")).is_equal(1)
	assert_str(ev[ev.size() - 1]["reason"]).is_equal("caught")


func test_д_скрытая_цель_не_препятствие_патрулю() -> void:
	var g := NodeGrid.new()
	var ice := TickIce.new({}, _route([Vector2i(2, 8), Vector2i(14, 8)]), g)
	ice.tick(_at(Vector2i(4, 8)), {"s": true})
	assert_object(ice.cell()).is_equal(Vector2i(4, 8))
	assert_int(ice.awareness_of("s")).is_equal(0)


func test_е_намерение_совпадает_с_позицией_после_такта() -> void:
	var g := NodeGrid.new()
	var ice := _east_ice(g)
	var tg := _at(Vector2i(9, 8))
	var it := ice.intent()
	assert_object(it["cell"]).is_equal(Vector2i(1, 8))
	assert_int(it["state"]).is_equal(0)
	assert_int(it["aware"]).is_equal(0)
	for i in 10:   # Патруль, Взгляд, Проверка, Поиск, прочёсывание
		it = ice.intent()
		assert_object(it["cell"]).is_equal(ice.cell())
		assert_int(it["state"]).is_equal(ice.state())
		assert_int(it["aware"]).is_equal(ice.awareness_of("s"))
		ice.tick(tg)
		assert_object(it["next_cell"]).is_equal(ice.cell())
		assert_object(it["next_dir"]).is_equal(ice.dir())
	# Сам вызов intent() ничего не меняет.
	var before := ice.cell()
	ice.intent()
	ice.intent()
	assert_object(ice.cell()).is_equal(before)


func test_е_намерение_учитывает_препятствие_на_патруле() -> void:
	var g := NodeGrid.new()
	var ice := TickIce.new({}, _route([Vector2i(2, 8), Vector2i(14, 8)]), g)
	var tg := _at(Vector2i(4, 8))
	ice.intent()
	ice.tick(tg)   # теперь ICE знает, где стоит цель
	var it := ice.intent()   # Поиск: пойдёт на цель
	ice.tick(tg)
	assert_object(it["next_cell"]).is_equal(ice.cell())


func test_ж_search_started_ровно_один_раз_за_поиск() -> void:
	var g := NodeGrid.new()
	var ice := _east_ice(g)
	var tg := _at(Vector2i(9, 8))
	var n := 0
	for _i in 8:
		n += _kinds(ice.tick(tg), "search_started")
	assert_int(n).is_equal(1)


func test_ж_мерцание_цели_в_поиске_не_запускает_поиск_заново() -> void:
	var g := NodeGrid.new()
	var ice := _still_ice(g, Vector2i(3, 8))
	var n := 0
	for _i in 3:
		n += _kinds(ice.tick(_at(Vector2i(9, 8))), "search_started")   # 2, 4, 6 — Поиск
	assert_int(n).is_equal(1)
	assert_int(ice.state()).is_equal(3)
	for _i in 2:
		n += _kinds(ice.tick(_at(Vector2i(9, 8)), {"s": true}), "search_started")   # пропала: 5, 4 — Проверка
	assert_int(ice.state()).is_equal(2)
	for _i in 4:
		var it := ice.intent()
		var c := _cell_seen_as(g, it["next_cell"], it["next_dir"], 2, 3.0, 5.0)
		n += _kinds(ice.tick(_at(c)), "search_started")   # снова в фокусе: Поиск без нового события
	assert_int(ice.state()).is_equal(3)
	assert_int(n).is_equal(1)


func test_з_возврат_на_маршрут_после_сброса_счётчика() -> void:
	var g := NodeGrid.new()
	var ice := TickIce.new({}, _route([Vector2i(2, 2), Vector2i(2, 13)]), g)
	var tg := _at(Vector2i(3, 9))   # в стороне от маршрута (x = 2)
	for _i in 6:
		ice.tick(tg)
	assert_int(ice.state()).is_greater_equal(2)
	# Цель пропала: счётчик падает до 0, ICE доигрывает осмотр и возвращается на маршрут.
	for _i in 30:
		ice.tick({"s": NodeGrid.center(Vector2i(3, 9))}, {"s": true})
	assert_int(ice.awareness_of("s")).is_equal(0)
	assert_int(ice.state()).is_equal(0)
	var on_route := ice.cell().x == 2
	assert_bool(on_route).is_true()
	# И снова патрулирует: идёт по маршруту (x = 2).
	var c0 := ice.cell()
	ice.tick({})
	assert_bool(ice.cell() != c0).is_true()
	assert_int(ice.cell().x).is_equal(2)


func test_и_скрытая_цель_не_набирает_счётчик() -> void:
	var g := NodeGrid.new()
	var ice := _east_ice(g)
	for _i in 5:
		ice.tick(_at(Vector2i(9, 8)), {"s": true})
		assert_int(ice.awareness_of("s")).is_equal(0)
		assert_int(ice.state()).is_equal(0)


func test_к_взгляд_до_захвата_не_раньше_трёх_тактов_даже_вблизи() -> void:
	var g := NodeGrid.new()
	var ice := _still_ice(g, Vector2i(3, 8))
	var tg := _at(Vector2i(8, 8))
	var caps: Array = []
	var states: Array = []
	for _i in 4:
		var ev := ice.tick(tg)
		caps.append(_kinds(ev, "capture"))
		states.append(ice.state())
	assert_array(states).is_equal([1, 2, 3, 3])   # «?» (Взгляд) → Проверка → Поиск
	assert_array(caps).is_equal([0, 0, 0, 1])


func test_забыть_нетраннера_сбрасывает_его_счётчик() -> void:
	var g := NodeGrid.new()
	var ice := _still_ice(g, Vector2i(3, 8))
	ice.tick(_at(Vector2i(8, 8)))
	assert_int(ice.awareness_of("s")).is_equal(2)
	ice.forget("s")
	assert_int(ice.awareness_of("s")).is_equal(0)
	ice.tick({})
	assert_int(ice.state()).is_equal(0)


func test_маршрут_из_точек_слоя_узла_в_клетки() -> void:
	var r := TickIce.route_from_points([Vector3(0, 0, -4), Vector3(6, 0, -4)])
	assert_object(r[0]).is_equal(NodeGrid.cell_of(Vector3(0, 0, -4)))
	assert_object(r[1]).is_equal(Vector2i(14, 10))


func test_проверка_и_поиск_встают_перед_нетраннером_а_не_входят_в_его_клетку() -> void:
	var g := NodeGrid.new()
	var ice := _still_ice(g, Vector2i(3, 8))
	var tg := _at(Vector2i(5, 8))
	for _i in 8:
		ice.tick(tg)
		assert_bool(ice.cell() != Vector2i(5, 8)).is_true()
	assert_object(ice.cell()).is_equal(Vector2i(4, 8))   # Проверка подошла вплотную и встала; в Поиске прочёсывание не заходит в клетку цели
	assert_int(ice.awareness_of("s")).is_equal(6)   # сосед по стороне — в фокусе, цель не потеряна
	assert_int(ice.state()).is_equal(3)


func test_нетраннер_в_клетке_ice_остаётся_в_фокусе_и_захватывается() -> void:
	var g := NodeGrid.new()
	var ice := _still_ice(g, Vector2i(3, 8))
	var tg := _at(Vector2i(3, 8))   # вошёл в клетку ICE сам
	var aws: Array = []
	var caps := 0
	for _i in 4:
		caps += _kinds(ice.tick(tg), "capture")
		aws.append(ice.awareness_of("s"))
	aws.resize(3)   # на 4-м такте прочёсывание уводит ICE в соседнюю клетку, цель за спиной — счётчик там уже не показатель
	assert_array(aws).is_equal([2, 4, 6])   # раньше «своя клетка» не видна: счётчик падал, ICE терял цель
	assert_int(caps).is_equal(1)


# --- Ожидание и поворот на точках маршрута (wait / look) ---

func _wait_route() -> Array:
	return [
		Vector2i(2, 4),
		{"cell": Vector2i(6, 4), "wait": 2, "look": "S"},
		{"cell": Vector2i(6, 8), "wait": 1, "look": [Vector2i(0, -1)]},
	]


func test_патруль_стоит_wait_тактов_глядя_в_look_и_не_переносит_остаток_шагов() -> void:
	var ice := TickIce.new({}, _wait_route(), NodeGrid.new())
	var seen: Array = []
	for _i in 8:
		ice.tick({})
		seen.append([ice.cell(), ice.dir()])
	assert_array(seen).is_equal([
		[Vector2i(4, 4), EAST],
		[Vector2i(6, 4), Vector2i(0, 1)],   # пришёл и сразу повернулся на юг
		[Vector2i(6, 4), Vector2i(0, 1)],   # ждёт 2 такта
		[Vector2i(6, 4), Vector2i(0, 1)],
		[Vector2i(6, 6), Vector2i(0, 1)],
		[Vector2i(6, 8), Vector2i(0, -1)],   # пришёл, смотрит на север
		[Vector2i(6, 8), Vector2i(0, -1)],   # ждёт 1 такт
		[Vector2i(4, 6), Vector2i(-1, -1)],   # к первой точке (2;4) — по диагонали, 2 клетки за такт
	])


func test_точка_без_wait_и_старый_вызов_ведут_себя_как_раньше() -> void:
	var g := NodeGrid.new()
	var plain := TickIce.new({}, [Vector2i(2, 4), Vector2i(5, 4), Vector2i(5, 8)], g)
	var with_zero := TickIce.new({}, [Vector2i(2, 4), {"cell": Vector2i(5, 4), "wait": 0, "look": "N"}, Vector2i(5, 8)], g)
	for _i in 6:
		plain.tick({})
		with_zero.tick({})
		assert_object(with_zero.cell()).is_equal(plain.cell())
		assert_object(with_zero.dir()).is_equal(plain.dir())


func test_ожидание_без_look_не_меняет_направление() -> void:
	var ice := TickIce.new({}, [Vector2i(2, 4), {"cell": Vector2i(6, 4), "wait": 1}], NodeGrid.new())
	ice.tick({})
	ice.tick({})   # пришёл на (6;4)
	assert_object(ice.cell()).is_equal(Vector2i(6, 4))
	assert_object(ice.dir()).is_equal(EAST)
	ice.tick({})   # стоит
	assert_object(ice.cell()).is_equal(Vector2i(6, 4))


func test_намерение_на_ожидании_не_двигает_ice_и_видит_стоянку() -> void:
	var ice := TickIce.new({}, _wait_route(), NodeGrid.new())
	ice.tick({})
	ice.tick({})   # пришёл на (6;4), впереди 2 такта ожидания
	var it := ice.intent()
	assert_object(it["next_cell"]).is_equal(Vector2i(6, 4))
	assert_object(it["next_dir"]).is_equal(Vector2i(0, 1))
	assert_object(ice.cell()).is_equal(Vector2i(6, 4))   # intent() состояние не меняет
	ice.tick({})
	ice.tick({})
	assert_object(ice.intent()["next_cell"]).is_equal(Vector2i(6, 6))   # ожидание кончилось — следующий шаг уже ход


func test_маршрут_из_точек_слоя_с_wait_и_look_и_имена_направлений() -> void:
	var r := TickIce.route_from_points([Vector3(0, 0, -4), {"point": Vector3(6, 0, -4), "wait": 2, "look": "S"}])
	assert_object(r[0]).is_equal(NodeGrid.cell_of(Vector3(0, 0, -4)))
	assert_object(r[1]["cell"]).is_equal(Vector2i(14, 10))
	assert_int(r[1]["wait"]).is_equal(2)
	assert_object(TickIce.look_dir("N")).is_equal(Vector2i(0, -1))
	assert_object(TickIce.look_dir(["w"])).is_equal(Vector2i(-1, 0))
	assert_object(TickIce.look_dir("SE")).is_equal(Vector2i(1, 1))
	assert_object(TickIce.look_dir("?")).is_equal(Vector2i.ZERO)
	assert_object(TickIce.look_dir(null)).is_equal(Vector2i.ZERO)


func test_после_погони_во_время_ожидания_патруль_возвращается_на_маршрут() -> void:
	var g := NodeGrid.new()
	var ice := TickIce.new({}, [Vector2i(2, 8), {"cell": Vector2i(6, 8), "wait": 5, "look": "S"}], g)
	ice.tick({})
	ice.tick({})   # на точке (6;8): впереди 5 тактов ожидания
	assert_object(ice.cell()).is_equal(Vector2i(6, 8))
	# цель в фокусе на юге — ICE идёт к ней (Проверка), потом цель пропадает; оставшееся ожидание не «доигрывается» на месте
	var tg := _at(Vector2i(6, 12))
	for _i in 4:
		ice.tick(tg)
	assert_bool(ice.cell() != Vector2i(6, 8)).is_true()
	for _i in 30:
		ice.tick({})
	assert_int(ice.state()).is_equal(0)
	assert_int(ice.cell().y).is_equal(8)   # вернулся на строку маршрута и снова идёт по нему (на точке (6;8) заново отстоял своё)


# --- Грейс прибытия (W3): неуязвимый не берётся и в его клетку не заходят ---

func test_грейс_патруль_не_заходит_в_клетку_неуязвимого_и_счётчик_не_взлетает() -> void:
	var g := NodeGrid.new()
	var ice := TickIce.new({}, _route([Vector2i(2, 8), Vector2i(14, 8)]), g)
	var tg := _at(Vector2i(4, 8))
	var ev := ice.tick(tg, {}, {"s": true})
	assert_object(ice.cell()).is_equal(Vector2i(3, 8))   # встал перед ним, как при «наткнулся»
	assert_int(ice.awareness_of("s")).is_less_equal(TickIce.AWARENESS_IMMUNE_MAX)   # самое большее «?»
	assert_int(ice.state()).is_less_equal(TickIce.Mode.GAZE)
	assert_int(_kinds(ev, "search_started")).is_equal(0)
	for _i in 4:
		ev = ice.tick(tg, {}, {"s": true})
		assert_int(_kinds(ev, "capture")).is_equal(0)   # захвата нет, сколько бы ни стоял на виду
		assert_object(ice.cell()).is_not_equal(Vector2i(4, 8))
	assert_int(ice.awareness_of("s")).is_less_equal(TickIce.AWARENESS_IMMUNE_MAX)


func test_грейс_скрытый_неуязвимый_тоже_обходится() -> void:
	# Скрытый в клетке на пути патруля раньше пропускался насквозь (ICE вставал на него): неуязвимого ICE обходит и скрытого.
	var g := NodeGrid.new()
	var ice := TickIce.new({}, _route([Vector2i(2, 8), Vector2i(14, 8)]), g)
	ice.tick(_at(Vector2i(4, 8)), {"s": true}, {"s": true})
	assert_object(ice.cell()).is_equal(Vector2i(3, 8))
	assert_int(ice.awareness_of("s")).is_equal(0)


func test_после_грейса_прежнее_поведение_наткнулся_и_захват() -> void:
	var g := NodeGrid.new()
	var ice := TickIce.new({}, _route([Vector2i(2, 8), Vector2i(14, 8)]), g)
	var tg := _at(Vector2i(4, 8))
	ice.tick(tg, {}, {"s": true})   # грейс: обошёл
	assert_int(ice.awareness_of("s")).is_less_equal(2)
	var caps := 0
	for _i in 4:
		caps += _kinds(ice.tick(tg), "capture")   # грейса нет — как обычно
	assert_int(ice.state()).is_equal(TickIce.Mode.SEARCH)
	assert_int(caps).is_greater(0)


func test_грейс_намерение_строится_с_обходом_клетки() -> void:
	var g := NodeGrid.new()
	var ice := TickIce.new({}, _route([Vector2i(2, 8), Vector2i(14, 8)]), g)
	ice.expect_immune({"s": NodeGrid.center(Vector2i(4, 8))})
	var it := ice.intent()
	assert_object(it["next_cell"]).is_equal(Vector2i(3, 8))   # встанет перед ним
	assert_int(it["state"]).is_equal(TickIce.Mode.PATROL)
	ice.expect_immune({})
	assert_object(ice.intent()["next_cell"]).is_equal(Vector2i(4, 8))   # без грейса шагнул бы в его клетку


# --- След маршрута на 3 шага (state.rt, PR B2) ---

func test_след_маршрута_три_клетки_первая_равна_следующему_шагу() -> void:
	var ice := _east_ice(NodeGrid.new())
	var it := ice.intent()
	var ahead: Array = it["ahead"]
	assert_int(ahead.size()).is_equal(TickIce.AHEAD_STEPS)
	assert_object(ahead[0]).is_equal(it["next_cell"])
	assert_array(ahead).is_equal([Vector2i(3, 8), Vector2i(5, 8), Vector2i(7, 8)])   # патруль идёт по 2 клетки
	assert_object(ice.cell()).is_equal(Vector2i(1, 8))   # intent() ICE не двигает


func test_след_маршрута_с_ожиданием_повторяет_клетку_пока_ICE_стоит() -> void:
	var ice := TickIce.new({}, _wait_route(), NodeGrid.new())
	ice.tick({})
	ice.tick({})   # пришёл на (6;4), впереди 2 такта ожидания
	assert_array(ice.intent()["ahead"]).is_equal([Vector2i(6, 4), Vector2i(6, 4), Vector2i(6, 6)])
	ice.tick({})
	assert_array(ice.intent()["ahead"]).is_equal([Vector2i(6, 4), Vector2i(6, 6), Vector2i(6, 8)])


func test_след_маршрута_совпадает_с_тем_что_ICE_делает_на_самом_деле() -> void:
	var g := NodeGrid.new()
	for route: Array in [[Vector2i(1, 8), Vector2i(14, 8)], _wait_route()]:
		var ice := TickIce.new({}, route, g)
		for _t in 14:
			var ahead: Array = ice.intent()["ahead"]
			assert_array(ahead).is_equal(_clone_run(route, g, _t, TickIce.AHEAD_STEPS))
			ice.tick({})


## Свежий ICE по тому же маршруту: `skip` тактов вхолостую, затем клетки следующих `n` тактов.
func _clone_run(route: Array, g: NodeGrid, skip: int, n: int) -> Array:
	var ice := TickIce.new({}, route, g)
	for _i in skip:
		ice.tick({})
	var out: Array = []
	for _i in n:
		ice.tick({})
		out.append(ice.cell())
	return out


# --- «?» с последствием (PR B3): взгляд на клетку, отпечаток, «потерял» ---

func test_заметил_взгляд_поворачивается_на_клетку_в_тот_же_такт() -> void:
	var g := NodeGrid.new()
	var ice := _still_ice(g, Vector2i(4, 8))   # смотрит на восток
	var seen := Vector2i(7, 6)   # на периферии конуса: 34° от оси
	assert_int(TickVision.classify(g, ice.cell(), ice.dir(), seen, 6.0, 50.0, 25.0)).is_equal(TickVision.PERIPHERY)
	assert_object(ice.dir()).is_equal(EAST)
	ice.tick(_at(seen))
	assert_int(ice.state()).is_equal(TickIce.Mode.GAZE)
	assert_object(ice.dir()).is_equal(NodeGrid.dir8(ice.cell(), seen))   # повернулся на клетку, где заметил
	assert_object(ice.dir()).is_not_equal(EAST)
	assert_object(ice.intent()["next_dir"]).is_equal(ice.dir())   # и стрелка / свет на следующий такт это знают


func test_проверка_идёт_к_отпечатку_а_не_к_клетке_куда_цель_перешла() -> void:
	var g := NodeGrid.new()
	var ice := _still_ice(g, Vector2i(4, 8))
	var a := Vector2i(9, 8)
	var b := Vector2i(9, 10)
	ice.tick(_at(a))   # такт 1: заметил на A (фокус, счётчик 2)
	assert_object(ice.footprint()).is_equal(a)
	ice.tick(_at(b))   # такт 2: цель на B, счётчик 4 — Проверка; отпечаток остался A
	assert_int(ice.state()).is_equal(TickIce.Mode.CHECK)
	assert_object(ice.footprint()).is_equal(a)
	assert_object(ice.intent()["fp"]).is_equal(a)
	ice.tick(_at(b))   # такт 3: шаг Проверки — по прямой к A (ряд 8), а не к B (ряд 10)
	assert_int(ice.cell().y).is_equal(8)
	assert_int(ice.cell().x).is_greater(4)


func test_не_нашёл_потерял_один_такт_и_возврат_на_маршрут() -> void:
	var g := NodeGrid.new()
	var ice := _east_ice(g)   # патруль (1;8) → (14;8), 2 клетки за такт
	var tg := _at(Vector2i(5, 8))
	var lost: Array[bool] = []
	var cells: Array[Vector2i] = []
	ice.tick(tg)   # такт 1: шаг до (3;8), цель в двух клетках, фокус: счётчик 2 — Взгляд
	lost.append(ice.lost())
	cells.append(ice.cell())
	assert_int(ice.state()).is_equal(TickIce.Mode.GAZE)
	assert_object(ice.footprint()).is_equal(Vector2i(5, 8))
	for _i in 3:   # цель ушла из виду (скрыта): счётчик 2 → 1 → 0 → 0
		ice.tick(tg, {"s": true})
		lost.append(ice.lost())
		cells.append(ice.cell())
	assert_array(lost).is_equal([false, false, true, false])   # «потерял» ровно на такте, когда счётчик дошёл до нуля
	assert_int(ice.state()).is_equal(TickIce.Mode.PATROL)
	assert_object(ice.footprint()).is_null()
	assert_object(cells[2]).is_equal(Vector2i(3, 8))   # на потерянном такте ещё стоит
	assert_object(cells[3]).is_equal(Vector2i(5, 8))   # дальше идёт по маршруту
	ice.tick(tg, {"s": true})
	assert_bool(ice.lost()).is_false()


func test_намерение_несёт_отпечаток_и_потерял() -> void:
	var g := NodeGrid.new()
	var ice := _still_ice(g, Vector2i(4, 8))
	assert_object(ice.intent()["fp"]).is_null()
	assert_bool(ice.intent()["lost"]).is_false()
	ice.tick(_at(Vector2i(8, 8)))
	assert_object(ice.intent()["fp"]).is_equal(Vector2i(8, 8))
	for _i in 2:
		ice.tick(_at(Vector2i(8, 8)), {"s": true})
	assert_bool(ice.intent()["lost"]).is_true()
	assert_object(ice.intent()["fp"]).is_null()


func test_поиск_берёт_отпечатком_последнюю_клетку_цели_и_осмотр_у_старого_не_засчитывается() -> void:
	var g := NodeGrid.new()
	var ice := _still_ice(g, Vector2i(4, 8))
	var a := Vector2i(9, 8)
	var b := Vector2i(9, 10)
	ice.tick(_at(a))
	ice.tick(_at(a))   # Проверка, ICE ещё стоит
	ice.tick(_at(a))   # дошёл до A? нет — идёт; цель держим на виду
	for _i in 4:
		ice.tick(_at(b))   # цель перешла на B и остаётся на виду — счётчик растёт до Поиска
	assert_int(ice.state()).is_equal(TickIce.Mode.SEARCH)
	for _i in 3:
		ice.tick(_at(b))
	assert_int(Vector2(ice.cell() - b).length() as int).is_less_equal(3)   # Поиск идёт за B, а не прочёсывает вокруг старого отпечатка
