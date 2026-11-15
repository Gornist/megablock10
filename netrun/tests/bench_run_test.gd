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


# --- G0: стенд без человека ---

func test_перцентили_по_сырым_кадрам_индекс_ceil_q_n_минус_1() -> void:
	var v := PackedFloat64Array()
	for i in range(20, 0, -1):   # 20…1 вперемешку с порядком: сортировка внутри
		v.append(float(i))
	assert_float(BenchRun.percentile(v, 0.5)).is_equal(10.0)    # ceil(10) − 1 = 9 → 10
	assert_float(BenchRun.percentile(v, 0.95)).is_equal(19.0)   # ceil(19) − 1 = 18 → 19
	assert_float(BenchRun.percentile(v, 1.0)).is_equal(20.0)
	assert_float(BenchRun.percentile(PackedFloat64Array([5.0]), 0.95)).is_equal(5.0)
	assert_float(BenchRun.percentile(PackedFloat64Array(), 0.95)).is_equal(0.0)
	assert_float(v[0]).is_equal(20.0)   # исходный массив не отсортирован


func test_статистика_кадров_доля_дольше_11_11() -> void:
	var f := PackedFloat64Array([10.0, 11.0, 12.0, 20.0])
	var g := PackedFloat64Array([8.0, -1.0, 12.0, 9.0])   # −1 — нет данных GPU, не считается
	var s := BenchRun.frame_stats(f, g)
	assert_float(s["frame_over"]).is_equal(0.5)
	assert_float(s["frame_peak"]).is_equal(20.0)
	assert_float(s["gpu_over"]).is_equal_approx(0.333, 0.001)   # 1 из 3
	assert_float(s["gpu_p50"]).is_equal(9.0)
	assert_float(s["gpu_peak"]).is_equal(12.0)
	assert_float(BenchRun.frame_stats(f, PackedFloat64Array([-1.0]))["gpu_p95"]).is_equal(-1.0)


func test_строка_csv_формат() -> void:
	assert_str(BenchRun.CSV_HEADER).is_equal("run,variant,frame,t_ms,frame_ms,gpu_ms")
	assert_str(BenchRun.csv_row(2, "B", 17, 1500.0, 11.111, 9.5)).is_equal("2,B,17,1500.00,11.111,9.500")
	assert_str(BenchRun.csv_row(1, "-", 0, 11.0, 11.0, -1.0)).is_equal("1,-,0,11.00,11.000,-1.000")
	assert_str(BenchRun.timestamp({"year": 2026, "month": 11, "day": 5, "hour": 7, "minute": 3, "second": 9})).is_equal("20261105-070309")


func test_расписание_ab_чётное_и_по_очереди() -> void:
	assert_array(BenchRun.ab_schedule(4)).is_equal([0, 1, 0, 1])
	assert_array(BenchRun.ab_schedule(3)).is_equal([0, 1, 0, 1])   # нечётное — вверх до чётного
	assert_array(BenchRun.ab_schedule(1)).is_equal([0, 1])
	assert_int(BenchRun.ab_runs(5)).is_equal(6)
	var b: BenchRun = auto_free(BenchRun.new())
	assert_str(b.configure_ab("msaa=2|4")).is_empty()
	assert_int(b.runs).is_equal(4)   # RUNS = 3 → 4


func test_разбор_bench_ab() -> void:
	var ok := BenchRun.parse_ab(" msaa = 2|4 ")
	assert_bool(ok["ok"]).is_true()
	assert_str(ok["name"]).is_equal("msaa")
	assert_str(ok["a"]).is_equal("2")
	assert_str(ok["b"]).is_equal("4")
	for bad in ["", "msaa", "=2|4", "msaa=2", "msaa=2|", "msaa=|4", "msaa=1|2|3"]:
		assert_bool(BenchRun.parse_ab(bad)["ok"]).is_false()
	assert_str(BenchRun.parse_ab("msaa=2")["error"]).contains("msaa")


