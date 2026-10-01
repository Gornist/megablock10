extends GdUnitTestSuite


func test_hold_fires_once_after_three_seconds() -> void:
	var s := ExitLogic.hold_new()
	s = ExitLogic.hold_step(s, true, 1.0)
	assert_float(s["progress"]).is_equal_approx(1.0 / 3.0, 0.001)
	assert_bool(s["just_fired"]).is_false()
	s = ExitLogic.hold_step(s, true, 1.9)
	assert_bool(s["fired"]).is_false()
	s = ExitLogic.hold_step(s, true, 0.2)
	assert_bool(s["just_fired"]).is_true()
	assert_float(s["progress"]).is_equal(1.0)
	s = ExitLogic.hold_step(s, true, 1.0)
	assert_bool(s["just_fired"]).is_false()
	assert_bool(s["fired"]).is_true()


func test_release_resets_hold() -> void:
	var s := ExitLogic.hold_step(ExitLogic.hold_new(), true, 2.5)
	s = ExitLogic.hold_step(s, false, 0.1)
	assert_float(s["held"]).is_equal(0.0)
	s = ExitLogic.hold_step(s, true, 2.5)
	assert_bool(s["fired"]).is_false()


func test_client_reasons() -> void:
	assert_bool(ExitLogic.is_client_reason("manual_hold")).is_true()
	assert_bool(ExitLogic.is_client_reason("headset_off")).is_true()
	assert_bool(ExitLogic.is_client_reason("connection_lost")).is_false()
	assert_bool(ExitLogic.is_client_reason("whatever")).is_false()


func test_event_deck_burned_only_under_hunt() -> void:
	assert_bool(ExitLogic.build_event("a", "manual_hold", false)["deck_burned"]).is_false()
	var e := ExitLogic.build_event("a", "headset_off", true)
	assert_bool(e["deck_burned"]).is_true()
	assert_str(e["reason"]).is_equal("headset_off")
