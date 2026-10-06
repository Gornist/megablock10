extends GdUnitTestSuite
## Клиентская копия попытки (BreachMirror, К3): сетка из события `bk`, подсветка по правилу строка/столбец без ожидания сервера, откат отклонённого
## тапа, порченые коды клиенту не выданы.

func test_mirror_builds_from_event_and_highlights_the_first_row() -> void:
	var m := BreachMirror.from_event(BreachTestUtil.make_bk_event())
	assert_object(m).is_not_null()
	assert_int(m.grid.size).is_equal(6)
	assert_int(m.buffer_size).is_equal(6)
	assert_int(m.left).is_equal(90)                              # таймер HARD в Взломе 2.0: 90 с (был 60)
	assert_str(m.ice_line).is_equal("ICE: тест")
	assert_int(m.targets.size()).is_equal(2)
	var avail := m.selectable()
	assert_int(avail.size()).is_equal(6)                       # первый выбор — любая клетка верхней строки
	for c in avail:
		assert_int(c.x).is_equal(0)


func test_mirror_rejects_a_broken_event() -> void:
	assert_object(BreachMirror.from_event({"kind": "bk"})).is_null()
	var ev := BreachTestUtil.make_bk_event()
	ev["targets"] = []
	assert_object(BreachMirror.from_event(ev)).is_null()


func test_tap_selects_locally_and_waits_for_the_server() -> void:
	var m := BreachMirror.from_event(BreachTestUtil.make_bk_event())
	assert_bool(m.tap(Vector2i(0, 2))).is_true()
	assert_bool(m.pending != null).is_true()
	assert_int(m.selectable().size()).is_equal(0)               # пока сервер не ответил, второй тап не уходит
	assert_bool(m.tap(Vector2i(1, 2))).is_false()
	m.apply_tick({"cell": [0, 2], "ok": true, "left": 59, "matched": []})
	assert_bool(m.pending == null).is_true()
	assert_int(m.left).is_equal(59)
	var next := m.selectable()                                   # вторая клетка — тот же столбец, кроме самой первой
	assert_int(next.size()).is_equal(5)
	for c in next:
		assert_int(c.y).is_equal(2)
		assert_bool(c != Vector2i(0, 2)).is_true()


func test_server_refusal_rolls_the_highlight_back() -> void:
	var m := BreachMirror.from_event(BreachTestUtil.make_bk_event())
	assert_bool(m.tap(Vector2i(0, 1))).is_true()
	m.apply_tick({"cell": [0, 1], "ok": false, "left": 58})
	assert_int(m.selected().size()).is_equal(0)
	assert_bool(m.pending == null).is_true()
	assert_int(m.selectable().size()).is_equal(6)                # подсветка вернулась


func test_unavailable_cell_is_not_sent() -> void:
	var m := BreachMirror.from_event(BreachTestUtil.make_bk_event())
	assert_bool(m.tap(Vector2i(3, 3))).is_false()                # не из верхней строки
	assert_bool(m.pending == null).is_true()
	assert_int(m.selected().size()).is_equal(0)


func test_trap_reply_is_remembered_and_matched_follow_the_server() -> void:
	var m := BreachMirror.from_event(BreachTestUtil.make_bk_event())
	m.tap(Vector2i(0, 0))
	m.apply_tick({"cell": [0, 0], "ok": true, "trap": true, "left": 50, "matched": ["d2"], "ice": "ICE: ловушка"})
	assert_bool(m.trap_hits.has(Vector2i(0, 0))).is_true()
	assert_bool(m.is_matched("d2")).is_true()
	assert_bool(m.is_matched("d1")).is_false()
	assert_str(m.ice_line).is_equal("ICE: ловушка")


func test_lock_decoys_and_lock_opened_come_from_the_server() -> void:
	# Взлом 2.0: сообщение старта несёт замок (внутри сетки) и приманки, ответ на тап и итог — lock_opened и «совпал до замка».
	for tier in ["BASE", "HARD", "NIGHTMARE"]:
		var ev := BreachTestUtil.make_bk_event(tier, 5)
		var m := BreachMirror.from_event(ev)
		var need := int(BreachData.shared().tier_params(tier)["lock_length"])
		assert_int(m.lock.size()).is_equal(need)
		assert_array(m.lock).is_equal(m.grid.lock)
		assert_array(m.attempt.lock()).is_equal(m.lock)            # зеркало считает правило замка так же, как сервер
		assert_bool(m.lock_opened).is_false()
		var traps: Vector2i = BreachData.shared().tier_params(tier)["lock_traps"]
		assert_int(m.decoys.size()).is_greater_equal(traps.x)
		assert_int(m.decoys.size()).is_less_equal(traps.y)
		for c in m.decoys:                                           # приманка — не мёртвая клетка, код обычный
			assert_bool(m.grid.is_dead(c)).is_false()
	var m2 := BreachMirror.from_event(BreachTestUtil.make_bk_event("HARD", 5))
	m2.tap(Vector2i(0, 0))
	m2.apply_tick({"cell": [0, 0], "ok": true, "trap": false, "left": 80, "matched": [], "lock_opened": true})
	assert_bool(m2.lock_opened).is_true()
	m2.apply_end({"outcome": "FAIL", "matched": [], "lock_opened": true, "matched_before_lock": ["d1"]})
	assert_array(m2.matched_before_lock).is_equal(["d1"])
	assert_bool(m2.lock_opened).is_true()


