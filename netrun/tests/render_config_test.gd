extends GdUnitTestSuite
## Настройки рендера netrun.cfg [render] (shared/render_config.gd): по умолчанию, парсинг, граничные и ошибочные значения.

const TMP := "user://render_config_test.cfg"


func after_test() -> void:
	DirAccess.remove_absolute(TMP)


func _cfg(values: Dictionary) -> ConfigFile:
	var c := ConfigFile.new()
	for k in values:
		c.set_value(RenderConfig.SECTION, k, values[k])
	return c


func test_значения_по_умолчанию() -> void:
	var c := RenderConfig.new()
	assert_int(c.msaa).is_equal(0)
	assert_str(c.aa).is_equal("none")
	assert_float(c.scale).is_equal(1.0)
	assert_int(c.foveation).is_equal(2)
	assert_bool(c.foveation_dynamic).is_false()
	assert_array(c.warnings).is_empty()


func test_нет_секции_значения_по_умолчанию_без_предупреждений() -> void:
	var cf := ConfigFile.new()
	cf.set_value("net", "host", "10.10.0.10")
	var c := RenderConfig.from_config(cf)
	assert_int(c.msaa).is_equal(0)
	assert_array(c.warnings).is_empty()


func test_все_поля_читаются() -> void:
	var c := RenderConfig.from_config(_cfg({"msaa": 2, "scale": 1.4, "foveation": 3, "foveation_dynamic": true}))
	assert_int(c.msaa).is_equal(2)
	assert_float(c.scale).is_equal_approx(1.4, 0.0001)
	assert_int(c.foveation).is_equal(3)
	assert_bool(c.foveation_dynamic).is_true()
	assert_array(c.warnings).is_empty()


func test_msaa_ноль_допустим() -> void:
	var c := RenderConfig.from_config(_cfg({"msaa": 0}))
	assert_int(c.msaa).is_equal(0)
	assert_array(c.warnings).is_empty()


func test_msaa_неверное_остаётся_по_умолчанию_с_предупреждением() -> void:
	for bad: Variant in [3, 8, -1, "много", 2.5]:
		var c := RenderConfig.from_config(_cfg({"msaa": bad}))
		assert_int(c.msaa).is_equal(RenderConfig.MSAA_DEFAULT)
		assert_int(c.warnings.size()).is_equal(1)


func test_числа_строкой_принимаются() -> void:
	var c := RenderConfig.from_config(_cfg({"msaa": "2", "scale": "1.25", "foveation": "1"}))
	assert_int(c.msaa).is_equal(2)
	assert_float(c.scale).is_equal_approx(1.25, 0.0001)
	assert_int(c.foveation).is_equal(1)


func test_scale_границы_включительно() -> void:
	assert_float(RenderConfig.from_config(_cfg({"scale": 0.5})).scale).is_equal(0.5)
	assert_float(RenderConfig.from_config(_cfg({"scale": 2.0})).scale).is_equal(2.0)
	assert_float(RenderConfig.from_config(_cfg({"scale": 2})).scale).is_equal(2.0)


func test_scale_вне_границ_или_не_число() -> void:
	for bad: Variant in [0.49, 2.01, 0.0, -1.0, "x", true]:
		var c := RenderConfig.from_config(_cfg({"scale": bad}))
		assert_float(c.scale).is_equal(RenderConfig.SCALE_DEFAULT)
		assert_int(c.warnings.size()).is_equal(1)


func test_foveation_границы() -> void:
	assert_int(RenderConfig.from_config(_cfg({"foveation": 0})).foveation).is_equal(0)
	assert_int(RenderConfig.from_config(_cfg({"foveation": 3})).foveation).is_equal(3)
	for bad: Variant in [4, -1, 1.5, "высокая"]:
		var c := RenderConfig.from_config(_cfg({"foveation": bad}))
		assert_int(c.foveation).is_equal(RenderConfig.FOVEATION_DEFAULT)
		assert_int(c.warnings.size()).is_equal(1)


