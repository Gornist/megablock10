extends GdUnitTestSuite
## Фон-купол и подсветка занятых клеток в клиентской сцене за ручками [assets] (владелец 15.11: скайбокс убрать, фон только чёрный, заливки тайлов нет).
## По умолчанию: купола нет, OccupiedFloor нет, фон чистый чёрный; backdrop=1 возвращает купол (цвет пустоты следует за тревогой, как раньше).

var _scene: Node3D


func before_test() -> void:
	AssetMaterials.reset_tuning()


func after_test() -> void:
	AssetMaterials.reset_tuning()
	if _scene != null:
		_scene.queue_free()
		_scene = null


func _make() -> void:
	_scene = preload("res://client/world_scene.gd").new()
	add_child(_scene)
	await get_tree().process_frame


func _void_color() -> Color:
	return ((_scene.backdrop as BackdropDome).material_override as ShaderMaterial).get_shader_parameter("void_color")


func test_умолчания_ручек_и_чёрный_фон() -> void:
	assert_float(float(AssetMaterials.knob("backdrop"))).is_equal(0.0)
	assert_float(float(AssetMaterials.knob("occupied_floor"))).is_equal(0.0)
	assert_object(preload("res://client/world_scene.gd").CALM_BG).is_equal(Color(0.0, 0.0, 0.0))
	assert_object(AssetMaterials.VOID_BG).is_equal(Color(0.0, 0.0, 0.0))


func test_по_умолчанию_купола_нет_и_фон_чёрный() -> void:
	await _make()
	assert_object(_scene.backdrop).is_null()
	assert_bool(_scene.find_children("*", "BackdropDome", true, false).is_empty()).is_true()
	assert_object(_scene._env.background_color).is_equal(Color(0.0, 0.0, 0.0))
	_scene.apply_alarm({"alarm": 60.0, "level": 2})   # тревога без купола не падает, сдвиг фона к красному остаётся
	assert_object(_scene._env.background_color).is_equal(_scene.alarm_bg(2))


func test_ручка_backdrop_один_возвращает_купол() -> void:
	AssetMaterials.tune({"backdrop": 1.0})
	await _make()
	assert_object(_scene.backdrop).is_instanceof(BackdropDome)
	assert_bool((_scene.backdrop as Node).is_inside_tree()).is_true()
	assert_object(_void_color()).is_equal(AssetMaterials.alarm_background(0))
	_scene.apply_alarm({"alarm": 60.0, "level": 2})
	assert_object(_void_color()).is_equal(AssetMaterials.alarm_background(2))
	_scene.apply_alarm({"alarm": 10.0, "level": 0})
	assert_object(_void_color()).is_equal(AssetMaterials.alarm_background(0))
