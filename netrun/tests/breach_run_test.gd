extends GdUnitTestSuite
## Ход попытки: таймер, итог, события реплик, три режима (порт BreachRunTest телефона и режимы Сети).

var _data: BreachData


func before_test() -> void:
	BreachData.reset_shared()
	_data = BreachData.shared()


func after_test() -> void:
	BreachData.reset_shared()


func _daemon(effect: String = "EXTRACT_SHARD") -> BreachDaemon:
	return BreachDaemon.make("a", ["1C", "55"], effect)


func _storage(timer_override: int = -1, ram: int = 6, seed_value: int = 1, tier: String = "BASE") -> BreachRun:
	var r := BreachRun.for_storage(tier, [_daemon()], ram, seed_value, _data)
	if timer_override >= 0:
		r.timer_sec = timer_override
		r.seconds_left = timer_override
	return r


func _solve(r: BreachRun) -> void:
	for cell in BreachAutoSolver.solve(r.attempt):
		r.tap(cell)


# --- таймер и итог (порт BreachRunTest) ---

func test_fresh_run_has_full_timer_and_no_result() -> void:
	var r := _storage()
	assert_int(r.seconds_left).is_equal(45)
	assert_str(r.result).is_empty()
	assert_bool(r.is_finished()).is_false()
	assert_bool(r.is_ticking()).is_true()
	assert_bool(r.selectable().is_empty()).is_false()


func test_tick_counts_down_and_resolves_when_time_is_out() -> void:
	var r := _storage(2)
	r.tick()
	assert_int(r.seconds_left).is_equal(1)
	assert_bool(r.is_ticking()).is_true()
	r.tick()
	assert_int(r.seconds_left).is_equal(0)
	assert_bool(r.is_ticking()).is_false()
	assert_str(r.result).is_equal("FAIL")  # ничего не выбрано
	assert_str(r.tick()).is_empty()         # после итога время не идёт
	assert_int(r.seconds_left).is_equal(0)


func test_tap_reports_trap_and_match() -> void:
	var r := _storage()
	var first := r.selectable()[0]
	var res := r.tap(first)
	assert_bool(res["ok"]).is_true()
	assert_bool(res["hit_trap"]).is_equal(r.attempt.grid.is_trap(first))
	assert_array(r.attempt.selected).is_equal([first])


func test_solved_run_matches_every_daemon_and_full_buffer_resolves_it() -> void:
	var r := _storage(-1, 2)
	var path := BreachAutoSolver.solve(r.attempt)
	var last := {}
	for cell in path:
		last = r.tap(cell)
	assert_bool(last["matched"]).is_true()
	assert_str(last["ice_event"]).is_equal("MATCH")
	assert_bool(last["finished"]).is_true()  # буфер из двух ячеек полон
	assert_str(r.result).is_equal("SUCCESS")
	assert_bool(r.is_ticking()).is_false()


func test_full_buffer_stops_the_timer_and_leaves_nothing_to_tap() -> void:
	var r := _storage(-1, 2)
	for _i in range(2):
		r.tap(r.attempt.selectable_cells()[0])
	assert_bool(r.attempt.is_full()).is_true()
	assert_bool(r.is_ticking()).is_false()
	assert_bool(r.selectable().is_empty()).is_true()
	assert_bool(r.is_finished()).is_true()


func test_resolve_is_idempotent_and_blocks_further_taps() -> void:
	var r := _storage()
	r.tap(r.attempt.selectable_cells()[0])
	assert_bool(r.resolve()).is_true()
	var kept := r.result
	assert_bool(r.resolve()).is_false()
	assert_str(r.result).is_equal(kept)
	assert_bool(r.selectable().is_empty()).is_true()
	assert_bool(r.is_ticking()).is_false()
	var res := r.tap(Vector2i(0, 0))
	assert_bool(res["ok"]).is_false()
	assert_bool(res["finished"]).is_true()


func test_empty_attempt_resolves_to_fail() -> void:
	var r := _storage()
	r.resolve()
	assert_str(r.result).is_equal("FAIL")
	assert_dict(r.result_info()).contains_key_value("outcome", "FAIL")


func test_early_resolve_counts_what_was_collected() -> void:
	var r := _storage(-1, 6)
	var path := BreachAutoSolver.solve(r.attempt)
	r.tap(path[0])
	assert_str(_resolved(r)).is_equal("FAIL")  # одна клетка цепочки из двух — ещё не совпадение
	var r2 := _storage(-1, 6)
	for cell in path:
		r2.tap(cell)
	r2.resolve()
	assert_str(r2.result).is_equal("SUCCESS")
	assert_array(r2.result_info()["matched"]).is_equal(["a"])


func _resolved(r: BreachRun) -> String:
	r.resolve()
	return r.result


