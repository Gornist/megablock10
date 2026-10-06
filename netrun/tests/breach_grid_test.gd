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


# --- замок и приманки Взлома 2.0 (breach.md 2.1, 2.4) ---

func _lock_params(tier: String) -> Dictionary:
	var p := _data.tier_params(tier)
	return {"dead_cells": p["dead_cells"], "corrupted_codes": p["corrupted_codes"], "lock_traps": p["lock_traps"]}


func _lock_grid(tier: String, seed_value: int, daemons: Array = []) -> BreachGrid:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var p := _data.tier_params(tier)
	var ds := daemons if not daemons.is_empty() else BreachTestUtil.random_daemons(rng, _data, 8 - int(p["lock_length"]))
	return BreachGrid.generate(int(p["grid_size"]), ds, rng, _data, _lock_params(tier), int(p["lock_length"]))


func test_lock_is_the_first_chain_of_the_solution_path_and_the_path_still_solves() -> void:
	for tier in TIERS:
		var lock_length := int(_data.tier_params(tier)["lock_length"])
		for s in range(SEEDS):
			var rng := RandomNumberGenerator.new()
			rng.seed = s * 7919 + 3
			var ds := BreachTestUtil.random_daemons(rng, _data, 8 - lock_length)
			var p := _data.tier_params(tier)
			var g := BreachGrid.generate(int(p["grid_size"]), ds, rng, _data, _lock_params(tier), lock_length)
			assert_object(g).override_failure_message("%s seed=%d: сетка не построена" % [tier, s]).is_not_null()
			if g.lock.size() != lock_length:
				fail("%s seed=%d: замок %d кодов, ожидалось %d" % [tier, s, g.lock.size(), lock_length])
				return
			for code in g.lock:
				if not code in _data.alphabet:
					fail("%s seed=%d: код замка %s не из алфавита" % [tier, s, code])
					return
			var total := lock_length + BreachTestUtil.total_length(ds)
			var a := BreachAttempt.make(g, ds, total, _data)
			if g.solution_path.size() != total:
				fail("%s seed=%d: путь %d клеток, ожидалось %d" % [tier, s, g.solution_path.size(), total])
				return
			for cell in g.solution_path:
				if not a.select(cell):
					fail("%s seed=%d: клетка пути %s недоступна по правилу строка/столбец" % [tier, s, cell])
					return
			if a.buffer_codes().slice(0, lock_length) != g.lock:
				fail("%s seed=%d: путь начат не с замка" % [tier, s])
				return
			if a.matched_daemon_ids().size() != ds.size():
				fail("%s seed=%d: путь решения с замком не собрал всех демонов" % [tier, s])
				return


func test_with_a_lock_traps_follow_lock_traps_and_stay_off_the_path() -> void:
	for tier in TIERS:
		var p := _data.tier_params(tier)
		var dead_r: Vector2i = p["dead_cells"]
		var traps_r: Vector2i = p["lock_traps"]
		for s in range(SEEDS):
			var g := _lock_grid(tier, s * 31 + 5)
			var dead := 0
			var decoys := 0
			for cell in g.trap_cells:
				if g.solution_path.has(cell):
					fail("%s seed=%d: ловушка %s на пути решения" % [tier, s, cell])
					return
				if g.is_dead(cell):
					dead += 1
				else:
					decoys += 1
			if dead < dead_r.x or dead > dead_r.y or decoys < traps_r.x or decoys > traps_r.y:
				fail("%s seed=%d: мёртвых %d из %s, приманок %d из %s" % [tier, s, dead, dead_r, decoys, traps_r])
				return


func test_decoys_sit_on_goal_codes_while_there_are_enough_of_them() -> void:
	# breach.md 2.4: приманка ложится на клетку с кодом из целей (замок и цепочки), пока такие свободные клетки есть.
	for tier in ["HARD", "NIGHTMARE"]:
		for s in range(300):
			var g := _lock_grid(tier, s + 900)
			var goal: Array = g.lock.duplicate()
			# Цели те же, что у попытки: цепочки демонов берём из самой сетки — по пути решения.
			for i in range(g.lock.size(), g.solution_path.size()):
				goal.append(g.code_at(g.solution_path[i]))
			var spare_goal_cells := 0
			var decoys_off_goal := 0
			for r in range(g.size):
				for c in range(g.size):
					var cell := Vector2i(r, c)
					if g.solution_path.has(cell) or g.is_dead(cell):
						continue
					var is_goal: bool = goal.has(g.code_at(cell))
					if g.is_trap(cell):
						if not is_goal:
							decoys_off_goal += 1
					elif is_goal:
						spare_goal_cells += 1
			if decoys_off_goal > 0 and spare_goal_cells > 0:
				fail("%s seed=%d: приманка не на коде цели, хотя свободных клеток с кодом цели ещё %d" % [tier, s, spare_goal_cells])
				return


func test_zero_lock_length_changes_nothing() -> void:
	# lock_length = 0 — сетка, путь и ловушки те же, что без параметра (заряд, расшифровка, приложение до замка).
	for tier in TIERS:
		for s in range(50):
			var ds := BreachTestUtil.random_daemons(RandomNumberGenerator.new(), _data, 8)
			var a_rng := RandomNumberGenerator.new()
			a_rng.seed = s
			var b_rng := RandomNumberGenerator.new()
			b_rng.seed = s
			var p := _data.tier_params(tier)
			var a := BreachGrid.generate(int(p["grid_size"]), ds, a_rng, _data, _traps_params(tier))
			var b := BreachGrid.generate(int(p["grid_size"]), ds, b_rng, _data, _traps_params(tier), 0)
			assert_array(a.cells).is_equal(b.cells)
			assert_array(a.solution_path).is_equal(b.solution_path)
			assert_array(a.lock).is_empty()
			assert_int(a.solution_path.size()).is_equal(BreachTestUtil.total_length(ds))
			assert_int(a.trap_cells.size()).is_equal(b.trap_cells.size())


func test_without_a_lock_decoys_use_corrupted_codes_not_lock_traps() -> void:
	# Старый диапазон corrupted_codes — без замка (HARD: 0; NIGHTMARE: 2–3), хотя lock_traps у тира больше.
	for s in range(200):
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var p := _data.tier_params("NIGHTMARE")
		var g := BreachGrid.generate(int(p["grid_size"]), [BreachDaemon.make("a", ["1C", "55"])], rng, _data, _lock_params("NIGHTMARE"))
		var decoys := 0
		for cell in g.trap_cells:
			if not g.is_dead(cell):
				decoys += 1
		assert_int(decoys).is_between(2, 3)


func test_lock_round_trips_through_to_dict() -> void:
	var g := _lock_grid("NIGHTMARE", 77)
	assert_int(g.lock.size()).is_equal(3)
	var copy := BreachGrid.from_dict(JSON.parse_string(JSON.stringify(g.to_dict())))
	assert_array(copy.lock).is_equal(g.lock)
	assert_array(BreachGrid.from_dict({"size": 5}).lock).is_empty()
