extends GdUnitTestSuite
## Зрение ICE на клетках (TickVision): дальность, фокус и периферия, углы, колонны, диагональное направление. Чистые функции — без сцен.
## Настройки как в ice.md 9: дальность 6 клеток, конус ±50°, фокус ±25°.

const SIGHT := 6.0
const HALF := 50.0
const FOCUS := 25.0
const ICE := Vector2i(4, 8)
const EAST := Vector2i(1, 0)


func _cls(g: NodeGrid, dir: Vector2i, dx: int, dy: int) -> int:
	return TickVision.classify(g, ICE, dir, ICE + Vector2i(dx, dy), SIGHT, HALF, FOCUS)


func test_на_восток_прямо_впереди_фокус_до_шести_клеток() -> void:
	var g := NodeGrid.new()
	assert_int(_cls(g, EAST, 6, 0)).is_equal(2)
	assert_int(_cls(g, EAST, 7, 0)).is_equal(0)   # дальше шести клеток
	assert_int(_cls(g, EAST, 1, 0)).is_equal(2)


func test_под_тридцать_градусов_периферия() -> void:
	var g := NodeGrid.new()
	assert_int(_cls(g, EAST, 5, 3)).is_equal(1)   # 31°, дальность 5,8
	assert_int(_cls(g, EAST, 5, -3)).is_equal(1)   # симметрично в другую сторону
	assert_int(_cls(g, EAST, 5, 1)).is_equal(2)   # 11° — ещё фокус


func test_под_шестьдесят_градусов_не_виден() -> void:
	var g := NodeGrid.new()
	assert_int(_cls(g, EAST, 1, 2)).is_equal(0)   # 63°
	assert_int(_cls(g, EAST, 2, 3)).is_equal(0)   # 56°
	assert_int(_cls(g, EAST, 2, 2)).is_equal(1)   # 45° — граница конуса внутри


func test_позади_и_своя_клетка_не_видны() -> void:
	var g := NodeGrid.new()
	assert_int(_cls(g, EAST, -3, 0)).is_equal(0)
	assert_int(_cls(g, EAST, 0, 0)).is_equal(0)
	assert_int(_cls(g, EAST, 0, 3)).is_equal(0)   # строго сбоку, 90°


func test_колонна_между_закрывает_взгляд() -> void:
	var g := NodeGrid.new()
	g.occ[ICE + Vector2i(3, 0)] = true
	assert_int(_cls(g, EAST, 5, 0)).is_equal(0)
	assert_int(_cls(g, EAST, 2, 0)).is_equal(2)   # до колонны видно
	assert_int(_cls(g, EAST, 3, 0)).is_equal(0)   # сама колонна — занятая клетка, там никого
	assert_int(_cls(g, EAST, 5, 2)).is_equal(2)   # мимо колонны — видно (линия идёт в обход), 22°


func test_диагональное_направление() -> void:
	var g := NodeGrid.new()
	var se := Vector2i(1, 1)
	assert_int(_cls(g, se, 3, 3)).is_equal(2)   # строго по диагонали
	assert_int(_cls(g, se, 5, 5)).is_equal(0)   # 7,07 клетки — дальше шести
	assert_int(_cls(g, se, 5, 1)).is_equal(1)   # 34° от диагонали
	assert_int(_cls(g, se, 5, -1)).is_equal(0)   # 56° от диагонали
	assert_int(_cls(g, se, -3, -3)).is_equal(0)


func test_visible_cells_согласована_с_classify() -> void:
	var g := NodeGrid.new()
	g.occ[ICE + Vector2i(3, 0)] = true
	var v := TickVision.visible_cells(g, ICE, EAST, SIGHT, HALF, FOCUS)
	assert_bool(v.has(ICE)).is_false()
	assert_bool(v.has(ICE + Vector2i(2, 0))).is_true()
	assert_int(int(v[ICE + Vector2i(2, 0)])).is_equal(2)
	assert_bool(v.has(ICE + Vector2i(3, 0))).is_false()   # занятая
	assert_bool(v.has(ICE + Vector2i(5, 0))).is_false()   # за колонной
	assert_bool(v.has(ICE + Vector2i(-2, 0))).is_false()
	for c: Vector2i in v:
		assert_int(int(v[c])).is_equal(_cls(g, EAST, c.x - ICE.x, c.y - ICE.y))
	assert_int(v.size()).is_greater(10)
