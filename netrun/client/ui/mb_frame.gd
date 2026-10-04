class_name MbFrame
extends MarginContainer
## Контейнер со срезанной рамкой (MbShape): панель, пузырь сообщения, метка, плашка. Дети лежат внутри полей; рамка рисуется под ними.

var fill: Color = DeckTheme.PLATE:
	set(v):
		fill = v
		queue_redraw()
var edge: Color = DeckTheme.PLATE_EDGE:
	set(v):
		edge = v
		queue_redraw()
var form: int = MbShape.Form.STD:
	set(v):
		form = v
		queue_redraw()
var cut: float = DeckTheme.CUT:
	set(v):
		cut = v
		queue_redraw()
var border: float = 1.0:
	set(v):
		border = v
		queue_redraw()


## pad — поля внутри рамки по горизонтали и вертикали (px), border не входит в них.
static func make(fill_color: Color, edge_color: Color, frame_form: int, cut_px: float, pad_x: int = 0, pad_y: int = 0) -> MbFrame:
	var f := MbFrame.new()
	f.fill = fill_color
	f.edge = edge_color
	f.form = frame_form
	f.cut = cut_px
	f.set_padding(pad_x, pad_y)
	return f


func set_padding(pad_x: int, pad_y: int) -> void:
	add_theme_constant_override("margin_left", pad_x)
	add_theme_constant_override("margin_right", pad_x)
	add_theme_constant_override("margin_top", pad_y)
	add_theme_constant_override("margin_bottom", pad_y)


func _draw() -> void:
	MbShape.draw_frame(self, Rect2(Vector2.ZERO, size), fill, edge, form, cut, border)
