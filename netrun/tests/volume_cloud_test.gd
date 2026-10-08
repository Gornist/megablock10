extends GdUnitTestSuite
## Облако частиц объекта (client/volume_cloud.gd) и реестр объёмных модулей (client/volume_registry.gd): чтение .points, ЛОД-префикс, ключ [render] volumetric.

const EXAMPLE := "res://tests/data/cloud_example.points"


func test_пример_файла_читается_64_точки_внутри_габарита() -> void:
	var pts := VolumeCloud.load_file(EXAMPLE)
	assert_int(VolumeCloud.points_in(pts)).is_equal(64)
	for i in 64:
		var o := i * VolumeCloud.POINT_FLOATS
		assert_bool(is_nan(pts[o]) or is_nan(pts[o + 1])).is_false()
		assert_float(pts[o]).is_between(-0.5, 0.5)       # x
		assert_float(pts[o + 1]).is_between(0.0, 2.0)    # y
		assert_float(pts[o + 6]).is_between(0.0, 1.0)    # вес
		assert_bool(pts[o + 5] == 0.0 or pts[o + 5] == 1.0).is_true()   # вид: точка или искра


func test_битый_размер_даёт_пустое_облако() -> void:
	assert_bool(VolumeCloud.parse(PackedByteArray([1, 2, 3, 4, 5])).is_empty()).is_true()
	assert_bool(VolumeCloud.parse(PackedByteArray()).is_empty()).is_true()
	assert_bool(VolumeCloud.load_file("res://tests/data/нет_такого.points").is_empty()).is_true()


func test_лод_ступени_по_расстоянию() -> void:
	assert_float(VolumeCloud.lod_fraction(1.0)).is_equal(1.0)
	assert_float(VolumeCloud.lod_fraction(5.0)).is_equal(0.5)
	assert_float(VolumeCloud.lod_fraction(10.0)).is_equal(0.25)
	assert_float(VolumeCloud.lod_fraction(30.0)).is_equal(VolumeCloud.LOD_FAR)


func test_видимых_точек_префикс_и_округление_вверх() -> void:
	assert_int(VolumeCloud.visible_for(64, 1.0)).is_equal(64)
	assert_int(VolumeCloud.visible_for(64, 0.5)).is_equal(32)
	assert_int(VolumeCloud.visible_for(64, 0.125)).is_equal(8)
	assert_int(VolumeCloud.visible_for(3, 0.01)).is_equal(1)   # у непустого облака не пропадает всё
	assert_int(VolumeCloud.visible_for(64, 0.0)).is_equal(0)
	assert_int(VolumeCloud.visible_for(0, 1.0)).is_equal(0)


func test_облако_строит_multimesh_с_буфером_и_лодом() -> void:
	var pts := VolumeCloud.load_file(EXAMPLE)
	var c: VolumeCloud = auto_free(VolumeCloud.new())
	c.auto_lod = false
	add_child(c)
	c.setup(pts, Color(0.2, 0.9, 1.0), AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 2, 1)))
	assert_int(c.point_count()).is_equal(64)
	assert_int(c.visible_count()).is_equal(64)
	var mmi := c.get_node("Particles") as MultiMeshInstance3D
	assert_int(mmi.multimesh.instance_count).is_equal(64)
	assert_int(mmi.multimesh.visible_instance_count).is_equal(64)
	# буфер экземпляров (в headless MultiMesh не отдаёт данные обратно, поэтому проверяем сам буфер): единичный базис, origin, цвет, данные частицы
	var buf := VolumeCloud.make_buffer(pts, Color(0.2, 0.9, 1.0))
	assert_int(buf.size()).is_equal(64 * VolumeCloud.STRIDE)
	for k in [0, 17, 63]:
		var o: int = k * VolumeCloud.STRIDE
		var p: int = k * VolumeCloud.POINT_FLOATS
		assert_float(buf[o]).is_equal(1.0)
		assert_float(buf[o + 5]).is_equal(1.0)
		assert_float(buf[o + 10]).is_equal(1.0)
		assert_float(buf[o + 3]).is_equal(pts[p])
		assert_float(buf[o + 7]).is_equal(pts[p + 1])
		assert_float(buf[o + 11]).is_equal(pts[p + 2])
		assert_float(buf[o + 13]).is_equal_approx(0.9, 0.0001)
		assert_float(buf[o + 16]).is_equal(pts[p + 3])   # полуразмер
		assert_float(buf[o + 19]).is_equal(pts[p + 6])   # вес
	# ЛОД и плотность — префикс
	c.set_lod(0.25)
	assert_int(mmi.multimesh.visible_instance_count).is_equal(16)
	c.density = 0.5
	c.set_lod(0.25)
	assert_int(c.visible_count()).is_equal(8)


func test_реестр_по_умолчанию_выкл_all_и_список() -> void:
	VolumeRegistry.configure("off")
	assert_bool(VolumeRegistry.is_enabled("ice")).is_false()
	VolumeRegistry.configure("all")
	assert_bool(VolumeRegistry.is_enabled("ice")).is_true()
	VolumeRegistry.configure("ICE, vault")
	assert_bool(VolumeRegistry.is_enabled("ice")).is_true()
	assert_bool(VolumeRegistry.is_enabled("vault")).is_true()
	assert_bool(VolumeRegistry.is_enabled("exit")).is_false()
	VolumeRegistry.configure("off")   # не оставляем состояние другим тестам
	assert_array(VolumeRegistry.parse_spec("off")).is_empty()
	assert_array(VolumeRegistry.parse_spec("all")).contains_exactly(["all"])
	assert_array(VolumeRegistry.parse_spec("ice,vault")).contains_exactly(["ice", "vault"])


func test_spawn_только_если_модуль_включён_и_есть_файл() -> void:
	var bounds := AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 2, 1))
	var model := "res://tests/data/cloud_example.glb"   # рядом лежит cloud_example.points
	assert_str(VolumeRegistry.points_path(model)).is_equal(EXAMPLE)
	VolumeRegistry.configure("off")
	assert_object(VolumeRegistry.spawn("ice", model, Color.WHITE, bounds)).is_null()
	VolumeRegistry.configure("ice")
	var c := VolumeRegistry.spawn("ice", model, Color.WHITE, bounds)
	assert_object(c).is_not_null()
	if c != null:
		c.free()
	assert_object(VolumeRegistry.spawn("vault", model, Color.WHITE, bounds)).is_null()   # модуль не включён
	assert_object(VolumeRegistry.spawn("ice", "res://tests/data/нет.glb", Color.WHITE, bounds)).is_null()   # файла нет
	VolumeRegistry.configure("off")


func test_конфиг_volumetric_по_умолчанию_off_и_парсится() -> void:
	assert_str(RenderConfig.new().volumetric).is_equal("off")
	var cfg := ConfigFile.new()
	cfg.set_value("render", "volumetric", " ICE,Vault ")
	assert_str(RenderConfig.from_config(cfg).volumetric).is_equal("ice,vault")
