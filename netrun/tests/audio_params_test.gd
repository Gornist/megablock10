extends GdUnitTestSuite

const L := TraceMeter.Level
const S := IceBrain.State


func test_trace_louder_and_higher_with_level() -> void:
	var prev := AudioParams.trace_params(L.NORMAL)
	for lv in [L.SUSPICIOUS, L.TRACE, L.LOCKDOWN]:
		var cur := AudioParams.trace_params(lv)
		assert_float(cur["volume_db"]).is_greater(prev["volume_db"])
		assert_float(cur["base_hz"]).is_greater(prev["base_hz"])
		assert_float(cur["pulse_hz"]).is_greater_equal(prev["pulse_hz"])
		prev = cur


func test_trace_flatline_background_vanishes() -> void:
	assert_float(AudioParams.trace_params(L.FLATLINE)["volume_db"]).is_less(-60.0)


func test_trace_unknown_level_clamped() -> void:
	assert_dict(AudioParams.trace_params(99)).is_equal(AudioParams.trace_params(L.FLATLINE))
	assert_dict(AudioParams.trace_params(-1)).is_equal(AudioParams.trace_params(L.NORMAL))


func test_ice_quieter_with_distance() -> void:
	var a := AudioParams.ice_params(S.PATROL, 2.0)["volume_db"] as float
	var b := AudioParams.ice_params(S.PATROL, 8.0)["volume_db"] as float
	assert_float(a).is_greater(b)


func test_ice_inaudible_beyond_far_and_full_when_near() -> void:
	var far: float = AudioSettings.DEFAULTS["ice"]["far_m"]
	assert_bool(AudioParams.ice_params(S.SEARCH, far + 1.0)["audible"]).is_false()
	assert_bool(AudioParams.ice_params(S.SEARCH, 1.0)["audible"]).is_true()
	assert_float(AudioParams.ice_params(S.PATROL, 0.0)["volume_db"]).is_equal(AudioSettings.DEFAULTS["ice"]["max_db"])


func test_ice_state_raises_pitch_and_volume() -> void:
	var p := AudioParams.ice_params(S.PATROL, 5.0)
	var s := AudioParams.ice_params(S.SUSPICIOUS, 5.0)
	var r := AudioParams.ice_params(S.SEARCH, 5.0)
	assert_float(s["base_hz"]).is_greater(p["base_hz"])
	assert_float(r["base_hz"]).is_greater(s["base_hz"])
	assert_float(r["volume_db"]).is_greater(p["volume_db"])


func test_settings_override_merges() -> void:
	var st := AudioSettings.merged({"ice": {"far_m": 30.0}})
	assert_float(st["ice"]["far_m"]).is_equal(30.0)
	assert_float(st["ice"]["near_m"]).is_equal(AudioSettings.DEFAULTS["ice"]["near_m"])
	assert_bool(AudioParams.ice_params(S.PATROL, 20.0, st)["audible"]).is_true()


func test_flatline_sound_falls_then_goes_silent() -> void:
	var start := AudioParams.flatline_params(0.0)
	var mid := AudioParams.flatline_params(0.8)
	var late := AudioParams.flatline_params(1.5)
	assert_bool(start["active"]).is_true()
	assert_float(mid["hz"]).is_less(start["hz"])
	assert_float(late["hz"]).is_less(mid["hz"])
	assert_float(late["volume_db"]).is_less(start["volume_db"])
	var done := AudioParams.flatline_params(AudioSettings.DEFAULTS["flatline"]["duration_s"])
	assert_bool(done["active"]).is_false()
	assert_bool(AudioParams.flatline_params(-1.0)["active"]).is_false()


func test_ice_hunt_state_is_loudest_and_lowest() -> void:
	var s := AudioParams.ice_params(IceBrain.State.SEARCH, 5.0)
	var h := AudioParams.ice_params(IceBrain.State.HUNT, 5.0)
	assert_float(h["volume_db"]).is_greater(s["volume_db"])
	assert_float(h["base_hz"]).is_less(s["base_hz"])
