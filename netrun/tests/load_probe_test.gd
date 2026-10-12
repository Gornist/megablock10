extends GdUnitTestSuite
## Синтетическая нагрузка (client/load_probe.gd): разбор строки, размер квада, позиции, шейдеры, ключ [render] probe.


func test_разбор_полной_строки() -> void:
	var s := LoadProbe.parse("quads=5000, px=24, mode=a2c")
	assert_bool(s["on"]).is_true()
	assert_int(s["quads"]).is_equal(5000)
	assert_float(s["px"]).is_equal(24.0)
	assert_str(s["mode"]).is_equal("a2c")
	assert_int(s["warnings"].size()).is_equal(0)


func test_пусто_и_off_выключают_пропуски_по_умолчанию() -> void:
	assert_bool(LoadProbe.parse("")["on"]).is_false()
	assert_bool(LoadProbe.parse("off")["on"]).is_false()
	var s := LoadProbe.parse("mode=point")
	assert_bool(s["on"]).is_true()
	assert_int(s["quads"]).is_equal(LoadProbe.DEFAULT_QUADS)


func test_неверные_поля_дают_предупреждения_и_значения_по_умолчанию() -> void:
	var s := LoadProbe.parse("quads=0,px=9999,mode=xyz,foo=1,bar")
	assert_int(s["quads"]).is_equal(LoadProbe.DEFAULT_QUADS)
	assert_float(s["px"]).is_equal(LoadProbe.DEFAULT_PX)
	assert_str(s["mode"]).is_equal("blend")
	assert_int(s["warnings"].size()).is_equal(5)


func test_размер_квада_растёт_с_пикселями_и_расстоянием() -> void:
	assert_float(LoadProbe.quad_size(16.0, 2.5)).is_equal_approx(16.0 * LoadProbe.RAD_PER_PX * 2.5, 0.00001)
	assert_float(LoadProbe.quad_size(32.0)).is_greater(LoadProbe.quad_size(16.0))


func test_позиции_детерминированы_и_перед_лицом() -> void:
	var a := LoadProbe.positions(200)
	var b := LoadProbe.positions(200)
	assert_int(a.size()).is_equal(200)
	for i in a.size():
		assert_vector(a[i]).is_equal(b[i])
		assert_float(a[i].z).is_less(0.0)   # −Z — вперёд от камеры


func test_шейдер_каждого_режима_нужного_вида() -> void:
	for m in LoadProbe.MODES:
		assert_str(LoadProbe.shader_code(m)).contains("shader_type spatial")
	assert_str(LoadProbe.shader_code("a2c")).contains("alpha_to_coverage_and_one")
	assert_str(LoadProbe.shader_code("point")).contains("POINT_SIZE")
	assert_str(LoadProbe.shader_code("opaque")).not_contains("ALPHA =")


func test_конфиг_render_probe() -> void:
	var cf := ConfigFile.new()
	cf.set_value("render", "probe", "quads=100,px=8,mode=opaque")
	var c := RenderConfig.from_config(cf)
	assert_str(c.probe).is_equal("quads=100,px=8,mode=opaque")
	assert_int(c.warnings.size()).is_equal(0)
	cf.set_value("render", "probe", "mode=nope")
	assert_int(RenderConfig.from_config(cf).warnings.size()).is_equal(1)
	assert_str(RenderConfig.new().probe).is_equal("")


func test_узел_строит_мультимеш_нужного_числа() -> void:
	var p: LoadProbe = auto_free(LoadProbe.new())
	p.setup(LoadProbe.parse("quads=50,px=10,mode=blend"))
	add_child(p)
	var mmi: MultiMeshInstance3D = p.get_child(0)
	assert_int(mmi.multimesh.instance_count).is_equal(50)


func test_sweep_строка_включает_серию() -> void:
	var s := LoadProbe.parse("sweep")
	assert_bool(s["on"]).is_true()
	assert_bool(s["sweep"]).is_true()
	assert_bool(LoadProbe.parse("quads=10")["sweep"]).is_false()
	var cf := ConfigFile.new()
	cf.set_value("render", "probe", "sweep")
	assert_str(RenderConfig.from_config(cf).probe).is_equal("sweep")


func test_все_варианты_серии_разбираются_без_предупреждений() -> void:
	for spec: String in LoadProbe.SWEEP:
		var s := LoadProbe.parse(spec)
		assert_bool(s["on"]).is_true()
		assert_int(s["warnings"].size()).is_equal(0)


func test_серия_идёт_база_потом_варианты_и_итог() -> void:
	var sw: ProbeSweep = auto_free(ProbeSweep.new())
	sw.setup(null)
	var got: Array = []
	sw.finished.connect(func(r: Array): got.append(r))
	sw._next_variant()   # то, что в игре делает _ready
	var seconds := (ProbeSweep.SETTLE_SEC + ProbeSweep.WINDOW_SEC) * (LoadProbe.SWEEP.size() + 1)
	for _i in int(seconds) + 2:
		sw.step(1.0, 10.0)
	assert_bool(sw.is_done()).is_true()
	assert_int(got[0].size()).is_equal(LoadProbe.SWEEP.size() + 1)
	assert_str(got[0][0]["spec"]).is_equal("base")
	assert_str(ProbeSweep.format_summary(got[0])).contains("quads=2000,px=8,mode=blend")


func test_сводка_показывает_разность_к_базе() -> void:
	var res := [{"spec": "base", "gpu_avg_ms": 10.0, "fps": 90.0}, {"spec": "quads=1", "gpu_avg_ms": 11.5, "fps": 80.0}]
	assert_str(ProbeSweep.format_summary(res)).contains("(+1.50)")