func test_ab_отказы_и_принятые_ручки() -> void:
	var b: BenchRun = auto_free(BenchRun.new())
	assert_str(b.configure_ab("floor_grid=0|0.35")).contains("не меняется живьём")   # читается при создании материалов
	assert_str(b.configure_ab("нет_ручки=1|2")).contains("неизвестная ручка")
	assert_str(b.configure_ab("msaa=2|3")).contains("не годится")
	assert_str(b.configure_ab("dust_cell=abc|0.02")).contains("не годится")
	assert_str(b.configure_ab("msaa=oops")).is_not_empty()
	assert_int(b.runs).is_equal(BenchRun.RUNS)   # отказ — замер без A/B, окна не округляются
	assert_str(b.configure_ab("cloud_light=0|1")).is_empty()
	assert_str(b.configure_ab("dust_fill=0|1")).is_empty()
	assert_str(BenchRun.knob_kind("msaa")).is_equal("msaa")
	assert_str(BenchRun.knob_kind("lit_dim")).is_equal("live")
	assert_str(BenchRun.knob_kind("dust_density")).is_equal("static")
	assert_str(BenchRun.knob_kind("x")).is_equal("unknown")


func test_поза_камеры_после_компенсации_равна_пресету_при_любом_трекинге() -> void:
	for n: String in ["entry", "wedge", "floor_down", "floor_horizon", "top"]:
		var target := BenchRun.preset_camera_transform(EyePresets.get_preset(n))
		for tracked in [
			Transform3D(Basis.from_euler(Vector3(0.3, -1.2, 0.2)), Vector3(0.4, 1.1, -0.7)),
			Transform3D(Basis.from_euler(Vector3(-0.9, 2.5, -0.4)), Vector3(-1.0, 0.8, 2.0)),
			Transform3D(),
		]:
			var rig := BenchRun.lock_transform(target, tracked)
			var cam: Transform3D = rig * tracked
			assert_bool(cam.origin.is_equal_approx(target.origin)).is_true()
			assert_bool(cam.basis.is_equal_approx(target.basis)).is_true()


func test_поза_пресета_смотрит_на_точку_взгляда() -> void:
	var p := EyePresets.get_preset("floor_down")
	var t := BenchRun.preset_camera_transform(p)
	var fwd := -t.basis.z
	var want: Vector3 = ((p["look"] as Vector3) - (p["pos"] as Vector3)).normalized()
	assert_bool(fwd.is_equal_approx(want)).is_true()
	assert_bool(t.origin.is_equal_approx(p["pos"])).is_true()


func test_ab_окна_идут_ABAB_с_выдержкой_и_итогом_разницы() -> void:
	var b: BenchRun = auto_free(BenchRun.new())
	b.settle_s = 1.0
	b.run_s = 2.0
	b.ab_settle_s = 1.0
	b.runs = 3
	assert_str(b.configure_ab("msaa=2|4")).is_empty()   # → 4 окна
	var applied: Array = []
	b.variant_changed.connect(func(k: String, v: String): applied.append("%s=%s" % [k, v]))
	var seen: Array = []
	b.finished.connect(func(r: Dictionary): seen.append(r))
	var gpu_by_variant := [8.0, 11.0]   # A — 8 мс, B — 11 мс на кадр
	b.step(1.0, 1.0)   # прогрев
	for i in 4:
		assert_int(b.current_variant()).is_equal(i % 2)
		b.step(1.0, 99.0)   # выдержка после смены варианта — не учитывается
		for _k in 2:
			b.step(1.0, gpu_by_variant[b.current_variant()])
	assert_bool(b.is_done()).is_true()
	assert_array(applied).is_equal(["msaa=2", "msaa=4", "msaa=2", "msaa=4"])
	assert_int(seen.size()).is_equal(1)
	assert_int(seen[0]["runs"]).is_equal(4)
	assert_float(seen[0]["gpu_p50"]).is_equal(8.0)   # выдержка в 99 мс в замер не попала
	var ab := b.ab_result
	assert_float(ab["a"]["gpu_p50"]).is_equal(8.0)
	assert_float(ab["b"]["gpu_p50"]).is_equal(11.0)
	assert_float(ab["d_gpu_p50"]).is_equal(3.0)
	assert_float(ab["d_gpu_p95"]).is_equal(3.0)
	assert_int(ab["a"]["windows"]).is_equal(2)
	assert_str(BenchRun.format_ab("msaa", "2", "4", ab)).is_equal("[bench] AB name=msaa a=2 b=4 d_gpu_p50=3.0 d_gpu_p95=3.0 d_frame_p50=0.0")


func test_без_данных_gpu_разница_n_a() -> void:
	var w := [{"avg_ms": 11.0, "gpu_avg_ms": -1.0, "frame_p50": 11.0, "frame_p95": 12.0, "gpu_p50": -1.0, "gpu_p95": -1.0}]
	var ab := BenchRun.ab_summary(w, w)
	assert_bool(ab["d_gpu_p50"] == null).is_true()
	assert_str(BenchRun.format_ab("msaa", "2", "4", ab)).contains("d_gpu_p50=n/a")


