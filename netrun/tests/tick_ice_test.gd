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
	assert_array(aws).is_equal([2, 4, 6, 5])   # на 4-м ICE уже стоит в клетке цели — «своя клетка» не видна, −1
	assert_array(states).is_equal([1, 2, 3, 3])   # Взгляд, Проверка, Поиск
	assert_array(caps).is_equal([0, 0, 0, 1])   # ICE ещё идёт: 5 клеток; захват — на такте, целиком проведённом в Поиске
	assert_object(ice.cell()).is_equal(Vector2i(9, 8))


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
