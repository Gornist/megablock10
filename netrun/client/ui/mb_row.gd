class_name MbRow
extends MarginContainer
## Строка списка деки (гайдлайн, «ListItem»): чаты, журнал звонков. Без рамки, с разделителем `chromeSoft` снизу; наведение — заливка
## `selFill`, нажатая — ярче; у непрочитанной слева жёлтая полоска («новое»). Содержимое (названия, время, бейдж) кладёт тот, кто
## строит строку (DeckUi.label / DeckUi.tag); подписи должны иметь mouse_filter = IGNORE, чтобы нажатие дошло до строки.

signal pressed

var unread := false:
	set(v):
		unread = v
		queue_redraw()
## Строка нажимается целиком. Без этого (журнал звонков, где нажимается только кнопка в строке) — ни подсветки, ни перехвата событий.
var interactive := true:
	set(v):
		interactive = v
		mouse_filter = Control.MOUSE_FILTER_STOP if v else Control.MOUSE_FILTER_PASS
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if v else Control.CURSOR_ARROW
		queue_redraw()
var _hover := false
var _down := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size.y = DeckTheme.ROW_H
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_constant_override("margin_left", 10)
	add_theme_constant_override("margin_right", 10)
	add_theme_constant_override("margin_top", 4)
	add_theme_constant_override("margin_bottom", 4)


func click() -> void:
	pressed.emit()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if _down:
		draw_rect(r, Color(DeckTheme.SEL_FILL, 0.9))
		draw_rect(Rect2(0, 0, size.x, 1), DeckTheme.ACC)
		draw_rect(Rect2(0, size.y - 1, size.x, 1), DeckTheme.ACC)
	elif _hover:
		draw_rect(r, Color(DeckTheme.SEL_FILL, 0.5))
	draw_rect(Rect2(0, size.y - 1, size.x, 1), DeckTheme.CHROME_SOFT)
	if unread:
		draw_rect(Rect2(0, 5, 3, size.y - 10), DeckTheme.MONEY)


func _notification(what: int) -> void:
	if not interactive:
		return
	if what == NOTIFICATION_MOUSE_ENTER:
		_hover = true
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hover = false
		_down = false
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_down = true
			queue_redraw()
		else:
			var inside := Rect2(Vector2.ZERO, size).has_point(event.position)
			var was_down := _down
			_down = false
			queue_redraw()
			if was_down and inside:
				pressed.emit()
		accept_event()
