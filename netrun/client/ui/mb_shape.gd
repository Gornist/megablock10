class_name MbShape
extends RefCounted
## Рамка со срезанным углом — единственная форма рамки в дизайн-системе приложения (гайдлайн, раздел 4): StyleBoxFlat срез не умеет,
## поэтому рисуем многоугольник сами. Формы — как MbChamferForm в app: STD (срезаны правый верхний и левый нижний), TAB (правый нижний),
## DLG (правый верхний); OWN — зеркало STD для своих сообщений (срезаны левый верхний и правый нижний). Рамка — два слоя: многоугольник цвета
## рамки и поверх него такой же, меньший на толщину рамки, цвета заливки (так же рисует Modifier.mbFrame в приложении).

enum Form { STD, TAB, DLG, OWN }


## Контур формы в системе координат (0, 0)…size. Срез не больше половины меньшей стороны; нулевой срез — обычный прямоугольник.
static func outline(size: Vector2, form: int, cut: float) -> PackedVector2Array:
	var c := clampf(cut, 0.0, minf(size.x, size.y) * 0.5)
	var w := size.x
	var h := size.y
	if c < 0.5:
		return PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])
	match form:
		Form.TAB:
			return PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h - c), Vector2(w - c, h), Vector2(0, h)])
		Form.DLG:
			return PackedVector2Array([Vector2(0, 0), Vector2(w - c, 0), Vector2(w, c), Vector2(w, h), Vector2(0, h)])
		Form.OWN:
			return PackedVector2Array([Vector2(c, 0), Vector2(w, 0), Vector2(w, h - c), Vector2(w - c, h), Vector2(0, h), Vector2(0, c)])
	return PackedVector2Array([Vector2(0, 0), Vector2(w - c, 0), Vector2(w, c), Vector2(w, h), Vector2(c, h), Vector2(0, h - c)])


## Рамка + заливка внутри rect на canvas item ci. Прозрачная рамка (edge.a = 0) — только заливка; без заливки (fill.a = 0) — только
## контур линией (многоугольник цвета рамки закрыл бы заливку и «дыру» из прозрачного не пробить).
static func draw_frame(ci: CanvasItem, rect: Rect2, fill: Color, edge: Color, form: int, cut: float, width: float = 1.0) -> void:
	if rect.size.x < 2.0 or rect.size.y < 2.0:
		return
	if fill.a <= 0.0:
		if edge.a > 0.0 and width > 0.0:
			var half := width * 0.5
			var line := _moved(outline(rect.size - Vector2(width, width), form, maxf(cut - half, 0.0)), rect.position + Vector2(half, half))
			line.append(line[0])
			ci.draw_polyline(line, edge, width)
		return
	if edge.a > 0.0 and width > 0.0:
		ci.draw_colored_polygon(_moved(outline(rect.size, form, cut), rect.position), edge)
	var inset := width if edge.a > 0.0 else 0.0
	var inner := Rect2(rect.position + Vector2(inset, inset), rect.size - Vector2(inset, inset) * 2.0)
	if inner.size.x >= 1.0 and inner.size.y >= 1.0:
		ci.draw_colored_polygon(_moved(outline(inner.size, form, maxf(cut - inset, 0.0)), inner.position), fill)


static func _moved(poly: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(poly.size())
	for i in poly.size():
		out[i] = poly[i] + by
	return out
