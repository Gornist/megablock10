class_name DeckGive
extends VBoxContainer
## Отправка добычи другому игроку (К5б), экран поверх вкладки ДОБЫЧА: выбор получателя → подтверждение. Из ГРУЗа отправляют шарды и демонов,
## которые можно отдать (ev deck.loot[].give); защищённые и рабочие кнопки «ОТПРАВИТЬ» не получают. Получатели одним списком: нетраннеры в Сети
## (кто в том же узле — первыми), затем контакты телефона (PhoneLink.contacts()). Список нетраннеров приходит с сервера позже, чем экран открыт:
## пока его нет, строка «Ищу игроков в Сети…», контакты видны сразу. Подтверждение всегда: отправленное нельзя вернуть и оно уходит из-под риска забега.
## Сам экран ничего не отправляет — он сообщает выбор (confirmed), а ответ сервера показывает панель строкой на ДОБЫЧЕ.

## Игрок подтвердил: id предмета, получатель (target — как уйдёт в `give.to`) и подпись получателя для итоговой строки.
signal confirmed(item_id: String, target: Dictionary, label: String)
## Закрыт без отправки («НАЗАД», «ОТМЕНА»).
signal closed

enum Step { PICK, CONFIRM }

## Ширина строки про последствия: в панели 512 px минус поля.
const WARN_WIDTH := 460.0

var _row: Dictionary = {}
var _runners: Variant = null            ## null — список ещё не пришёл
var _contacts: Array = []
var _targets: Array = []
var _chosen: Dictionary = {}
var _step := Step.PICK
var _head_title: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _confirm_box: VBoxContainer
var _confirm_lines: Array = []


func _init() -> void:
	add_theme_constant_override("separation", DeckTheme.GAP)
	var head := DeckUi.hbox(8)
	var back := MbButton.new("‹ НАЗАД", "quiet")
	back.button_height = DeckTheme.BTN_SMALL_H
	back.pressed.connect(_on_back)
	head.add_child(back)
	_head_title = DeckUi.label("", DeckTheme.V_HEAD)
	_head_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	DeckUi.expand(_head_title)
	head.add_child(_head_title)
	add_child(head)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	DeckUi.expand(_scroll, true)
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_list = DeckUi.vbox(0)
	DeckUi.expand(_list)
	_scroll.add_child(_list)
	add_child(_scroll)
	_confirm_box = DeckUi.vbox(DeckTheme.GAP)
	DeckUi.expand(_confirm_box, true)
	add_child(_confirm_box)
	visible = false


## Показать выбор получателя для строки ГРУЗа [param row] (HudLogic.loot_rows); [param contacts] — контакты телефона сразу.
func open(row: Dictionary, contacts: Array) -> void:
	_row = row
	_contacts = contacts
	_runners = null
	_chosen = {}
	_step = Step.PICK
	visible = true
	_rebuild()


## Пришёл список нетраннеров в Сети ([{id, name, same}]) — если экран ещё открыт на выборе, он обновляется.
func set_runners(runners: Array) -> void:
	_runners = runners
	if visible and _step == Step.PICK:
		_rebuild()


func is_open() -> bool:
	return visible


func step_name() -> String:
	return "confirm" if _step == Step.CONFIRM else "pick"


func item_id() -> String:
	return str(_row.get("id", ""))


func close() -> void:
	var was := visible
	visible = false
	_row = {}
	_chosen = {}
	if was:
		closed.emit()


## Выбрать получателя по месту в списке (для проверок и указки): как нажатие строки.
func choose(index: int) -> void:
	if index >= 0 and index < _targets.size():
		_on_pick(_targets[index])


## Подтвердить (для проверок): как нажатие «ОТПРАВИТЬ» на втором шаге.
func confirm() -> void:
	if _step != Step.CONFIRM or _chosen.is_empty():
		return
	var id := item_id()
	var target: Dictionary = _chosen["target"]
	var label := str(_chosen["label"])
	visible = false
	_row = {}
	_chosen = {}
	confirmed.emit(id, target, label)


func targets() -> Array:
	return _targets


## Что видно сейчас (для проверок): подписи экрана.
func texts() -> PackedStringArray:
	return DeckUi.texts(self)


func scroll_by(px: float) -> void:
	_scroll.scroll_vertical += roundi(px)


func _on_back() -> void:
	if _step == Step.CONFIRM:
		_step = Step.PICK
		_rebuild()
	else:
		close()


func _on_pick(target_row: Dictionary) -> void:
	_chosen = target_row
	_step = Step.CONFIRM
	_rebuild()


func _rebuild() -> void:
	_head_title.text = "Отправить: %s" % _row.get("title", "?")
	_scroll.visible = _step == Step.PICK
	_confirm_box.visible = _step == Step.CONFIRM
	DeckUi.clear(_list)
	DeckUi.clear(_confirm_box)
	if _step == Step.PICK:
		_build_pick()
	else:
		_build_confirm()


func _build_pick() -> void:
	_targets = HudLogic.give_targets(_runners if _runners is Array else [], _contacts)
	var section := ""
	for i in _targets.size():
		var t: Dictionary = _targets[i]
		if t["section"] != section:
			section = t["section"]
			_list.add_child(DeckUi.section_title(section))
		_list.add_child(_target_row(t))
	if _runners == null:
		_list.add_child(DeckUi.label("Ищу игроков в Сети…", DeckTheme.V_DIM, false))
	elif _targets.is_empty():
		_list.add_child(DeckUi.label("Получателей нет: в Сети никого, контактов телефона тоже", DeckTheme.V_DIM, false))
	elif not _targets.any(func(t: Dictionary) -> bool: return t["kind"] == WorldMsg.VIA_RUNNER):
		_list.add_child(DeckUi.label("Других игроков в Сети сейчас нет", DeckTheme.V_DIM, false))


func _target_row(t: Dictionary) -> MbRow:
	var r := MbRow.new()
	var h := DeckUi.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_l := DeckUi.label(str(t["label"]), DeckTheme.V_NAME)
	DeckUi.expand(name_l)
	h.add_child(name_l)
	var tag := DeckUi.tag(str(t["tag"]), "acc" if t["kind"] == WorldMsg.VIA_RUNNER else "ok", t["same"])
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tag)
	r.add_child(h)
	r.pressed.connect(_on_pick.bind(t))
	return r


func _build_confirm() -> void:
	_confirm_lines = HudLogic.give_confirm_lines(_row, _chosen)
	_confirm_box.add_child(DeckUi.label(str(_confirm_lines[0]), DeckTheme.V_NAME))
	var warn := DeckUi.label(str(_confirm_lines[1]), DeckTheme.V_WARN, false)
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.custom_minimum_size.x = WARN_WIDTH
	_confirm_box.add_child(warn)
	var spacer := Control.new()
	DeckUi.expand(spacer, true)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm_box.add_child(spacer)
	var buttons := DeckUi.hbox(DeckTheme.GAP)
	var send := MbButton.new("ОТПРАВИТЬ", "success")
	send.button_height = DeckTheme.BTN_H
	DeckUi.expand(send)
	send.pressed.connect(confirm)
	var cancel := MbButton.new("ОТМЕНА", "quiet")
	cancel.button_height = DeckTheme.BTN_H
	DeckUi.expand(cancel)
	cancel.pressed.connect(_on_back)
	buttons.add_child(send)
	buttons.add_child(cancel)
	_confirm_box.add_child(buttons)