func test_foveation_dynamic_строкой_и_ошибка() -> void:
	assert_bool(RenderConfig.from_config(_cfg({"foveation_dynamic": "true"})).foveation_dynamic).is_true()
	var c := RenderConfig.from_config(_cfg({"foveation_dynamic": 1}))
	assert_bool(c.foveation_dynamic).is_false()
	assert_int(c.warnings.size()).is_equal(1)


func test_неизвестный_ключ_предупреждение_остальное_читается() -> void:
	var c := RenderConfig.from_config(_cfg({"msaa": 2, "фокус": 1}))
	assert_int(c.msaa).is_equal(2)
	assert_int(c.warnings.size()).is_equal(1)


func test_маппинг_msaa_в_режим_viewport() -> void:
	assert_int(RenderConfig.msaa_mode(0)).is_equal(Viewport.MSAA_DISABLED)
	assert_int(RenderConfig.msaa_mode(2)).is_equal(Viewport.MSAA_2X)
	assert_int(RenderConfig.msaa_mode(4)).is_equal(Viewport.MSAA_4X)
	assert_int(RenderConfig.msaa_mode(7)).is_equal(Viewport.MSAA_DISABLED)


func test_load_file_нет_файла_по_умолчанию() -> void:
	var c := RenderConfig.load_file(PackedStringArray(["user://нет_такого_render.cfg"]))
	assert_int(c.msaa).is_equal(0)
	assert_str(c.file_path).is_empty()
	assert_array(c.warnings).is_empty()


func test_load_file_читает_секцию_render_того_же_netrun_cfg() -> void:
	var cf := _cfg({"msaa": 0, "scale": 1.2})
	cf.set_value(NetConfig.FILE_SECTION, "host", "10.10.0.10")
	cf.save(TMP)
	var c := RenderConfig.load_file(PackedStringArray(["user://нет_такого_render.cfg", TMP]))
	assert_int(c.msaa).is_equal(0)
	assert_float(c.scale).is_equal_approx(1.2, 0.0001)
	assert_str(c.file_path).is_equal(TMP)


func test_load_file_битый_файл_по_умолчанию_с_предупреждением() -> void:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("[render\nmsaa = ")
	f.close()
	var c := RenderConfig.load_file(PackedStringArray([TMP]))
	assert_int(c.msaa).is_equal(0)
	assert_int(c.warnings.size()).is_equal(1)


func test_путь_по_умолчанию_тот_же_что_у_netconfig() -> void:
	assert_str(NetConfig.FILE_NAME).is_equal("netrun.cfg")
	assert_array(NetConfig.default_paths()).is_not_empty()


func test_поля_журнала() -> void:
	var f := RenderConfig.new().log_fields()
	assert_int(f["msaa"]).is_equal(0)
	assert_str(f["aa"]).is_equal("none")
	assert_str(f["file"]).is_equal("none")


## Заглушка интерфейса OpenXR: те же свойства, что у OpenXRInterface.
class FakeXr extends RefCounted:
	var render_target_size_multiplier: float = 1.0
	var foveation_level: int = 0
	var foveation_dynamic: bool = false


func test_apply_xr_ставит_масштаб_и_фовеацию() -> void:
	var c := RenderConfig.from_config(_cfg({"scale": 1.3, "foveation": 3, "foveation_dynamic": true}))
	var x := FakeXr.new()
	var missing := c.apply_xr(x)
	assert_array(missing).is_empty()
	assert_float(x.render_target_size_multiplier).is_equal_approx(1.3, 0.0001)
	assert_int(x.foveation_level).is_equal(3)
	assert_bool(x.foveation_dynamic).is_true()


func test_apply_xr_без_свойств_возвращает_их_имена_и_не_падает() -> void:
	var missing := RenderConfig.new().apply_xr(RefCounted.new())
	assert_int(missing.size()).is_equal(3)