func test_mirror_and_server_have_the_same_selectable_after_every_step_of_a_lock_walk() -> void:
	# Зеркало на очках и попытка сервера идут одной дорогой (путь автосолвера через замок): доступные клетки совпадают после каждого шага.
	for tier in ["BASE", "HARD", "NIGHTMARE"]:
		for seed_value in range(15):
			var daemons := [BreachDaemon.make("d1", ["1C", "BD"], "EXTRACT_SHARD", 2, "Извлечение"), BreachDaemon.make("d2", ["55", "7A"], "GHOST", 1, "Призрак")]
			var need := int(BreachData.shared().tier_params(tier)["lock_length"]) + 4
			var run := BreachRun.for_storage(tier, daemons, maxi(6, need), seed_value)
			var m := BreachMirror.from_event(BreachTestUtil.make_bk_event(tier, seed_value))
			var path := BreachAutoSolver.solve(run.attempt)
			var at := "%s seed %d" % [tier, seed_value]
			assert_bool(path.size() > m.lock.size()).override_failure_message(at + ": путь короче замка").is_true()
			for c in path:
				assert_array(m.selectable()).override_failure_message(at + ": доступные до " + str(c)).is_equal(run.selectable())
				var r := run.tap(c)
				assert_bool(m.tap(c)).is_true()
				m.apply_tick({"cell": [c.x, c.y], "ok": r["ok"], "trap": r["hit_trap"], "left": run.seconds_left, "matched": run.attempt.matched_daemon_ids(), "lock_opened": r["lock_opened"]})
			assert_bool(run.attempt.lock_opened()).override_failure_message(at + ": замок не вскрыт").is_true()
			assert_bool(m.lock_opened).is_true()


func test_end_blocks_further_taps() -> void:
	var m := BreachMirror.from_event(BreachTestUtil.make_bk_event())
	m.apply_end({"outcome": "PARTIAL", "matched": ["d1"], "opened": ["v1"]})
	assert_bool(m.finished).is_true()
	assert_bool(m.tap(Vector2i(0, 0))).is_false()
	assert_array(m.matched).is_equal(["d1"])


func test_public_grid_hides_corrupted_codes_but_shows_dead_cells() -> void:
	# NIGHTMARE: 5–6 мёртвых клеток и 2–3 порченых кода. Клиенту уходят только мёртвые (по маркеру), порченых он не видит.
	for seed_value in range(20):
		var daemons := [BreachDaemon.make("d1", ["1C", "BD"], "EXTRACT_SHARD", 2, "И")]
		var run := BreachRun.for_storage("NIGHTMARE", daemons, 6, seed_value)
		var pub := VaultBreach.public_grid(run.attempt.grid)
		var dead := 0
		for c in run.attempt.grid.trap_cells:
			if run.attempt.grid.is_dead(c):
				dead += 1
		assert_int((pub["traps"] as Array).size()).is_equal(dead)
		assert_bool(pub.has("solution")).is_false()
		assert_bool((pub["traps"] as Array).size() < run.attempt.grid.trap_cells.size()).is_true()   # порченые не выданы


func test_auto_solver_finishes_every_grid_the_client_sees() -> void:
	# Бот и тесты решают сетку так, как её видит клиент (public_grid): без путей и порченых кодов. Хотя бы мёртвые клетки обходятся всегда.
	for tier in ["BASE", "HARD"]:
		for seed_value in range(60):
			var m := BreachMirror.from_event(BreachTestUtil.make_bk_event(tier, seed_value, 8))
			var path := BreachAutoSolver.solve(m.attempt)
			assert_bool(path.size() >= 4).override_failure_message("%s seed %d: путь %d" % [tier, seed_value, path.size()]).is_true()
			var a := m.attempt
			for c in path:
				assert_bool(a.select(c)).is_true()
			assert_int(a.matched_daemon_ids().size()).override_failure_message("%s seed %d" % [tier, seed_value]).is_equal(2)


func test_auto_solver_single_daemon_ram_eight() -> void:
	for seed_value in range(80):
		var d := BreachDaemon.make("d1", ["1C", "BD"], "EXTRACT_SHARD", 2, "И")
		var run := BreachRun.for_storage("BASE", [d], 8, seed_value)
		var ev := {"kind": WorldMsg.EV_BK, "vault": "v", "n": 1, "tier": "BASE", "grid": VaultBreach.public_grid(run.attempt.grid),
			"targets": [{"id": "d1", "name": "И", "effect": "EXTRACT_SHARD", "cells": ["1C", "BD"]}], "buffer": 8, "sec": 45}
		var m := BreachMirror.from_event(ev)
		var path := BreachAutoSolver.solve(m.attempt)
		assert_bool(path.size() >= 2).override_failure_message("seed %d: путь %d" % [seed_value, path.size()]).is_true()
