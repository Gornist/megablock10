class_name DeckPointer
extends Node3D
## Указатель деки: правый контроллер (поза «aim», нет данных — рука) бьёт лучом в панель; точка попадания переводится в пиксель
## SubViewport (DeckPointerMath, чистая функция в shared/) и уходит туда событиями мыши — кнопки, вкладки и строки деки подсвечиваются
## и нажимаются как обычный интерфейс. Курок правой руки (`trigger_click`) — левая кнопка мыши; левый стик по Y листает список,
## пока луч на панели. Пока луч на панели, видны точка и короткий луч от руки. Плоская сборка — тот же код: луч из камеры через
## курсор мыши, левая кнопка — клик, колесо — прокрутка; клик по панели не доходит до захвата предметов.
## Подключает WorldUI.attach; правый стик телепорта и захват (grip) не затрагиваются.

## Клик по панели (курок или мышь): правая рука может ответить лёгким импульсом.
signal clicked
## Нажатая кнопка курка правого контроллера (действие OpenXR).
const TRIGGER := "trigger_click"
## Ход списка колесом мыши на одно деление, px.
const WHEEL_PX := 64.0
const SCROLL_PX_S := 520.0
## Цвета — слои палитры клиента (AssetMaterials.layer): pointer_dot (точка), pointer_press (нажатие), pointer_beam (луч; мимо панели — слабее, BEAM_MISS_SCALE).
const BEAM_MISS_SCALE := 0.35
## Слабый луч к панели, если целишься рядом (в пределах этого расстояния от центра), чтобы её было легче найти.
const NEAR_MISS_M := 0.4

## Панель-цель: DeckPanel или BreachPanel (общий набор: view_size, surface_transform, panel_size_m, push_pointer_event, is_interactive, scroll_by).
var panel: Node3D
var rig: XRRig
var enabled := true
## Результат последнего пересчёта DeckPointerMath.ray_to_view.
var last_hit: Dictionary = {"hit": false}
var hovering := false
## Сколько событий ушло в панель (для проверки).
var motion_events := 0
var button_events := 0

var _pressed := false
var _trigger_poll_down := false
var _press_pos := Vector2.ZERO
var _last_pos := Vector2(-1.0, -1.0)
var _dot: MeshInstance3D
var _dot_mat: StandardMaterial3D
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _bound_hand: XRController3D


func _init() -> void:
	name = "DeckPointer"
	top_level = true   # всё считаем в мировых координатах
	_dot_mat = _unshaded(AssetMaterials.layer("pointer_dot"))
	var sphere := SphereMesh.new()
	sphere.radius = 0.005
	sphere.height = 0.01
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.material = _dot_mat
	_dot = MeshInstance3D.new()
	_dot.mesh = sphere
	_dot.visible = false
	_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dot)
	_beam_mat = _unshaded(AssetMaterials.layer("pointer_beam"))
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var box := BoxMesh.new()
	box.size = Vector3(0.002, 0.002, 1.0)
	box.material = _beam_mat
	_beam = MeshInstance3D.new()
	_beam.mesh = box
	_beam.visible = false
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)


func setup(r: XRRig, p: Node3D) -> void:
	rig = r
	panel = p
	name = "DeckPointer" if p is DeckPanel else "BreachPointer"
	if rig != null and rig.right_hand != null:
		_bound_hand = rig.right_hand
		_bound_hand.button_pressed.connect(_on_hand_button.bind(true))
		_bound_hand.button_released.connect(_on_hand_button.bind(false))


func _on_hand_button(action: String, pressed: bool) -> void:
	if action == TRIGGER and rig != null and rig.xr_active:
		set_trigger(pressed)


func _process(delta: float) -> void:
	if rig == null or panel == null:
		return
	if not enabled or not panel.is_interactive():
		_release_all()
		return
	var ray := _current_ray()
	if ray.is_empty():
		update_ray(Vector3.ZERO, Vector3.ZERO)
	else:
		update_ray(ray["origin"], ray["dir"])
	_poll_trigger()
	if hovering and rig.xr_active and rig.left_hand != null:
		var dy := DeckPointerMath.scroll_step(rig.left_hand.get_vector2("primary").y, delta, SCROLL_PX_S)
		if dy != 0.0:
			panel.scroll_by(dy)


## Курок ещё и как аналоговая ось («trigger»): если у контроллера нет привязки trigger_click, клик всё равно придёт. Реагируем на
## пересечение порогов (нажал — глубже 0,75, отпустил — слабее 0,4), а не на значение, чтобы не двоить сигнал trigger_click.
func _poll_trigger() -> void:
	if not rig.xr_active or rig.right_hand == null:
		return
	var v := rig.right_hand.get_float("trigger")
	if not _trigger_poll_down and v > 0.75:
		_trigger_poll_down = true
		set_trigger(true)
	elif _trigger_poll_down and v < 0.4:
		_trigger_poll_down = false
		set_trigger(false)


## Откуда и куда смотрит указатель: VR — правый контроллер (aim, иначе рука), плоская сборка — камера через курсор. {} — луча нет.
func _current_ray() -> Dictionary:
	if rig.xr_active:
		var n: XRController3D = rig.right_aim if rig.right_aim != null and rig.right_aim.get_has_tracking_data() else rig.right_hand
		if n == null or not n.get_has_tracking_data():
			return {}
		return {"origin": n.global_position, "dir": -n.global_basis.z}
	var vp := get_viewport()
	if vp == null or rig.camera == null or not rig.camera.is_inside_tree():
		return {}
	var mouse := vp.get_mouse_position()
	if not vp.get_visible_rect().has_point(mouse):
		return {}
	return {"origin": rig.camera.project_ray_origin(mouse), "dir": rig.camera.project_ray_normal(mouse)}


