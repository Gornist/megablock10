extends GdUnitTestSuite
## Регулятор плотности облаков по GPU-времени кадра (client/volume_budget.gd) и ключ [render] volume_budget_ms.


func test_выше_потолка_плотность_падает_ступенью_до_минимума() -> void:
	var d := 1.0
	for i in 20:
		d = VolumeBudget.next_density(d, 12.0, 10.5)
	assert_float(d).is_equal(VolumeBudget.MIN_DENSITY)
	assert_float(VolumeBudget.next_density(1.0, 11.0, 10.5)).is_equal_approx(VolumeBudget.STEP_DOWN, 0.0001)


func test_ниже_потолка_с_гистерезисом_плотность_растёт_до_единицы() -> void:
	var d := 0.5
	for i in 20:
		d = VolumeBudget.next_density(d, 8.0, 10.5)
	assert_float(d).is_equal(VolumeBudget.MAX_DENSITY)


func test_в_полосе_гистерезиса_и_без_данных_без_изменений() -> void:
	var lim := 10.5
	assert_float(VolumeBudget.next_density(0.6, lim - VolumeBudget.HYSTERESIS_MS * 0.5, lim)).is_equal(0.6)
	assert_float(VolumeBudget.next_density(0.6, -1.0, lim)).is_equal(0.6)
	assert_float(VolumeBudget.next_density(0.6, 99.0, 0.0)).is_equal(0.6)   # потолок 0 — регулятор выключен


func test_окно_накапливает_кадры_и_меняет_плотность_облаков_группы() -> void:
	var cloud: VolumeCloud = auto_free(VolumeCloud.new())
	var pts := VolumeCloud.load_file("res://tests/data/cloud_example.points")
	cloud.auto_lod = false
	cloud.setup(pts, Color.WHITE, AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2)))
	add_child(cloud)
	var vb: VolumeBudget = auto_free(VolumeBudget.new())
	vb.limit_ms = 10.0
	add_child(vb)
	var got: Array = []
	vb.changed.connect(func(d: float): got.append(d))
	for i in 4:   # окно 1 с из четырёх кадров по 0,25 с, GPU 12 мс — выше потолка
		vb.feed(0.25, 12.0)
	assert_int(got.size()).is_equal(1)
	assert_float(vb.density).is_equal_approx(VolumeBudget.STEP_DOWN, 0.0001)
	assert_float(cloud.density).is_equal_approx(VolumeBudget.STEP_DOWN, 0.0001)
	assert_int(cloud.visible_count()).is_less(cloud.point_count())
	for i in 4:   # потом 6 мс — ниже потолка с запасом, плотность растёт
		vb.feed(0.25, 6.0)
	assert_float(cloud.density).is_greater(VolumeBudget.STEP_DOWN)


func test_выключенный_регулятор_ничего_не_делает() -> void:
	var vb: VolumeBudget = auto_free(VolumeBudget.new())
	add_child(vb)
	for i in 200:
		vb.feed(0.02, 30.0)
	assert_float(vb.density).is_equal(1.0)


func test_ключ_конфига_volume_budget_ms() -> void:
	var cf := ConfigFile.new()
	assert_float(RenderConfig.from_config(cf).volume_budget_ms).is_equal(0.0)
	cf.set_value("render", "volume_budget_ms", 10.5)
	var c := RenderConfig.from_config(cf)
	assert_float(c.volume_budget_ms).is_equal(10.5)
	assert_int(c.warnings.size()).is_equal(0)
	for bad: Variant in [2.0, 50.0, "много", -1.0]:
		cf.set_value("render", "volume_budget_ms", bad)
		var b := RenderConfig.from_config(cf)
		assert_float(b.volume_budget_ms).is_equal(0.0)
		assert_int(b.warnings.size()).is_equal(1)
	cf.set_value("render", "volume_budget_ms", 0)
	assert_int(RenderConfig.from_config(cf).warnings.size()).is_equal(0)
