class_name HintsCorner
extends Control
## Подсказки в углу экрана (flat-playtest.md п. 8): строки из `SoloControls.entries()`; H — скрыть и показать, выбор запоминается (SoloSeen).
## Номер сборки в углу виден всегда, даже когда подсказки скрыты. Мышь не берёт: под ним идёт игра.

const BUILD_PREFIX := "сборка "
const TOGGLE_NOTE := "H — скрыть подсказки"
const TOGGLE_NOTE_HIDDEN := "H — подсказки"
const WIDTH := 430.0
const MARGIN := 14.0

var seen: SoloSeen
var _plate: MbFrame
var _note: Label


## Строки подсказок: «клавиши — действие», в порядке схемы.
static func hint_lines(entries: Array[Dictionary]) -> PackedStringArray:
	var out := PackedStringArray()
	for e in entries:
		out.append("%s — %s" % [str(e.get("keys", "")), str(e.get("action", ""))])
	return out


static func build_text(build: String) -> String:
	return BUILD_PREFIX + build


func _init(seen_: SoloSeen = null) -> void:
	seen = seen_ if seen_ != null else SoloSeen.new()
	name = "HintsCorner"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_plate = MbFrame.make(Color(DeckTheme.PLATE, 0.62), Color(DeckTheme.PLATE_EDGE, 0.8), MbShape.Form.STD, DeckTheme.CUT_SMALL, 12, 8)
	_plate.position = Vector2(MARGIN, MARGIN + 22.0)
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plate)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(col)
	for line in hint_lines(SoloControls.entries()):
		col.add_child(SoloWidgets.paragraph(line, WIDTH, 14, DeckTheme.INK2))
	_note = SoloWidgets.label(TOGGLE_NOTE, 14, DeckTheme.ACC, DeckTheme.font_mono())
	_note.position = Vector2(MARGIN, MARGIN - 4.0)
	add_child(_note)
	# Номер сборки — отдельно, в правом верхнем углу, всегда.
	var build := SoloWidgets.label(build_text(BuildInfo.BUILD), SoloWidgets.FS_META, DeckTheme.INK3, DeckTheme.font_mono())
	build.name = "BuildLabel"
	build.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	build.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	build.offset_left = -MARGIN
	build.offset_right = -MARGIN
	build.offset_top = MARGIN - 4.0
	build.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(build)
	_apply()


func hints_visible() -> bool:
	return seen.hints_visible


## H: скрыть или показать подсказки и запомнить выбор.
func toggle() -> void:
	seen.set_hints_visible(not seen.hints_visible)
	_apply()


func _apply() -> void:
	if _plate == null:
		return
	_plate.visible = seen.hints_visible
	_note.text = TOGGLE_NOTE if seen.hints_visible else TOGGLE_NOTE_HIDDEN
