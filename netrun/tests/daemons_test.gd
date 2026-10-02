extends GdUnitTestSuite

var _svc: DaemonService


func before_test() -> void:
	_svc = DaemonService.new()
	assert_int(_svc.load_dir()).is_equal(3)


func _session(deck: Array = ["ghost_1", "jitter_1", "extract_shard_1"]) -> DaemonSession:
	var s := DaemonSession.new(deck)
	s.trace.tick(0.0)
	return s


func test_ghost_sets_flag_for_duration() -> void:
	var s := _session()
	var r := _svc.apply(s, "ghost_1", {}, 10.0)
	assert_bool(r["ok"]).is_true()
	assert_bool(s.is_ghost(29.9)).is_true()
	assert_bool(s.is_ghost(30.0)).is_false()
	assert_bool(s.is_ghost(5.0)).is_true()  # до применения флаг не «отматывается», но и не требуется


func test_jitter_freezes_trace() -> void:
	var s := _session()
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
	var s := _session()
	assert_bool(_svc.apply(s, "jitter_1", {}, 0.0)["ok"]).is_true()
	assert_str(_svc.apply(s, "jitter_1", {}, 44.0)["error"]).is_equal("cooldown")
	assert_bool(_svc.apply(s, "jitter_1", {}, 45.0)["ok"]).is_true()


func test_failed_apply_does_not_start_cooldown() -> void:
	var s := _session()
	_svc.apply(s, "extract_shard_1", {"type": "daemon"}, 0.0)
	assert_float(s.cooldown_left("extract_shard_1", 0.0)).is_equal(0.0)


func test_new_daemon_with_existing_effect_is_data_only() -> void:
	var def := DaemonDef.from_dict({"id": "ghost_2", "effect": "GHOST", "tier": 2, "cooldown_sec": 10.0, "params": {"duration_sec": 60.0}})
	assert_bool(_svc.add_def(def)).is_true()
	var s := _session(["ghost_2"])
	assert_bool(_svc.apply(s, "ghost_2", {}, 0.0)["ok"]).is_true()
	assert_bool(s.is_ghost(59.0)).is_true()


func test_unknown_effect_rejected_on_load() -> void:
	assert_bool(_svc.add_def(DaemonDef.from_dict({"id": "x", "effect": "TELEPORT"}))).is_false()
	assert_bool(_svc.add_def(DaemonDef.from_dict({"id": "x"}))).is_false()


func test_item_daemon_params_come_from_effect_and_tier() -> void:
	var d1 := _svc.add_item_daemon("it_1", {"effect": "GHOST", "tier": 1, "name": "Призрак"})
	var d3 := _svc.add_item_daemon("it_3", {"effect": "GHOST", "tier": 3, "name": "Призрак+"})
	assert_str(d1.unsupported_reason).is_empty()
	assert_float(d1.params["duration_sec"]).is_equal(20.0)
	assert_float(d3.params["duration_sec"]).is_equal(45.0)
	assert_float(d3.cooldown_sec).is_equal(50.0)
	assert_str(_svc.display_name("it_3")).is_equal("Призрак+")
	var s := _session(["it_3"])
	assert_bool(_svc.apply(s, "it_3", {}, 10.0)["ok"]).is_true()
	assert_bool(s.is_ghost(54.9)).is_true()
	assert_bool(s.is_ghost(55.0)).is_false()


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
