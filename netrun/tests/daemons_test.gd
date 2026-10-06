extends GdUnitTestSuite

var _svc: DaemonService


func before_test() -> void:
	_svc = DaemonService.new()
	assert_int(_svc.load_dir()).is_equal(3)


## Заряженная сессия: защитный демон вне взлома срабатывает только после заряда (К6).


func _session(deck: Array = ["ghost_1", "jitter_1", "extract_shard_1"]) -> DaemonSession:
	var s := DaemonSession.new(deck)
	s.trace.tick(0.0)
	return s


## Сессия, где все защитные демоны деки уже заряжены (заряд — отдельный тест).
func _charged(deck: Array = ["ghost_1", "jitter_1", "extract_shard_1"]) -> DaemonSession:
	var s := _session(deck)
	for id in deck:
		if _svc.is_chargeable(id):
			s.set_charged(id)
	return s


func test_ghost_sets_flag_for_duration() -> void:
	var s := _charged()
	var r := _svc.apply(s, "ghost_1", {}, 10.0)
	assert_bool(r["ok"]).is_true()
	assert_bool(s.is_ghost(29.9)).is_true()
	assert_bool(s.is_ghost(30.0)).is_false()
	assert_bool(s.is_ghost(5.0)).is_true()  # до применения флаг не «отматывается», но и не требуется


func test_active_effects_lists_ghost_only_while_active() -> void:
	var s := _charged()
	assert_array(s.active_effects(5.0)).is_empty()
	_svc.apply(s, "ghost_1", {}, 10.0)
	assert_array(s.active_effects(15.0)).is_equal(["GHOST"])
	assert_array(s.active_effects(30.0)).is_empty()


func test_jitter_freezes_trace() -> void:
	var s := _charged()
	s.trace.add_action("noise", 1.0)  # 3
	var r := _svc.apply(s, "jitter_1", {}, 1.0)
	assert_bool(r["ok"]).is_true()
	assert_bool(s.trace.is_frozen(15.9)).is_true()
	assert_bool(s.trace.is_frozen(16.0)).is_false()
	s.trace.add_action("noise", 5.0)  # заморожено — рост игнорируется
	assert_float(s.trace.value()).is_equal(3.0)


func test_extract_shard_adds_loot_event_only() -> void:
	var s := _session()
	var r := _svc.apply(s, "extract_shard_1", {"id": "shard_a", "type": "shard", "tier": 1}, 0.0)
	assert_bool(r["ok"]).is_true()
	assert_str(r["event"]["item"]).is_equal("shard_a")
	assert_int(s.loot.size()).is_equal(1)


func test_extract_shard_bad_targets() -> void:
	var s := _session()
	assert_str(_svc.apply(s, "extract_shard_1", {"id": "d", "type": "daemon"}, 0.0)["error"]).is_equal("bad_target")
	assert_str(_svc.apply(s, "extract_shard_1", {"id": "s", "type": "shard", "tier": 3}, 0.0)["error"]).is_equal("tier_too_high")
	assert_bool(_svc.apply(s, "extract_shard_1", {"id": "s", "type": "shard", "tier": 1}, 0.0)["ok"]).is_true()
	assert_str(_svc.apply(s, "extract_shard_1", {"id": "s", "type": "shard", "tier": 1}, 100.0)["error"]).is_equal("already_taken")
	assert_int(s.loot.size()).is_equal(1)


func test_not_in_deck_and_unknown() -> void:
	var s := _session(["jitter_1"])
	assert_str(_svc.apply(s, "ghost_1", {}, 0.0)["error"]).is_equal("not_in_deck")
	assert_str(_svc.apply(s, "nope", {}, 0.0)["error"]).is_equal("unknown_daemon")
	assert_bool(s.is_ghost(1.0)).is_false()


func test_cooldown_blocks_then_releases() -> void:
	var s := _charged()
	assert_bool(_svc.apply(s, "jitter_1", {}, 0.0)["ok"]).is_true()
	assert_str(_svc.apply(s, "jitter_1", {}, 44.0)["error"]).is_equal("cooldown")
	s.set_charged("jitter_1")   # заряд ушёл с запуском: после перезарядки нужен новый
	assert_bool(_svc.apply(s, "jitter_1", {}, 45.0)["ok"]).is_true()


func test_failed_apply_does_not_start_cooldown() -> void:
	var s := _session()
	_svc.apply(s, "extract_shard_1", {"type": "daemon"}, 0.0)
	assert_float(s.cooldown_left("extract_shard_1", 0.0)).is_equal(0.0)


