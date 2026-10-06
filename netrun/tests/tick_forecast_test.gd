extends GdUnitTestSuite
## Прогноз такта (TickForecast): цвет рамки по намерениям ICE — зелёный / жёлтый / красный, предзахват Поиска, разбор сообщения state.
## Чистые функции, без сцен. ICE смотрит на восток из (4; 8), дальность 6, конус ±50°, фокус ±25° (как TickIce по умолчанию).

const ICE := Vector2i(4, 8)
const EAST := Vector2i(1, 0)


func _it(c: Vector2i, d: Vector2i, st: int = 0, nc: Variant = null, nd: Variant = null) -> Dictionary:
	return {"c": c, "d": d, "st": st, "nc": nc if nc != null else c, "nd": nd if nd != null else d, "sc": 6.0}


func test_пустой_список_зелёный() -> void:
	assert_int(TickForecast.threat(NodeGrid.new(), [], Vector2i(5, 8))).is_equal(TickForecast.GREEN)


func test_красный_в_фокусе_после_следующего_шага() -> void:
	var g := NodeGrid.new()
	var it := _it(ICE, EAST)
	assert_int(TickForecast.threat(g, [it], ICE + Vector2i(4, 0))).is_equal(TickForecast.RED)   # прямо впереди
	assert_int(TickForecast.threat(g, [it], ICE + Vector2i(5, 1))).is_equal(TickForecast.RED)   # 11°


func test_жёлтый_на_периферии_следующего_шага() -> void:
	var g := NodeGrid.new()
	# Сейчас ICE в (4; 8), шагнёт в (6; 8): клетка (10; 11) — 36° от направления, периферия.
	var it := _it(ICE, EAST, 0, Vector2i(6, 8))
	assert_int(TickForecast.threat(g, [it], Vector2i(10, 11))).is_equal(TickForecast.YELLOW)
	# Если бы ICE стоял на месте, клетка была бы за дальностью (6,7 клетки): прогноз берётся по nc, не по c.
	assert_int(TickForecast.threat(g, [_it(ICE, EAST)], Vector2i(10, 11))).is_equal(TickForecast.GREEN)


func test_прогноз_по_следующей_позиции_а_не_по_текущей() -> void:
	var g := NodeGrid.new()
	# Клетка (11; 8) за пределом дальности от (4; 8), но в 5 клетках от следующей позиции (6; 8).
	var it := _it(ICE, EAST, 0, Vector2i(6, 8))
	assert_int(TickForecast.threat(g, [it], Vector2i(11, 8))).is_equal(TickForecast.RED)
	# Повернётся на север: клетка впереди по востоку уже вне конуса.
	var turn := _it(ICE, EAST, 0, ICE, Vector2i(0, -1))
	assert_int(TickForecast.threat(g, [turn], ICE + Vector2i(4, 0))).is_equal(TickForecast.GREEN)
	assert_int(TickForecast.threat(g, [turn], ICE + Vector2i(0, -4))).is_equal(TickForecast.RED)


func test_зелёный_за_колонной() -> void:
	var g := NodeGrid.new()
	g.occ[ICE + Vector2i(3, 0)] = true
	var it := _it(ICE, EAST)
	assert_int(TickForecast.threat(g, [it], ICE + Vector2i(5, 0))).is_equal(TickForecast.GREEN)
	assert_int(TickForecast.threat(g, [it], ICE + Vector2i(2, 0))).is_equal(TickForecast.RED)   # до колонны видно


func test_зелёный_позади_и_вне_дальности() -> void:
	var g := NodeGrid.new()
	var it := _it(ICE, EAST)
	assert_int(TickForecast.threat(g, [it], ICE + Vector2i(-3, 0))).is_equal(TickForecast.GREEN)
	assert_int(TickForecast.threat(g, [it], ICE + Vector2i(7, 0))).is_equal(TickForecast.GREEN)


func test_предзахват_поиск_рядом_красный_даже_вне_конуса() -> void:
	var g := NodeGrid.new()
	# Поиск; следующий шаг в (6; 8), смотрит на восток. Клетка (6; 9) на 1 м сбоку (вне конуса), (5; 8) на 1 м позади.
	var it := _it(ICE, EAST, TickForecast.ST_SEARCH, Vector2i(6, 8), EAST)
	assert_int(TickForecast.threat(g, [it], Vector2i(6, 9))).is_equal(TickForecast.RED)
	assert_int(TickForecast.threat(g, [it], Vector2i(5, 8))).is_equal(TickForecast.RED)   # позади направления, но в 1 м
	assert_bool(TickForecast.is_precapture(it, Vector2i(5, 8))).is_true()
	# Та же клетка при Проверке: позади — зелёный.
	var check := _it(ICE, EAST, 2, Vector2i(6, 8), EAST)
	assert_int(TickForecast.threat(g, [check], Vector2i(5, 8))).is_equal(TickForecast.GREEN)
	assert_bool(TickForecast.is_precapture(check, Vector2i(5, 8))).is_false()


