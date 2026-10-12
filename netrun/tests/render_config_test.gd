extends GdUnitTestSuite
## Настройки рендера netrun.cfg [render] (shared/render_config.gd): по умолчанию, парсинг, граничные и ошибочные значения.
## Принятая база (владелец 12.10): MSAA 2×, фовеация 0, панели слоями «behind». Удалены ключи aa, fringe, scale, foveation_dynamic.

const TMP := "user://render_config_test.cfg"


func after_test() -> void:
	DirAccess.remove_absolute(TMP)


func _cfg(values: Dictionary) -> ConfigFile:
	var c := ConfigFile.new()
	for k in values:
		c.set_value(RenderConfig.SECTION, k, values[k])
	return c


func test_значения_по_умолчанию_принятая_база() -> void:
	var c := RenderConfig.new()
	assert_int(c.msaa).is_equal(2)
	assert_int(c.foveation).is_equal(0)
	assert_str(c.layers).is_equal("behind")
	assert_str(c.perf).is_equal("off")
	assert_str(c.volumetric).is_equal("off")
	assert_str(c.bench).is_empty()
	assert_str(c.probe).is_empty()
	assert_array(c.warnings).is_empty()


func test_нет_секции_значения_по_умолчанию_без_предупреждений() -> void:
	var cf := ConfigFile.new()
	cf.set_value("net", "host", "10.10.0.10")
	var c := RenderConfig.from_config(cf)
	assert_int(c.msaa).is_equal(2)
	assert_array(c.warnings).is_empty()


func test_поля_читаются() -> void:
	var c := RenderConfig.from_config(_cfg({"msaa": 0, "foveation": 3, "layers": "on"}))
	assert_int(c.msaa).is_equal(0)
	assert_int(c.foveation).is_equal(3)   # без MSAA фовеация допустима
	assert_str(c.layers).is_equal("on")
	assert_array(c.warnings).is_empty()


func test_msaa_допустимые_значения() -> void:
	for ok: int in [0, 2, 4]:
		var c := RenderConfig.from_config(_cfg({"msaa": ok}))
		assert_int(c.msaa).is_equal(ok)
		assert_array(c.warnings).is_empty()


func test_msaa_неверное_остаётся_по_умолчанию_с_предупреждением() -> void:
	for bad: Variant in [3, 8, -1, "много", 2.5]:
		var c := RenderConfig.from_config(_cfg({"msaa": bad}))
		assert_int(c.msaa).is_equal(RenderConfig.MSAA_DEFAULT)
		assert_int(c.warnings.size()).is_equal(1)


func test_числа_строкой_принимаются() -> void:
	var c := RenderConfig.from_config(_cfg({"msaa": "4", "foveation": "0"}))
	assert_int(c.msaa).is_equal(4)
	assert_int(c.foveation).is_equal(0)


func test_foveation_границы_без_msaa() -> void:
	assert_int(RenderConfig.from_config(_cfg({"msaa": 0, "foveation": 0})).foveation).is_equal(0)
	assert_int(RenderConfig.from_config(_cfg({"msaa": 0, "foveation": 3})).foveation).is_equal(3)
	for bad: Variant in [4, -1, 1.5, "высокая"]:
		var c := RenderConfig.from_config(_cfg({"msaa": 0, "foveation": bad}))
		assert_int(c.foveation).is_equal(RenderConfig.FOVEATION_DEFAULT)
		assert_int(c.warnings.size()).is_equal(1)


func test_фовеация_с_msaa_гасится_до_нуля_с_предупреждением() -> void:
	# MSAA + фовеация на Adreno 650 = пустой экран (замер 08.10): msaa по умолчанию 2, значит одиночное foveation=2 тоже гасится
	for cfg: Dictionary in [{"foveation": 2}, {"msaa": 2, "foveation": 1}, {"msaa": 4, "foveation": 3}]:
		var c := RenderConfig.from_config(_cfg(cfg))
		assert_int(c.foveation).is_equal(0)
		assert_int(c.warnings.size()).is_equal(1)
		assert_str(c.warnings[0]).contains("пустой экран")


func test_удалённые_ключи_игнорируются_с_предупреждением() -> void:
	# Старые netrun.cfg на очках: aa, fringe, scale, foveation_dynamic — тупики замеров; значения не читаются
	var c := RenderConfig.from_config(_cfg({"msaa": 2, "aa": "fxaa", "fringe": "off", "scale": 1.25, "foveation_dynamic": true}))
	assert_int(c.msaa).is_equal(2)
	assert_int(c.foveation).is_equal(0)
	assert_int(c.warnings.size()).is_equal(4)
	for w in c.warnings:
		assert_str(w).contains("удалён")
	for k in RenderConfig.LEGACY_KEYS:
		assert_bool(RenderConfig.KEYS.has(k)).is_false()


func test_неизвестный_ключ_предупреждение_остальное_читается() -> void:
	var c := RenderConfig.from_config(_cfg({"msaa": 4, "фокус": 1}))
	assert_int(c.msaa).is_equal(4)
	assert_int(c.warnings.size()).is_equal(1)


func test_маппинг_msaa_в_режим_viewport() -> void:
	assert_int(RenderConfig.msaa_mode(0)).is_equal(Viewport.MSAA_DISABLED)
	assert_int(RenderConfig.msaa_mode(2)).is_equal(Viewport.MSAA_2X)
	assert_int(RenderConfig.msaa_mode(4)).is_equal(Viewport.MSAA_4X)
	assert_int(RenderConfig.msaa_mode(7)).is_equal(Viewport.MSAA_DISABLED)


