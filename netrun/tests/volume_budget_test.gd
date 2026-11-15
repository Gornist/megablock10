extends GdUnitTestSuite
## Регулятор плотности облаков по GPU-времени кадра (client/volume_budget.gd) и ключ [render] volume_budget_ms.
## Схема: кольцо 120 валидных кадров → p95 раз в 0,25 с → цель (ступени по превышению) → видимая плотность догоняет цель плавно каждый кадр.

const DT := 1.0 / 90.0


func _budget(limit: float) -> VolumeBudget:
	var vb: VolumeBudget = auto_free(VolumeBudget.new())
	vb.limit_ms = limit
	add_child(vb)
	return vb


func _cloud() -> VolumeCloud:
	var cloud: VolumeCloud = auto_free(VolumeCloud.new())
	cloud.auto_lod = false
	add_child(cloud)
	cloud.setup(VolumeCloud.load_file("res://tests/data/cloud_example.points"), Color.WHITE, AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2)))
	return cloud


## Секунды кадров по gpu_ms (функция от текущей видимой плотности — замкнутая модель сцены).
func _run(vb: VolumeBudget, seconds: float, gpu: Callable) -> void:
	for i in int(seconds / DT):
		vb.feed(DT, gpu.call(vb.density))


func test_p95_кольца() -> void:
	var ring := PackedFloat32Array()
	for i in 100:
		ring.append(float(i + 1))   # 1…100
	assert_float(VolumeBudget.p95(ring)).is_equal(95.0)
	assert_float(VolumeBudget.p95(PackedFloat32Array([7.0]))).is_equal(7.0)
	assert_float(VolumeBudget.p95(PackedFloat32Array())).is_less(0.0)   # нет данных


func test_next_target_ступени_порог_и_гистерезис() -> void:
	var lim := 10.5
	# выше потолка — на долю превышения
	assert_float(VolumeBudget.next_target(1.0, 11.5, lim)).is_equal_approx(1.0 - VolumeBudget.K_DOWN * (1.0 / lim), 0.0001)
	# жёсткий порог (> limit + 1,5) — сразу ×0,75
	assert_float(VolumeBudget.next_target(1.0, 12.1, lim)).is_equal_approx(0.75, 0.0001)
	# не ниже минимума
	assert_float(VolumeBudget.next_target(0.26, 30.0, lim)).is_equal(VolumeBudget.MIN_DENSITY)
	# в полосе [limit − margin, limit] и без данных — без изменений
	assert_float(VolumeBudget.next_target(0.6, lim - VolumeBudget.MARGIN_MS * 0.5, lim)).is_equal(0.6)
	assert_float(VolumeBudget.next_target(0.6, -1.0, lim)).is_equal(0.6)
	assert_float(VolumeBudget.next_target(0.6, 99.0, 0.0)).is_equal(0.6)   # потолок 0 — выключен
	# восстановление — на 0,05, не выше 1
	assert_float(VolumeBudget.next_target(0.6, 8.0, lim)).is_equal_approx(0.65, 0.0001)
	assert_float(VolumeBudget.next_target(0.99, 8.0, lim)).is_equal(1.0)


func test_follow_вниз_быстрее_чем_вверх_и_не_перелетает() -> void:
	var down := VolumeBudget.follow(1.0, 0.5, 0.3)
	var up := VolumeBudget.follow(0.5, 1.0, 0.3)
	assert_float(down).is_equal_approx(1.0 - 0.5 * (1.0 - exp(-1.0)), 0.001)   # постоянная 0,3 с
	assert_float(up).is_equal_approx(0.5 + 0.5 * (1.0 - exp(-0.3 / 2.0)), 0.001)   # постоянная 2 с
	assert_float(down).is_greater(0.5)
	assert_float(up).is_less(1.0)
	assert_float(VolumeBudget.follow(0.7, 0.7, 1.0)).is_equal(0.7)
	assert_float(VolumeBudget.follow(0.7, 0.2, 0.0)).is_equal(0.7)   # нулевой кадр не двигает


func test_ступень_нагрузки_плотность_падает() -> void:
	var vb := _budget(10.5)
	var cloud := _cloud()
	_run(vb, 2.0, func(_d: float) -> float: return 9.0)   # спокойно: ничего не меняется
	assert_float(vb.density).is_equal(1.0)
	_run(vb, 3.0, func(_d: float) -> float: return 14.0)  # ступень до 14 мс
	assert_float(vb.target).is_less(0.6)
	assert_float(vb.density).is_less(0.7)
	assert_float(cloud.density).is_equal_approx(vb.density, 0.01)
	assert_int(cloud.visible_count()).is_less(cloud.point_count())


