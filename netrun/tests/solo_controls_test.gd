extends GdUnitTestSuite
## Управление одиночной игры (client/solo_controls.gd, режим тестера xr_rig): схема, поворот щелчком 45°, прицел по центру, курсор для деки и панели взлома.
## Ввод подаётся прямо в риг и в SoloControls (в тестах нет ни окна, ни клавиатуры); кадр — 1/72 с.

const DT := 1.0 / 72.0
const T0 := 1_700_000_000.0
const DAEMONS := [
	{"id": "d1", "name": "Извлечение", "effect": "EXTRACT_SHARD", "tier": 2, "cells": ["1C", "BD"]},
	{"id": "d2", "name": "Призрак", "effect": "GHOST", "tier": 1, "cells": ["55", "7A", "FF"]},
]

var _attempts: Array = []
var _rig: XRRig
var _ui: WorldUI
var _link: FakePhoneLink


## Ложная панель взлома: открыта или нет.
class FakePanel extends Node:
	var open := false

	func is_interactive() -> bool:
		return open


## Слушатель событий «после» SoloControls: считает кнопки мыши, дошедшие до неподавленного ввода (как сцена с «взять объект»).
class Spy extends Node:
	var buttons := 0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			buttons += 1


func after_test() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _all_keys() -> String:
	return " | ".join(SoloControls.entries().map(func(e: Dictionary): return str(e["keys"])))


func _scene() -> Node3D:
	var scene: Node3D = auto_free(preload("res://client/rig_test_scene.gd").new())
	add_child(scene)
	_attempts = []
	scene.rig.teleport_attempted.connect(func(from: Vector3, to: Vector3, ok: bool, reason: String):
		_attempts.append({"from": from, "to": to, "ok": ok, "reason": reason}))
	return scene


## Риг сцены в режиме тестера + SoloControls (панель взлома — ложная).
func _tester(panel: Node = null) -> SoloControls:
	_rig = _scene().rig
	var c: SoloControls = auto_free(SoloControls.new())
	add_child(c)
	c.setup(_rig, panel)
	return c


func _frames(rig: XRRig, n: int, turn_x: float = 0.0, stick: Vector2 = Vector2.ZERO) -> void:
	for i in n:
		rig.drive(turn_x, stick, false, DT)


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = true
	return e


func _button(index: MouseButton, pressed: bool, pos: Vector2 = Vector2.ZERO) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = index
	e.pressed = pressed
	e.position = pos
	return e


func _procs(n: int) -> void:
	for i in n:
		_rig._process(DT)


# ---------------------------------------------------------------- схема

func test_схема_без_wasd_с_q_e_лкм_и_tab() -> void:
	var keys := _all_keys()
	var tokens := keys.replace("/", " ").replace("(", " ").replace(")", " ").replace("|", " ").split(" ", false)
	for k in ["W", "A", "S", "D"]:
		assert_bool(tokens.has(k)).is_false()
	assert_bool(keys.contains("Q / E")).is_true()
	assert_bool(keys.contains("ЛКМ")).is_true()
	assert_bool(keys.contains("Tab")).is_true()


func test_у_каждой_строки_схемы_есть_клавиши_действие_и_группа() -> void:
	assert_int(SoloControls.entries().size()).is_greater(5)
	for e in SoloControls.entries():
		for f in ["keys", "action", "group"]:
			assert_str(str(e.get(f, ""))).is_not_empty()


func test_строки_схемы_не_повторяются() -> void:
	var seen := {}
	for e in SoloControls.entries():
		var k := str(e["keys"])
		assert_bool(seen.has(k)).is_false()
		seen[k] = true


# ---------------------------------------------------------------- риг: поворот, ходьба, досягаемость