func test_предзахват_не_дальше_двух_метров() -> void:
	var g := NodeGrid.new()
	var it := _it(ICE, EAST, TickForecast.ST_SEARCH, Vector2i(6, 8), EAST)
	assert_bool(TickForecast.is_precapture(it, Vector2i(4, 8))).is_true()    # ровно 2 м
	assert_bool(TickForecast.is_precapture(it, Vector2i(3, 8))).is_false()   # 3 м
	assert_int(TickForecast.threat(g, [it], Vector2i(3, 8))).is_equal(TickForecast.GREEN)


func test_клетка_следующего_шага_ICE_красная() -> void:
	var it := _it(ICE, EAST, 0, Vector2i(5, 8))
	assert_int(TickForecast.threat(NodeGrid.new(), [it], Vector2i(5, 8))).is_equal(TickForecast.RED)


func test_берёт_худшую_из_нескольких_ICE() -> void:
	var g := NodeGrid.new()
	var far := _it(Vector2i(20, 20), EAST)
	var near := _it(ICE, EAST)
	assert_int(TickForecast.threat(g, [far, near], ICE + Vector2i(3, 0))).is_equal(TickForecast.RED)
	assert_int(TickForecast.threat(g, [far], ICE + Vector2i(3, 0))).is_equal(TickForecast.GREEN)


func test_Black_ICE_без_предзахвата_по_c_и_d() -> void:
	var g := NodeGrid.new()
	var black := {"c": ICE, "d": EAST, "st": 3, "nc": ICE, "nd": EAST, "sc": 12.0, "black": true}
	assert_int(TickForecast.threat(g, [black], ICE + Vector2i(4, 0))).is_equal(TickForecast.RED)
	assert_int(TickForecast.threat(g, [black], ICE + Vector2i(-1, 0))).is_equal(TickForecast.GREEN)   # st = 3, но это охота, не предзахват


func test_разбор_сообщения_state() -> void:
	var msg := [
		{"id": "ice_1", "p": [0, 0, 0], "f": [1, 0], "s": 1, "b": 0, "c": [4, 8], "d": [1, 0], "st": 2, "nc": [6, 8], "nd": [1, 1], "aw": 3, "sc": 6},
		{"id": "ice_2", "p": [0, 0, 0], "f": [1, 0], "s": 0, "b": 1, "c": [9, 9], "d": [0, 1], "st": 3, "nc": [9, 9], "nd": [0, 1], "aw": 0, "sc": 12},
		{"id": "old", "p": [0, 0, 0], "f": [1, 0], "s": 0, "b": 0},   # realtime: без клеток
	]
	var its := TickForecast.parse_intents(msg)
	assert_int(its.size()).is_equal(2)
	assert_that(its[0]["c"]).is_equal(Vector2i(4, 8))
	assert_that(its[0]["nc"]).is_equal(Vector2i(6, 8))
	assert_that(its[0]["nd"]).is_equal(Vector2i(1, 1))
	assert_int(its[0]["st"]).is_equal(2)
	assert_float(its[0]["sc"]).is_equal(6.0)
	assert_bool(its[0]["black"]).is_false()
	assert_bool(its[1]["black"]).is_true()
	assert_that(its[1]["nc"]).is_equal(Vector2i(9, 9))
	assert_float(its[1]["sc"]).is_equal(12.0)


func test_разбор_без_sc_берёт_стартовую_дальность() -> void:
	var its := TickForecast.parse_intents([{"c": [1, 1], "d": [1, 0], "st": 0, "nc": [1, 1], "nd": [1, 0]}])
	assert_float(its[0]["sc"]).is_equal(TickForecast.DEFAULT_SIGHT)
	assert_array(TickForecast.parse_intents([])).is_empty()


func test_залипание_красной_ровно_с_0_4_секунды() -> void:
	assert_bool(TickForecast.red_hold_ok(0.0)).is_false()
	assert_bool(TickForecast.red_hold_ok(0.39)).is_false()
	assert_bool(TickForecast.red_hold_ok(0.4)).is_true()
	assert_bool(TickForecast.red_hold_ok(2.0)).is_true()