func test_low_time_and_warning_windows() -> void:
	var r := _storage(60)
	r.seconds_left = 11
	assert_bool(r.is_low_time()).is_false()
	r.seconds_left = 10
	assert_bool(r.is_low_time()).is_true()
	r.seconds_left = 1
	assert_bool(r.is_low_time()).is_true()
	r.seconds_left = 0
	assert_bool(r.is_low_time()).is_false()
	r.seconds_left = 6
	assert_bool(r.is_warning()).is_false()
	r.seconds_left = 5
	assert_bool(r.is_warning()).is_true()
	r.seconds_left = 1
	assert_bool(r.is_warning()).is_true()
	r.seconds_left = 0
	assert_bool(r.is_warning()).is_false()
	r.seconds_left = 5
	r.resolve()
	assert_bool(r.is_low_time()).is_false()  # после итога таймер не мигает


func test_time_events_only_in_long_timers() -> void:
	var long_run := _storage(60)
	long_run.seconds_left = 30
	assert_str(long_run.time_event()).is_equal("HALF_TIME")
	long_run.seconds_left = 10
	assert_str(long_run.time_event()).is_equal("LOW_TIME")
	long_run.seconds_left = 29
	assert_str(long_run.time_event()).is_empty()
	var short_run := _storage(20)
	short_run.seconds_left = 10
	assert_str(short_run.time_event()).is_empty()


func test_when_half_time_coincides_with_ten_seconds_low_time_wins() -> void:
	var r := _storage(21)
	r.seconds_left = 10
	assert_str(r.time_event()).is_equal("LOW_TIME")


func test_tick_returns_the_time_events_of_a_full_countdown() -> void:
	var r := _storage(60)
	var seen: Dictionary = {}
	while r.is_ticking():
		var ev := r.tick()
		if ev != "":
			seen[r.seconds_left] = ev
	assert_dict(seen).is_equal({30: "HALF_TIME", 10: "LOW_TIME"})
	assert_bool(r.is_finished()).is_true()


func test_advance_accumulates_fractional_seconds() -> void:
	var r := _storage(60)
	assert_array(r.advance(0.4)).is_empty()
	assert_int(r.seconds_left).is_equal(60)
	r.advance(0.7)
	assert_int(r.seconds_left).is_equal(59)
	var events := r.advance(40.0)  # 59 -> ~18..19: проходит 30 (HALF_TIME)
	assert_array(events).is_equal(["HALF_TIME"])
	events = r.advance(10.0)
	assert_array(events).is_equal(["LOW_TIME"])
	r.advance(100.0)
	assert_bool(r.is_finished()).is_true()
	assert_int(r.seconds_left).is_equal(0)
	assert_array(r.advance(5.0)).is_empty()


# --- режимы ---

func test_storage_takes_grid_timer_and_traps_from_the_tier() -> void:
	var hard := BreachRun.for_storage("HARD", [_daemon()], 6, 3, _data)
	assert_str(hard.mode).is_equal("storage")
	assert_int(hard.attempt.grid.size).is_equal(6)
	assert_int(hard.timer_sec).is_equal(60)
	assert_int(hard.attempt.buffer_size).is_equal(6)
	assert_int(hard.attempt.grid.trap_cells.size()).is_between(2, 3)
	var nm := BreachRun.for_storage("NIGHTMARE", [_daemon()], 6, 3, _data)
	assert_int(nm.attempt.grid.size).is_equal(7)
	assert_int(nm.timer_sec).is_equal(75)
	assert_int(nm.attempt.grid.trap_cells.size()).is_between(7, 9)
	var base := BreachRun.for_storage("BASE", [_daemon()], 6, 3, _data)
	assert_int(base.attempt.grid.trap_cells.size()).is_equal(0)


func test_storage_jitter_adds_fifteen_seconds_only_when_chosen() -> void:
	var plain := BreachRun.for_storage("HARD", [_daemon()], 6, 1, _data)
	var jittery := BreachRun.for_storage("HARD", [_daemon(), BreachDaemon.make("j", ["BD", "E9"], "JITTER")], 6, 1, _data)
	assert_int(plain.timer_sec).is_equal(60)
	assert_int(jittery.timer_sec).is_equal(75)
	assert_int(jittery.seconds_left).is_equal(75)


func test_storage_rejects_daemons_that_do_not_fit_the_ram() -> void:
	var a := BreachDaemon.make("a", ["1C", "55", "BD"])
	var b := BreachDaemon.make("b", ["E9", "7A", "FF"])
	assert_object(BreachRun.for_storage("BASE", [a, b], 5, 1, _data)).is_null()
	assert_object(BreachRun.for_storage("BASE", [a, b], 6, 1, _data)).is_not_null()
	assert_object(BreachRun.for_storage("BASE", [], 6, 1, _data)).is_null()


func test_charge_buffer_is_chain_plus_two_and_has_no_traps() -> void:
	for level in [1, 2, 3]:
		var d := BreachDaemon.make("x", ["1C", "55", "BD", "E9"], "GHOST", level)
		var r := BreachRun.for_charge(d, 11, _data)
		var expected_tier := BreachData.tier_name(level)
		var p := _data.tier_params(expected_tier)
		assert_str(r.mode).is_equal("charge")
		assert_str(r.tier).is_equal(expected_tier)
		assert_int(r.attempt.buffer_size).is_equal(4 + 2)
		assert_int(r.attempt.grid.size).is_equal(int(p["grid_size"]))
		assert_int(r.timer_sec).is_equal(int(p["cipher_timer_sec"]))   # прежние 45/60/75, не timer_sec хранилища
		assert_int(r.timer_sec).is_equal([45, 60, 75][level - 1])
		assert_int(r.attempt.grid.trap_cells.size()).is_equal(0)


