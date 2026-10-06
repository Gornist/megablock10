extends GdUnitTestSuite
## Правила взлома без состояния: чередование строка/столбец, совпадение подряд, исход (порт BreachEngineTest и BreachResult телефона).


func test_dimension_alternates_starting_with_column() -> void:
	assert_str(BreachRules.next_link_dimension(1)).is_equal("COLUMN")
	assert_str(BreachRules.next_link_dimension(2)).is_equal("ROW")
	assert_str(BreachRules.next_link_dimension(3)).is_equal("COLUMN")
	assert_str(BreachRules.next_link_dimension(4)).is_equal("ROW")


func test_candidates_are_same_column_or_row_without_visited() -> void:
	var visited := BreachRules.cell_set([Vector2i(0, 2), Vector2i(3, 2)])
	var col := BreachRules.candidates_for(Vector2i(3, 2), "COLUMN", 5, visited)
	assert_array(col).contains_exactly_in_any_order([Vector2i(1, 2), Vector2i(2, 2), Vector2i(4, 2)])
	var row := BreachRules.candidates_for(Vector2i(3, 2), "ROW", 5, visited)
	assert_array(row).contains_exactly_in_any_order([Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 3), Vector2i(3, 4)])


func test_resolve_requires_contiguous_and_in_order() -> void:
	var d := BreachDaemon.make("x", ["1C", "55"])
	assert_array(BreachRules.resolve_daemons(["BD", "1C", "55", "E9"], [d])).is_equal(["x"])
	assert_array(BreachRules.resolve_daemons(["1C", "E9", "55"], [d])).is_empty()  # разорвано
	assert_array(BreachRules.resolve_daemons(["55", "1C"], [d])).is_empty()        # не по порядку
	assert_array(BreachRules.resolve_daemons(["1C"], [d])).is_empty()              # короче цепочки


func test_partial_buffer_matches_only_daemons_that_already_fit() -> void:
	var a := BreachDaemon.make("a", ["1C", "55"])
	var b := BreachDaemon.make("b", ["BD", "E9", "7A"])
	assert_array(BreachRules.resolve_daemons(["1C", "55", "BD", "E9"], [a, b])).is_equal(["a"])


func test_overlapping_daemons_both_match() -> void:
	var a := BreachDaemon.make("a", ["1C", "55"])
	var b := BreachDaemon.make("b", ["55", "BD"])
	assert_array(BreachRules.resolve_daemons(["1C", "55", "BD"], [a, b])).is_equal(["a", "b"])


func test_outcome_success_partial_fail() -> void:
	var a := BreachDaemon.make("a", ["1C"])
	var b := BreachDaemon.make("b", ["55"])
	assert_str(BreachRules.outcome([a, b], ["a", "b"])).is_equal("SUCCESS")
	assert_str(BreachRules.outcome([a, b], ["b"])).is_equal("PARTIAL")
	assert_str(BreachRules.outcome([a, b], [])).is_equal("FAIL")
	# Без демонов успеха быть не может.
	assert_str(BreachRules.outcome([], [])).is_equal("FAIL")


# --- замок хранилища (breach.md 2.2) ---

func test_loot_counts_only_after_the_lock_and_traces_count_anywhere() -> void:
	var loot := BreachDaemon.make("e", ["BD", "E9"], "EXTRACT_SHARD")
	var ghost := BreachDaemon.make("g", ["BD", "E9"], "GHOST")
	var lock := ["1C", "55"]
	# Добыча легла до замка: не засчитана; следы — засчитаны.
	assert_array(BreachRules.resolve_daemons(["BD", "E9", "1C", "55"], [loot, ghost], lock)).is_equal(["g"])
	# Замок, потом добыча: засчитано всё.
	assert_array(BreachRules.resolve_daemons(["1C", "55", "BD", "E9"], [loot, ghost], lock)).is_equal(["e", "g"])
	# Замок не вскрыт: добыча не засчитана, следы засчитаны.
	assert_array(BreachRules.resolve_daemons(["BD", "E9"], [loot, ghost], lock)).is_equal(["g"])
	# Без замка — как раньше.
	assert_array(BreachRules.resolve_daemons(["BD", "E9"], [loot, ghost])).is_equal(["e", "g"])


func test_every_loot_effect_is_gated_by_the_lock_and_others_are_not() -> void:
	var lock := ["1C"]
	for effect in ["EXTRACT_SHARD", "EXTRACT_DAEMON", "MINER"]:
		assert_bool(BreachRules.is_loot(effect)).is_true()
		var d := BreachDaemon.make("x", ["55", "BD"], effect)
		assert_array(BreachRules.resolve_daemons(["55", "BD", "1C"], [d], lock)).is_empty()
		assert_array(BreachRules.resolve_daemons(["1C", "55", "BD"], [d], lock)).is_equal(["x"])
	for effect in ["GHOST", "TIMESKEW", "BLACKOUT", "JITTER", "DECRYPT"]:
		assert_bool(BreachRules.is_loot(effect)).is_false()
		var d := BreachDaemon.make("x", ["55", "BD"], effect)
		assert_array(BreachRules.resolve_daemons(["55", "BD"], [d], lock)).is_equal(["x"])


func test_loot_chain_may_not_overlap_the_lock() -> void:
	# Цепочка добычи целиком после замка: общий код с хвостом замка не считается.
	var loot := BreachDaemon.make("e", ["55", "BD"], "EXTRACT_SHARD")
	assert_array(BreachRules.resolve_daemons(["1C", "55", "BD"], [loot], ["1C", "55"])).is_empty()
	assert_array(BreachRules.resolve_daemons(["1C", "55", "55", "BD"], [loot], ["1C", "55"])).is_equal(["e"])


func test_lock_opened_at_and_a_trap_breaks_the_lock() -> void:
	var sentinel := BreachData.TRAP_SENTINEL
	assert_int(BreachRules.lock_opened_at(["BD", "1C", "55"], ["1C", "55"])).is_equal(3)
	assert_int(BreachRules.lock_opened_at(["1C", "BD", "55"], ["1C", "55"])).is_equal(-1)
	assert_int(BreachRules.lock_opened_at(["1C", sentinel, "55"], ["1C", "55"])).is_equal(-1)
	assert_int(BreachRules.lock_opened_at(["BD"], [])).is_equal(0)   # замка нет
	assert_int(BreachRules.lock_opened_at([], ["1C"])).is_equal(-1)