func test_итог_совместим_старые_поля_на_месте_новые_в_конце() -> void:
	var b: BenchRun = auto_free(BenchRun.new())
	var got: Array = []
	b.finished.connect(func(r: Dictionary): got.append(r))
	for _i in int(BenchRun.SETTLE_SEC) + int(BenchRun.RUN_SEC) * BenchRun.RUNS:
		b.step(1.0, 10.0)
	var line := BenchRun.format_result(got[0])
	var old := "[bench] ИТОГ preset= runs=3 median_fps=1.0 median_avg_ms=1000.0 median_gpu_ms=10.0 gpu_min=10.0 gpu_max=10.0 avg_min=1000.0 avg_max=1000.0"
	assert_bool(line.begins_with(old)).is_true()
	assert_str(line.substr(old.length())).is_equal(" frame_p50=1000.0 frame_p95=1000.0 frame_peak=1000.0 frame_over=1.0 gpu_p50=10.0 gpu_p95=10.0 gpu_peak=10.0 gpu_over=0.0")
	var run_line := BenchRun.format_run(1, b._runs[0])
	assert_bool(run_line.begins_with("[bench] run=1 fps=1.0 avg_ms=1000.0 max_ms=1000.0 gpu_avg_ms=10.0 frame_p50=")).is_true()


func test_проекция_строка() -> void:
	assert_str(BenchRun.proj_line([-1.0, -0.98765], Vector2(2160, 2160), 4)).is_equal("[bench] proj p11_l=-1.0000 p11_r=-0.9877 viewport=2160x2160 msaa=4")
	assert_int(BenchRun.msaa_number(Viewport.MSAA_8X)).is_equal(8)
	assert_int(BenchRun.msaa_viewport_mode(2)).is_equal(Viewport.MSAA_2X)
	assert_int(BenchRun.msaa_viewport_mode(7)).is_equal(Viewport.MSAA_DISABLED)


func test_конфиг_ключи_замера() -> void:
	var c := RenderConfig.new()
	assert_bool(c.bench_lock).is_true()
	assert_float(c.bench_settle_s).is_equal(10.0)
	assert_int(c.bench_runs).is_equal(3)
	assert_float(c.bench_run_s).is_equal(20.0)
	assert_float(c.bench_ab_settle_s).is_equal(2.0)
	assert_str(c.bench_ab).is_empty()
	var cfg := ConfigFile.new()
	cfg.set_value("render", "bench_lock", "false")
	cfg.set_value("render", "bench_settle_s", 3)
	cfg.set_value("render", "bench_runs", "4")
	cfg.set_value("render", "bench_run_s", 5.5)
	cfg.set_value("render", "bench_ab", "msaa=2|4")
	cfg.set_value("render", "bench_ab_settle_s", "0")
	var r := RenderConfig.from_config(cfg)
	assert_bool(r.bench_lock).is_false()
	assert_float(r.bench_settle_s).is_equal(3.0)
	assert_int(r.bench_runs).is_equal(4)
	assert_float(r.bench_run_s).is_equal(5.5)
	assert_str(r.bench_ab).is_equal("msaa=2|4")
	assert_float(r.bench_ab_settle_s).is_equal(0.0)
	assert_array(r.warnings).is_empty()
	for k in ["bench_lock", "bench_settle_s", "bench_runs", "bench_run_s", "bench_ab", "bench_ab_settle_s"]:
		assert_bool(RenderConfig.KEYS.has(k)).is_true()


func test_конфиг_битые_ключи_замера_по_умолчанию_с_предупреждением() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("render", "bench_lock", "может")
	cfg.set_value("render", "bench_runs", 0)
	cfg.set_value("render", "bench_run_s", 0)
	cfg.set_value("render", "bench_settle_s", -1)
	cfg.set_value("render", "bench_ab", "msaa=2")
	var r := RenderConfig.from_config(cfg)
	assert_bool(r.bench_lock).is_true()
	assert_int(r.bench_runs).is_equal(3)
	assert_float(r.bench_run_s).is_equal(20.0)
	assert_float(r.bench_settle_s).is_equal(10.0)
	assert_str(r.bench_ab).is_empty()
	assert_int(r.warnings.size()).is_equal(5)
