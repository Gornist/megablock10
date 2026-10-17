class_name SurveyScreen
extends SoloScreen
## Анкета тестера (flat-playtest.md §3): шесть вопросов один раз, после первой настоящей попытки (не учебной). Ответы — в журнал той же попытки
## через RunJournal.log_survey (строка `survey.<id> value=…`), решает и вызывает SoloUi. Свободный текст — как есть, без фильтров.

const KIND_SCALE := "scale"
const KIND_CHOICE := "choice"
const KIND_TEXT := "text"
const TITLE := "ПАРА ВОПРОСОВ"
const SUBMIT := "ОТПРАВИТЬ"
const WIDTH := 640.0
## Вопросы по порядку: id (ключ в журнале), текст, вид, варианты (для scale и choice). Шкала 1–5: 1 — совсем не понял, 5 — всё понял.
const QUESTIONS := [
	{"id": "q1", "text": "Понял ли, почему тебя заметили? (1 — совсем нет, 5 — полностью)", "kind": "scale", "options": ["1", "2", "3", "4", "5"]},
	{"id": "q2", "text": "Понял ли замок к второму взлому?", "kind": "choice", "options": ["да", "нет", "не дошёл"]},
	{"id": "q3", "text": "Где заблудился?", "kind": "text", "options": []},
	{"id": "q4", "text": "Было ли «нечестно» — где?", "kind": "text", "options": []},
	{"id": "q5", "text": "Что раздражало больше всего?", "kind": "text", "options": []},
	{"id": "q6", "text": "Сыграл бы ещё раз?", "kind": "choice", "options": ["да", "нет"]},
]

var _answers := {}                   # id -> строка ответа
var _choice_buttons := {}            # id -> Array[MbButton]
var _edits := {}                     # id -> LineEdit
var _submit: MbButton


## Ответы заполнены: на каждый вопрос со шкалой или выбором есть ответ из списка вариантов (текстовые необязательны).
static func is_complete(answers: Dictionary) -> bool:
	for q: Dictionary in QUESTIONS:
		if str(q["kind"]) != KIND_TEXT and not (str(q["id"]) in answers and str(answers[q["id"]]) in (q["options"] as Array)):
			return false
	return true


## Выбрать вариант (клик по кнопке делает то же).
func select(id: String, option: String) -> void:
	_answers[id] = option
	_refresh()


## Текст свободного ответа (ввод в поле делает то же).
func set_text(id: String, text: String) -> void:
	_answers[id] = text
	var e: LineEdit = _edits.get(id)
	if e != null and e.text != text:
		e.text = text


## Ответы в порядке вопросов: у неотвеченных текстовых — пустая строка, неотвеченных выборов нет (кнопка «Отправить» ждёт их).
func answers() -> Dictionary:
	var out := {}
	for q: Dictionary in QUESTIONS:
		var id := str(q["id"])
		if str(q["kind"]) == KIND_TEXT:
			out[id] = str(_answers.get(id, ""))
		elif id in _answers:
			out[id] = str(_answers[id])
	return out


func can_submit() -> bool:
	return is_complete(answers())


## Отправить анкету (кнопка делает то же): сигнал `chosen("submit")`, если всё обязательное отвечено.
func submit() -> void:
	if can_submit():
		chosen.emit("submit")


func _build(b: VBoxContainer) -> void:
	b.add_child(SoloWidgets.title(TITLE))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vp_h := get_viewport_rect().size.y if is_inside_tree() else 1080.0
	scroll.custom_minimum_size = Vector2(WIDTH + 12.0, minf(560.0, maxf(vp_h - 240.0, 260.0)))
	b.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	for q: Dictionary in QUESTIONS:
		list.add_child(SoloWidgets.paragraph("%s. %s" % [str(q["id"]).trim_prefix("q"), q["text"]], WIDTH, SoloWidgets.FS_BODY, DeckTheme.INK_STRONG))
		if str(q["kind"]) == KIND_TEXT:
			list.add_child(_make_edit(str(q["id"])))
		else:
			list.add_child(_make_choices(str(q["id"]), q["options"]))
	_submit = SoloWidgets.button(SUBMIT, "primary")
	_submit.pressed.connect(submit)   # отправка — только через submit(): с проверкой, что всё обязательное отвечено
	b.add_child(_submit)
	_refresh()


func _make_choices(id: String, options: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var buttons: Array[MbButton] = []
	for o: String in options:
		var btn := SoloWidgets.button(o.to_upper() if o.length() > 1 else o, "ghost")
		btn.button_height = 46.0
		btn.pressed.connect(select.bind(id, o))
		row.add_child(btn)
		buttons.append(btn)
	_choice_buttons[id] = buttons
	return row


func _make_edit(id: String) -> LineEdit:
	var e := LineEdit.new()
	e.custom_minimum_size = Vector2(WIDTH, 44.0)
	e.add_theme_font_override("font", DeckTheme.font_text())
	e.add_theme_font_size_override("font_size", SoloWidgets.FS_BODY)
	e.add_theme_color_override("font_color", DeckTheme.INK)
	e.add_theme_color_override("caret_color", DeckTheme.ACC)
	for st in ["normal", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = DeckTheme.PLATE2
		sb.border_color = DeckTheme.ACC if st == "focus" else DeckTheme.PLATE_EDGE
		sb.set_border_width_all(1)
		sb.set_content_margin_all(8.0)
		e.add_theme_stylebox_override(st, sb)
	e.text_changed.connect(func(t: String): _answers[id] = t)
	_edits[id] = e
	return e


func _refresh() -> void:
	for id: String in _choice_buttons:
		var q := _question(id)
		var opts: Array = q["options"]
		var buttons: Array = _choice_buttons[id]
		for i in buttons.size():
			(buttons[i] as MbButton).kind = "primary" if _answers.get(id, "") == opts[i] else "ghost"
	if _submit != null:
		_submit.disabled = not can_submit()


static func _question(id: String) -> Dictionary:
	for q: Dictionary in QUESTIONS:
		if str(q["id"]) == id:
			return q
	return {}
