extends GdUnitTestSuite
## Состояние очков (P6): окно кадров, «пора слать», связь по RTT, заряд, поля сообщения.


func test_window_average_fps_and_worst_frame() -> void:
	var w := BeatStats.new()
	for i in 10:
		w.add_frame(0.01)
	w.add_frame(0.1)  # один долгий кадр
	var r := w.take()
	assert_int(r["fps"]).is_equal(55)  # 11 кадров за 0.2 с
	assert_int(r["worst_ms"]).is_equal(100)
	var empty := w.take()  # окно обнулилось
	assert_int(empty["fps"]).is_equal(0)
	assert_int(empty["worst_ms"]).is_equal(0)


func test_window_ignores_nonpositive_delta() -> void:
	var w := BeatStats.new()
	w.add_frame(0.0)
	w.add_frame(-1.0)
	assert_int(w.take()["fps"]).is_equal(0)


func test_due() -> void:
	assert_bool(BeatStats.due(1000, -1, 5000)).is_true()
	assert_bool(BeatStats.due(5999, 1000, 5000)).is_false()
	assert_bool(BeatStats.due(6000, 1000, 5000)).is_true()
	assert_bool(BeatStats.due(500, 1000, 5000)).is_false()  # часы пошли назад


func test_server_gap_is_shorter_than_period() -> void:
	assert_int(BeatStats.server_gap_ms(5.0)).is_equal(4000)


func test_link_from_rtt() -> void:
	assert_int(BeatStats.link_from_rtt(-1)).is_equal(-1)
	assert_int(BeatStats.link_from_rtt(5)).is_equal(100)
	assert_int(BeatStats.link_from_rtt(20)).is_equal(100)
	assert_int(BeatStats.link_from_rtt(160)).is_equal(50)
	assert_int(BeatStats.link_from_rtt(300)).is_equal(0)
	assert_int(BeatStats.link_from_rtt(5000)).is_equal(0)


func test_battery_pct() -> void:
	assert_int(BeatStats.battery_pct(null)).is_equal(-1)
	assert_int(BeatStats.battery_pct("80")).is_equal(-1)
	assert_int(BeatStats.battery_pct(80)).is_equal(80)
	assert_int(BeatStats.battery_pct(79.6)).is_equal(80)
	assert_int(BeatStats.battery_pct(101)).is_equal(-1)
	assert_int(BeatStats.battery_pct(-3)).is_equal(-1)


func test_make_fields_skips_missing() -> void:
	assert_dict(BeatStats.make_fields("t03", -1, null, 72, 30, -1)).is_equal({"term": "t03", "fps": 72, "worst": 30})
	assert_dict(BeatStats.make_fields("t03", 80, true, 72, 30, 12)).is_equal({"term": "t03", "fps": 72, "worst": 30, "bat": 80, "chg": true, "rtt": 12})


func test_battery_probe_without_sensor_is_null() -> void:
	var p := BatteryProbe.new()
	var r := p.read()  # на ПК датчика нет
	assert_object(r["percent"]).is_null()
	assert_object(r["charging"]).is_null()
	p.provider = func(): return {"percent": 55, "charging": false}
	assert_dict(p.read()).is_equal({"percent": 55, "charging": false})


func test_config_terminal_id_and_beat_arg() -> void:
	var c := NetConfig.from_args(PackedStringArray(["--token=t03:секрет", "--beat=2.5"]))
	assert_str(c.terminal_id()).is_equal("t03")
	assert_float(c.beat_sec).is_equal(2.5)
	assert_str(NetConfig.from_args(PackedStringArray(["--token=t1"])).terminal_id()).is_empty()
	assert_float(NetConfig.new().beat_sec).is_equal(5.0)
