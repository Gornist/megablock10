extends GdUnitTestSuite
## Вид тревоги узла на клиенте (ice.md §4): уровень 0–4 сдвигает фон и кромки комнаты (цвета — AssetMaterials у Blender), пульс фона на «охоте»,
## уровень переживает пересборку комнаты. Подписка — alarm_changed сцены.

var _scene: Node3D


func before_test() -> void:
	_scene = preload("res://client/world_scene.gd").new()
	add_child(_scene)
	await get_tree().process_frame


func after_test() -> void:
	_scene.queue_free()


func test_спокойный_фон_без_сдвига() -> void:
	var c: Color = _scene.alarm_bg(0)
	assert_float(c.r).is_equal_approx(0.02, 0.0001)
	assert_float(c.g).is_equal_approx(0.024, 0.0001)


func test_фон_краснеет_с_уровнем() -> void:
	var r1: float = _scene.alarm_bg(1).r
	var r4: float = _scene.alarm_bg(4).r
	assert_bool(r1 > 0.02).is_true()
	assert_bool(r4 > r1).is_true()
	assert_float(_scene.alarm_bg(4).g).is_less(0.024)


func test_охота_пульсирует_в_такте() -> void:
	var start: Color = _scene.alarm_bg(3, 0.0)
	var end: Color = _scene.alarm_bg(3, 1.0)
	assert_bool(start.r > end.r).is_true()


func test_событие_тревоги_ставит_уровень_и_фон() -> void:
	_scene.apply_alarm({"alarm": 60.0, "level": 2})
	assert_int(_scene.view.alarm_level).is_equal(2)
	assert_float(_scene._env.background_color.r).is_equal_approx(_scene.alarm_bg(2).r, 0.0001)
	_scene.apply_alarm({"alarm": 0.0, "level": 0})
	assert_int(_scene.view.alarm_level).is_equal(0)
	assert_float(_scene._env.background_color.r).is_equal_approx(0.02, 0.0001)


func test_уровень_переживает_пересборку_комнаты() -> void:
	_scene.apply_alarm({"alarm": 80.0, "level": 3})
	_scene.view.set_tier("HARD")
	assert_int(_scene.view.alarm_level).is_equal(3)
