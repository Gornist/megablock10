extends GdUnitTestSuite
## Телеграф такта на полу (TickFloor) и глаз ICE: число клеток света, фокус ярче периферии, свет после шага, стрелки (шаг, поворот, предзахват),
## вдох (пульс ×1,6 за 0,5 с один раз), сцена: в тактовом режиме есть пол и глаз, в realtime — ничего нового.

const ICE := Vector2i(4, 8)
const EAST := Vector2i(1, 0)


func _it(c: Vector2i, d: Vector2i, st: int = 0, nc: Variant = null, nd: Variant = null) -> Dictionary:
	return {"c": c, "d": d, "st": st, "nc": nc if nc != null else c, "nd": nd if nd != null else d, "sc": 6.0, "black": false}


func _floor(grid: NodeGrid = null) -> TickFloor:
	var f := TickFloor.new(grid if grid != null else NodeGrid.new())
	add_child(auto_free(f))
	return f


func _cells(g: NodeGrid, c: Vector2i, d: Vector2i) -> Dictionary:
	return TickVision.visible_cells(g, c, d, 6.0, TickForecast.HALF_DEG, TickForecast.FOCUS_DEG)


func test_стоящий_ICE_свет_по_числу_видимых_клеток_без_будущего() -> void:
	var g := NodeGrid.new()
	var f := _floor(g)
	f.apply([_it(ICE, EAST)], {}, Vector2i(0, 0))
	assert_int(f.cell_count()).is_equal(_cells(g, ICE, EAST).size())
	assert_int(f.cell_count()).is_greater(10)
	assert_int(f.arrow_count()).is_equal(0)   # стоит — без стрелки


func test_идущий_ICE_рисует_ещё_и_свет_после_шага_и_стрелку() -> void:
	var g := NodeGrid.new()
	var f := _floor(g)
	var nc := Vector2i(6, 8)
	f.apply([_it(ICE, EAST, 0, nc)], {}, Vector2i(0, 0))
	assert_int(f.cell_count()).is_equal(_cells(g, ICE, EAST).size() + _cells(g, nc, EAST).size())
	assert_int(f.arrow_count()).is_equal(1)
	var a := f.arrow_spec(0)
	assert_vector(a["from"]).is_equal(NodeGrid.center(ICE))
	assert_vector(a["to"]).is_equal(NodeGrid.center(nc))
	assert_bool(a["precapture"]).is_false()


func test_свет_рисуется_контуром_четыре_полосы_на_клетку() -> void:
	var f := _floor()
	assert_int(f.edge_count()).is_equal(0)
	f.apply([_it(ICE, EAST, 3)], {}, Vector2i(0, 0))
	assert_int(f.cell_count()).is_greater(0)
	assert_int(f.edge_count()).is_equal(f.cell_count() * 4)


func test_фокус_ярче_периферии_и_цвет_по_состоянию() -> void:
	var g := NodeGrid.new()
	var f := _floor(g)
	f.apply([_it(ICE, EAST, 3)], {}, Vector2i(0, 0))   # Поиск: красный
	var focus_a := -1.0
	var periph_a := -1.0
	for i in f.cell_count():
		var col := f.cell_color(i)
		assert_float(col.r).is_equal_approx(AssetMaterials.layer("ice_hunt").r, 0.01)
		assert_float(col.g).is_equal_approx(AssetMaterials.layer("ice_hunt").g, 0.01)
		var cell := NodeGrid.cell_of(f.cell_position(i))
		if int(_cells(g, ICE, EAST)[cell]) == TickVision.FOCUS:
			focus_a = col.a
		else:
			periph_a = col.a
	assert_float(focus_a).is_equal_approx(TickFloor.FOCUS_ALPHA, 0.001)
	assert_float(periph_a).is_equal_approx(TickFloor.PERIPHERY_ALPHA, 0.001)
	assert_float(focus_a).is_greater(periph_a)


func test_свет_после_шага_тусклее_и_другого_оттенка() -> void:
	var f := _floor()
	f.apply([_it(ICE, EAST, 1, Vector2i(6, 8))], {}, Vector2i(0, 0))
	var now_n := _cells(NodeGrid.new(), ICE, EAST).size()
	var now := f.cell_color(0)
	var future := f.cell_color(now_n)
	assert_float(future.a).is_less(now.a + 0.0001)
	assert_bool(future.is_equal_approx(Color(now.r, now.g, now.b, future.a))).is_false()   # оттенок другой
	assert_float(f.cell_position(now_n).y).is_less(f.cell_position(0).y)


