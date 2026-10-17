extends GdUnitTestSuite
## Вспышка ожога по краям зрения (AssetMaterials.burn_flash_material, burn_flash.gdshader, П6-6 (г)): цвета берутся из палитры слоёв, клиенту нужен только uniform `strength`.
## Вид — по кадру assets/preview_alarm.tscn (burn_0 / burn_10 / burn_5) и с очков.

const UNIFORMS := ["strength", "tint", "hot", "half_fov", "inner", "wash", "rim_width"]


func test_шейдер_вспышки_ожога_имеет_uniform_и_стартует_выключенным() -> void:
	var m := AssetMaterials.burn_flash_material()
	var have: Array = m.shader.get_shader_uniform_list().map(func(u): return u["name"])
	for u in UNIFORMS:
		assert_bool(have.has(u)).override_failure_message("нет uniform '%s' в burn_flash.gdshader" % u).is_true()
	assert_float(float(m.get_shader_parameter("strength"))).is_equal(0.0)
	assert_int(m.render_priority).override_failure_message("выше меток DangerCue (100)").is_greater(100)


func test_цвета_вспышки_ожога_из_палитры_слоёв() -> void:
	var m := AssetMaterials.burn_flash_material(0.8)
	assert_float(float(m.get_shader_parameter("half_fov"))).is_equal_approx(0.8, 0.0001)
	assert_bool((m.get_shader_parameter("tint") as Color).is_equal_approx(AssetMaterials.layer("burn_flash", 1.0))).is_true()
	assert_bool((m.get_shader_parameter("hot") as Color).is_equal_approx(AssetMaterials.layer("burn_flash_hot", 1.0))).is_true()
	# красное только у угрозы: основной тон — PAL_THREAT, обод — PAL_THREAT_HOT
	assert_bool(AssetMaterials.layer("burn_flash").is_equal_approx(AssetMaterials.PAL_THREAT)).is_true()
	assert_bool(AssetMaterials.layer("burn_flash_hot").is_equal_approx(AssetMaterials.PAL_THREAT_HOT)).is_true()


func test_константы_вспышки_в_пределах_vr_комфорта() -> void:
	assert_float(AssetMaterials.BURN_FLASH_START).is_between(0.5, 1.0)
	assert_float(AssetMaterials.BURN_FLASH_SEC).override_failure_message("одна вспышка ≤ 1 с (без стробоскопа)").is_between(0.3, 1.0)
