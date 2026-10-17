class_name SoloScreen
extends Control
## Основа модального экрана тестера: затемнение на всё окно, по центру — панель с заголовком и содержимым. Мышь не пропускает (под экраном идёт игра).
## Экран ничего не решает: нажатая кнопка — сигнал `chosen(action)`, дальше решает SoloUi. Подклассы строят содержимое в `_build(box)`.

signal chosen(action: String)

var panel: MbFrame
var box: VBoxContainer


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = AssetMaterials.layer("end_veil", 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = SoloWidgets.panel()
	center.add_child(panel)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	_build(box)


## Подклассы: заполнить box.
func _build(_box: VBoxContainer) -> void:
	pass


## Кнопка, нажатие которой — chosen(action).
func add_action(parent: Control, text: String, action: String, kind: String = "ghost") -> MbButton:
	var b := SoloWidgets.button(text, kind)
	b.pressed.connect(func(): chosen.emit(action))
	parent.add_child(b)
	return b
