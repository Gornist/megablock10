extends GdUnitTestSuite
## Риг: пауза приложения и потеря фокуса не выкидывают игрока сразу. Выход с причиной headset_off — только если не вернулся за 15 с.
## Время подаётся в вызовы (в игре — Time.get_ticks_msec()); сигналы OpenXR и уведомления Android сводятся к тем же away_begin/away_end.

const S := 1000
var _reasons: Array = []
var _events: Array = []


func _rig() -> XRRig:
	var scene: Node3D = auto_free(preload("res://client/rig_test_scene.gd").new())
	add_child(scene)
	_reasons = []
	_events = []
	scene.rig.exit_requested.connect(func(reason: String): _reasons.append(reason))
	scene.rig.away_event.connect(func(kind: String, source: String, _sec: float): _events.append("%s:%s" % [kind, source]))
	return scene.rig


func test_a_short_pause_does_not_exit() -> void:
	var rig := _rig()
	rig.away_begin("pause", 0)
	rig.away_end("pause", 11 * S)       # как в сессии 4 октября: спал 11,3 с
	assert_array(_reasons).is_empty()
	assert_array(_events).is_equal(["begin:pause", "end:pause"])


func test_a_long_pause_exits_with_headset_off_when_the_player_returns() -> void:
	var rig := _rig()
	rig.away_begin("pause", 0)
	rig.away_end("pause", 16 * S)
	assert_array(_reasons).is_equal([ExitLogic.REASON_HEADSET_OFF])
	assert_array(_events).is_equal(["begin:pause", "end:pause", "exit:pause"])


func test_losing_focus_for_less_than_the_window_does_not_exit() -> void:
	var rig := _rig()
	rig.away_begin("focus", 0)          # системное меню поверх игры
	rig.away_tick(10 * S)
	rig.away_end("focus", 12 * S)
	rig.away_tick(40 * S)
	assert_array(_reasons).is_empty()


func test_staying_unfocused_longer_than_the_window_exits_without_waiting_for_return() -> void:
	var rig := _rig()
	rig.away_begin("focus", 0)
	rig.away_tick(14 * S)
	assert_array(_reasons).is_empty()
	rig.away_tick(15 * S)
	rig.away_tick(16 * S)
	assert_array(_reasons).is_equal([ExitLogic.REASON_HEADSET_OFF])     # один раз
	assert_bool(_events.has("exit:timeout")).is_true()


func test_taking_the_headset_off_and_putting_it_back_quickly_keeps_the_run() -> void:
	var rig := _rig()
	rig.away_begin("presence", 0)
	rig.away_begin("pause", 1 * S)
	rig.away_end("pause", 9 * S)
	rig.away_end("presence", 9 * S + 200)
	assert_array(_reasons).is_empty()


func test_returning_without_leaving_is_ignored() -> void:
	var rig := _rig()
	rig.away_end("focus", 500)          # session_focussed на старте, до любого session_visible
	assert_array(_reasons).is_empty()
	assert_array(_events).is_empty()


func test_holding_the_exit_button_still_exits_at_once() -> void:
	var rig := _rig()
	for i in 300:
		rig._update_exit_hold(0.02)     # прежний путь выхода не затронут: удержание кнопки
		if not _reasons.is_empty():
			break
	rig.exit_requested.emit(ExitLogic.REASON_MANUAL_HOLD)
	assert_bool(_reasons.has(ExitLogic.REASON_MANUAL_HOLD)).is_true()
