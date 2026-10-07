extends GdUnitTestSuite
## Пресеты камеры (shared/eye_presets.gd): полные данные, высота глаз как у риг-а клиента, точки внутри комнаты.

const NAMES := ["entry", "north", "south", "vault_w", "top", "top_north", "top_south"]


func test_все_кадры_приёмки_есть_по_порядку() -> void:
	assert_array(EyePresets.names()).is_equal(NAMES)


func test_у_каждого_пресета_pos_look_fov() -> void:
	for n: String in EyePresets.names():
		var p := EyePresets.get_preset(n)
		assert_bool(p.get("pos") is Vector3).is_true()
		assert_bool(p.get("look") is Vector3).is_true()
		assert_bool(p.get("fov") is float).is_true()
		assert_float(p["fov"]).is_greater(10.0)
		assert_float(p["fov"]).is_less(120.0)
		assert_bool((p["pos"] as Vector3).is_equal_approx(p["look"])).is_false()   # взгляд не в саму камеру


func test_неизвестный_пресет_пустой() -> void:
	assert_dict(EyePresets.get_preset("нет_такого")).is_empty()


func test_get_preset_отдаёт_копию() -> void:
	var p := EyePresets.get_preset("entry")
	p["fov"] = 1.0
	assert_float(EyePresets.get_preset("entry")["fov"]).is_equal(EyePresets.FOV_DEG)


func test_высота_глаз_равна_камере_риг_а() -> void:
	var rig: Node = auto_free(preload("res://client/xr_rig.tscn").instantiate())
	var cam: Node3D = rig.get_node("XRCamera3D")
	assert_float(EyePresets.EYE_HEIGHT).is_equal_approx(cam.position.y, 0.001)
	for n: String in EyePresets.names():
		var p := EyePresets.get_preset(n)
		if p["eye"]:
			assert_float((p["pos"] as Vector3).y).is_equal_approx(EyePresets.EYE_HEIGHT, 0.001)


func test_глаза_внутри_комнаты_и_обзор_над_ней() -> void:
	for n: String in EyePresets.names():
		var p := EyePresets.get_preset(n)
		assert_bool(NodeLayout.in_room(p["pos"])).is_true()
		assert_bool(NodeLayout.in_room(p["look"])).is_true()
		if not p["eye"]:
			assert_float((p["pos"] as Vector3).y).is_greater(EyePresets.EYE_HEIGHT)


func test_вход_глазами_стоит_на_спавне() -> void:
	var p := EyePresets.get_preset("entry")
	assert_float(NodeLayout.flat_distance(p["pos"], NodeLayout.SPAWN)).is_less(0.001)
	assert_float(((p["look"] as Vector3) - (p["pos"] as Vector3)).z).is_less(0.0)   # на север, в комнату


func test_vault_w_лицом_к_западному_хранилищу_с_площадки() -> void:
	var foyer := LayoutData.cached("foyer")
	var west: Dictionary = foyer.vaults[0]
	var p := EyePresets.get_preset("vault_w")
	assert_float(NodeLayout.flat_distance(p["pos"], west["pad"])).is_less(0.001)
	assert_float(NodeLayout.flat_distance(p["look"], west["slot"])).is_less(0.001)