func test_q_e_поворачивают_ровно_на_45_градусов_за_нажатие() -> void:
	var rig := _tester().rig
	assert_str(rig.turn_mode).is_equal(RigMath.TURN_MODE_SNAP)
	var yaw0 := rig.rotation.y
	_frames(rig, 5, 1.0)   # E зажата: один щелчок, не вращение
	assert_float(rad_to_deg(rig.rotation.y - yaw0)).is_equal_approx(-45.0, 0.001)   # вправо — минус, как у правого стика
	_frames(rig, 3, 0.0)
	_frames(rig, 5, -1.0)   # Q — назад
	assert_float(rad_to_deg(rig.rotation.y - yaw0)).is_equal_approx(0.0, 0.001)
	_frames(rig, 2, 0.0)
	_frames(rig, 1, -1.0)
	_frames(rig, 1, 0.0)
	_frames(rig, 1, -1.0)
	assert_float(rad_to_deg(rig.rotation.y - yaw0)).is_equal_approx(90.0, 0.001)   # два нажатия — два щелчка


func test_comfort_с_плавным_поворотом_в_режиме_тестера_не_действует() -> void:
	var rig: XRRig = _scene().rig
	rig.turn_mode = RigMath.TURN_MODE_SMOOTH
	rig.snap_step_deg = 30.0
	rig.set_tester_mode(true)
	assert_str(rig.turn_mode).is_equal(RigMath.TURN_MODE_SNAP)
	assert_float(rig.snap_step_deg).is_equal(45.0)


func test_wasd_не_двигает_даже_с_walk() -> void:
	var rig: XRRig = _scene().rig
	rig.walk_enabled = true   # как --walk
	rig.set_tester_mode(true)
	assert_bool(rig.walk_enabled).is_false()
	rig.walk_enabled = true   # даже если кто-то включит позже
	var start := rig.global_position
	for i in 30:
		rig.drive(0.0, Vector2.ZERO, false, DT, Vector2(0, 1))
	assert_vector(rig.global_position).is_equal(start)
	assert_vector(rig._flat_move()).is_equal(Vector2.ZERO)


func test_обычная_плоская_сборка_с_walk_ходит_как_раньше() -> void:
	var rig: XRRig = _scene().rig
	rig.walk_enabled = true
	assert_bool(rig.tester_mode).is_false()
	assert_bool(rig.mouse_captured).is_false()
	var start := rig.global_position
	for i in 30:
		rig.drive(0.0, Vector2.ZERO, false, DT, Vector2(0, 1))
	assert_float(rig.global_position.distance_to(start)).is_greater(0.3)


func test_досягаемость_телепорта_не_больше_решения_game() -> void:
	assert_float(NodeGrid.REACH_M).is_equal(4.5)   # 4,5 м ≈ 2,2 клетки карты по 2 м
	var rig: XRRig = _scene().rig
	rig.teleport_range = RigMath.TELEPORT_RANGE_LIMIT   # comfort.cfg растянул до потолка
	rig.set_tester_mode(true)
	assert_float(rig.teleport_range).is_equal(NodeGrid.REACH_M)
	var start := rig.global_position
	_frames(rig, 3, 0.0, Vector2(0, 1))
	assert_bool(rig.is_aiming()).is_true()
	assert_float(NodeLayout.flat_distance(rig.aim_target(), start)).is_less_equal(NodeGrid.REACH_M + NodeGrid.CELL_M)
	_frames(rig, 40)
	for a in _attempts:
		if a["ok"]:
			assert_float(NodeLayout.flat_distance(a["from"], a["to"])).is_less_equal(NodeGrid.REACH_M + NodeGrid.CELL_M)


func test_осмотр_мышью_только_пока_мышь_захвачена_и_без_пкм() -> void:
	var c := _tester()
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(100, 0)
	_rig._unhandled_input(ev)
	assert_float(_rig.camera.rotation.y).is_equal_approx(-0.3, 0.0001)
	c.toggle_cursor()   # курсор свободен: взгляд замер
	_rig._unhandled_input(ev)
	assert_float(_rig.camera.rotation.y).is_equal_approx(-0.3, 0.0001)


# ---------------------------------------------------------------- SoloControls: прицел и курсор

