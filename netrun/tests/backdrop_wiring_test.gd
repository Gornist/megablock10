extends GdUnitTestSuite
## Фон-купол в клиентской сцене (решение владельца 18.10, шаг B): купол есть, цвет пустоты следует за уровнем тревоги вместе с фоном окружения.

var _scene: Node3D


func before_test() -> void:
	_scene = preload("res://client/world_scene.gd").new()
	add_child(_scene)
	await get_tree().process_frame


func after_test() -> void:
	_scene.queue_free()


func _void_color() -> Color:
	return ((_scene.backdrop as BackdropDome).material_override as ShaderMaterial).get_shader_parameter("sky_void")


func test_купол_есть_в_сцене_и_спокойного_цвета() -> void:
	assert_object(_scene.backdrop).is_instanceof(BackdropDome)
	assert_bool((_scene.backdrop as Node).is_inside_tree()).is_true()
	assert_object(_void_color()).override_failure_message("спокойный узел: купол ничего не добавляет к чёрному фону").is_equal(BackdropDome.void_for(0))


func test_цвет_пустоты_идёт_за_уровнем_тревоги() -> void:
	_scene.apply_alarm({"alarm": 60.0, "level": 2})
	assert_object(_void_color()).is_equal(BackdropDome.void_for(2))
	assert_float(_void_color().r).override_failure_message("тревога добавляет красный сдвиг").is_greater(0.0)
	_scene.apply_alarm({"alarm": 10.0, "level": 0})
	assert_object(_void_color()).is_equal(BackdropDome.void_for(0))


## Цвет фона в просветах граней облака (sky_floor) равен фону клиента CALM_BG: иначе колонна читается чёрным блоком на сером небе (очки 20.10).
func test_просвет_грани_того_же_цвета_что_фон_клиента() -> void:
	var code := FileAccess.get_file_as_string("res://assets/shaders/backdrop_sky.gdshaderinc")
	var calm: Color = preload("res://client/world_scene.gd").CALM_BG
	var re := RegEx.create_from_string("sky_floor\\s*:\\s*source_color\\s*=\\s*vec3\\(([0-9.]+),\\s*([0-9.]+),\\s*([0-9.]+)\\)")
	var m := re.search(code)
	assert_object(m).override_failure_message("sky_floor не найден в backdrop_sky.gdshaderinc (%d байт)" % code.length()).is_not_null()
	assert_float(m.get_string(1).to_float()).is_equal_approx(calm.r, 0.0005)
	assert_float(m.get_string(2).to_float()).is_equal_approx(calm.g, 0.0005)
	assert_float(m.get_string(3).to_float()).override_failure_message("sky_floor должен быть CALM_BG клиента (%s)" % calm).is_equal_approx(calm.b, 0.0005)
