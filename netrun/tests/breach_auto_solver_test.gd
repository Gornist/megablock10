extends GdUnitTestSuite
## Автосолвер для ботов: проходит любую сгенерированную сетку и не наступает на ловушки там, где без них можно.

const SEEDS := 1000
const TIERS := ["BASE", "HARD", "NIGHTMARE"]

var _data: BreachData


func before_test() -> void:
	BreachData.reset_shared()
	_data = BreachData.shared()


func after_test() -> void:
	BreachData.reset_shared()


func test_solver_passes_every_generated_grid_of_every_tier_without_traps() -> void:
	for tier in TIERS:
		var p := _data.tier_params(tier)
		for s in range(SEEDS):
			var rng := RandomNumberGenerator.new()
			rng.seed = s * 104729 + 13
			var ds := BreachTestUtil.random_daemons(rng, _data, 8)
			var traps := {"dead_cells": p["dead_cells"], "corrupted_codes": p["corrupted_codes"]}
			var g := BreachGrid.generate(int(p["grid_size"]), ds, rng, _data, traps)
			var a := BreachAttempt.make(g, ds, 8, _data)
			var path := BreachAutoSolver.solve(a)
			var play := BreachAttempt.make(g, ds, 8, _data)
			for cell in path:
				if not play.select(cell):
					fail("%s seed=%d: солвер вернул недопустимую клетку %s" % [tier, s, cell])
					return
				if g.is_trap(cell):
					fail("%s seed=%d: солвер наступил на ловушку %s, хотя путь без ловушек есть" % [tier, s, cell])
					return
			if play.matched_daemon_ids().size() != ds.size():
				fail("%s seed=%d: солвер собрал %d из %d демонов" % [tier, s, play.matched_daemon_ids().size(), ds.size()])
				return
			assert_int(a.selected.size()).is_equal(0)  # исходная попытка не тронута


func test_solver_uses_the_whole_ram_of_thirteen_cells() -> void:
	var ds: Array = [
		BreachDaemon.make("a", ["1C", "55", "BD", "E9", "7A"]),
		BreachDaemon.make("b", ["FF", "1C", "55", "BD", "E9"]),
		BreachDaemon.make("c", ["7A", "FF", "1C"]),
	]
	for s in range(50):
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var g := BreachGrid.generate(7, ds, rng, _data)
		var a := BreachAttempt.make(g, ds, 13, _data)
		var play := BreachAttempt.make(g, ds, 13, _data)
		for cell in BreachAutoSolver.solve(a):
			assert_bool(play.select(cell)).is_true()
		assert_int(play.matched_daemon_ids().size()).is_equal(3)


func test_solver_returns_the_best_partial_when_the_buffer_is_too_small() -> void:
	# Буфер на одну цепочку из двух: берёт ту, что влезает, остальное не собрать.
	var ds: Array = [BreachDaemon.make("a", ["1C", "55"]), BreachDaemon.make("b", ["BD", "E9"])]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var g := BreachGrid.generate(5, ds, rng, _data)
	var a := BreachAttempt.make(g, ds, 2, _data)
	var play := BreachAttempt.make(g, ds, 2, _data)
	for cell in BreachAutoSolver.solve(a):
		play.select(cell)
	assert_int(play.selected.size()).is_less_equal(2)
	assert_int(play.matched_daemon_ids().size()).is_less_equal(1)


func test_solver_continues_from_an_existing_prefix() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var ds: Array = [BreachDaemon.make("a", ["1C", "55", "BD"])]
	var g := BreachGrid.generate(5, ds, rng, _data)
	var a := BreachAttempt.make(g, ds, 6, _data)
	a.select(g.solution_path[0])
	var path := BreachAutoSolver.solve(a)
	assert_object(path[0]).is_equal(g.solution_path[0])
	var play := BreachAttempt.make(g, ds, 6, _data)
	for cell in path:
		assert_bool(play.select(cell)).is_true()
	assert_int(play.matched_daemon_ids().size()).is_equal(1)


func test_solver_without_daemons_returns_the_prefix() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var g := BreachGrid.generate(5, [BreachDaemon.make("a", ["1C", "55"])], rng, _data)
	var a := BreachAttempt.make(g, [], 6, _data)
	assert_array(BreachAutoSolver.solve(a)).is_empty()


func test_solver_falls_back_to_search_when_a_filler_cell_is_needed() -> void:
	# 7A не в верхней строке: до неё надо дойти через вставку (0,1) -> (1,1) 7A -> (1,2) FF. Точной цепочки нет, работает перебор.
	var g := BreachGrid.new()
	g.size = 3
	g.cells = [["1C", "55", "BD"], ["E9", "7A", "FF"], ["1C", "55", "BD"]]
	var ds: Array = [BreachDaemon.make("a", ["7A", "FF"])]
	var a := BreachAttempt.make(g, ds, 3, _data)
	var path := BreachAutoSolver.solve(a)
	assert_array(path).is_equal([Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)])
	var play := BreachAttempt.make(g, ds, 3, _data)
	for cell in path:
		assert_bool(play.select(cell)).is_true()
	assert_array(play.matched_daemon_ids()).is_equal(["a"])


func test_solver_avoids_a_trap_that_would_shorten_the_path() -> void:
	# Путь через ловушку (1,1) «7A» короче, но ловушка рвёт цепочку, так что собрать можно только в обход.
	var g := BreachGrid.new()
	g.size = 3
	g.cells = [["1C", "55", "BD"], ["E9", "7A", "FF"], ["1C", "55", "BD"]]
	g.trap_cells[Vector2i(1, 1)] = true
	var ds: Array = [BreachDaemon.make("a", ["55", "7A"])]
	var a := BreachAttempt.make(g, ds, 6, _data)
	var path := BreachAutoSolver.solve(a)
	var play := BreachAttempt.make(g, ds, 6, _data)
	for cell in path:
		play.select(cell)
	assert_array(play.matched_daemon_ids()).is_empty()  # 7A есть только в ловушке: собрать нельзя
	for cell in path:
		assert_bool(g.is_trap(cell)).is_false()          # и бот на неё не лезет