func test_колонна_убирает_клетки_света() -> void:
	var open := _floor()
	open.apply([_it(ICE, EAST)], {}, Vector2i(0, 0))
	var g := NodeGrid.new()
	g.occ[ICE + Vector2i(3, 0)] = true
	var blocked := _floor(g)
	blocked.apply([_it(ICE, EAST)], {}, Vector2i(0, 0))
	assert_int(blocked.cell_count()).is_less(open.cell_count())


func test_поворот_на_месте_короткая_стрелка_в_новую_сторону() -> void:
	var f := _floor()
	f.apply([_it(ICE, EAST, 0, ICE, Vector2i(0, 1))], {}, Vector2i(0, 0))
	assert_int(f.arrow_count()).is_equal(1)
	var a := f.arrow_spec(0)
	assert_vector(a["from"]).is_equal(NodeGrid.center(ICE))
	assert_float((a["to"] as Vector3).z).is_greater((a["from"] as Vector3).z)   # нужное направление (+z)


func test_предзахват_стрелка_красная_и_в_клетку_игрока() -> void:
	var f := _floor()
	var player := Vector2i(7, 8)
	f.apply([_it(ICE, EAST, TickForecast.ST_SEARCH, Vector2i(6, 8))], {}, player)
	assert_int(f.arrow_count()).is_equal(1)
	var a := f.arrow_spec(0)
	assert_bool(a["precapture"]).is_true()
	assert_vector(a["to"]).is_equal(NodeGrid.center(player))
	assert_vector(a["from"]).is_equal(NodeGrid.center(Vector2i(6, 8)))
	assert_object(a["color"]).is_equal(AssetMaterials.layer("ice_precapture"))
	# Игрок далеко (не ближе 2 м от следующего шага) — обычная стрелка шага, не красная.
	f.apply([_it(ICE, EAST, TickForecast.ST_SEARCH, Vector2i(6, 8))], {}, Vector2i(14, 8))
	assert_bool(f.arrow_spec(0)["precapture"]).is_false()


func test_Black_ICE_света_не_даёт_и_realtime_без_записей() -> void:
	var f := _floor()
	var black := _it(ICE, EAST, 3)
	black["black"] = true
	f.apply([black], {}, Vector2i(0, 0))
	assert_int(f.cell_count()).is_equal(0)
	f.apply([], {}, Vector2i(0, 0))
	assert_int(f.cell_count()).is_equal(0)
	assert_int(f.arrow_count()).is_equal(0)


func test_вдох_пульс_один_раз_за_полсекунды_до_1_6() -> void:
	var f := _floor()
	f.apply([_it(ICE, EAST)], {"inh": 0}, Vector2i(0, 0))
	f.step(0.1)
	assert_float(f.brightness()).is_equal(1.0)
	f.apply([_it(ICE, EAST)], {"inh": 1}, Vector2i(0, 0))   # вдох начался
	assert_bool(f.pulsing()).is_true()
	f.step(0.25)   # середина
	assert_float(f.brightness()).is_equal_approx(TickFloor.PULSE_GAIN, 0.01)
	f.apply([_it(ICE, EAST)], {"inh": 1}, Vector2i(0, 0))   # вдох держится — не перезапускаем
	f.step(0.26)
	assert_bool(f.pulsing()).is_false()
	assert_float(f.brightness()).is_equal(1.0)
	f.apply([_it(ICE, EAST)], {"inh": 1}, Vector2i(0, 0))
	assert_bool(f.pulsing()).is_false()   # inh всё ещё 1: второго пульса нет
	f.apply([_it(ICE, EAST)], {"inh": 0}, Vector2i(0, 0))
	f.apply([_it(ICE, EAST)], {"inh": 1}, Vector2i(0, 0))
	assert_bool(f.pulsing()).is_true()   # новый вдох — новый пульс


# ---------------------------------------------------------------- сцена и глаз ICE

func _scene() -> Node3D:
	var scene: Node3D = auto_free(preload("res://client/rig_test_scene.gd").new())
	add_child(scene)
	return scene


func _ice_msg(st: int, b: int = 0, tick: bool = true) -> Dictionary:
	var p := NodeGrid.center(ICE)
	var e := {"id": "ice_1", "p": [p.x, 0.0, p.z], "f": [1.0, 0.0], "s": 0, "b": b}
	if tick:
		e.merge({"c": [4, 8], "d": [1, 0], "st": st, "nc": [6, 8], "nd": [1, 0], "aw": 0, "sc": 6})
	var s := {"k": 1.0, "trace": 0.0, "level": 0, "cd": [], "ice": [e]}
	if tick:
		s["tk"] = {"n": 1, "at": 0.5, "win": 5.0, "inh": 0, "mv": 0}
	return s


