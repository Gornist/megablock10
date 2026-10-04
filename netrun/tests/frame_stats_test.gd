extends GdUnitTestSuite
## Долгий кадр — пропуск обновления экрана, а не дрожание таймера на доли миллисекунды (сессия на Pico 4 4 октября 2026:
## 372 строки frame.slow при ровных 72 Гц). Сводка `perf` за окно: кадров, среднее/наибольшее время, долгих.


func test_jitter_around_the_refresh_period_is_not_slow() -> void:
	for ms in [13.89, 14.29, 14.58, 16.59, 17.3]:
		assert_bool(FrameStats.is_slow(ms / 1000.0)).is_false()


func test_a_missed_refresh_is_slow() -> void:
	for ms in [17.5, 19.44, 23.18, 27.8, 144.45]:
		assert_bool(FrameStats.is_slow(ms / 1000.0)).is_true()


func test_limit_is_a_quarter_over_the_period() -> void:
	assert_float(FrameStats.SLOW_SEC * 1000.0).is_equal_approx(17.36, 0.01)


func test_take_summarises_the_window_and_resets_it() -> void:
	var st := FrameStats.new()
	for ms in [13.89, 13.89, 19.44, 13.89]:
		st.add(ms / 1000.0)
	var r := st.take()
	assert_int(r["frames"]).is_equal(4)
	assert_int(r["slow"]).is_equal(1)
	assert_float(r["max_ms"]).is_equal_approx(19.44, 0.01)
	assert_float(r["avg_ms"]).is_equal_approx(15.28, 0.01)
	var next := st.take()
	assert_int(next["frames"]).is_equal(0)
	assert_int(next["slow"]).is_equal(0)
	assert_float(next["avg_ms"]).is_equal(0.0)
	assert_float(next["max_ms"]).is_equal(0.0)
