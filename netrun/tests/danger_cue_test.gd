extends GdUnitTestSuite
## Опасное в центре зрения (ice.md §8 «Правило П6»): метка у центра, звук и вибрация на пробуждение Black ICE, ожог и рост тревоги.

var _scene: Node3D
var _pulses: Array = []


func before_test() -> void:
	_scene = preload("res://client/rig_test_scene.gd").new()
	add_child(_scene)
	await get_tree().process_frame
	_pulses = []
	_scene.world_ui.danger.pulse_sink = func(hand: String, amp: float, sec: float): _pulses.append([hand, amp, sec])


func after_test() -> void:
	_scene.queue_free()


func _state(burn: int, ice: Array = []) -> Dictionary:
	return {"k": 1.0, "trace": 0.0, "level": 0, "cd": [], "ice": ice, "burn": burn}


func _black(phase: int, wake: int) -> Dictionary:
	return {"id": "b1", "p": [0.0, 0.0, 0.0], "f": [0.0, 1.0], "s": 0, "b": 1, "bp": phase, "bw": wake, "pg": 0, "c": [3, 3]}


func test_ожог_показывает_метку_вспышку_и_импульсы_обеими_руками() -> void:
	var d: DangerCue = _scene.world_ui.danger
	_scene.apply_state(_state(1))
	assert_str(d.shown_text()).is_equal("ОЖОГ 1/3")
	assert_bool(d.is_showing()).is_true()
	assert_int(_pulses.size()).is_equal(2)
	assert_array(_pulses.map(func(p): return p[0])).contains_exactly_in_any_order(["left", "right"])
	assert_float(_pulses[0][1]).is_equal(1.0)


func test_тот_же_ожог_второй_раз_не_повторяется() -> void:
	var d: DangerCue = _scene.world_ui.danger
	_scene.apply_state(_state(1))
	_scene.apply_state(_state(1))
	assert_int(d.shown["burn"]).is_equal(1)
	_scene.apply_state(_state(2))
	assert_str(d.shown_text()).is_equal("ОЖОГ 2/3")
	assert_int(d.shown["burn"]).is_equal(2)


func test_пробуждение_считает_тактами_и_молчит_без_смены_числа() -> void:
	var d: DangerCue = _scene.world_ui.danger
	_scene.apply_state(_state(0, [_black(1, 6)]))
	assert_str(d.shown_text()).is_equal("ЧЁРНЫЙ ЛЁД 6…")
	_scene.apply_state(_state(0, [_black(1, 6)]))
	assert_int(d.shown["wake"]).is_equal(1)
	_scene.apply_state(_state(0, [_black(1, 5)]))
	assert_str(d.shown_text()).is_equal("ЧЁРНЫЙ ЛЁД 5…")
	assert_int(d.shown["wake"]).is_equal(2)
	_scene.apply_state(_state(0, [_black(2, 0)]))   # охота: отсчёт кончился
	_scene.apply_state(_state(0, [_black(1, 6)]))   # уснул и проснулся снова — снова покажется
	assert_int(d.shown["wake"]).is_equal(3)


func test_спящий_black_ice_отсчёта_не_даёт() -> void:
	var d: DangerCue = _scene.world_ui.danger
	_scene.apply_state(_state(0, [_black(0, 0)]))
	assert_int(d.shown["wake"]).is_equal(0)
	assert_str(d.shown_text()).is_equal("")


func test_тревога_кричит_с_уровня_2_и_только_при_росте() -> void:
	var d: DangerCue = _scene.world_ui.danger
	_scene.apply_alarm({"alarm": 30.0, "level": 1})
	assert_int(d.shown["alarm"]).is_equal(0)
	_scene.apply_alarm({"alarm": 60.0, "level": 2})
	assert_str(d.shown_text()).is_equal("ТРЕВОГА 2")
	_scene.apply_alarm({"alarm": 30.0, "level": 1})
	assert_int(d.shown["alarm"]).is_equal(1)
	_scene.apply_alarm({"alarm": 90.0, "level": 3})
	assert_str(d.shown_text()).is_equal("ТРЕВОГА 3")


func test_метка_гаснет_за_время_показа() -> void:
	var d: DangerCue = _scene.world_ui.danger
	_scene.apply_state(_state(1))
	d._step(DangerCue.SHOW_SEC + 0.1)
	assert_bool(d.is_showing()).is_false()
	assert_str(d.shown_text()).is_equal("")