func test_сцена_в_тактовом_режиме_создаёт_пол_и_красит_глаз() -> void:
	var scene := _scene()
	scene.apply_state(_ice_msg(3))
	assert_object(scene.tick_floor).is_not_null()
	assert_int(scene.tick_floor.cell_count()).is_greater(0)
	var ice: IceView = scene.ice_node("ice_1")
	assert_int(ice.eye_state()).is_equal(3)
	assert_float(ice.eye_color().r).is_equal_approx(AssetMaterials.layer("ice_hunt").r, 0.01)
	assert_float(ice.eye_color().g).is_equal_approx(AssetMaterials.layer("ice_hunt").g, 0.01)
	scene.apply_state(_ice_msg(1))
	assert_int(ice.eye_state()).is_equal(1)
	assert_float(ice.eye_color().g).is_equal_approx(AssetMaterials.layer("ice_suspect").g, 0.01)


func test_демо_кадр_колонны_свет_красная_стрелка_и_жёлтая_рамка() -> void:
	var scene := _scene()
	scene.show_tick_demo()
	var f: TickFloor = scene.tick_floor
	assert_object(f).is_not_null()
	assert_int(f.arrow_count()).is_equal(2)
	var red := 0
	for i in f.arrow_count():
		if f.arrow_spec(i)["precapture"]:
			red += 1
	assert_int(red).is_equal(1)   # Поиск рядом с игроком: красная стрелка
	assert_int(f.cell_count()).is_greater(30)
	assert_object(scene.rig.aim_visual.frame_color()).is_equal(AssetMaterials.layer("aim_warn"))
	assert_bool(scene.rig.grid.is_occupied(Vector2i(4, 8))).is_true()   # колонна узла на месте: проход между двумя колоннами


func test_сцена_в_realtime_без_пола_и_глаза() -> void:
	var scene := _scene()
	scene.apply_state(_ice_msg(0, 0, false))
	assert_object(scene.tick_floor).is_null()
	assert_int((scene.ice_node("ice_1") as IceView).eye_state()).is_equal(-1)


# --- След маршрута: отпечатки шагов (state.rt, PR B2) ---