func test_charge_jitter_does_not_extend_its_own_timer() -> void:
	var d := BreachDaemon.make("x", ["1C", "55"], "JITTER", 1)
	assert_int(BreachRun.for_charge(d, 1, _data).timer_sec).is_equal(45)


func test_charge_can_be_completed_by_the_solver() -> void:
	for s in range(100):
		var d := BreachDaemon.make("x", ["1C", "55", "BD"], "GHOST", 1 + s % 3)
		var r := BreachRun.for_charge(d, s, _data)
		_solve(r)
		r.resolve()
		assert_str(r.result).is_equal("SUCCESS")


func test_decrypt_length_and_grid_follow_the_shard_tier() -> void:
	for level in [1, 2, 3]:
		var r := BreachRun.for_decrypt(level, 5, [], _data)
		var p := _data.tier_params(BreachData.tier_name(level))
		var lock: BreachDaemon = r.attempt.daemons[0]
		assert_str(r.mode).is_equal("decrypt")
		assert_int(lock.length()).is_equal(2 + level)
		assert_int(r.attempt.buffer_size).is_equal(2 + level + 2)
		assert_int(r.attempt.grid.size).is_equal(int(p["grid_size"]))
		assert_int(r.timer_sec).is_equal(int(p["cipher_timer_sec"]))
		assert_int(r.timer_sec).is_equal([45, 60, 75][level - 1])
		assert_int(r.attempt.grid.trap_cells.size()).is_equal(0)


func test_decrypt_target_comes_from_the_seed_or_from_the_caller() -> void:
	var a := BreachRun.for_decrypt(2, 77, [], _data)
	var b := BreachRun.for_decrypt(2, 77, [], _data)
	assert_array(a.attempt.daemons[0].sequence).is_equal(b.attempt.daemons[0].sequence)
	var given := BreachRun.for_decrypt(1, 77, ["FF", "FF", "7A"], _data)
	assert_array(given.attempt.daemons[0].sequence).is_equal(["FF", "FF", "7A"])
	assert_int(given.attempt.buffer_size).is_equal(5)


func test_decrypt_can_be_completed_by_the_solver() -> void:
	for s in range(100):
		var r := BreachRun.for_decrypt(1 + s % 3, s, [], _data)
		_solve(r)
		r.resolve()
		assert_str(r.result).is_equal("SUCCESS")


func test_same_seed_same_run() -> void:
	var a := _storage(-1, 6, 99, "HARD")
	var b := _storage(-1, 6, 99, "HARD")
	assert_array(a.attempt.grid.cells).is_equal(b.attempt.grid.cells)


func test_ice_line_is_stable_for_the_run() -> void:
	var r := _storage(-1, 6, 5, "NIGHTMARE")
	var line := r.ice_line("TRAP")
	assert_str(line).is_not_empty()
	assert_str(r.ice_line("TRAP")).is_equal(line)
	assert_array(_data.ice_lines["NIGHTMARE"]["TRAP"]).contains([line])


func test_trap_tap_reports_ice_event_trap_before_match() -> void:
	# Ищем на NIGHTMARE ход, который попадает в ловушку: он доступен хотя бы на каком-то из первых шагов.
	for s in range(200):
		var r := BreachRun.for_storage("NIGHTMARE", [_daemon()], 6, s, _data)
		for cell in r.selectable():
			if r.attempt.grid.is_trap(cell):
				var res := r.tap(cell)
				assert_bool(res["hit_trap"]).is_true()
				assert_str(res["ice_event"]).is_equal("TRAP")
				return
	fail("за 200 сеток ни разу не попалась ловушка в верхней строке")


# --- замок: итог и признак lock_opened (breach.md 2.6) ---

func test_result_info_reports_lock_and_loot_before_it() -> void:
	var loot := BreachDaemon.make("a", ["1C", "E9"], "EXTRACT_SHARD")
	var g := BreachGrid.new()
	g.size = 3
	g.cells = [["1C", "55", "BD"], ["E9", "7A", "FF"], ["1C", "55", "BD"]]
	g.lock = ["7A", "55"]
	var run := BreachRun.from_attempt(BreachAttempt.make(g, [loot], 4, _data), 45, "BASE", BreachRun.MODE_STORAGE, 0, _data)
	var last := {}
	for c in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)]:
		last = run.tap(c)
	assert_bool(last["finished"]).is_true()
	assert_bool(last["lock_opened"]).is_true()
	var info := run.result_info()
	assert_str(info["outcome"]).is_equal("FAIL")   # добыча легла до замка — не засчитана
	assert_bool(info["lock_opened"]).is_true()
	assert_array(info["matched"]).is_empty()
	assert_array(info["matched_before_lock"]).is_equal(["a"])