func test_старт_захватывает_мышь_и_показывает_точку_по_центру() -> void:
	var c := _tester()
	assert_bool(_rig.tester_mode).is_true()
	assert_bool(_rig.mouse_captured).is_true()
	assert_bool(c.is_free()).is_false()
	assert_bool(c.crosshair.visible).is_true()
	var dot: Control = c.crosshair
	assert_float(dot.anchor_right).is_equal(1.0)   # на весь экран, точка рисуется по центру
	assert_float(dot.anchor_bottom).is_equal(1.0)
	assert_float(SoloControls.CROSSHAIR_PX).is_between(4.0, 6.0)


func test_лкм_держит_прицел_отпустить_прыгнуть() -> void:
	var c := _tester()
	var start := _rig.global_position
	c._input(_button(MOUSE_BUTTON_LEFT, true))
	_procs(3)
	assert_bool(_rig.is_aiming()).is_true()
	assert_vector(_rig.global_position).is_equal(start)
	c._input(_button(MOUSE_BUTTON_LEFT, false))
	_procs(40)
	assert_int(_attempts.size()).is_equal(1)
	assert_bool(_attempts[0]["ok"]).is_true()
	assert_float(_rig.global_position.distance_to(start)).is_greater(1.0)


func test_пкм_отменяет_прицел_без_прыжка_и_зажатая_лкм_не_начинает_новый() -> void:
	var c := _tester()
	var start := _rig.global_position
	c._input(_button(MOUSE_BUTTON_LEFT, true))
	_procs(3)
	assert_bool(_rig.is_aiming()).is_true()
	c._input(_button(MOUSE_BUTTON_RIGHT, true))
	_procs(40)
	assert_bool(_rig.is_aiming()).is_false()
	assert_int(_attempts.size()).is_equal(0)
	assert_vector(_rig.global_position).is_equal(start)
	c._input(_button(MOUSE_BUTTON_LEFT, false))   # отпустили — снова можно целиться
	c._input(_button(MOUSE_BUTTON_LEFT, true))
	_procs(3)
	assert_bool(_rig.is_aiming()).is_true()


func test_клавиша_c_отменяет_прицел_и_не_даёт_зажатой_лкм_начать_заново() -> void:
	var c := _tester()
	c._input(_button(MOUSE_BUTTON_LEFT, true))
	_procs(3)
	assert_bool(_rig.is_aiming()).is_true()
	c._input(_key(KEY_C))
	_rig._unhandled_input(_key(KEY_C))   # саму отмену ставит риг
	_procs(40)
	assert_bool(_rig.is_aiming()).is_false()
	assert_int(_attempts.size()).is_equal(0)


func test_tab_переключает_курсор_и_шлёт_сигнал() -> void:
	var c := _tester()
	var seen := []
	c.cursor_mode_changed.connect(func(free: bool): seen.append(free))
	c._input(_key(KEY_TAB))
	assert_bool(c.is_free()).is_true()
	assert_bool(_rig.mouse_captured).is_false()
	assert_bool(c.crosshair.visible).is_false()
	c._input(_key(KEY_TAB))
	assert_bool(c.is_free()).is_false()
	assert_bool(_rig.mouse_captured).is_true()
	assert_bool(c.crosshair.visible).is_true()
	assert_array(seen).is_equal([true, false])


func test_свободный_курсор_гасит_прицел() -> void:
	var c := _tester()
	c._input(_button(MOUSE_BUTTON_LEFT, true))
	_procs(3)
	assert_bool(_rig.is_aiming()).is_true()
	c._input(_key(KEY_TAB))
	_procs(40)
	assert_bool(_rig.is_aiming()).is_false()
	assert_int(_attempts.size()).is_equal(0)   # отмена, а не прыжок
	c._input(_button(MOUSE_BUTTON_LEFT, true))   # при свободном курсоре ЛКМ не целится
	_procs(3)
	assert_bool(_rig.is_aiming()).is_false()


