class_name BreachCell
extends Control
## Клетка сетки взлома на панели (К3): код, состояние (доступна по правилу строка/столбец, выбрана, ловушка, мёртвая, недоступна). Рисуется сама;
## нажимается указателем деки как кнопка (события мыши SubViewport). Нажатие недоступной клетки игнорируется — подсветку считает клиент
## (BreachMirror), подтверждает сервер.

signal tapped(cell: Vector2i)

enum State { IDLE, AVAILABLE, TAKEN, TRAP }

var cell := Vector2i.ZERO
var code := ""
var dead := false
var state: int = State.IDLE:
	set(v):
		if state != v:
			state = v
			queue_redraw()
## Ожидает подтверждения сервера: выбрана у нас, но ещё не у него.
var pending := false:
	set(v):
		pending = v
		queue_redraw()
var font_size := 24
var _hover := false
var _down := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func setup(c: Vector2i, cell_code: String, is_dead: bool, px: int) -> void:
	cell = c
	code = cell_code
	dead = is_dead
	custom_minimum_size = Vector2(px, px)
	font_size = 22 if px < 56 else 24
	queue_redraw()


func is_available() -> bool:
	return state == State.AVAILABLE


## Нажать программно (проверки): то же, что отпускание курка на клетке.
func click() -> void:
	if state == State.AVAILABLE:
		tapped.emit(cell)


func _draw() -> void:
	var fill := DeckTheme.PLATE
	var edge := DeckTheme.PLATE_EDGE
	var ink := DeckTheme.INK3
	match state:
		State.AVAILABLE:
			fill = Color(DeckTheme.SEL_FILL, 0.55 if not _hover else 0.95)
			edge = DeckTheme.ACC
			ink = DeckTheme.INK_STRONG
		State.TAKEN:
			fill = DeckTheme.ACC if not pending else Color(DeckTheme.ACC, 0.6)
			edge = DeckTheme.ACC
			ink = DeckTheme.ACC_INK
		State.TRAP:
			fill = DeckTheme.BAD
			edge = DeckTheme.BAD
			ink = Color.WHITE
		_:
			if dead:
				ink = Color(DeckTheme.BAD, 0.7)
	MbShape.draw_frame(self, Rect2(Vector2.ZERO, size), fill, edge, MbShape.Form.TAB, DeckTheme.CUT_SMALL, 2.0 if state == State.AVAILABLE else 1.0)
	var f := DeckTheme.font_mono()
	var y := (size.y + f.get_ascent(font_size) - f.get_descent(font_size)) * 0.5
	draw_string(f, Vector2(0, y), code, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, ink)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hover = true
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hover = false
		_down = false
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_down = true
		else:
			var inside := Rect2(Vector2.ZERO, size).has_point(event.position)
			var was_down := _down
			_down = false
			if was_down and inside and state == State.AVAILABLE:
				tapped.emit(cell)
		accept_event()
