class_name SoloControls
extends Node
## Управление одиночной игры для тестеров без гарнитуры (docs/gamedesign/flat-playtest.md §1 п. 4–5): ход — только телепорт, прицел по центру экрана,
## поворот щелчком 45°, WASD нет. Здесь — схема управления (`entries()`: по ней К5 рисует подсказки в углу и картинку управления, текст подсказок живёт только здесь)
## и само управление мышью.
## Мышь захвачена: взгляд ведёт мышь, в центре экрана точка-прицел; ЛКМ зажата — прицел телепорта, отпустить — прыжок; ПКМ или C — отмена.
## Tab — свободный курсор: взгляд замирает, мышь нажимает деку и панель взлома (клики, колесо); ещё раз Tab — обратно к взгляду.
## Панель взлома видна (хранилище рядом) — курсор освобождается сам и возвращается, когда панель закрыта; Tab при открытой панели — вернуться к взгляду, пока она не закроется.
## Подключение: flat_stub.start с аргументом --tester (его передаст solo_stub); сам риг в режиме тестера — XRRig.set_tester_mode.

## Курсор освобождён (true — мышь нажимает деку и панель взлома, взгляд замер) или захвачен (false — мышь ведёт взгляд, в центре точка-прицел).
signal cursor_mode_changed(free: bool)

## Диаметр точки-прицела, px. Цвет — слой pointer_dot палитры клиента (AssetMaterials.layer): ледяной белый, как точка указки на деке.
const CROSSHAIR_PX := 5.0

var rig: XRRig
var breach_panel: Node
var crosshair: Control
var _panel_open := false
var _flip := false          # Tab: курсор противоположен тому, что просит панель
var _applied := true        # какой режим курсора применён к окну и риге
var _aim_down := false
var _aim_blocked := false   # прицел отменён при зажатой ЛКМ: заново — только после отпускания


## Схема управления, строка за строкой: {"keys": что нажать, "action": что происходит, "group": ход / взгляд / действия / курсор / система}.
## Чистая функция: порядок строк — порядок подсказок; ни одной клавиши ходьбы в схеме нет.
static func entries() -> Array[Dictionary]:
	return [
		{"keys": "ЛКМ (держать)", "action": "прицел телепорта: точка в центре экрана; отпустить — прыжок", "group": "ход"},
		{"keys": "ПКМ / C", "action": "отменить прицел", "group": "ход"},
		{"keys": "Q / E", "action": "поворот на 45°", "group": "ход"},
		{"keys": "Мышь", "action": "осмотр", "group": "взгляд"},
		{"keys": "R", "action": "центровка взгляда", "group": "взгляд"},
		{"keys": "F", "action": "взять объект у прицела", "group": "действия"},
		{"keys": "1–9", "action": "применить демона из деки", "group": "действия"},
		{"keys": "X", "action": "выйти на площадке выхода", "group": "действия"},
		{"keys": "Tab", "action": "курсор: нажимать деку и панель взлома мышью (ещё раз — обратно к взгляду)", "group": "курсор"},
		{"keys": "Колесо", "action": "прокрутка списков на деке (при свободном курсоре)", "group": "курсор"},
		{"keys": "Esc (3 с)", "action": "аварийный выход", "group": "система"},
	]


## Включить режим тестера у рига: breach_panel_ — панель взлома (ждёт is_interactive; null — курсор только по Tab). Мышь сразу захватывается.
func setup(rig_: XRRig, breach_panel_: Node = null) -> void:
	rig = rig_
	breach_panel = breach_panel_
	rig.set_tester_mode(true)
	crosshair = _build_crosshair()
	_applied = not is_free()   # заставить _apply сработать при первом вызове
	_apply(false)


## Курсор свободен сейчас (мышь нажимает деку и панель, взгляд замер).
func is_free() -> bool:
	return _panel_open != _flip


## Панель взлома открылась / закрылась: курсор следует за ней, ручной Tab сбрасывается.
func set_panel_open(open: bool) -> void:
	if open == _panel_open:
		return
	_panel_open = open
	_flip = false
	_apply(true)


## Tab: переключить курсор.
func toggle_cursor() -> void:
	_flip = not _flip
	_apply(true)


func _apply(notify: bool) -> void:
	var f := is_free()
	if f == _applied:
		return
	_applied = f
	rig.mouse_captured = not f
	if f:
		if rig.is_aiming() or _aim_down:
			rig.request_aim_cancel()
		_aim_down = false
		_aim_blocked = false
		rig.tester_aim = false
	if crosshair != null:
		crosshair.visible = not f
	_set_window_mouse(f)
	if notify:
		cursor_mode_changed.emit(f)


func _set_window_mouse(free: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if free else Input.MOUSE_MODE_CAPTURED
	var vp := get_viewport() if is_inside_tree() else null
	if free and vp != null:
		vp.warp_mouse(vp.get_visible_rect().size / 2.0)   # курсор появляется в центре, там, куда только что смотрел взгляд


func _process(_delta: float) -> void:
	var open := breach_panel != null and is_instance_valid(breach_panel) and bool(breach_panel.call("is_interactive"))
	set_panel_open(open)


func _input(event: InputEvent) -> void:
	if rig == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_TAB:
			toggle_cursor()
			_handled()
		elif event.physical_keycode == KEY_C:
			_cancel_while_held()   # сам прицел отменяет риг (клавиша C); здесь — не дать зажатой ЛКМ тут же начать новый
		return
	if is_free() or not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_aim_down = true
		else:
			_aim_down = false
			_aim_blocked = false
		rig.tester_aim = _aim_down and not _aim_blocked
		_handled()   # ЛКМ — прицел, а не «взять объект» (его делает F)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			rig.request_aim_cancel()
			_cancel_while_held()
		_handled()


## Свободный курсор: ЛКМ и ПКМ, не попавшие в панель (панель берёт их раньше), не должны «брать объект» в сцене.
func _unhandled_input(event: InputEvent) -> void:
	if rig != null and is_free() and event is InputEventMouseButton:
		var b: int = (event as InputEventMouseButton).button_index
		if b == MOUSE_BUTTON_LEFT or b == MOUSE_BUTTON_RIGHT:
			_handled()


func _cancel_while_held() -> void:
	if _aim_down:
		_aim_blocked = true
		rig.tester_aim = false


func _handled() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and rig != null:
		_set_window_mouse(is_free())   # вернулись в окно: захват мыши ОС снимает при потере фокуса
	elif what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		if rig != null:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_crosshair() -> Control:
	var layer := CanvasLayer.new()
	layer.name = "Crosshair"
	layer.layer = 5
	add_child(layer)
	var c := _Crosshair.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(c)
	return c


## Точка по центру экрана (взгляд камеры — центр окна).
class _Crosshair extends Control:
	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var center := size / 2.0
		draw_circle(center, SoloControls.CROSSHAIR_PX / 2.0 + 1.0, Color(0.0, 0.0, 0.0, 0.55))   # тёмный ободок: точка читается и на светлом
		draw_circle(center, SoloControls.CROSSHAIR_PX / 2.0, AssetMaterials.layer("pointer_dot"))
