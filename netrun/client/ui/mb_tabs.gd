class_name MbTabs
extends Control
## Вкладки деки (гайдлайн, «Tabs»): подпись ЗАГЛАВНЫМИ, под каждой полоса 3 px; активная — бирюзовая (`acc`), остальные — обвязочные;
## справа от подписи — жёлтый бейдж со счётчиком (непрочитанные, пропущенные). Нажатие — сигнал `tab_selected(id)`.

signal tab_selected(id: String)

## [{id, text, badge: int}]
var items: Array = []
var selected := ""
var _hover := -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _get_minimum_size() -> Vector2:
	return Vector2(0, DeckTheme.TAB_H)


func set_items(list: Array) -> void:
	items = list.duplicate(true)
	queue_redraw()


func select(id: String) -> void:
	if selected != id:
		selected = id
		queue_redraw()


func set_badge(id: String, count: int) -> void:
	for it in items:
		if it["id"] == id and int(it.get("badge", 0)) != count:
			it["badge"] = count
			queue_redraw()


func badge(id: String) -> int:
	for it in items:
		if it["id"] == id:
			return int(it.get("badge", 0))
	return 0


## Прямоугольник вкладки (для проверок и подсветки); вкладки делят ширину поровну.
func tab_rect(index: int) -> Rect2:
	var n := maxi(items.size(), 1)
	var w := size.x / n
	return Rect2(w * index, 0.0, w, size.y)


func _draw() -> void:
	var f := DeckTheme.font_medium()
	var mono := DeckTheme.font_mono()
	var fs := DeckTheme.FS_TAB
	for i in items.size():
		var it: Dictionary = items[i]
		var r := tab_rect(i)
		var active: bool = it["id"] == selected
		var hover := i == _hover and not active
		if hover:
			draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y - 3.0)), Color(DeckTheme.SEL_FILL, 0.35))
		var color := DeckTheme.ACC if active else (DeckTheme.INK if hover else DeckTheme.CHROME)
		var text: String = it["text"]
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var badge_text := PhoneLogic.badge_text(int(it.get("badge", 0)))
		var bw := 0.0
		if not badge_text.is_empty():
			bw = mono.get_string_size(badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, DeckTheme.FS_META).x + 12.0
		var x := r.position.x + (r.size.x - tw - (bw + 6.0 if bw > 0.0 else 0.0)) * 0.5
		var base := (r.size.y - 3.0 + f.get_ascent(fs) - f.get_descent(fs)) * 0.5
		draw_string(f, Vector2(x, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
		if bw > 0.0:
			var tag := Rect2(x + tw + 6.0, (r.size.y - 3.0 - 20.0) * 0.5, bw, 20.0)
			MbShape.draw_frame(self, tag, DeckTheme.MONEY, Color(0, 0, 0, 0), MbShape.Form.TAB, DeckTheme.CUT_SMALL)
			var mb := tag.position.y + (tag.size.y + mono.get_ascent(DeckTheme.FS_META) - mono.get_descent(DeckTheme.FS_META)) * 0.5
			draw_string(mono, Vector2(tag.position.x, mb), badge_text, HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, DeckTheme.FS_META, DeckTheme.ON_MONEY)
		# Полоса под вкладкой: активная — бирюзовая, остальные — светло-розовая приглушённая (3 px), как в приложении.
		var bar_color := DeckTheme.ACC if active else Color(DeckTheme.TAB_BAR_IDLE, 0.55)
		draw_rect(Rect2(r.position.x + 2.0, r.size.y - 3.0, r.size.x - 4.0, 3.0), bar_color)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != -1:
		_hover = -1
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _index_at(event.position)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var i := _index_at(event.position)
		if i >= 0:
			choose(items[i]["id"])
		accept_event()


## Выбрать вкладку как по нажатию: сигнал уходит, даже если она уже выбрана (экран может вернуться к началу).
func choose(id: String) -> void:
	select(id)
	tab_selected.emit(id)


func _index_at(p: Vector2) -> int:
	if items.is_empty() or p.x < 0.0 or p.x >= size.x or p.y < 0.0 or p.y >= size.y:
		return -1
	return clampi(int(p.x / (size.x / items.size())), 0, items.size() - 1)
