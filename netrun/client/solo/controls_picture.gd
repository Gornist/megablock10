class_name ControlsPicture
extends SoloScreen
## Картинка управления: схема мыши и таблица клавиш по группам, всё нарисовано Control-ами по `SoloControls.entries()` — текст живёт только там.
## Показывается при первом запуске (флаг в SoloSeen) и по кнопке меню.

const TITLE := "УПРАВЛЕНИЕ"
const CLOSE := "ПОНЯТНО"
const ACTION_W := 470.0
const SCROLL_H := 470.0


## Строки схемы по группам в порядке первого появления: [{group, rows: [{keys, action}]}].
static func grouped(entries: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var at := {}
	for e in entries:
		var g := str(e.get("group", ""))
		if not at.has(g):
			at[g] = out.size()
			out.append({"group": g, "rows": []})
		(out[at[g]]["rows"] as Array).append({"keys": str(e.get("keys", "")), "action": str(e.get("action", ""))})
	return out


## Клавиши строки по кепам: «ПКМ / C» — две клавиши; пояснение в скобках остаётся в кепе («ЛКМ (держать)»).
static func key_tokens(keys: String) -> PackedStringArray:
	var out := PackedStringArray()
	for t in keys.split(" / "):
		if not t.strip_edges().is_empty():
			out.append(t.strip_edges())
	return out


func _build(b: VBoxContainer) -> void:
	b.add_child(SoloWidgets.title(TITLE))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	b.add_child(row)
	row.add_child(_MouseSketch.new())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vp_h := get_viewport_rect().size.y if is_inside_tree() else 1080.0
	scroll.custom_minimum_size = Vector2(ACTION_W + 190.0, minf(SCROLL_H, maxf(vp_h - 260.0, 240.0)))
	row.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for g in grouped(SoloControls.entries()):
		list.add_child(SoloWidgets.label(str(g["group"]).to_upper(), SoloWidgets.FS_META, DeckTheme.LABEL, DeckTheme.font_mono()))
		for r: Dictionary in g["rows"]:
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 10)
			var caps := HBoxContainer.new()
			caps.add_theme_constant_override("separation", 5)
			caps.custom_minimum_size.x = 190.0
			for t in key_tokens(str(r["keys"])):
				caps.add_child(SoloWidgets.keycap(t))
			line.add_child(caps)
			line.add_child(SoloWidgets.paragraph(str(r["action"]), ACTION_W, SoloWidgets.FS_SMALL, DeckTheme.INK))
			list.add_child(line)
	add_action(b, CLOSE, "close", "primary")


## Схема мыши: корпус, ЛКМ (прицел), ПКМ (отмена), колесо.
class _MouseSketch extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(150.0, 230.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var f := DeckTheme.font_mono()
		var body := Rect2(25.0, 10.0, 100.0, 150.0)
		var lmb := Rect2(body.position, Vector2(50.0, 65.0))
		var rmb := Rect2(body.position + Vector2(50.0, 0.0), Vector2(50.0, 65.0))
		draw_rect(lmb, Color(DeckTheme.ACC, 0.35))
		draw_rect(rmb, Color(DeckTheme.WARN, 0.25))
		draw_rect(body, DeckTheme.CHROME, false, 2.0)
		draw_line(body.position + Vector2(0.0, 65.0), body.position + Vector2(100.0, 65.0), DeckTheme.CHROME, 2.0)
		draw_line(body.position + Vector2(50.0, 0.0), body.position + Vector2(50.0, 65.0), DeckTheme.CHROME, 2.0)
		draw_rect(Rect2(body.position + Vector2(44.0, 14.0), Vector2(12.0, 28.0)), DeckTheme.INK2)   # колесо
		draw_string(f, Vector2(25.0, 182.0), "ЛКМ: прицел", HORIZONTAL_ALIGNMENT_LEFT, 150.0, 15, DeckTheme.ACC)
		draw_string(f, Vector2(25.0, 202.0), "ПКМ: отмена", HORIZONTAL_ALIGNMENT_LEFT, 150.0, 15, DeckTheme.WARN)
		draw_string(f, Vector2(25.0, 222.0), "мышь: осмотр", HORIZONTAL_ALIGNMENT_LEFT, 150.0, 15, DeckTheme.INK2)
