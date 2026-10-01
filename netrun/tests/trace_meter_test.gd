extends GdUnitTestSuite

const L := TraceMeter.Level

var _events: Array = []


func _meter(settings: Dictionary = {}) -> TraceMeter:
	var m := TraceMeter.new(settings)
	m.level_changed.connect(func(o: int, n: int, _v: float) -> void: _events.append([o, n]))
	m.tick(0.0)
	return m


func before_test() -> void:
	_events = []


func test_starts_normal() -> void:
	var m := _meter()
	assert_int(m.level()).is_equal(L.NORMAL)
	assert_float(m.value()).is_equal(0.0)


func test_each_threshold_changes_level_once() -> void:
	var m := _meter({"weights": {"noise": 25.0}})
	for i in 4:
		m.add_action("noise", 0.0)
	assert_array(_events).is_equal([
		[L.NORMAL, L.SUSPICIOUS], [L.SUSPICIOUS, L.TRACE],
		[L.TRACE, L.LOCKDOWN], [L.LOCKDOWN, L.FLATLINE]])


func test_no_event_within_level() -> void:
	var m := _meter({"weights": {"noise": 5.0}})
	m.add_action("noise", 0.0)
	m.add_action("noise", 0.0)
	assert_array(_events).is_empty()


func test_boundary_values_belong_to_upper_level() -> void:
	var m := _meter()
	assert_int(m.level_for(24.9)).is_equal(L.NORMAL)
	assert_int(m.level_for(25.0)).is_equal(L.SUSPICIOUS)
	assert_int(m.level_for(50.0)).is_equal(L.TRACE)
	assert_int(m.level_for(75.0)).is_equal(L.LOCKDOWN)
	assert_int(m.level_for(100.0)).is_equal(L.FLATLINE)


func test_jump_over_levels_gives_single_event() -> void:
	var m := _meter()
	m.add_action("seen_by_ice", 0.0, 7.0)  # 56
	assert_array(_events).is_equal([[L.NORMAL, L.TRACE]])


func test_value_clamped_to_max() -> void:
	var m := _meter()
	m.add_action("noise", 0.0, 1000.0)
	assert_float(m.value()).is_equal(100.0)


func test_decay_over_time_and_event_downwards() -> void:
	var m := _meter()
	m.add_action("seen_by_ice", 0.0, 4.0)  # 32, SUSPICIOUS
	_events.clear()
	m.tick(7.0)  # -7 -> 25
	assert_array(_events).is_empty()
	m.tick(8.0)  # 24 -> NORMAL
	assert_array(_events).is_equal([[L.SUSPICIOUS, L.NORMAL]])


func test_decay_not_below_zero() -> void:
	var m := _meter()
	m.add_action("noise", 0.0)
	m.tick(1000.0)
	assert_float(m.value()).is_equal(0.0)


func test_no_decay_while_seen() -> void:
	var m := _meter()
	m.add_action("seen_by_ice", 0.0, 2.0)  # 16
	m.tick(10.0, false)
	assert_float(m.value()).is_equal(16.0)
	m.tick(15.0, true)
	assert_float(m.value()).is_equal(11.0)


func test_decay_uses_settings() -> void:
	var m := _meter({"decay_per_sec": 2.0})
	m.add_action("seen_by_ice", 0.0, 2.0)
	m.tick(3.0)
	assert_float(m.value()).is_equal(10.0)


func test_settings_override_thresholds_and_weights() -> void:
	var m := _meter({"suspicious_at": 5.0, "weights": {"noise": 6.0}})
	m.add_action("noise", 0.0)
	assert_int(m.level()).is_equal(L.SUSPICIOUS)


func test_freeze_stops_growth_and_decay() -> void:
	var m := _meter()
	m.add_action("seen_by_ice", 0.0, 2.0)  # 16
	m.freeze(0.0, 15.0)
	m.add_action("seen_by_ice", 5.0)
	assert_float(m.value()).is_equal(16.0)
	m.tick(15.0)
	assert_float(m.value()).is_equal(16.0)
	assert_bool(m.is_frozen(14.9)).is_true()
	assert_bool(m.is_frozen(15.0)).is_false()
	m.tick(20.0)  # после заморозки спад идёт: 5 с
	assert_float(m.value()).is_equal(11.0)


func test_decay_across_freeze_end_counts_only_unfrozen_part() -> void:
	var m := _meter()
	m.add_action("seen_by_ice", 0.0, 2.0)  # 16
	m.freeze(0.0, 10.0)
	m.tick(14.0)  # спадает только 4 с
	assert_float(m.value()).is_equal(12.0)


func test_flatline_is_latched_until_reset() -> void:
	var m := _meter()
	m.add_action("noise", 0.0, 1000.0)
	m.tick(500.0)
	assert_int(m.level()).is_equal(L.FLATLINE)
	_events.clear()
	m.reset(500.0)
	assert_int(m.level()).is_equal(L.NORMAL)
	assert_array(_events).is_empty()


func test_event_carries_value() -> void:
	var m := TraceMeter.new()
	var got: Array = []
	m.level_changed.connect(func(o: int, n: int, v: float) -> void: got.append([o, n, v]))
	m.add_action("seen_by_ice", 0.0, 4.0)
	assert_array(got).is_equal([[L.NORMAL, L.SUSPICIOUS, 32.0]])
