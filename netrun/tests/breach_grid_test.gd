extends GdUnitTestSuite
## Свойства генератора сетки на 1000 зёрен на тир (docs/netrun-deck-design.md, §7.4, §10.4): решаемость по правилам игрока,
## ловушки вне пути решения, число ловушек в диапазоне тира. Конкретные сетки с телефоном не совпадают — совпадают свойства.

const SEEDS := 1000
const TIERS := ["BASE", "HARD", "NIGHTMARE"]

var _data: BreachData


func before_test() -> void:
	BreachData.reset_shared()
	_data = BreachData.shared()


func after_test() -> void:
	BreachData.reset_shared()


func _traps_params(tier: String) -> Dictionary:
	var p := _data.tier_params(tier)
	return {"dead_cells": p["dead_cells"], "corrupted_codes": p["corrupted_codes"]}


func _grid(tier: String, seed_value: int, daemons: Array = []) -> BreachGrid:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var p := _data.tier_params(tier)
	var ds := daemons if not daemons.is_empty() else BreachTestUtil.random_daemons(rng, _data, 8)
	return BreachGrid.generate(int(p["grid_size"]), ds, rng, _data, _traps_params(tier))


func test_every_generated_grid_is_solvable_by_the_path_it_was_built_on() -> void:
	for tier in TIERS:
		for s in range(SEEDS):
			var rng := RandomNumberGenerator.new()
			rng.seed = s * 7919 + 1
			var ds := BreachTestUtil.random_daemons(rng, _data, 8)
			var p := _data.tier_params(tier)
			var g := BreachGrid.generate(int(p["grid_size"]), ds, rng, _data, _traps_params(tier))
			assert_object(g).override_failure_message("%s seed=%d: сетка не построена" % [tier, s]).is_not_null()
			# Путь проигрывается теми же правилами выбора, что видит игрок.
			var a := BreachAttempt.make(g, ds, BreachTestUtil.total_length(ds), _data)
			assert_int(g.solution_path.size()).is_equal(BreachTestUtil.total_length(ds))
			for cell in g.solution_path:
				if not a.select(cell):
					fail("%s seed=%d: клетка пути %s недоступна по правилу строка/столбец" % [tier, s, cell])
					return
			if a.matched_daemon_ids().size() != ds.size():
				fail("%s seed=%d: путь не собрал всех демонов" % [tier, s])
				return
			if a.selected[0].x != 0:
				fail("%s seed=%d: путь начат не с верхней строки" % [tier, s])
				return


func test_traps_never_sit_on_the_solution_path_and_counts_stay_in_tier_range() -> void:
	for tier in TIERS:
		var p := _data.tier_params(tier)
		var dead_r: Vector2i = p["dead_cells"]
		var corr_r: Vector2i = p["corrupted_codes"]
		for s in range(SEEDS):
			var g := _grid(tier, s * 31 + 5)
			var dead := 0
			var corrupted := 0
			for cell in g.trap_cells:
				if g.solution_path.has(cell):
					fail("%s seed=%d: ловушка %s на пути решения" % [tier, s, cell])
					return
				if g.is_dead(cell):
					dead += 1
				else:
					corrupted += 1
			# Маркер мёртвой клетки стоит только на мёртвых клетках.
			var markers := 0
			for r in range(g.size):
				for c in range(g.size):
					if g.code_at(Vector2i(r, c)) == _data.dead_marker:
						markers += 1
			if markers != dead:
				fail("%s seed=%d: маркеров ×× %d, а мёртвых клеток %d" % [tier, s, markers, dead])
				return
			if dead < dead_r.x or dead > dead_r.y or corrupted < corr_r.x or corrupted > corr_r.y:
				fail("%s seed=%d: ловушек вне диапазона тира: мёртвых %d из %s, порченых %d из %s" % [tier, s, dead, dead_r, corrupted, corr_r])
				return


func test_cells_use_only_the_alphabet_and_dead_marker() -> void:
	for tier in TIERS:
		for s in range(100):
			var g := _grid(tier, s)
			assert_int(g.size).is_equal(int(_data.tier_params(tier)["grid_size"]))
			for r in range(g.size):
				for c in range(g.size):
					var code := g.code_at(Vector2i(r, c))
					assert_bool(code in _data.alphabet or code == _data.dead_marker).is_true()


func test_same_seed_gives_the_same_grid_and_other_seeds_differ() -> void:
	var a := _grid("HARD", 12345)
	var b := _grid("HARD", 12345)
	assert_array(a.cells).is_equal(b.cells)
	assert_array(a.solution_path).is_equal(b.solution_path)
	var different := 0
	for s in range(20):
		if _grid("HARD", 100 + s).cells != a.cells:
			different += 1
	assert_bool(different > 15).is_true()


func test_generator_survives_the_longest_chain_on_the_smallest_grid() -> void:
	# Максимальный буфер (RAM 13) на самой маленькой сетке (BASE 5x5): генератор не должен отказывать.
	var codes := _data.alphabet
	var ds: Array = [
		BreachDaemon.make("a", [codes[0], codes[1], codes[2], codes[3], codes[4]]),
		BreachDaemon.make("b", [codes[2], codes[3], codes[4], codes[5], codes[0]]),
		BreachDaemon.make("c", [codes[4], codes[5], codes[0]]),
	]
	for s in range(300):
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		assert_object(BreachGrid.generate(5, ds, rng, _data, _traps_params("BASE"))).is_not_null()


func test_impossible_requests_give_null() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var long_seq: Array = []
	for _i in range(10):
		long_seq.append("1C")
	assert_object(BreachGrid.generate(3, [BreachDaemon.make("x", long_seq)], rng, _data)).is_null()
	assert_object(BreachGrid.generate(5, [], rng, _data)).is_null()


func test_traps_do_not_exceed_free_cells_on_a_crowded_grid() -> void:
	# 4x4 с путём из 12 клеток: свободных клеток 4, ловушек просили 7-9 — ставится ровно столько, сколько свободно, и все вне пути.
	var seq: Array = []
	for i in range(12):
		seq.append(_data.alphabet[i % _data.alphabet.size()])
	for s in range(20):
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var g := BreachGrid.generate(4, [BreachDaemon.make("x", seq)], rng, _data, {"dead_cells": Vector2i(5, 6), "corrupted_codes": Vector2i(2, 3)})
		assert_object(g).is_not_null()
		assert_int(g.trap_cells.size()).is_equal(4)
		for cell in g.trap_cells:
			assert_bool(g.solution_path.has(cell)).is_false()


func test_to_dict_round_trip_hides_the_solution() -> void:
	var g := _grid("NIGHTMARE", 77)
	var d := g.to_dict()
	assert_bool(d.has("solution_path")).is_false()
	var copy := BreachGrid.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_array(copy.cells).is_equal(g.cells)
	assert_int(copy.trap_cells.size()).is_equal(g.trap_cells.size())
	for cell in g.trap_cells:
		assert_bool(copy.is_trap(cell)).is_true()
	assert_array(copy.solution_path).is_empty()
