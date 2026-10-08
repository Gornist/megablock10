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
