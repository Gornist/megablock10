class_name DeckChat
extends VBoxContainer
## Вкладка ЧАТ: список диалогов (позывной, последняя строка, время, бейдж непрочитанных) и переписка выбранного — последние сообщения
## пузырями «я / собеседник» и ряд заготовок быстрого ответа. Отвечать в очках можно только заготовками (PhoneLogic.QUICK_REPLIES):
## свободный текст — с телефона. Открытие диалога = mark_read. Данные — из PhoneLink; сам экран ничего не хранит, кроме открытого диалога.

## Нажата заготовка: диалог и текст (после send_text, для журнала клиента).
signal reply_sent(thread_id: String, text: String)
## Просьба позвонить из шапки диалога (после start_call).
signal call_requested(peer: String)

var link: PhoneLink
var _list_scroll: ScrollContainer
var _list_box: VBoxContainer
var _thread_view: VBoxContainer
var _head_title: Label
var _call_btn: MbButton
var _msg_scroll: ScrollContainer
var _msg_box: VBoxContainer
var _chips: Array = []
var _open_id := ""
var _list_sig := ""
var _msg_sig := ""
var _to_bottom := 0
var _row_ids: Array = []


func _init() -> void:
	add_theme_constant_override("separation", DeckTheme.GAP)
	_list_scroll = _scroll()
	_list_box = DeckUi.vbox(0)
	DeckUi.expand(_list_box)
	_list_scroll.add_child(_list_box)
	add_child(_list_scroll)
	_thread_view = DeckUi.vbox(DeckTheme.GAP)
	DeckUi.expand(_thread_view, true)
	add_child(_thread_view)
	_thread_view.visible = false
	var head := DeckUi.hbox(8)
	var back := MbButton.new("‹ ЧАТЫ", "quiet")
	back.button_height = DeckTheme.BTN_SMALL_H
	back.pressed.connect(close_thread)
	head.add_child(back)
	_head_title = DeckUi.label("", DeckTheme.V_HEAD)
	_head_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	DeckUi.expand(_head_title)
	head.add_child(_head_title)
	_call_btn = MbButton.new("ПОЗВОНИТЬ", "ghost")
	_call_btn.button_height = DeckTheme.BTN_SMALL_H
	_call_btn.pressed.connect(_on_call_pressed)
	head.add_child(_call_btn)
	_thread_view.add_child(head)
	_msg_scroll = _scroll()
	_msg_box = DeckUi.vbox(DeckTheme.GAP)
	DeckUi.expand(_msg_box)
	_msg_scroll.add_child(_msg_box)
	_thread_view.add_child(_msg_scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", DeckTheme.GAP)
	grid.add_theme_constant_override("v_separation", DeckTheme.GAP)
	for phrase in PhoneLogic.QUICK_REPLIES:
		var b := MbButton.new(phrase, "chip")
		b.button_height = DeckTheme.CHIP_H
		b.pad_x = 6.0
		DeckUi.expand(b)
		b.pressed.connect(_on_chip.bind(phrase))
		grid.add_child(b)
		_chips.append(b)
	_thread_view.add_child(grid)
	set_process(false)


func bind(phone: PhoneLink) -> void:
	link = phone
	refresh()


func current_thread() -> String:
	return _open_id


## Показан список диалогов (а не переписка).
func is_list_shown() -> bool:
	return _open_id.is_empty()


func open_thread(thread_id: String) -> void:
	if link == null or thread_id.is_empty():
		return
	_open_id = thread_id
	_list_scroll.visible = false
	_thread_view.visible = true
	_msg_sig = ""
	link.mark_read(thread_id)
	refresh()


func close_thread() -> void:
	_open_id = ""
	_thread_view.visible = false
	_list_scroll.visible = true
	_list_sig = ""
	refresh()


## Перестроить то, что изменилось. Одинаковые данные не трогаем (ни лишней раскладки, ни перерисовки).
func refresh() -> void:
	if link == null:
		return
	if _open_id.is_empty():
		_refresh_list()
	else:
		_refresh_thread()


## Пришло сообщение, пока открыт этот диалог и вкладка на виду, — оно сразу прочитано.
func on_message_received(thread_id: String) -> void:
	if link != null and thread_id == _open_id and is_visible_in_tree():
		link.mark_read(thread_id)


## Двигает видимый список (стик указателя, колесо мыши).
func scroll_by(px: float) -> void:
	var sc := _msg_scroll if _thread_view.visible else _list_scroll
	sc.scroll_vertical += roundi(px)


func chip_buttons() -> Array:
	return _chips


func row_titles() -> PackedStringArray:
	var out := PackedStringArray()
	for id in _row_ids:
		out.append(str(id))
	return out


## Нажатие на строку списка (для проверок): как указателем.
func press_row(thread_id: String) -> void:
	for row in DeckUi.live_children(_list_box):
		if row is MbRow and row.get_meta("thread_id", "") == thread_id:
			(row as MbRow).click()
			return


func bubble_count() -> int:
	return DeckUi.live_children(_msg_box).size()


func call_button() -> MbButton:
	return _call_btn


func message_scroll() -> ScrollContainer:
	return _msg_scroll


func _process(_delta: float) -> void:
	# Содержимое только что построено: после раскладки уходим вниз, к свежим сообщениям.
	_msg_scroll.scroll_vertical = int(_msg_scroll.get_v_scroll_bar().max_value)
	_to_bottom -= 1
	if _to_bottom <= 0:
		set_process(false)


# ---------------------------------------------------------------- список

func _refresh_list() -> void:
	var threads := PhoneLogic.sort_threads(link.threads())
	var sig := str(threads.map(func(t): return [t["id"], t["unread"], t["last_text"], t["last_ts"]]))
	if sig == _list_sig:
		return
	_list_sig = sig
	DeckUi.clear(_list_box)
	_row_ids.clear()
	for t in threads:
		_list_box.add_child(_thread_row(t))
		_row_ids.append(t["title"])
	if threads.is_empty():
		_list_box.add_child(DeckUi.label("Диалогов пока нет. Сообщения придут с телефона.", DeckTheme.V_DIM, false))


func _thread_row(t: Dictionary) -> MbRow:
	var unread := int(t["unread"])
	var row := MbRow.new()
	row.unread = unread > 0
	row.set_meta("thread_id", t["id"])
	var h := DeckUi.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := DeckUi.vbox(0)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	DeckUi.expand(left)
	var name_row := DeckUi.hbox(8)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_l := DeckUi.label(str(t["title"]), DeckTheme.V_NAME)
	name_l.add_theme_color_override("font_color", DeckTheme.INK_STRONG if unread > 0 else Color("#9FB8B4"))
	DeckUi.expand(name_l)   # подпись с многоточием без растяжки сжимается в ноль
	name_row.add_child(name_l)
	if t["kind"] == PhoneLink.KIND_FACTION:
		name_row.add_child(DeckUi.tag("ФРАКЦИЯ", "ok", false))
	left.add_child(name_row)
	var preview := DeckUi.label(str(t["last_text"]), DeckTheme.V_DIM)
	preview.add_theme_color_override("font_color", DeckTheme.INK if unread > 0 else Color("#6F8784"))
	left.add_child(preview)
	h.add_child(left)
	var right := DeckUi.vbox(2)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var time_l := DeckUi.label(PhoneLogic.clock_text(float(t["last_ts"])) if float(t["last_ts"]) > 0.0 else "", DeckTheme.V_META, false)
	time_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(time_l)
	if unread > 0:
		var badge := DeckUi.tag(PhoneLogic.badge_text(unread), "money", true)
		badge.size_flags_horizontal = Control.SIZE_SHRINK_END
		right.add_child(badge)
	h.add_child(right)
	row.add_child(h)
	row.pressed.connect(open_thread.bind(str(t["id"])))
	return row


# ---------------------------------------------------------------- переписка

func _refresh_thread() -> void:
	var t := _find_thread(_open_id)
	if t.is_empty():
		close_thread()
		return
	var faction: bool = t["kind"] == PhoneLink.KIND_FACTION
	_head_title.text = str(t["title"])
	_call_btn.visible = not faction
	_call_btn.disabled = link.call_state()["phase"] != PhoneLink.PHASE_IDLE
	var msgs := link.messages(_open_id, PhoneLogic.MESSAGES_SHOWN)
	var sig := str(msgs.map(func(m): return [m["id"], m["status"]]))
	if sig == _msg_sig:
		return
	var grew := msgs.size() > 0 and _msg_sig != ""
	_msg_sig = sig
	DeckUi.clear(_msg_box)
	for m in msgs:
		_msg_box.add_child(_bubble(m, faction))
	if msgs.is_empty():
		_msg_box.add_child(DeckUi.label("Сообщений пока нет. Ответьте заготовкой.", DeckTheme.V_DIM, false))
	_to_bottom = 3
	set_process(true)
	if grew:
		_msg_scroll.scroll_vertical = int(_msg_scroll.get_v_scroll_bar().max_value)


func _find_thread(id: String) -> Dictionary:
	for t in link.threads():
		if t["id"] == id:
			return t
	return {}


## Пузырь: свой — справа, срез слева сверху; чужой — слева, срез справа сверху. Время (и статус для своих) — справа в той же строке.
func _bubble(m: Dictionary, faction: bool) -> Control:
	var mine: bool = m["mine"]
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_END if mine else BoxContainer.ALIGNMENT_BEGIN
	var failed: bool = mine and m["status"] == PhoneLink.STATUS_FAILED
	var frame := MbFrame.make(
		Color("#3A1214") if failed else (DeckTheme.BUBBLE_OWN_FILL if mine else DeckTheme.BUBBLE_IN_FILL),
		DeckTheme.BAD if failed else (DeckTheme.BUBBLE_OWN_EDGE if mine else DeckTheme.BUBBLE_IN_EDGE),
		MbShape.Form.OWN if mine else MbShape.Form.STD, DeckTheme.CUT_BUBBLE, 9, 4)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := DeckUi.vbox(0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(col)
	if faction and not mine and not str(m.get("from", "")).is_empty():
		col.add_child(DeckUi.label(str(m["from"]), DeckTheme.V_ACC, false))
	var line := DeckUi.hbox(8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text := str(m["text"])
	var body := DeckUi.label(text, &"", false)
	body.add_theme_color_override("font_color", Color("#FFE3DF") if failed else (DeckTheme.BUBBLE_OWN_TEXT if mine else DeckTheme.BUBBLE_IN_TEXT))
	var meta_text := PhoneLogic.clock_text(float(m["ts"]))
	if mine:
		meta_text += {"sent": " ✓", "delivered": " ✓✓", "failed": " !"}.get(m["status"], "")
	var meta := DeckUi.label(meta_text, DeckTheme.V_META, false)
	meta.size_flags_vertical = Control.SIZE_SHRINK_END
	var text_w := DeckTheme.font_text().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, DeckTheme.FS_TEXT).x
	var meta_w := DeckTheme.font_mono().get_string_size(meta_text, HORIZONTAL_ALIGNMENT_LEFT, -1, DeckTheme.FS_META).x
	var avail := DeckTheme.BUBBLE_MAX_W - 18.0 - meta_w - 8.0
	if text_w <= avail:
		body.custom_minimum_size.x = ceilf(text_w) + 1.0
	else:
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size.x = avail
	line.add_child(body)
	line.add_child(meta)
	col.add_child(line)
	if failed:
		col.add_child(DeckUi.label(PhoneLogic.status_text(PhoneLink.STATUS_FAILED) + " · повторится само", DeckTheme.V_BAD, false))
	row.add_child(frame)
	return row


# ---------------------------------------------------------------- действия

func _on_chip(phrase: String) -> void:
	if link == null or _open_id.is_empty():
		return
	link.send_text(_open_id, phrase)
	reply_sent.emit(_open_id, phrase)


func _on_call_pressed() -> void:
	if link == null or _open_id.is_empty():
		return
	var t := _find_thread(_open_id)
	if t.is_empty() or t["kind"] != PhoneLink.KIND_DM:
		return
	link.start_call(str(t["title"]))
	call_requested.emit(str(t["title"]))


func _scroll() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	DeckUi.expand(sc, true)
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	return sc
