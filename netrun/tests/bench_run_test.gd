extends GdUnitTestSuite
## Воспроизводимый замер кадра (client/bench_run.gd): медиана, итог прогона, порядок фаз, конфиг [render] bench.


func test_медиана_нечётная_чётная_и_пустая() -> void:
	assert_float(BenchRun.median([3.0, 1.0, 2.0])).is_equal(2.0)
	assert_float(BenchRun.median([4.0, 1.0, 2.0, 3.0])).is_equal(2.5)
	assert_float(BenchRun.median([])).is_equal(0.0)


func test_итог_прогона_и_медиана_по_прогонам() -> void:
	var a := BenchRun.summarize_run(3600, 40000.0, 20.0, 60.0, 36000.0, 3600)   # 60 fps … 11,1 мс, GPU 10 мс
	assert_float(a["fps"]).is_equal_approx(60.0, 0.05)
	assert_float(a["avg_ms"]).is_equal_approx(11.11, 0.01)
	assert_float(a["gpu_avg_ms"]).is_equal_approx(10.0, 0.01)
	var runs := [a, {"fps": 62.0, "avg_ms": 11.0, "max_ms": 18.0, "gpu_avg_ms": 11.0}, {"fps": 58.0, "avg_ms": 12.0, "max_ms": 25.0, "gpu_avg_ms": 12.5}]
	var m := BenchRun.median_result(runs)
	assert_int(m["runs"]).is_equal(3)
	assert_float(m["gpu_avg_ms"]).is_equal_approx(11.0, 0.001)   # медиана 10; 11; 12,5
	assert_float(m["fps"]).is_equal_approx(60.0, 0.05)
	assert_float(BenchRun.summarize_run(10, 100.0, 10.0, 1.0, 0.0, 0)["gpu_avg_ms"]).is_equal(-1.0)   # нет данных GPU


func test_фазы_settle_потом_3_прогона_и_итог() -> void:
	var b: BenchRun = auto_free(BenchRun.new())
	b.preset = "entry"
	var got: Array = []
	b.finished.connect(func(r: Dictionary): got.append(r))
	# SETTLE_SEC без замера (шаг 1 с)
	for _i in int(BenchRun.SETTLE_SEC):
		b.step(1.0, 10.0)
	assert_bool(b.is_done()).is_false()
	# RUNS прогонов по RUN_SEC (шаг 1 с, GPU 10 мс постоянно)
	for _i in int(BenchRun.RUN_SEC) * BenchRun.RUNS:
		b.step(1.0, 10.0)
	assert_bool(b.is_done()).is_true()
	assert_int(got.size()).is_equal(1)
	assert_int(got[0]["runs"]).is_equal(BenchRun.RUNS)
	assert_float(got[0]["gpu_avg_ms"]).is_equal_approx(10.0, 0.001)
	assert_str(got[0]["preset"]).is_equal("entry")
	assert_str(BenchRun.format_result(got[0])).contains("preset=entry")


func test_конфиг_bench_пресет_пусто_и_неизвестный() -> void:
	assert_str(RenderConfig.new().bench).is_equal("")
	var cfg := ConfigFile.new()
	cfg.set_value("render", "bench", " Entry ")
	assert_str(RenderConfig.from_config(cfg).bench).is_equal("entry")
	cfg.set_value("render", "bench", "нет_такого")
	var c := RenderConfig.from_config(cfg)
	assert_str(c.bench).is_equal("")
	assert_int(c.warnings.size()).is_equal(1)


func test_итог_содержит_разброс_окон() -> void:
	var runs := [
		{"fps": 90.0, "avg_ms": 11.0, "max_ms": 15.0, "gpu_avg_ms": 8.0},
		{"fps": 90.0, "avg_ms": 11.5, "max_ms": 16.0, "gpu_avg_ms": 9.0},
		{"fps": 80.0, "avg_ms": 12.5, "max_ms": 20.0, "gpu_avg_ms": 11.0}]
	var m := BenchRun.median_result(runs)
	assert_float(m["gpu_avg_ms_min"]).is_equal(8.0)
	assert_float(m["gpu_avg_ms_max"]).is_equal(11.0)
	assert_float(m["avg_ms_min"]).is_equal(11.0)
	assert_float(m["avg_ms_max"]).is_equal(12.5)
	assert_str(BenchRun.format_result(m)).contains("gpu_min=8.0 gpu_max=11.0")