func test_снятие_нагрузки_плотность_возвращается_к_единице() -> void:
	var vb := _budget(10.5)
	var cloud := _cloud()
	_run(vb, 3.0, func(_d: float) -> float: return 14.0)
	assert_float(vb.density).is_less(0.7)
	_run(vb, 30.0, func(_d: float) -> float: return 9.0)  # снято, ниже порога восстановления 10,1
	assert_float(vb.target).is_equal(1.0)
	assert_float(vb.density).is_greater(0.99)
	assert_float(cloud.density).is_greater(0.99)


func test_постоянная_нагрузка_у_порога_без_автоколебаний() -> void:
	var vb := _budget(10.5)
	var dirs := [0]   # [число смен направления цели]
	var last := [vb.target, 0]   # [предыдущая цель, последний знак изменения]
	vb.targeted.connect(func(t: float) -> void:
		var s := signi(int(signf(t - float(last[0]))))
		if s != 0 and int(last[1]) != 0 and s != int(last[1]):
			dirs[0] += 1
		if s != 0:
			last[1] = s
		last[0] = t)
	_run(vb, 20.0, func(_d: float) -> float: return 10.4)   # чуть ниже потолка, выше порога восстановления
	assert_int(int(dirs[0])).is_less_equal(2)
	assert_float(vb.density).is_equal(1.0)


func test_замкнутая_модель_сцены_плотность_устанавливается_без_раскачки() -> void:
	# сцена: 6 мс базы + 8 мс × плотность (при 1,0 — 14 мс), потолок 10,5: равновесие около 0,5…0,56
	var vb := _budget(10.5)
	var dirs := [0]
	var last := [vb.target, 0]
	vb.targeted.connect(func(t: float) -> void:
		var s := signi(int(signf(t - float(last[0]))))
		if s != 0 and int(last[1]) != 0 and s != int(last[1]):
			dirs[0] += 1
		if s != 0:
			last[1] = s
		last[0] = t)
	_run(vb, 20.0, func(d: float) -> float: return 6.0 + 8.0 * d)
	assert_float(vb.density).is_between(0.4, 0.62)
	# за последние 10 с поведение спокойное: много смен направления — раскачка
	var settled := int(dirs[0])
	_run(vb, 10.0, func(d: float) -> float: return 6.0 + 8.0 * d)
	assert_int(int(dirs[0]) - settled).is_less_equal(4)


func test_нет_таймингов_плотность_не_меняется() -> void:
	var vb := _budget(10.5)
	var cloud := _cloud()
	for i in 900:
		vb.feed(DT, -1.0)   # рендерер не отдал время
		vb.feed(DT, 0.0)    # нулевое — невалидное
	assert_float(vb.density).is_equal(1.0)
	assert_float(vb.target).is_equal(1.0)
	assert_float(cloud.density).is_equal(1.0)


func test_меньше_30_валидных_кадров_плотность_не_трогается() -> void:
	var vb := _budget(10.5)
	for i in 29:
		vb.feed(DT * 3.0, 30.0)   # время идёт (оценка раз в 0,25 с срабатывает), но валидных кадров 29
	assert_float(vb.target).is_equal(1.0)
	for i in 5:
		vb.feed(DT * 3.0, 30.0)
	assert_float(vb.target).is_less(1.0)


func test_выключенный_регулятор_ничего_не_делает() -> void:
	var vb: VolumeBudget = auto_free(VolumeBudget.new())
	add_child(vb)
	for i in 200:
		vb.feed(0.02, 30.0)
	assert_float(vb.density).is_equal(1.0)
	assert_float(vb.target).is_equal(1.0)


func test_плотность_применяется_к_группе_только_при_заметном_изменении() -> void:
	var vb := _budget(10.5)
	var cloud := _cloud()
	var applied := [0]
	vb.changed.connect(func(_d: float) -> void: applied[0] += 1)
	_run(vb, 1.0, func(_d: float) -> float: return 9.0)   # цель 1,0 и показано 1,0: ничего не применяется
	assert_int(int(applied[0])).is_equal(0)
	_run(vb, 3.0, func(_d: float) -> float: return 14.0)
	assert_int(int(applied[0])).is_greater(0)
	assert_int(int(applied[0])).is_less(3 * 90)   # не на каждый кадр: только при сдвиге > 0,005
	assert_float(cloud.density).is_equal_approx(vb.density, 0.006)


func test_новое_облако_получает_текущую_плотность() -> void:
	var vb := _budget(10.5)
	_run(vb, 3.0, func(_d: float) -> float: return 14.0)
	assert_float(vb.density).is_less(0.8)
	var late := _cloud()   # вошло в группу после снижения
	assert_float(late.density).is_equal_approx(vb.density, 0.001)
	assert_int(late.visible_count()).is_less(late.point_count())


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
