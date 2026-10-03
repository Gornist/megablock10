class_name DeckPanel
extends Node3D
## Дека на руке: панель в мире; 2D-содержимое рисуется только в SubViewport и показывается на поверхности (Sprite3D).
## Данные — словарь {"daemons": [{id, name, cooldown_left}], "selected": id}; позже придут с сервера.

const VIEW_SIZE := Vector2i(320, 240)
## Не чаще стольких перерисовок деки в секунду: на Pico кадр рендерится дважды, а текст деки меняется раз в секунду.
const MAX_FPS := 30.0

## Сколько раз содержимое деки рисовалось в текстуру (для проверки).
var redraw_count := 0

var _list: VBoxContainer
var _viewport: SubViewport
var _surface: Sprite3D
var _shown_rows: Array = []
var _dirty := true
var _since_draw := 0.0


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = VIEW_SIZE
	_viewport.transparent_bg = true
	# Рисуем по требованию (см. _process), а не каждый кадр.
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	var bg := PanelContainer.new()
	bg.size = Vector2(VIEW_SIZE)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.06, 0.1, 0.85)
	style.border_color = Color(0.1, 0.8, 0.9)
	style.set_border_width_all(3)
	bg.add_theme_stylebox_override("panel", style)
	_viewport.add_child(bg)
	_list = VBoxContainer.new()
	bg.add_child(_list)
	_surface = Sprite3D.new()
	_surface.texture = _viewport.get_texture()
	_surface.pixel_size = 0.0005
	_surface.shaded = false
	_surface.double_sided = false
	add_child(_surface)
	set_deck({"daemons": [], "selected": ""})


## Перерисовка по требованию, не чаще MAX_FPS: UPDATE_ALWAYS гнал бы лишний рендер каждого кадра в обоих глазах.
func _process(delta: float) -> void:
	_since_draw += delta
	if _dirty and _since_draw >= 1.0 / MAX_FPS:
		_dirty = false
		_since_draw = 0.0
		redraw_count += 1
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func set_deck(deck: Dictionary) -> void:
	var rows := HudLogic.deck_rows(deck)
	# Сервер шлёт состояние чаще, чем меняется текст: то же самое не перестраиваем и не перерисовываем.
	if rows == _shown_rows and _list.get_child_count() > 0:
		return
	_shown_rows = rows
	_dirty = true
	for c in _list.get_children():
		c.queue_free()
		_list.remove_child(c)
	var title := Label.new()
	title.text = "ДЕКА"
	title.add_theme_color_override("font_color", Color(0.1, 0.8, 0.9))
	_list.add_child(title)
	for row in rows:
		var l := Label.new()
		l.text = ("> " if row["selected"] else "  ") + row["text"]
		l.add_theme_color_override("font_color", Color(0.3, 1.0, 0.6) if row["ready"] else Color(0.7, 0.7, 0.75))
		_list.add_child(l)


## Для проверки: что рисует панель.
func row_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for c in _list.get_children():
		if c is Label:
			out.append(c.text)
	return out


func has_viewport_surface() -> bool:
	return _surface.texture == _viewport.get_texture()
