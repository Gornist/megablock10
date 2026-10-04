class_name MbButton
extends Control
## Кнопка деки (гайдлайн, «Button»): срезанная рамка, подпись ЗАГЛАВНЫМИ, виды primary / ghost / success / danger / alert / quiet и chip
## (заготовка ответа). Нажимается указателем деки (DeckPointer) через обычные события мыши SubViewport; отпускание внутри кнопки —
## сигнал `pressed`. Наведение подсвечивает рамку и заливку, нажатие — ярче (×1,35, как в приложении).

signal pressed

var text := "":
	set(v):
		text = v
		update_minimum_size()
		queue_redraw()
var kind := "ghost":
	set(v):
		kind = v
		queue_redraw()
var disabled := false:
	set(v):
		disabled = v
		queue_redraw()
var font_size := DeckTheme.FS_BUTTON
var button_height := DeckTheme.BTN_H:
	set(v):
		button_height = v
		update_minimum_size()
## Поля по горизонтали при расчёте минимальной ширины.
var pad_x := 14.0
var _hover := false
var _down := false


func _init(label: String = "", button_kind: String = "ghost") -> void:
	text = label
	kind = button_kind
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _get_minimum_size() -> Vector2:
	var w := DeckTheme.font_medium().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return Vector2(ceilf(w + pad_x * 2.0), button_height)


func is_hovered_now() -> bool:
	return _hover


## Нажать программно (проверки; отпускание внутри кнопки делает то же).
func click() -> void:
	if not disabled:
		pressed.emit()


func _draw() -> void:
	var c := DeckTheme.button_colors(kind, disabled)
	var fill: Color = c["fill"]
	var edge: Color = c["edge"]
	var chip := kind == "chip"
	if not disabled:
		if _down:
			fill = fill.lightened(0.35)
		elif _hover:
			fill = DeckTheme.SEL_FILL if chip else fill.lightened(0.15)
			edge = DeckTheme.ACC if chip else edge.lightened(0.25)
	var form := MbShape.Form.TAB if chip else MbShape.Form.STD
	MbShape.draw_frame(self, Rect2(Vector2.ZERO, size), fill, edge, form, DeckTheme.CUT_SMALL if chip else DeckTheme.CUT, 1.5 if _hover and not disabled else 1.0)
	var f := DeckTheme.font_medium()
	var y := (size.y + f.get_ascent(font_size) - f.get_descent(font_size)) * 0.5
	draw_string(f, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, c["text"])


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
			queue_redraw()
		else:
			var inside := Rect2(Vector2.ZERO, size).has_point(event.position)
			var was_down := _down
			_down = false
			queue_redraw()
			if was_down and inside and not disabled:
				pressed.emit()
		accept_event()
