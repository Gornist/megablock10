extends GdUnitTestSuite
## Сетка клеток 1 м (NodeGrid): размеры, центры, колонны как занятые клетки, линия взгляда/прыжка, дальность и причины отказа.
## Чистые функции — без сцен. Колонны NodeLayout.PILLARS: (3;−5) закрывает клетки x 10–11, z 8–9 (клетка = пол(p − ROOM_MIN)).


func _grid_with(cells: Array) -> NodeGrid:
	var g := NodeGrid.new()
	for c: Vector2i in cells:
		g.occ[c] = true
	return g


func test_размеры_и_центры() -> void:
	assert_int(NodeGrid.cols()).is_equal(16)
	assert_int(NodeGrid.rows()).is_equal(16)
	var c0 := NodeGrid.center(Vector2i(0, 0))
	assert_float(c0.x).is_equal_approx(-7.5, 0.0001)
	assert_float(c0.z).is_equal_approx(-13.5, 0.0001)
	assert_float(c0.y).is_equal(0.0)
	assert_object(NodeGrid.cell_of(Vector3(-7.5, 0, -13.5))).is_equal(Vector2i(0, 0))
	assert_object(NodeGrid.cell_of(Vector3(7.99, 0, 1.99))).is_equal(Vector2i(15, 15))
	assert_object(NodeGrid.cell_of(Vector3(-8.5, 0, 0))).is_equal(Vector2i(-1, 14))  # без зажима
	assert_bool(NodeGrid.in_bounds(Vector2i(15, 15))).is_true()
	assert_bool(NodeGrid.in_bounds(Vector2i(16, 0))).is_false()
	assert_bool(NodeGrid.in_bounds(Vector2i(0, -1))).is_false()


func test_колонна_это_четыре_занятые_клетки() -> void:
	var g := NodeGrid.for_layout()
	assert_int(g.occ.size()).is_equal(16)  # 4 колонны × 4 клетки, друг с другом не пересекаются
	for c in [Vector2i(10, 8), Vector2i(11, 8), Vector2i(10, 9), Vector2i(11, 9)]:  # колонна (3;−5)
		assert_bool(g.is_occupied(c)).is_true()
	assert_bool(g.is_occupied(Vector2i(9, 8))).is_false()
	assert_bool(g.is_occupied(Vector2i(12, 9))).is_false()
	assert_bool(g.is_occupied(Vector2i(10, 7))).is_false()
	assert_bool(g.is_occupied(Vector2i(10, 10))).is_false()
	assert_bool(g.is_occupied(Vector2i(-1, 0))).is_true()  # вне комнаты — занято
	assert_bool(g.is_occupied(Vector2i(0, 16))).is_true()


func test_линия_через_колонну_закрыта_мимо_открыта() -> void:
	var g := NodeGrid.for_layout()
	assert_bool(g.line_clear(Vector2i(10, 5), Vector2i(10, 13))).is_false()
	assert_bool(g.line_clear(Vector2i(8, 5), Vector2i(8, 13))).is_true()
	assert_bool(g.line_clear(Vector2i(8, 9), Vector2i(12, 9))).is_false()
	assert_bool(g.line_clear(Vector2i(8, 7), Vector2i(12, 7))).is_true()
	assert_bool(g.line_clear(Vector2i(4, 4), Vector2i(4, 4))).is_true()  # сама в себя
	# Концы не проверяются: можно «смотреть» на занятую клетку, если на пути ничего нет.
	assert_bool(g.line_clear(Vector2i(10, 5), Vector2i(10, 8))).is_true()


func test_диагональ_через_вершину() -> void:
	# Одна боковая занята — диагональный шаг открыт; обе — закрыт.
	var one := _grid_with([Vector2i(5, 4)])
	assert_bool(one.line_clear(Vector2i(4, 4), Vector2i(5, 5))).is_true()
	var both := _grid_with([Vector2i(5, 4), Vector2i(4, 5)])
	assert_bool(both.line_clear(Vector2i(4, 4), Vector2i(5, 5))).is_false()
	# Диагональ длиннее: занята клетка прямо на линии — закрыта.
	var mid := _grid_with([Vector2i(5, 5)])
	assert_bool(mid.line_clear(Vector2i(4, 4), Vector2i(6, 6))).is_false()
	# Обратное направление и другие знаки — то же.
	assert_bool(both.line_clear(Vector2i(5, 5), Vector2i(4, 4))).is_false()
	var other := _grid_with([Vector2i(4, 4), Vector2i(5, 5)])
	assert_bool(other.line_clear(Vector2i(5, 4), Vector2i(4, 5))).is_false()
	assert_bool(_grid_with([Vector2i(4, 4)]).line_clear(Vector2i(5, 4), Vector2i(4, 5))).is_true()


func test_can_see_по_точкам() -> void:
	var g := NodeGrid.for_layout()
	assert_bool(g.can_see(Vector3(3, 0, -8), Vector3(3, 0, -2))).is_false()  # колонна (3;−5) между
	assert_bool(g.can_see(Vector3(7, 0, -8), Vector3(7, 0, -2))).is_true()


func test_достижимые_клетки() -> void:
	var g := NodeGrid.for_layout()
	var from := Vector2i(7, 6)  # открытое место: справа и слева свободно
	var cells := g.reach_cells(from)
	assert_bool(from in cells).is_false()
	assert_bool(Vector2i(11, 6) in cells).is_true()  # 4 клетки по прямой
	assert_bool(Vector2i(12, 6) in cells).is_false()  # 5 клеток — дальше 4,5 м
	assert_bool(Vector2i(3, 6) in cells).is_true()
	assert_bool(Vector2i(10, 9) in cells).is_false()  # занято
	assert_bool(Vector2i(10, 8) in cells).is_false()
	# Дальность считается по центрам: смещение (3;4) клетки — ровно 5 м, дальше 4,5.
	assert_bool(Vector2i(10, 10) in cells).is_false()
	assert_bool(Vector2i(10, 4) in cells).is_true()  # смещение (3;−2): 3,6 м
	# За колонной: из (8;9) клетка (12;9) в пределах 4 м, но линия закрыта.
	var behind := g.reach_cells(Vector2i(8, 9))
	assert_bool(Vector2i(9, 9) in behind).is_true()
	assert_bool(Vector2i(12, 9) in behind).is_false()
	assert_bool(Vector2i(8, 5) in behind).is_true()


func test_причины_отказа_в_прыжке() -> void:
	var g := NodeGrid.for_layout()
	var from := NodeGrid.center(Vector2i(8, 9))
	assert_str(g.hop_verdict(from, NodeGrid.center(Vector2i(8, 5)))).is_equal("")
	assert_str(g.hop_verdict(from, NodeGrid.center(Vector2i(10, 9)))).is_equal("occupied")
	assert_str(g.hop_verdict(from, Vector3(-20, 0, 0))).is_equal("occupied")  # вне комнаты
	assert_str(g.hop_verdict(from, NodeGrid.center(Vector2i(12, 9)))).is_equal("blocked")
	assert_str(g.hop_verdict(from, NodeGrid.center(Vector2i(7, 3)))).is_equal("range")
	# Порядок проверок: занято важнее дальности, дальность — важнее закрытой линии.
	assert_str(g.hop_verdict(from, NodeGrid.center(Vector2i(8, 3)))).is_equal("occupied")  # колонна (1;−11), и далеко
	assert_str(g.hop_verdict(NodeGrid.center(Vector2i(7, 9)), NodeGrid.center(Vector2i(13, 9)))).is_equal("range")