func test_new_daemon_with_existing_effect_is_data_only() -> void:
	var def := DaemonDef.from_dict({"id": "ghost_2", "effect": "GHOST", "tier": 2, "cooldown_sec": 10.0, "params": {"duration_sec": 60.0}})
	assert_bool(_svc.add_def(def)).is_true()
	var s := _charged(["ghost_2"])
	assert_bool(_svc.apply(s, "ghost_2", {}, 0.0)["ok"]).is_true()
	assert_bool(s.is_ghost(59.0)).is_true()


func test_unknown_effect_rejected_on_load() -> void:
	assert_bool(_svc.add_def(DaemonDef.from_dict({"id": "x", "effect": "TELEPORT"}))).is_false()
	assert_bool(_svc.add_def(DaemonDef.from_dict({"id": "x"}))).is_false()


func test_item_daemon_params_come_from_effect_and_tier() -> void:
	var d1 := _svc.add_item_daemon("it_1", {"effect": "GHOST", "tier": 1, "name": "Призрак"})
	var d3 := _svc.add_item_daemon("it_3", {"effect": "GHOST", "tier": 3, "name": "Призрак+"})
	assert_str(d1.unsupported_reason).is_empty()
	assert_float(d1.params["duration_sec"]).is_equal(10.0)   # W1-Ч1: Призрак 10 / 15 / 20 с, перезарядка 60 с
	assert_float(d3.params["duration_sec"]).is_equal(20.0)
	assert_float(d3.cooldown_sec).is_equal(60.0)
	assert_str(_svc.display_name("it_3")).is_equal("Призрак+")
	var s := _charged(["it_3"])
	assert_bool(_svc.apply(s, "it_3", {}, 10.0)["ok"]).is_true()
	assert_bool(s.is_ghost(29.9)).is_true()
	assert_bool(s.is_ghost(30.0)).is_false()


func test_item_daemon_without_effect_in_net_is_visible_but_refused() -> void:
	var def := _svc.add_item_daemon("it_m", {"effect": "MINER", "tier": 1, "name": "Майнер"})
	assert_str(def.unsupported_reason).contains("MINER")
	var s := _session(["it_m"])
	var r := _svc.apply(s, "it_m", {}, 0.0)
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal("effect_unsupported")
	assert_str(r["reason"]).is_not_empty()
	assert_object(_svc.add_item_daemon("it_x", {"tier": 1})).is_null()
	assert_str(_svc.add_item_daemon("it_y", {"effect": "НЕТ", "tier": 1}).unsupported_reason).is_not_empty()


# ---------------------------------------------------------------- заряд и окна TIMESKEW / BLACKOUT (К6)

func test_protective_daemon_needs_a_charge_and_the_charge_is_spent_by_one_launch() -> void:
	var s := _session()
	assert_str(_svc.apply(s, "ghost_1", {}, 0.0)["error"]).is_equal("not_charged")
	assert_bool(s.is_ghost(1.0)).is_false()
	assert_float(s.cooldown_left("ghost_1", 0.0)).is_equal(0.0)   # отказ перезарядку не запускает
	s.set_charged("ghost_1")
	assert_bool(s.is_charged("ghost_1")).is_true()
	assert_bool(_svc.apply(s, "ghost_1", {}, 0.0)["ok"]).is_true()
	assert_bool(s.is_charged("ghost_1")).is_false()
	assert_float(s.cooldown_left("ghost_1", 0.0)).is_equal(60.0)
	assert_str(_svc.apply(s, "ghost_1", {}, 100.0)["error"]).is_equal("not_charged")   # перезарядка кончилась, а заряда нет


func test_charge_check_refuses_with_a_reason() -> void:
	var s := _session()
	assert_str(_svc.charge_check(s, "nope", 0.0)).is_equal("unknown_daemon")
	assert_str(_svc.charge_check(_session(["jitter_1"]), "ghost_1", 0.0)).is_equal("not_in_deck")
	assert_str(_svc.charge_check(s, "extract_shard_1", 0.0)).is_equal("not_chargeable")
	assert_str(_svc.charge_check(s, "ghost_1", 0.0)).is_empty()
	s.set_charged("ghost_1")
	assert_str(_svc.charge_check(s, "ghost_1", 0.0)).is_equal("already_charged")
	_svc.apply(s, "ghost_1", {}, 10.0)
	assert_str(_svc.charge_check(s, "ghost_1", 20.0)).is_equal("cooldown")   # сначала перезарядка, потом снова заряд
	assert_str(_svc.charge_check(s, "ghost_1", 70.0)).is_empty()
	var m := _svc.add_item_daemon("it_m", {"effect": "MINER", "tier": 1, "name": "Майнер"})
	assert_str(_svc.charge_check(_session(["it_m"]), m.id, 0.0)).is_equal("effect_unsupported")