func test_панель_взлома_освобождает_курсор_сама_и_возвращает() -> void:
	var panel: FakePanel = auto_free(FakePanel.new())
	var c := _tester(panel)
	assert_bool(c.is_free()).is_false()
	panel.open = true
	c._process(DT)
	assert_bool(c.is_free()).is_true()
	assert_bool(_rig.mouse_captured).is_false()
	panel.open = false
	c._process(DT)
	assert_bool(c.is_free()).is_false()
	assert_bool(_rig.mouse_captured).is_true()


func test_tab_при_открытой_панели_возвращает_взгляд_до_её_закрытия() -> void:
	var panel: FakePanel = auto_free(FakePanel.new())
	var c := _tester(panel)
	panel.open = true
	c._process(DT)
	c._input(_key(KEY_TAB))
	assert_bool(c.is_free()).is_false()   # смотрю по сторонам, панель открыта
	c._process(DT)
	assert_bool(c.is_free()).is_false()
	panel.open = false
	c._process(DT)
	assert_bool(c.is_free()).is_false()
	panel.open = true   # открылась новая — курсор снова сам
	c._process(DT)
	assert_bool(c.is_free()).is_true()


func test_лкм_и_пкм_не_доходят_до_сцены_ни_захваченными_ни_со_свободным_курсором() -> void:
	var spy: Spy = auto_free(Spy.new())
	add_child(spy)   # раньше SoloControls в дереве — события приходят ему позже
	var c := _tester()
	get_viewport().push_input(_button(MOUSE_BUTTON_LEFT, true))
	get_viewport().push_input(_button(MOUSE_BUTTON_LEFT, false))
	get_viewport().push_input(_button(MOUSE_BUTTON_RIGHT, true))
	assert_int(spy.buttons).is_equal(0)   # захват: ЛКМ — прицел, «взять» — F
	c.toggle_cursor()
	get_viewport().push_input(_button(MOUSE_BUTTON_LEFT, true))
	get_viewport().push_input(_button(MOUSE_BUTTON_LEFT, false))
	assert_int(spy.buttons).is_equal(0)   # свободный курсор мимо панели: тоже не «взять»


# ---------------------------------------------------------------- мышь по деке и панели взлома

func _setup_ui() -> void:
	_rig = auto_free(preload("res://client/xr_rig.tscn").instantiate())
	add_child(_rig)
	_ui = auto_free(WorldUI.new())
	add_child(_ui)
	_ui.attach(_rig)
	_link = FakePhoneLink.new(T0, false)
	_link.auto_reply = false
	_ui.set_phone(_link)
	for i in 4:
		await get_tree().process_frame


func _mouse_at_panel_px(panel: Node3D, px: Vector2, view: Vector2) -> Vector2:
	var world := DeckPointerMath.view_to_world(px, panel.surface_transform(), panel.panel_size_m(), view)
	return _rig.camera.unproject_position(world)


func test_мышь_нажимает_деку_только_при_свободном_курсоре() -> void:
	await _setup_ui()
	_ui.deck.select_tab(DeckPanel.TAB_CHAT)
	_ui.deck.chat().open_thread(FakePhoneLink.ID_SHERSHEN)
	for i in 3:
		await get_tree().process_frame
	var chip: MbButton = _ui.deck.chat().chip_buttons()[3]   # «Перезвоню»
	var screen := _mouse_at_panel_px(_ui.deck, chip.get_global_rect().get_center(), Vector2(DeckPanel.VIEW_SIZE))
	_rig.mouse_captured = true   # мышь ведёт взгляд: клик в сторону деки её не нажимает
	_ui.pointer._input(_button(MOUSE_BUTTON_LEFT, true, screen))
	_ui.pointer._input(_button(MOUSE_BUTTON_LEFT, false, screen))
	assert_str(_link.messages(FakePhoneLink.ID_SHERSHEN, 1)[0]["text"]).is_not_equal("Перезвоню")   # в переписке только входящее
	_rig.mouse_captured = false   # Tab: курсор свободен
	_ui.pointer._input(_button(MOUSE_BUTTON_LEFT, true, screen))
	_ui.pointer._input(_button(MOUSE_BUTTON_LEFT, false, screen))
	assert_str(_link.messages(FakePhoneLink.ID_SHERSHEN, 1)[0]["text"]).is_equal("Перезвоню")


