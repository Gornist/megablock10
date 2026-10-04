class_name DeckUi
extends RefCounted
## Мелкие общие детали экранов деки: подпись, метка (Tag), разделитель, заголовок группы. Экраны строятся только из них и компонентов
## MbFrame / MbButton / MbTabs / MbRow — каждый кусок рисуется одним кодом (гайдлайн: «конструктор, а не рисование»).


## Подпись. variation — вариация из DeckTheme (V_NAME, V_DIM, V_META…); ellipsis — длинный текст обрезается многоточием, а не растягивает ряд.
static func label(text: String, variation: StringName = &"", ellipsis: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ellipsis:
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l


## Метка (гайдлайн, «Tag»): моношрифт, срезанный правый нижний угол. filled — заливка тоном (новое, счётчики), иначе только рамка.
static func tag(text: String, tone: String = "money", filled: bool = true) -> MbFrame:
	var c := DeckTheme.tone_color(tone)
	var f := MbFrame.make(c if filled else Color(0, 0, 0, 0), c, MbShape.Form.TAB, DeckTheme.CUT_SMALL, 6, 1)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(text, &"", false)
	l.theme_type_variation = DeckTheme.V_META
	l.add_theme_color_override("font_color", DeckTheme.ON_MONEY if filled and tone == "money" else (DeckTheme.ACC_INK if filled else c))
	f.add_child(l)
	return f


## Шкала (полоса заполнения): рамка-трек и заливка на долю fraction (0..1) её ширины. Заливка — `ColorRect` на якорях трека, поэтому
## ширина следует за раскладкой.
static func meter(fraction: float, color: Color, height: int = 14) -> Control:
	var m := Control.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.custom_minimum_size.y = height
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var track := MbFrame.make(Color(DeckTheme.PLATE2, 1.0), DeckTheme.PLATE_EDGE, MbShape.Form.TAB, DeckTheme.CUT_SMALL)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_child(track)
	var fill := ColorRect.new()
	fill.color = color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.anchor_left = 0.0
	fill.anchor_top = 0.0
	fill.anchor_right = clampf(fraction, 0.0, 1.0)
	fill.anchor_bottom = 1.0
	fill.offset_left = 2.0
	fill.offset_top = 2.0
	fill.offset_bottom = -2.0
	fill.offset_right = -2.0 if fraction >= 1.0 else 0.0
	fill.visible = fraction > 0.0
	m.add_child(fill)
	return m


static func vbox(separation: int = DeckTheme.GAP) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", separation)
	return b


static func hbox(separation: int = DeckTheme.GAP) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", separation)
	return b


## Растянуть по горизонтали (и по вертикали при vertical).
static func expand(c: Control, vertical: bool = false) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if vertical:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## Заголовок группы (гайдлайн, «SectionTitle»): текст, мета справа, под ними линия бирюзового цвета.
static func section_title(text: String, meta: String = "") -> Control:
	var b := vbox(2)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(expand(label(text, DeckTheme.V_DIM)))
	if not meta.is_empty():
		row.add_child(label(meta, DeckTheme.V_META, false))
	b.add_child(row)
	var line := ColorRect.new()
	line.color = DeckTheme.ACC
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(line)
	return b


## Убрать всех детей: скрыть сразу (раскладка их уже не видит) и освободить в конце кадра. Из дерева не вынимаем: отсоединённая
## ветка с вложенными узлами до конца кадра считается «сиротами» (gdUnit4 красит такой прогон, код выхода 101).
static func clear(node: Node) -> void:
	for c in node.get_children():
		if c.is_queued_for_deletion():
			continue
		if c is CanvasItem:
			(c as CanvasItem).hide()
		c.queue_free()


## Дети, которые ещё живы (не ждут освобождения в конце кадра после clear).
static func live_children(node: Node) -> Array:
	return node.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion())


## Все кнопки поддерева (для проверок).
static func buttons(node: Node) -> Array:
	var out: Array = []
	for c in live_children(node):
		if c is MbButton:
			out.append(c)
		out.append_array(buttons(c))
	return out


## Тексты всех подписей поддерева, кроме скрытых (для проверок).
static func texts(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for c in live_children(node):
		if c is CanvasItem and not (c as CanvasItem).visible:
			continue
		if c is Label:
			out.append((c as Label).text)
		elif c is MbButton:
			out.append((c as MbButton).text)
		out.append_array(texts(c))
	return out
