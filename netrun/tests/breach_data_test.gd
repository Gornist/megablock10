extends GdUnitTestSuite
## Числа и реплики движка взлома: data/rules/breach.json. Сами значения сверяет с константами Kotlin-тест :rules (задача К0);
## здесь — что файл читается, полон и содержит числа телефона (опорные значения продублированы, чтобы тихая правка файла краснила и этот тест).


func before_test() -> void:
	BreachData.reset_shared()


func after_test() -> void:
	BreachData.reset_shared()


func test_default_data_loads_without_errors() -> void:
	var d := BreachData.shared()
	assert_array(d.errors()).is_empty()
	assert_str(d.source).is_not_empty()


func test_data_comes_from_the_final_file() -> void:
	assert_str(BreachData.shared().source).is_equal(BreachData.PATH)


func test_tier_params_match_the_phone() -> void:
	var d := BreachData.shared()
	var base := d.tier_params("BASE")
	assert_int(base["grid_size"]).is_equal(5)
	assert_int(base["timer_sec"]).is_equal(45)
	assert_object(base["dead_cells"]).is_equal(Vector2i(0, 0))
	var hard := d.tier_params("HARD")
	assert_int(hard["grid_size"]).is_equal(6)
	assert_int(hard["timer_sec"]).is_equal(60)
	assert_object(hard["dead_cells"]).is_equal(Vector2i(2, 3))
	assert_object(hard["corrupted_codes"]).is_equal(Vector2i(0, 0))
	var nm := d.tier_params("NIGHTMARE")
	assert_int(nm["grid_size"]).is_equal(7)
	assert_int(nm["timer_sec"]).is_equal(75)
	assert_object(nm["dead_cells"]).is_equal(Vector2i(5, 6))
	assert_object(nm["corrupted_codes"]).is_equal(Vector2i(2, 3))


func test_global_constants_match_the_phone() -> void:
	var d := BreachData.shared()
	assert_array(d.alphabet).is_equal(["1C", "55", "BD", "E9", "7A", "FF"])
	assert_str(d.dead_marker).is_equal("××")
	assert_int(d.jitter_bonus_sec).is_equal(15)
	assert_int(d.cooldown_minutes).is_equal(30)
	assert_array(d.decrypt_target_length).is_equal([3, 4, 5])
	assert_int(d.decrypt_buffer_extra).is_equal(2)
	assert_int(d.events_min_timer_sec).is_equal(20)
	assert_int(d.low_time_sec).is_equal(10)
	assert_int(d.warning_sec).is_equal(5)


func test_decrypt_length_by_shard_tier_with_fallback() -> void:
	var d := BreachData.shared()
	assert_int(d.decrypt_length(1)).is_equal(3)
	assert_int(d.decrypt_length(2)).is_equal(4)
	assert_int(d.decrypt_length(3)).is_equal(5)
	assert_int(d.decrypt_length(0)).is_equal(3)
	assert_int(d.decrypt_length(9)).is_equal(3)


func test_unknown_tier_falls_back_to_base() -> void:
	var d := BreachData.shared()
	assert_int(d.tier_params("ULTRA")["grid_size"]).is_equal(5)
	assert_str(BreachData.tier_name(2)).is_equal("HARD")
	assert_str(BreachData.tier_name(7)).is_equal("BASE")


func test_ice_line_comes_from_the_pool_and_is_stable_per_seed() -> void:
	var d := BreachData.shared()
	for tier in BreachData.TIER_NAMES:
		for ev in BreachData.EVENT_NAMES:
			var line := d.ice_line(tier, ev, 42)
			assert_str(line).is_not_empty()
			assert_array(d.ice_lines[tier][ev]).contains([line])
			assert_str(d.ice_line(tier, ev, 42)).is_equal(line)


func test_missing_file_is_reported() -> void:
	var d := BreachData.load_file("res://data/rules/нет_такого.json")
	assert_array(d.errors()).is_not_empty()


func test_errors_catch_a_broken_tier() -> void:
	var d := BreachData.from_dict({"alphabet": ["1C", "55"], "dead_marker": "xx", "trap_sentinel": " ", "tiers": {}})
	assert_bool(d.errors().size() > 0).is_true()