## Один шаг по готовому лучу (так же зовут тесты): пересчёт попадания, события мыши в панель, точка и луч.
func update_ray(origin: Vector3, dir: Vector3) -> void:
	if panel == null:
		return
	if dir == Vector3.ZERO:
		last_hit = {"hit": false, "reason": "noray"}
	else:
		last_hit = DeckPointerMath.ray_to_view(origin, dir, panel.surface_transform(), panel.panel_size_m(), Vector2(panel.view_size()))
	if last_hit["hit"]:
		var pos: Vector2 = last_hit["pos"]
		if not hovering or pos.distance_to(_last_pos) >= 0.5:
			_send(_motion(pos, pos - _last_pos if hovering else Vector2.ZERO))
			motion_events += 1
		hovering = true
		_last_pos = pos
	elif hovering:
		# Луч ушёл с панели: «мышь» уходит за её край, подсветка гаснет. Нажатую кнопку отпустит set_trigger(false).
		hovering = false
		_send(_motion(Vector2(-1000.0, -1000.0), Vector2.ZERO))
		motion_events += 1
	_update_visuals(origin)


## Курок: нажат — левая кнопка на точке под лучом (только если луч на панели); отпущен — отпускание там же, где нажали.
func set_trigger(pressed: bool) -> void:
	if pressed:
		if not hovering or _pressed:
			return
		_pressed = true
		_press_pos = _last_pos
		_send(_button(_last_pos, true))
		button_events += 1
		_dot_mat.albedo_color = AssetMaterials.layer("pointer_press")
		clicked.emit()
	elif _pressed:
		_pressed = false
		_send(_button(_last_pos if hovering else _press_pos, false))
		button_events += 1
		_dot_mat.albedo_color = AssetMaterials.layer("pointer_dot")


func is_pressed() -> bool:
	return _pressed


## Плоская сборка: мышь. Левая кнопка на панели — клик (и не уходит дальше, например в захват предметов), колесо — прокрутка.
func _input(event: InputEvent) -> void:
	if rig == null or panel == null or rig.xr_active or not enabled or not panel.is_interactive():
		return
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			if _mouse_over_panel(mb.position):
				var h := _hit_for_mouse(mb.position)
				if not hovering or (h["pos"] as Vector2).distance_to(_last_pos) >= 0.5:
					_last_pos = h["pos"]
					hovering = true
					_send(_motion(_last_pos, Vector2.ZERO))
				set_trigger(true)
				get_viewport().set_input_as_handled()
		elif _pressed:
			set_trigger(false)
			get_viewport().set_input_as_handled()
	elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		if _mouse_over_panel(mb.position):
			panel.scroll_by(-WHEEL_PX if mb.button_index == MOUSE_BUTTON_WHEEL_UP else WHEEL_PX)
			get_viewport().set_input_as_handled()


func _hit_for_mouse(mouse: Vector2) -> Dictionary:
	var cam := rig.camera
	return DeckPointerMath.ray_to_view(cam.project_ray_origin(mouse), cam.project_ray_normal(mouse), panel.surface_transform(),
		panel.panel_size_m(), Vector2(panel.view_size()))


func _mouse_over_panel(mouse: Vector2) -> bool:
	return rig.camera != null and rig.camera.is_inside_tree() and _hit_for_mouse(mouse)["hit"]


func _release_all() -> void:
	if _pressed:
		set_trigger(false)
	if hovering:
		hovering = false
		last_hit = {"hit": false, "reason": "off"}
		_send(_motion(Vector2(-1000.0, -1000.0), Vector2.ZERO))
	_dot.visible = false
	_beam.visible = false


func _send(event: InputEvent) -> void:
	panel.push_pointer_event(event)


func _motion(pos: Vector2, rel: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if _pressed else 0
	return e


func _button(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	return e


## Точка на панели и короткий луч от руки (в плоской сборке луча нет — он шёл бы из камеры). Рядом с панелью, но мимо — слабый луч.
func _update_visuals(origin: Vector3) -> void:
	var hit: bool = last_hit["hit"]
	var near: bool = not hit and last_hit.get("reason", "") == DeckPointerMath.MISS_OUTSIDE and (last_hit["local"] as Vector2).length() <= NEAR_MISS_M
	_dot.visible = hit
	if hit:
		var surface: Transform3D = panel.surface_transform()
		var normal: Vector3 = surface.basis * Vector3(0, 0, 1)
		_dot.global_position = (last_hit["point"] as Vector3) + normal.normalized() * 0.003
	var show_beam: bool = (hit or near) and rig != null and rig.xr_active
	_beam.visible = show_beam
	if show_beam:
		var to: Vector3 = last_hit["point"]
		var span := origin.distance_to(to)
		if span > 0.01:
			_beam.global_position = origin.lerp(to, 0.5)
			_beam.look_at(to, Vector3.UP if absf((to - origin).normalized().y) < 0.99 else Vector3.RIGHT)
			_beam.scale = Vector3(1, 1, span)
		var beam := AssetMaterials.layer("pointer_beam")
		_beam_mat.albedo_color = beam if hit else Color(beam, beam.a * BEAM_MISS_SCALE)


## Цвет точки и луча сейчас (для тестов: слои pointer_dot / pointer_press / pointer_beam).
func dot_color() -> Color:
	return _dot_mat.albedo_color


func beam_color() -> Color:
	return _beam_mat.albedo_color


func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m