func _rt(cells: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in cells:
		out.append(c)
	return out


func test_след_маршрута_два_тусклых_отпечатка_прозрачность_по_номеру_шага() -> void:
	var g := NodeGrid.new()
	var f := _floor(g)
	var it := _it(ICE, EAST, 0, Vector2i(6, 8))
	it["rt"] = _rt([Vector2i(6, 8), Vector2i(8, 8), Vector2i(10, 8)])
	f.apply([it], {}, Vector2i(0, 0))
	assert_int(f.footprint_count()).is_equal(2)
	assert_int(f.arrow_count()).is_equal(1)   # 1-й шаг по-прежнему яркая стрелка
	var a2 := f.footprint_spec(0)
	var a3 := f.footprint_spec(1)
	assert_int(a2["step"]).is_equal(2)
	assert_int(a3["step"]).is_equal(3)
	assert_object(a2["cell"]).is_equal(Vector2i(8, 8))
	assert_object(a3["cell"]).is_equal(Vector2i(10, 8))
	assert_float(a2["alpha"]).is_greater(a3["alpha"])   # затухают
	assert_float(a3["alpha"]).is_less(TickFloor.FUTURE_ALPHA * TickFloor.FOCUS_ALPHA)
	# Отпечатки лежат в тех же квадратах пола: последние две отметки, цвет — слои следа палитры (2-й шаг trail_step, 3-й trail_dim).
	var total := f.cell_count()
	assert_object(NodeGrid.cell_of(f.cell_position(total - 2))).is_equal(Vector2i(8, 8))
	assert_float(f.cell_color(total - 1).a).is_equal_approx(a3["alpha"], 0.0001)
	assert_float(f.cell_color(total - 1).r).is_equal_approx(AssetMaterials.layer("trail_dim").r, 0.01)
	assert_float(f.cell_color(total - 1).b).is_equal_approx(AssetMaterials.layer("trail_dim").b, 0.01)
	assert_float(f.cell_color(total - 2).b).is_equal_approx(AssetMaterials.layer("trail_step").b, 0.01)


func test_след_цвет_отпечатков_из_слоёв_палитры_а_не_по_состоянию_ICE() -> void:
	var f := _floor()
	var it := _it(ICE, EAST, 2, Vector2i(6, 8))   # Проверка: свет зрения цвета стадии, след — слои trail_*
	it["rt"] = _rt([Vector2i(6, 8), Vector2i(8, 8), Vector2i(10, 8)])
	f.apply([it], {}, Vector2i(0, 0))
	var col := f.cell_color(f.cell_count() - 1)
	assert_float(col.g).is_equal_approx(AssetMaterials.layer("trail_dim").g, 0.01)
	assert_float(col.b).is_equal_approx(AssetMaterials.layer("trail_dim").b, 0.01)


func test_след_стоянка_отпечатка_не_даёт() -> void:
	var f := _floor()
	var it := _it(ICE, EAST, 0, ICE)
	it["rt"] = _rt([ICE, ICE, Vector2i(6, 8)])   # стоит на 1–2 шаге, идёт на 3-м
	f.apply([it], {}, Vector2i(0, 0))
	assert_int(f.footprint_count()).is_equal(1)
	assert_int(f.footprint_spec(0)["step"]).is_equal(3)


func test_след_без_rt_как_раньше_и_красная_стрелка_приоритетнее() -> void:
	var g := NodeGrid.new()
	var f := _floor(g)
	f.apply([_it(ICE, EAST, 0, Vector2i(6, 8))], {}, Vector2i(0, 0))
	assert_int(f.footprint_count()).is_equal(0)
	# Поиск рядом с игроком: красная стрелка предзахвата, следа нет вовсе.
	var it := _it(ICE, EAST, 3, Vector2i(6, 8))
	it["rt"] = _rt([Vector2i(6, 8), Vector2i(8, 8), Vector2i(10, 8)])
	var player := Vector2i(7, 8)
	f.apply([it], {}, player)
	assert_bool(f.arrow_spec(0)["precapture"]).is_true()
	assert_int(f.footprint_count()).is_equal(0)


# --- «?» с последствием (PR B3): отпечаток на полу и «…» над ICE ---

func test_отпечаток_fp_маркер_на_клетке_и_яркая_клетка() -> void:
	var g := NodeGrid.new()
	var f := _floor(g)
	var it := _it(ICE, EAST, 1)   # Взгляд: жёлтый
	f.apply([it], {}, Vector2i(0, 0))
	var plain := f.cell_count()
	assert_int(f.marker_count()).is_equal(0)
	it["fp"] = Vector2i(8, 8)
	f.apply([it], {}, Vector2i(0, 1))   # другой снимок игрока — пересборка
	assert_int(f.marker_count()).is_equal(1)
	assert_object(f.marker_spec(0)["cell"]).is_equal(Vector2i(8, 8))
	assert_float(f.marker_spec(0)["color"].g).is_equal_approx(AssetMaterials.layer("ice_suspect").g, 0.01)
	assert_int(f.cell_count()).is_equal(plain + 1)   # ещё одна яркая клетка — отпечаток
	var last := f.cell_count() - 1
	assert_object(NodeGrid.cell_of(f.cell_position(last))).is_equal(Vector2i(8, 8))
	assert_float(f.cell_color(last).a).is_greater(TickFloor.FOCUS_ALPHA)   # ярче света зрения
	# но заливка не выше слоя палитры (иначе бурая клетка), а контур отпечатка не слабее обычного
	var la := TickFloor.layer_alphas(f.cell_color(last).a)
	assert_float(la.x).is_equal_approx(AssetMaterials.layer("cell_vision_fill").a, 0.0001)
	assert_float(la.y).is_greater_equal(AssetMaterials.layer("cell_vision_edge").a - 0.0001)
	var periph := TickFloor.layer_alphas(TickFloor.PERIPHERY_ALPHA)   # периферия слабее фокуса
	assert_float(periph.x).is_less(la.x)
	var label := f.get_node("Mark0") as Label3D
	assert_bool(label.visible).is_true()
	assert_str(label.text).is_equal("?")
	# Отпечаток спал — маркер скрыт.
	it.erase("fp")
	f.apply([it], {}, Vector2i(0, 2))
	assert_int(f.marker_count()).is_equal(0)
	assert_bool((f.get_node("Mark0") as Label3D).visible).is_false()


func test_значок_потерял_виден_только_на_такте_lost() -> void:
	var scene := _scene()
	var msg := _ice_msg(0)
	scene.apply_state(msg)
	var ice: IceView = scene.ice_node("ice_1")
	assert_bool(ice.lost_visible()).is_false()
	(msg["ice"][0] as Dictionary)["lost"] = 1
	scene.apply_state(msg)
	assert_bool(ice.lost_visible()).is_true()
	assert_str((ice.get_node("LostMark") as Label3D).text).is_equal("…")
	(msg["ice"][0] as Dictionary).erase("lost")   # следующий такт: возврат на маршрут
	scene.apply_state(msg)
	assert_bool(ice.lost_visible()).is_false()


func test_сцена_передаёт_fp_полу() -> void:
	var scene := _scene()
	var msg := _ice_msg(1)
	(msg["ice"][0] as Dictionary)["fp"] = [8, 8]
	scene.apply_state(msg)
	assert_int(scene.tick_floor.marker_count()).is_equal(1)