func test_load_file_нет_файла_по_умолчанию() -> void:
	var c := RenderConfig.load_file(PackedStringArray(["user://нет_такого_render.cfg"]))
	assert_int(c.msaa).is_equal(2)
	assert_str(c.file_path).is_empty()
	assert_array(c.warnings).is_empty()


func test_load_file_читает_секцию_render_того_же_netrun_cfg() -> void:
	var cf := _cfg({"msaa": 4, "layers": "off"})
	cf.set_value(NetConfig.FILE_SECTION, "host", "10.10.0.10")
	cf.save(TMP)
	var c := RenderConfig.load_file(PackedStringArray(["user://нет_такого_render.cfg", TMP]))
	assert_int(c.msaa).is_equal(4)
	assert_str(c.layers).is_equal("off")
	assert_str(c.file_path).is_equal(TMP)


func test_load_file_битый_файл_по_умолчанию_с_предупреждением() -> void:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("[render\nmsaa = ")
	f.close()
	var c := RenderConfig.load_file(PackedStringArray([TMP]))
	assert_int(c.msaa).is_equal(2)
	assert_int(c.warnings.size()).is_equal(1)


func test_путь_по_умолчанию_тот_же_что_у_netconfig() -> void:
	assert_str(NetConfig.FILE_NAME).is_equal("netrun.cfg")
	assert_array(NetConfig.default_paths()).is_not_empty()


func test_поля_журнала() -> void:
	var f := RenderConfig.new().log_fields()
	assert_int(f["msaa"]).is_equal(2)
	assert_int(f["foveation"]).is_equal(0)
	assert_str(f["file"]).is_equal("none")
	assert_str(f["layers"]).is_equal("behind")
	for k in ["aa", "fringe", "scale", "dynamic"]:
		assert_bool(f.has(k)).is_false()


func test_layers_парсинг_и_маппинг() -> void:
	assert_str(RenderConfig.new().layers).is_equal("behind")
	assert_str(RenderConfig.from_config(_cfg({"layers": "on"})).layers).is_equal("on")
	assert_str(RenderConfig.from_config(_cfg({"layers": "ON"})).layers).is_equal("on")
	assert_str(RenderConfig.from_config(_cfg({"layers": "Off"})).layers).is_equal("off")
	assert_bool(RenderConfig.layers_enabled("on")).is_true()
	assert_bool(RenderConfig.layers_enabled("off")).is_false()
	assert_bool(RenderConfig.layers_enabled(RenderConfig.LAYERS_DEFAULT)).is_true()   # по умолчанию слои включены (behind)
	# «behind»: слои включены, но позади сцены (руки и луч поверх панели)
	assert_str(RenderConfig.from_config(_cfg({"layers": "Behind"})).layers).is_equal("behind")
	assert_bool(RenderConfig.layers_enabled("behind")).is_true()
	assert_bool(RenderConfig.layers_behind("behind")).is_true()
	assert_bool(RenderConfig.layers_behind(RenderConfig.LAYERS_DEFAULT)).is_true()
	assert_bool(RenderConfig.layers_behind("on")).is_false()
	assert_bool(RenderConfig.layers_behind("off")).is_false()


func test_layers_неверное_по_умолчанию_с_предупреждением() -> void:
	for bad: Variant in ["вкл", "", 1, true]:
		var c := RenderConfig.from_config(_cfg({"layers": bad}))
		assert_str(c.layers).is_equal(RenderConfig.LAYERS_DEFAULT)
		assert_int(c.warnings.size()).is_equal(1)


## Заглушка интерфейса OpenXR: те же свойства, что у OpenXRInterface.
class FakeXr extends RefCounted:
	var render_target_size_multiplier: float = 1.0
	var foveation_level: int = 0
	var foveation_dynamic: bool = false


func test_apply_xr_ставит_только_фовеацию() -> void:
	var c := RenderConfig.from_config(_cfg({"msaa": 0, "foveation": 3}))
	var x := FakeXr.new()
	var missing := c.apply_xr(x)
	assert_array(missing).is_empty()
	assert_int(x.foveation_level).is_equal(3)
	assert_float(x.render_target_size_multiplier).is_equal(1.0)   # масштаб не трогаем
	assert_bool(x.foveation_dynamic).is_false()


func test_apply_xr_без_свойств_возвращает_их_имена_и_не_падает() -> void:
	var missing := RenderConfig.new().apply_xr(RefCounted.new())
	assert_int(missing.size()).is_equal(1)
	assert_str(missing[0]).is_equal("foveation_level")


func test_apply_msaa_ставит_режим_вьюпорта_и_без_fxaa() -> void:
	var vp: SubViewport = auto_free(SubViewport.new())
	RenderConfig.from_config(_cfg({"msaa": 4})).apply_msaa(vp)
	assert_int(vp.msaa_3d).is_equal(Viewport.MSAA_4X)
	assert_int(vp.screen_space_aa).is_equal(Viewport.SCREEN_SPACE_AA_DISABLED)
	RenderConfig.new().apply_msaa(vp)
	assert_int(vp.msaa_3d).is_equal(Viewport.MSAA_2X)
	assert_int(vp.screen_space_aa).is_equal(Viewport.SCREEN_SPACE_AA_DISABLED)
	RenderConfig.from_config(_cfg({"msaa": 0})).apply_msaa(vp)
	assert_int(vp.msaa_3d).is_equal(Viewport.MSAA_DISABLED)


func test_apply_assets_без_файла_не_падает() -> void:
	# Контракт с AssetMaterials.tune_from_config (зона Blender): нет файла — ручки как были
	RenderConfig.new().apply_assets(PackedStringArray(["user://нет_такого_render.cfg"]))
	assert_bool(true).is_true()
