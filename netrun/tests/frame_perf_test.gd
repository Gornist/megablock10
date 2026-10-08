extends GdUnitTestSuite
## Счётчик кадра для стенда на очках (client/frame_perf.gd): сводка за окно, формат строки, конфиг [render] perf.


func test_сводка_окна_кадры_среднее_максимум_и_gpu() -> void:
	var s := FramePerf.summarize(360, 4000.0, 20.0, 5.0, 1800.0, 360, 9.0)
	assert_float(s["fps"]).is_equal_approx(72.0, 0.05)
	assert_float(s["avg_ms"]).is_equal_approx(11.11, 0.01)
	assert_float(s["max_ms"]).is_equal_approx(20.0, 0.01)
	assert_bool(s["over_budget"]).is_false()   # 11,1 мс < 13,9
	assert_float(s["gpu_avg_ms"]).is_equal_approx(5.0, 0.01)
	assert_float(s["gpu_max_ms"]).is_equal_approx(9.0, 0.01)


func test_кадр_длиннее_бюджета_и_нет_gpu_данных() -> void:
	var s := FramePerf.summarize(300, 5000.0, 30.0, 5.0, 0.0, 0, 0.0)
	assert_bool(s["over_budget"]).is_true()   # 16,7 мс > 13,9 — это 60 Гц
	assert_float(s["gpu_avg_ms"]).is_equal(-1.0)
	assert_str(FramePerf.format(s)).contains("[perf] fps=60.0")


func test_feed_печатает_итог_раз_в_интервал() -> void:
	var p: FramePerf = auto_free(FramePerf.new())
	var got: Array = []
	p.reported.connect(func(s: Dictionary): got.append(s))
	for _i in 360:
		p.feed(1.0 / 72.0, 4.0)
	assert_int(got.size()).is_equal(1)
	assert_float(got[0]["fps"]).is_equal_approx(72.0, 1.0)
	assert_float(got[0]["gpu_avg_ms"]).is_equal_approx(4.0, 0.01)
	for _i in 100:   # окно сброшено: до следующего итога ещё не дошло
		p.feed(1.0 / 72.0, 4.0)
	assert_int(got.size()).is_equal(1)


func test_конфиг_perf_по_умолчанию_выкл_и_парсится() -> void:
	assert_str(RenderConfig.new().perf).is_equal("off")
	assert_bool(RenderConfig.perf_enabled("on")).is_true()
	assert_bool(RenderConfig.perf_enabled("off")).is_false()
	var cfg := ConfigFile.new()
	cfg.set_value("render", "perf", "ON")
	assert_str(RenderConfig.from_config(cfg).perf).is_equal("on")
	cfg.set_value("render", "perf", "много")
	var c := RenderConfig.from_config(cfg)
	assert_str(c.perf).is_equal("off")
	assert_int(c.warnings.size()).is_equal(1)
