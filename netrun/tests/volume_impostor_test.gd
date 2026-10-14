extends GdUnitTestSuite
## Импостор дальних облаков (client/volume_impostor.gd, VolumeCloud.impostor_m), ручка `[render] volume_impostor_m`, облако у выхода/ICE/шарда.


func _points(n: int) -> PackedFloat32Array:
	return VolumeSampler.sample_triangles(PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)]), n, 3)


func test_порог_с_гистерезисом() -> void:
	var th := 8.0
	var h := VolumeImpostor.HYSTERESIS
	assert_bool(VolumeImpostor.next_far(false, th, th)).is_false()           # на самом пороге — ещё близко
	assert_bool(VolumeImpostor.next_far(false, th + h + 0.1, th)).is_true()  # ушли за порог + запас — далеко
	assert_bool(VolumeImpostor.next_far(true, th, th)).is_true()             # вернулись на порог — ещё далеко
	assert_bool(VolumeImpostor.next_far(true, th - h - 0.1, th)).is_false()  # вошли за порог − запас — близко


func test_порог_ноль_выключает_импостор() -> void:
	assert_bool(VolumeImpostor.next_far(false, 100.0, 0.0)).is_false()
	assert_bool(VolumeImpostor.next_far(true, 100.0, 0.0)).is_false()


func test_облако_далеко_становится_билбордом_и_возвращается() -> void:
	var c := VolumeCloud.new()
	c.auto_lod = false   # ЛОД не мешает: смотрим только на режим «далеко»
	add_child(c)
	c.setup(_points(100), Color.WHITE, AABB())
	assert_bool(c.is_far()).is_false()
	c.impostor_m = 8.0
	c._set_far(true)
	assert_bool(c.is_far()).is_true()
	assert_object(c.get_node_or_null("Impostor")).is_not_null()
	assert_bool((c.get_node("Particles") as Node3D).visible).is_false()
	c._set_far(false)
	assert_bool(c.is_far()).is_false()
	assert_bool((c.get_node("Particles") as Node3D).visible).is_true()
	assert_bool((c.get_node("Impostor") as Node3D).visible).is_false()
	c.free()


func test_габарит_облака_берётся_по_точкам_когда_не_задан() -> void:
	var c := VolumeCloud.new()
	c.setup(_points(50), Color.WHITE, AABB())
	assert_float(c._bounds.size.x).is_greater(0.5)   # у файла .points габарита нет — по самим точкам
	c.free()


func test_ключ_конфига_volume_impostor_m() -> void:
	var cf := ConfigFile.new()
	assert_float(RenderConfig.from_config(cf).volume_impostor_m).is_equal(0.0)
	cf.set_value("render", "volume_impostor_m", 8.0)
	var c := RenderConfig.from_config(cf)
	assert_float(c.volume_impostor_m).is_equal(8.0)
	assert_array(c.warnings).is_empty()
	cf.set_value("render", "volume_impostor_m", 1.0)   # ниже допустимого — выключено с предупреждением
	var bad := RenderConfig.from_config(cf)
	assert_float(bad.volume_impostor_m).is_equal(0.0)
	assert_int(bad.warnings.size()).is_equal(1)
	assert_bool(RenderConfig.KEYS.has("volume_impostor_m")).is_true()


func test_цвет_облака_ice_и_exit_из_палитры() -> void:
	assert_bool(VolumeRegistry.color_of("ice").a > 0.0).is_true()
	assert_bool(VolumeRegistry.color_of("exit").a > 0.0).is_true()
	assert_bool(VolumeRegistry.color_of("vault") == AssetMaterials.layer("hud_ok")).is_true()


func test_рамка_выхода_облаком_только_при_включённом_exit() -> void:
	VolumeRegistry.configure("off")
	var view: NodeView = auto_free(NodeView.new())
	add_child(view)
	view.set_look("BASE", null)
	assert_object(view.find_child("ExitFrame", true, false)).is_null()
	VolumeRegistry.configure("exit")
	view.set_look("HARD", null)   # другой тир — комната пересобирается
	assert_object(view.find_child("ExitFrame", true, false)).is_not_null()
	assert_int(view.find_children("Cloud_exit", "Node3D", true, false).size()).is_equal(1)
	VolumeRegistry.configure("off")


func test_ice_облако_внутри_модели_только_при_включённом_ice() -> void:
	VolumeRegistry.configure("off")
	var plain: IceView = auto_free(IceView.new(true))
	add_child(plain)
	assert_int(plain.find_children("Cloud_ice", "Node3D", true, false).size()).is_equal(0)
	VolumeRegistry.configure("ice")
	var holo: IceView = auto_free(IceView.new(true))
	add_child(holo)
	assert_int(holo.find_children("Cloud_ice", "Node3D", true, false).size()).is_equal(1)
	VolumeRegistry.configure("off")