func test_only_protective_effects_are_chargeable() -> void:
	for e in ["GHOST", "JITTER", "TIMESKEW", "BLACKOUT"]:
		assert_bool(DaemonEffects.is_chargeable(e)).is_true()
	for e in ["EXTRACT_SHARD", "EXTRACT_DAEMON", "MINER", "DECRYPT"]:
		assert_bool(DaemonEffects.is_chargeable(e)).is_false()


func test_timeskew_and_blackout_windows_come_from_effect_files_by_tier() -> void:
	var t1 := _svc.add_item_daemon("it_t1", {"effect": "TIMESKEW", "tier": 1, "name": "Сдвиг"})
	var t3 := _svc.add_item_daemon("it_t3", {"effect": "TIMESKEW", "tier": 3, "name": "Сдвиг+"})
	var b1 := _svc.add_item_daemon("it_b1", {"effect": "BLACKOUT", "tier": 1, "name": "Затмение"})
	for d in [t1, t3, b1]:
		assert_str(d.unsupported_reason).is_empty()
	assert_float(t1.params["duration_sec"]).is_equal(30.0)
	assert_float(t3.params["duration_sec"]).is_equal(50.0)
	assert_float(b1.params["duration_sec"]).is_equal(8.0)
	assert_float(b1.cooldown_sec).is_equal(240.0)   # BLACKOUT: короткое окно, длинная перезарядка
	assert_bool(b1.cooldown_sec > b1.params["duration_sec"] * 10.0).is_true()


func test_timeskew_window_opens_for_its_duration_and_is_reported_active() -> void:
	_svc.add_item_daemon("it_t1", {"effect": "TIMESKEW", "tier": 1, "name": "Сдвиг"})
	var s := _charged(["it_t1"])
	assert_array(s.active_effects(5.0)).is_empty()
	assert_bool(_svc.apply(s, "it_t1", {}, 10.0)["ok"]).is_true()
	assert_array(s.active_effects(10.0)).is_equal(["TIMESKEW"])
	assert_array(s.active_effects(39.9)).is_equal(["TIMESKEW"])
	assert_array(s.active_effects(40.0)).is_empty()
	assert_float(s.active_left("TIMESKEW", 25.0)).is_equal_approx(15.0, 0.001)
	assert_float(s.active_left("TIMESKEW", 50.0)).is_equal(0.0)


func test_blackout_window_is_short_and_the_active_list_has_all_three_in_order() -> void:
	_svc.add_item_daemon("it_b1", {"effect": "BLACKOUT", "tier": 1, "name": "Затмение"})
	_svc.add_item_daemon("it_t1", {"effect": "TIMESKEW", "tier": 1, "name": "Сдвиг"})
	var s := _charged(["ghost_1", "it_t1", "it_b1"])
	for id in ["ghost_1", "it_t1", "it_b1"]:
		assert_bool(_svc.apply(s, id, {}, 0.0)["ok"]).is_true()
	assert_array(s.active_effects(1.0)).is_equal(["GHOST", "TIMESKEW", "BLACKOUT"])
	assert_array(s.active_effects(9.0)).is_equal(["GHOST", "TIMESKEW"])   # BLACKOUT тира 1: 8 с
	assert_array(s.active_effects(21.0)).is_equal(["TIMESKEW"])
	assert_array(s.active_effects(31.0)).is_empty()


func test_an_early_relaunch_extends_the_window_never_shortens_it() -> void:
	_svc.add_item_daemon("it_t1", {"effect": "TIMESKEW", "tier": 1, "name": "Сдвиг"})
	var s := _charged(["it_t1"])
	_svc.apply(s, "it_t1", {}, 0.0)
	s.timeskew_until = 100.0   # окно уже длиннее, чем даст новый запуск
	s.start_cooldown("it_t1", 0.0, 0.0)
	s.set_charged("it_t1")
	_svc.apply(s, "it_t1", {}, 10.0)
	assert_float(s.timeskew_until).is_equal(100.0)