func test_apply_msaa_ставит_режим_вьюпорта() -> void:
	var vp: SubViewport = auto_free(SubViewport.new())
	RenderConfig.from_config(_cfg({"msaa": 2})).apply_msaa(vp)
	assert_int(vp.msaa_3d).is_equal(Viewport.MSAA_2X)
	assert_int(vp.screen_space_aa).is_equal(Viewport.SCREEN_SPACE_AA_DISABLED)
	RenderConfig.new().apply_msaa(vp)
	assert_int(vp.msaa_3d).is_equal(Viewport.MSAA_DISABLED)
	assert_int(vp.screen_space_aa).is_equal(Viewport.SCREEN_SPACE_AA_DISABLED)


func test_apply_msaa_включает_fxaa() -> void:
	var vp: SubViewport = auto_free(SubViewport.new())
	RenderConfig.from_config(_cfg({"aa": "fxaa"})).apply_msaa(vp)
	assert_int(vp.screen_space_aa).is_equal(Viewport.SCREEN_SPACE_AA_FXAA)
	RenderConfig.new().apply_msaa(vp)
	assert_int(vp.screen_space_aa).is_equal(Viewport.SCREEN_SPACE_AA_DISABLED)


func test_aa_парсинг_и_маппинг() -> void:
	assert_str(RenderConfig.from_config(_cfg({"aa": "fxaa"})).aa).is_equal("fxaa")
	assert_str(RenderConfig.from_config(_cfg({"aa": "FXAA"})).aa).is_equal("fxaa")
	assert_str(RenderConfig.from_config(_cfg({"aa": "none"})).aa).is_equal("none")
	assert_int(RenderConfig.aa_mode("fxaa")).is_equal(Viewport.SCREEN_SPACE_AA_FXAA)
	assert_int(RenderConfig.aa_mode("none")).is_equal(Viewport.SCREEN_SPACE_AA_DISABLED)
	assert_int(RenderConfig.aa_mode("что-то")).is_equal(Viewport.SCREEN_SPACE_AA_DISABLED)


func test_aa_неверное_по_умолчанию_с_предупреждением() -> void:
	for bad: Variant in ["smaa", "", 1, true]:
		var c := RenderConfig.from_config(_cfg({"aa": bad}))
		assert_str(c.aa).is_equal(RenderConfig.AA_DEFAULT)
		assert_int(c.warnings.size()).is_equal(1)


func test_fringe_парсинг_и_маппинг() -> void:
	assert_str(RenderConfig.new().fringe).is_equal("on")
	assert_str(RenderConfig.from_config(_cfg({"fringe": "off"})).fringe).is_equal("off")
	assert_str(RenderConfig.from_config(_cfg({"fringe": "OFF"})).fringe).is_equal("off")
	assert_str(RenderConfig.from_config(_cfg({"fringe": "On"})).fringe).is_equal("on")
	assert_bool(RenderConfig.fringe_enabled("on")).is_true()
	assert_bool(RenderConfig.fringe_enabled("off")).is_false()


func test_fringe_неверное_по_умолчанию_с_предупреждением() -> void:
	for bad: Variant in ["выкл", "", 0, false]:
		var c := RenderConfig.from_config(_cfg({"fringe": bad}))
		assert_str(c.fringe).is_equal(RenderConfig.FRINGE_DEFAULT)
		assert_int(c.warnings.size()).is_equal(1)


func test_apply_fringe_ставит_статическую_переменную_материалов() -> void:
	var was := AssetMaterials.fringe_on
	RenderConfig.from_config(_cfg({"fringe": "off"})).apply_fringe()
	assert_bool(AssetMaterials.fringe_on).is_false()
	RenderConfig.from_config(_cfg({"fringe": "on"})).apply_fringe(PackedStringArray())
	assert_bool(AssetMaterials.fringe_on).is_true()
	# не задан в файле — значение материалов (в т.ч. из [assets]) не трогается
	AssetMaterials.fringe_on = false
	RenderConfig.new().apply_fringe(PackedStringArray())
	assert_bool(AssetMaterials.fringe_on).is_false()
	AssetMaterials.fringe_on = was


func test_msaa_четыре_читается_из_файла() -> void:
	assert_int(RenderConfig.from_config(_cfg({"msaa": 4})).msaa).is_equal(4)