func test_мышь_нажимает_клетку_панели_взлома_как_кнопку_деки() -> void:
	await _setup_ui()
	var panel: BreachPanel = _ui.breach_panel
	panel.set_context("Серверная", "HARD", DAEMONS, 6)
	panel.place(BreachPanelLayout.pose(Vector3(0, 1.2, 0), Vector3(0, 1, -1.5)))
	panel.begin(BreachMirror.from_event(BreachTestUtil.make_bk_event("HARD", 77, 6)))
	for i in 3:
		await get_tree().process_frame
	var taps := []
	panel.cell_tapped.connect(func(c: Vector2i): taps.append(c))
	var cell: BreachCell = panel.cell_nodes().values().filter(func(c: BreachCell): return c.is_available())[0]
	var screen := _mouse_at_panel_px(panel, cell.get_global_rect().get_center(), Vector2(BreachPanel.VIEW_SIZE))
	_rig.mouse_captured = true
	_ui.breach_pointer._input(_button(MOUSE_BUTTON_LEFT, true, screen))
	_ui.breach_pointer._input(_button(MOUSE_BUTTON_LEFT, false, screen))
	assert_array(taps).is_empty()   # захваченная мышь клетки не нажимает
	_rig.mouse_captured = false
	_ui.breach_pointer._input(_button(MOUSE_BUTTON_LEFT, true, screen))
	_ui.breach_pointer._input(_button(MOUSE_BUTTON_LEFT, false, screen))
	assert_array(taps).is_equal([cell.cell])


func test_захват_мыши_во_время_нажатия_отпускает_кнопку_панели() -> void:
	await _setup_ui()
	var panel: BreachPanel = _ui.breach_panel
	panel.set_context("Серверная", "HARD", DAEMONS, 6)
	panel.place(BreachPanelLayout.pose(Vector3(0, 1.2, 0), Vector3(0, 1, -1.5)))
	panel.begin(BreachMirror.from_event(BreachTestUtil.make_bk_event("HARD", 77, 6)))
	for i in 3:
		await get_tree().process_frame
	var cell: BreachCell = panel.cell_nodes().values().filter(func(c: BreachCell): return c.is_available())[0]
	var screen := _mouse_at_panel_px(panel, cell.get_global_rect().get_center(), Vector2(BreachPanel.VIEW_SIZE))
	_ui.breach_pointer._input(_button(MOUSE_BUTTON_LEFT, true, screen))
	assert_bool(_ui.breach_pointer.is_pressed()).is_true()
	_rig.mouse_captured = true
	_ui.breach_pointer._process(DT)
	assert_bool(_ui.breach_pointer.is_pressed()).is_false()


# ---------------------------------------------------------------- подключение в flat_stub

func test_flat_stub_включает_режим_тестера_только_по_аргументу() -> void:
	var plain: Node = auto_free(preload("res://client/flat_stub.gd").new())
	add_child(plain)
	plain.start(PackedStringArray())
	assert_object(plain.controls).is_null()
	var proto_plain := plain.get_node("Proto") as ProtoClient
	assert_bool(proto_plain.scene.rig.tester_mode).is_false()
	var tester: Node = auto_free(preload("res://client/flat_stub.gd").new())
	add_child(tester)
	tester.start(PackedStringArray(["--tester", "--walk"]))
	assert_object(tester.controls).is_not_null()
	var rig: XRRig = (tester.get_node("Proto") as ProtoClient).scene.rig
	assert_bool(rig.tester_mode).is_true()
	assert_bool(rig.walk_enabled).is_false()   # --walk в режиме тестера не действует
