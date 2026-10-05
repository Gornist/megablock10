extends GdUnitTestSuite
## Состояние попытки: доступные клетки по правилу строка/столбец, совпадения, ловушка рвёт цепочку, чужой ввод не бросает исключений.

var _data: BreachData

## Сетка 3x3, ловушка в (2,1):
##   1C 55 BD
##   E9 7A FF
##   1C 55 BD
const CELLS := [["1C", "55", "BD"], ["E9", "7A", "FF"], ["1C", "55", "BD"]]


func before_test() -> void:
	BreachData.reset_shared()
	_data = BreachData.shared()


func after_test() -> void:
	BreachData.reset_shared()


func _attempt(daemons: Array, buffer: int = 6, traps: Array = [Vector2i(2, 1)]) -> BreachAttempt:
	var g := BreachGrid.new()
	g.size = 3
	g.cells = CELLS.duplicate(true)
	for t in traps:
		g.trap_cells[t] = true
	return BreachAttempt.make(g, daemons, buffer, _data)


func test_fresh_attempt_offers_exactly_the_top_row() -> void:
	var a := _attempt([BreachDaemon.make("a", ["55", "7A"])])
	assert_array(a.selectable_cells()).contains_exactly_in_any_order([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)])


func test_second_pick_is_in_the_same_column_third_in_the_same_row() -> void:
	var a := _attempt([BreachDaemon.make("a", ["55", "7A"])])
	assert_bool(a.select(Vector2i(0, 1))).is_true()
	assert_array(a.selectable_cells()).contains_exactly_in_any_order([Vector2i(1, 1), Vector2i(2, 1)])
	assert_bool(a.select(Vector2i(1, 1))).is_true()
	assert_array(a.selectable_cells()).contains_exactly_in_any_order([Vector2i(1, 0), Vector2i(1, 2)])


func test_select_rejects_unavailable_cells_without_changes() -> void:
	var a := _attempt([BreachDaemon.make("a", ["55", "7A"])])
	assert_bool(a.select(Vector2i(2, 2))).is_false()   # не верхняя строка
	assert_bool(a.select(Vector2i(9, 9))).is_false()   # за сеткой
	assert_bool(a.select(Vector2i(-1, 0))).is_false()
	assert_array(a.selected).is_empty()
	a.select(Vector2i(0, 1))
	assert_bool(a.select(Vector2i(0, 1))).is_false()   # уже выбрана
	assert_bool(a.select(Vector2i(1, 0))).is_false()   # не тот столбец
	assert_int(a.selected.size()).is_equal(1)


func test_match_appears_when_the_whole_chain_is_in_the_buffer() -> void:
	var a := _attempt([BreachDaemon.make("a", ["55", "7A"])])
	a.select(Vector2i(0, 1))
	assert_array(a.matched_daemon_ids()).is_empty()
	a.select(Vector2i(1, 1))
	assert_array(a.matched_daemon_ids()).is_equal(["a"])
	assert_array(a.buffer_codes()).is_equal(["55", "7A"])


func test_trap_cell_breaks_the_chain_even_if_its_code_would_fit() -> void:
	# В (0,1) и (2,1) один и тот же код 55 в одном столбце, но (2,1) — ловушка: пара «55 55» не складывается.
	var a := _attempt([BreachDaemon.make("a", ["55", "55"])])
	a.select(Vector2i(0, 1))
	a.select(Vector2i(2, 1))
	assert_array(a.buffer_codes()).is_equal(["55", "55"])  # на сетке два одинаковых кода подряд
	assert_array(a.matched_daemon_ids()).is_empty()         # но ловушка в совпадение не входит
	assert_array(a.match_codes()).is_equal(["55", _data.trap_sentinel])


func test_same_chain_matches_when_the_cell_is_not_a_trap() -> void:
	var a := _attempt([BreachDaemon.make("a", ["55", "55"])], 6, [])
	a.select(Vector2i(0, 1))
	a.select(Vector2i(2, 1))
	assert_array(a.matched_daemon_ids()).is_equal(["a"])


func test_full_buffer_leaves_nothing_selectable() -> void:
	var a := _attempt([BreachDaemon.make("a", ["55", "7A"])], 2)
	a.select(Vector2i(0, 1))
	a.select(Vector2i(1, 1))
	assert_bool(a.is_full()).is_true()
	assert_array(a.selectable_cells()).is_empty()
	assert_bool(a.select(Vector2i(1, 0))).is_false()


func test_duplicate_is_independent() -> void:
	var a := _attempt([BreachDaemon.make("a", ["55", "7A"])])
	a.select(Vector2i(0, 1))
	var b := a.duplicate_attempt()
	b.select(Vector2i(1, 1))
	assert_int(a.selected.size()).is_equal(1)
	assert_int(b.selected.size()).is_equal(2)
