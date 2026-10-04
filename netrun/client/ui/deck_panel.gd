class_name DeckPanel
extends Node3D
## Дека на руке: панель в мире; 2D-содержимое рисуется только в SubViewport и показывается на поверхности (Sprite3D).
## Вкладки ДЕКА | ДОБЫЧА | ЧАТ | ЗВОНКИ: ДЕКА — полоса RAM и ПРОГРАММЫ (рабочие демоны: имя, тир, цепочка, эффект, состояние; данные с сервера:
## {"daemons": [{id, name, cooldown_left, st?, active_left?, tier?, cells?, effect?, unsupported?}], "selected": id, "ram"?, "used"?, "ram_default"?}),
## ДОБЫЧА — шарды, добытые демоны и эдди без действий (set_loot; вкладка появляется, когда сервер прислал деку), ЧАТ и ЗВОНКИ — мессенджер и звонки
## из PhoneLink (сейчас фиктивный FakePhoneLink). Без связи с телефоном (set_phone не вызван или --phone=off) ЧАТ и ЗВОНКИ скрыты; пока
## сервер не прислал деку (голая панель в тестах) нет и ДОБЫЧИ: остаётся одна ДЕКА, как раньше.
## Нажимает указатель правого контроллера (DeckPointer): события мыши идут прямо в SubViewport (push_pointer_event).

## Размер текстуры панели, px, и физическая ширина панели при масштабе 1, м (высота — по соотношению сторон): единственное место, где их
## подгоняют. На запястье WorldUI уменьшает деку ещё в WRIST_DECK_SCALE раз (0,75): 32 см → 24 см, кнопка 48 px ≈ 2,25 см. Изменив VIEW_SIZE,
## пересмотрите размеры в DeckTheme (они в пикселях).
const VIEW_SIZE := Vector2i(512, 384)
const PANEL_WIDTH_M := 0.32
const PANEL_HEIGHT_M := PANEL_WIDTH_M * 384.0 / 512.0
## Не чаще стольких перерисовок деки в секунду: на Pico кадр рендерится дважды, а текст деки меняется раз в секунду.
const MAX_FPS := 30.0
## Новая строка в ДОБЫЧЕ мигает столько секунд (период — BLINK_PERIOD_SEC); пока вкладку не открыли, на ней бейдж с числом нового.
const BLINK_SEC := 2.4
const BLINK_PERIOD_SEC := 0.3
## Рамка деки, когда к ней поднесена рука с шардом (приёмник): цвет и толщина вместо обычных.
const RECEIVE_BORDER := 5.0
const NOTICE_SEC := 3.0

const TAB_DECK := "deck"
const TAB_LOOT := "loot"
const TAB_CHAT := "chat"
const TAB_CALLS := "calls"

signal tab_changed(id: String)
## Заряд демона (К6): нажата «ЗАРЯДИТЬ» у программы / клетка сетки заряда на запястье / «ОТМЕНА». Просит сервер ProtoClient; решает сервер.
signal charge_requested(daemon_id: String)
signal charge_cell_tapped(cell: Vector2i)
signal charge_cancel_requested
## Уведомление на деке показывается столько секунд.
## Нажата заготовка ответа (диалог, текст) — для журнала клиента.
signal reply_sent(thread_id: String, text: String)
## Отправка добычи (К5б): открыли выбор получателя — нужен список нетраннеров в Сети; подтвердили отправку (to — как в WorldMsg.GIVE).
signal give_list_requested
signal give_requested(item_id: String, to: Dictionary)

## Сколько раз содержимое деки рисовалось в текстуру (для проверки).
var redraw_count := 0
var phone: PhoneLink

var _viewport: SubViewport
var _surface: Sprite3D
var _frame: MbFrame
var _tabs: MbTabs
var _deck_scroll: ScrollContainer
var _list: VBoxContainer
var _loot_scroll: ScrollContainer
var _loot_list: VBoxContainer
var _give: DeckGive
var _chat: DeckChat
var _charge: DeckCharge
var _notice: Label
var _notice_left := 0.0
var _rows_chargeable := false              # в списке есть кнопка «ЗАРЯДИТЬ»: деку есть чем нажимать
var _calls: DeckCalls
var _tab := TAB_DECK
var _row_texts := PackedStringArray()
var _shown_rows: Array = []
var _shown_deck_key: Variant = null
var _loot_texts := PackedStringArray()
var _shown_loot: Variant = null
var _loot_known := false
var _loot_rows: Array = []                 # строки ДОБЫЧИ, как показаны сейчас (HudLogic.loot_rows)
var _loot_eddies := 0
var _loot_seen: Dictionary = {}            # id добычи, которую уже показывали (первый набор — всё «старое»)
var _loot_new: Dictionary = {}             # id нового, пока вкладку ДОБЫЧА не открыли
var _blink_ids: Dictionary = {}            # id строк, что мигают сейчас
var _blink_left := 0.0
var _blink_rows: Array[MbRow] = []
var _receiving := false
var _give_status := ""                      # строка на ДОБЫЧЕ про последнюю отправку / полученное
var _give_status_tone := "dim"
var _give_label := ""                       # как игрок назвал получателя последней отправки (для телефона сервер имени не знает)
var _calls_seen_missed := 0
var _last_phase := PhoneLink.PHASE_IDLE
var _dirty := true
var _since_draw := 0.0


func _ready() -> void:
	# Любая перерисовка Control внутри SubViewport (подсветка под лучом, текст, раскладка) помечает деку грязной; сама текстура
	# обновляется по требованию в _process.
	get_tree().node_added.connect(_on_node_added)
	_viewport = SubViewport.new()
	_viewport.size = VIEW_SIZE
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.msaa_2d = Viewport.MSAA_4X   # срезанные углы без «лесенки»
	# Рисуем по требованию (см. _process), а не каждый кадр.
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_frame = MbFrame.make(Color(DeckTheme.BG, 0.97), DeckTheme.CHROME, MbShape.Form.DLG, 14.0, 8, 6)
	_frame.border = 2.0
	_frame.theme = DeckTheme.theme()
	_frame.size = Vector2(VIEW_SIZE)
	_viewport.add_child(_frame)
	var col := DeckUi.vbox(DeckTheme.GAP)
	_frame.add_child(col)
	_tabs = MbTabs.new()
	_tabs.tab_selected.connect(select_tab)
	col.add_child(_tabs)
	_notice = DeckUi.label("", DeckTheme.V_WARN, false)
	_notice.visible = false
	col.add_child(_notice)
	_deck_scroll = ScrollContainer.new()
	_deck_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	DeckUi.expand(_deck_scroll, true)
	_list = DeckUi.vbox(4)
	DeckUi.expand(_list)
	_deck_scroll.add_child(_list)
	col.add_child(_deck_scroll)
	_loot_scroll = ScrollContainer.new()
	_loot_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	DeckUi.expand(_loot_scroll, true)
	_loot_list = DeckUi.vbox(4)
	DeckUi.expand(_loot_list)
	_loot_scroll.add_child(_loot_list)
	col.add_child(_loot_scroll)
	_give = DeckGive.new()
	DeckUi.expand(_give, true)
	_give.confirmed.connect(_on_give_confirmed)
	_give.closed.connect(_on_give_closed)
	col.add_child(_give)
	_chat = DeckChat.new()
	DeckUi.expand(_chat, true)
	_chat.reply_sent.connect(func(tid: String, text: String): reply_sent.emit(tid, text))
	col.add_child(_chat)
	_calls = DeckCalls.new()
	DeckUi.expand(_calls, true)
	col.add_child(_calls)
	_charge = DeckCharge.new()
	DeckUi.expand(_charge, true)
	_charge.cell_tapped.connect(func(cell: Vector2i): charge_cell_tapped.emit(cell))
	_charge.cancel_requested.connect(func(): charge_cancel_requested.emit())
	_charge.finished.connect(_end_charge_view)
	col.add_child(_charge)
	_surface = Sprite3D.new()
	_surface.texture = _viewport.get_texture()
	_surface.pixel_size = PANEL_WIDTH_M / VIEW_SIZE.x
	_surface.shaded = false
	_surface.double_sided = false
	add_child(_surface)
	_apply_tabs()
	_show_tab(TAB_DECK)
	set_deck({"daemons": [], "selected": ""})
	_build_loot([], 0)


## Перерисовка по требованию, не чаще MAX_FPS: UPDATE_ALWAYS гнал бы лишний рендер каждого кадра в обоих глазах.
func _process(delta: float) -> void:
	if phone != null and _calls.tick(delta):
		_dirty = true
	if _blink_left > 0.0:
		_blink_left = maxf(_blink_left - delta, 0.0)
		_apply_blink()
	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left <= 0.0:
			_notice.visible = false
			_dirty = true
	_since_draw += delta
	if _dirty and _since_draw >= 1.0 / MAX_FPS:
		_dirty = false
		_since_draw = 0.0
		redraw_count += 1
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Содержимое изменилось: текстуру перерисуем при ближайшей возможности (не чаще MAX_FPS).
func mark_dirty() -> void:
	_dirty = true


func _on_node_added(n: Node) -> void:
	if _viewport != null and n is CanvasItem and _viewport.is_ancestor_of(n):
		var ci := n as CanvasItem
		if not ci.draw.is_connected(mark_dirty):
			ci.draw.connect(mark_dirty)


# ---------------------------------------------------------------- дека (демоны)

func set_deck(deck: Dictionary) -> void:
	var rows := HudLogic.deck_rows(deck)
	var ram: Variant = HudLogic.ram_view(int(deck.get("ram", 0)), int(deck.get("used", 0)), bool(deck.get("ram_default", false)))
	# Сервер шлёт состояние чаще, чем меняется текст: то же самое не перестраиваем и не перерисовываем.
	var key := [rows, ram]
	if key == _shown_deck_key and _list.get_child_count() > 0:
		return
	_shown_deck_key = key
	_shown_rows = rows
	_rows_chargeable = rows.any(func(r: Dictionary) -> bool: return bool(r["can_charge"]))
	_dirty = true
	DeckUi.clear(_list)
	_row_texts = PackedStringArray(["ПРОГРАММЫ"])
	if ram != null:
		_list.add_child(_ram_block(ram))
	_list.add_child(DeckUi.section_title("ПРОГРАММЫ", str(rows.size())))
	for row in rows:
		var text: String = ("> " if row["selected"] else "  ") + row["text"]
		_row_texts.append(text)
		_list.add_child(_program_plate(row))
	if rows.is_empty():
		_list.add_child(DeckUi.label("Программ нет", DeckTheme.V_DIM, false))
	elif rows.any(func(r: Dictionary) -> bool: return bool(r["charged"])):
		_row_texts.append(HudLogic.LAUNCH_HINT)
		_list.add_child(DeckUi.label(HudLogic.LAUNCH_HINT, DeckTheme.V_DIM, false))


## Полоса RAM: «RAM  [██░░░░]  4/6» и метка «ПО УМОЛЧАНИЮ», если ёмкость условная (Мост её ещё не передаёт).
func _ram_block(ram: Dictionary) -> Control:
	var row := DeckUi.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(DeckUi.label("RAM", DeckTheme.V_NAME, false))
	row.add_child(DeckUi.meter(float(ram["fraction"]), DeckTheme.BAD if ram["over"] else DeckTheme.ACC, 16))
	var value := DeckUi.label(str(ram["text"]), DeckTheme.V_NAME, false)
	row.add_child(value)
	if ram["default"]:
		row.add_child(_centered(DeckUi.tag("ПО УМОЛЧАНИЮ", "warn", false)))
	return row


## Плашка программы: имя, тир и состояние; ниже цепочка кодов (моноширинный, V_CODE) и эффект.
func _program_plate(row: Dictionary) -> Control:
	var tone: String = row["tone"]
	var plate := MbFrame.make(DeckTheme.PLATE, DeckTheme.ACC if row["selected"] else DeckTheme.PLATE_EDGE, MbShape.Form.TAB, DeckTheme.CUT_SMALL, 10, 5)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := DeckUi.vbox(2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(col)
	var top := DeckUi.hbox(8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_l := DeckUi.label(("> " if row["selected"] else "") + row["name"], DeckTheme.V_NAME)
	name_l.add_theme_color_override("font_color", DeckTheme.INK_STRONG if row["selected"] else DeckTheme.INK)
	top.add_child(DeckUi.expand(name_l))
	if int(row["tier"]) > 0:
		top.add_child(DeckUi.label("тир %d" % int(row["tier"]), DeckTheme.V_DIM, false))
	if bool(row["can_charge"]):
		# Защитный демон не заряжен: вместо надписи состояния — кнопка (текст «не заряжен» остаётся в row_texts).
		var charge_btn := MbButton.new("ЗАРЯДИТЬ", "quiet")
		charge_btn.button_height = DeckTheme.BTN_SMALL_H
		charge_btn.pressed.connect(func(): charge_requested.emit(str(row["id"])))
		top.add_child(charge_btn)
	else:
		var state_l := DeckUi.label(row["state"], DeckTheme.V_NAME, false)
		state_l.add_theme_color_override("font_color", DeckTheme.tone_color(tone))
		top.add_child(state_l)
	col.add_child(top)
	if not row["chain"].is_empty() or not row["effect"].is_empty():
		var low := DeckUi.hbox(10)
		low.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not row["chain"].is_empty():
			low.add_child(DeckUi.label(row["chain"], DeckTheme.V_CODE, false))
		low.add_child(DeckUi.expand(DeckUi.label(row["effect"], DeckTheme.V_DIM)))
		col.add_child(low)
	return plate


## Для проверки: что рисует вкладка ДЕКА (заголовок и строки демонов).
func row_texts() -> PackedStringArray:
	return _row_texts


# ---------------------------------------------------------------- добыча

## Добыча забега (ev deck: loot [{id, kind, tier, title, enc}], eddies): вкладка ДОБЫЧА, без действий. Первое же обращение показывает вкладку:
## сервер деку прислал, значит и пустое состояние («Добычи пока нет») честное. Первый набор считается старым; всё, что появилось позже
## (шард, который игрок положил в деку), мигает в списке BLINK_SEC и, пока ДОБЫЧУ не открыли, держит на вкладке бейдж с числом нового.
func set_loot(loot: Array, eddies: int = 0) -> void:
	var rows := HudLogic.loot_rows(loot)
	var first := not _loot_known
	_loot_known = true
	var ids := {}
	var fresh := false
	for row in rows:
		var id: String = row["id"]
		ids[id] = true
		if not first and not _loot_seen.has(id) and id != "":
			fresh = true
			_blink_ids[id] = true
			if _tab != TAB_LOOT:
				_loot_new[id] = true
	for id in _loot_new.keys():
		if not ids.has(id):
			_loot_new.erase(id)
	_loot_seen = ids
	if fresh:
		_blink_left = BLINK_SEC
	var key := [rows, eddies]
	if key != _shown_loot or first:
		_shown_loot = key
		_loot_rows = rows
		_loot_eddies = eddies
		_build_loot(rows, eddies)
		_dirty = true
	if first:
		_apply_tabs()
	_update_badges()   # то же самое, что показано, не перерисовываем


func _build_loot(rows: Array, eddies: int) -> void:
	DeckUi.clear(_loot_list)
	_blink_rows.clear()
	_loot_texts = PackedStringArray(["ДОБЫЧА"])
	_loot_list.add_child(DeckUi.section_title("ДОБЫЧА", str(rows.size())))
	if _give_status != "":
		_loot_texts.append(_give_status)
		var st := DeckUi.label(_give_status, &"", false)
		st.add_theme_color_override("font_color", DeckTheme.tone_color(_give_status_tone))
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		st.custom_minimum_size.x = 460.0
		_loot_list.add_child(st)
	var money := DeckUi.hbox(8)
	money.mouse_filter = Control.MOUSE_FILTER_IGNORE
	money.add_child(DeckUi.expand(DeckUi.label("Эдди", DeckTheme.V_NAME)))
	money.add_child(DeckUi.label(str(eddies), DeckTheme.V_CODE, false))
	_loot_texts.append("Эдди  %d" % eddies)
	_loot_list.add_child(money)
	for row in rows:
		var is_new := _loot_new.has(row["id"])
		_loot_texts.append(("НОВОЕ  " if is_new else "") + row["text"])
		var r := _loot_row(row)
		r.unread = is_new   # жёлтая полоска слева, как у непрочитанного
		if _blink_ids.has(row["id"]):
			_blink_rows.append(r)
		_loot_list.add_child(r)
	if rows.is_empty():
		_loot_list.add_child(DeckUi.label("Добычи пока нет", DeckTheme.V_DIM, false))
	_apply_blink()


## Мигание новых строк: яркая — тусклая каждые BLINK_PERIOD_SEC, по концу срока строка остаётся обычной (полоска «новое» держится до просмотра).
func _apply_blink() -> void:
	var on := _blink_left <= 0.0 or int(_blink_left / BLINK_PERIOD_SEC) % 2 == 0
	for r in _blink_rows:
		if is_instance_valid(r):
			r.modulate = Color.WHITE if on else Color(1, 1, 1, 0.25)
	if _blink_left <= 0.0:
		_blink_ids.clear()
		_blink_rows.clear()
	_dirty = true


## Новая добыча сейчас мигает (для проверки).
func is_blinking() -> bool:
	return _blink_left > 0.0


## Сколько единиц добычи новые (на вкладке ДОБЫЧА бейдж) и какие строки.
func new_loot_ids() -> Array:
	return _loot_new.keys()


## К деке поднесена рука с шардом: рамка ярче — «сюда можно положить». Хватает перехода состояния, не каждого кадра.
func set_receiving(on: bool) -> void:
	if on == _receiving:
		return
	_receiving = on
	_frame.edge = DeckTheme.ACC if on else DeckTheme.CHROME
	_frame.border = RECEIVE_BORDER if on else 2.0
	_dirty = true


func is_receiving() -> bool:
	return _receiving


## Метка в ряду не растягивается на высоту ряда, а стоит по центру.
func _centered(c: Control) -> Control:
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c


## Строка добычи: вид (ШАРД / ДЕМОН), название, тир и значок «открыт / зашифрован» (метка Tag: зашифрованный — заливка, открытый — рамка).
func _loot_row(row: Dictionary) -> MbRow:
	var r := MbRow.new()
	r.interactive = false
	var h := DeckUi.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_centered(DeckUi.tag(row["kind_name"], "acc", false)))
	h.add_child(DeckUi.expand(DeckUi.label(row["title"], DeckTheme.V_NAME)))
	h.add_child(DeckUi.label("тир %d" % int(row["tier"]), DeckTheme.V_DIM, false))
	h.add_child(_centered(DeckUi.tag(row["label"], "warn" if row["enc"] else "ok", row["enc"])))
	if not bool(row.get("give", false)):
		r.add_child(h)
		return r
	# Отправить можно: вторая строка с кнопкой (в первой название должно читаться целиком).
	var col := DeckUi.vbox(2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(h)
	var low := DeckUi.hbox(8)
	low.mouse_filter = Control.MOUSE_FILTER_IGNORE
	low.add_child(DeckUi.expand(Control.new()))
	var send := MbButton.new("ОТПРАВИТЬ", "ghost")
	send.button_height = DeckTheme.BTN_SMALL_H
	send.set_meta("item_id", row["id"])
	send.pressed.connect(open_give.bind(str(row["id"])))
	low.add_child(send)
	col.add_child(low)
	r.add_child(col)
	return r


## Для проверки: что рисует вкладка ДОБЫЧА (заголовок, эдди, строки добычи).
func loot_texts() -> PackedStringArray:
	return _loot_texts


# ---------------------------------------------------------------- отправка добычи (К5б)

## Открыть выбор получателя для предмета [param item_id] из ГРУЗа (кнопка «ОТПРАВИТЬ» на строке). Просит у сервера список нетраннеров в Сети.
func open_give(item_id: String) -> void:
	for row in _loot_rows:
		if row["id"] == item_id and bool(row.get("give", false)):
			_give.open(row, phone.contacts() if phone != null else [])
			_loot_scroll.visible = false
			_dirty = true
			give_list_requested.emit()
			return


## Список нетраннеров в Сети ([{id, name, same}], событие give_list) пришёл.
func set_give_runners(runners: Array) -> void:
	_give.set_runners(runners)
	_dirty = true


func give_view() -> DeckGive:
	return _give


## Строка про отправку на ДОБЫЧЕ (ответ сервера give, dir out/in).
func show_give_result(ev: Dictionary) -> void:
	var incoming := str(ev.get("dir", WorldMsg.GIVE_OUT)) == WorldMsg.GIVE_IN
	set_give_status(HudLogic.give_result_text(ev, _give_label), "ok" if bool(ev.get("ok", false)) else "bad")
	if not incoming:
		_give_label = ""


func set_give_status(text: String, tone: String = "dim") -> void:
	_give_status = text
	_give_status_tone = tone
	_build_loot(_loot_rows, _loot_eddies)
	_dirty = true


func give_status() -> String:
	return _give_status


func _on_give_confirmed(item_id: String, target: Dictionary, label: String) -> void:
	_give_label = label
	_loot_scroll.visible = _tab == TAB_LOOT
	set_give_status("Отправляю → %s…" % label, "warn")
	give_requested.emit(item_id, target)


func _on_give_closed() -> void:
	_loot_scroll.visible = _tab == TAB_LOOT
	_dirty = true


func has_loot_tab() -> bool:
	return _loot_known


func has_viewport_surface() -> bool:
	return _surface.texture == _viewport.get_texture()


# ---------------------------------------------------------------- телефон и вкладки

## Подключить (или отключить, null) связь с телефоном: с ней появляются вкладки ЧАТ и ЗВОНКИ.
func set_phone(link: PhoneLink) -> void:
	if phone != null:
		phone.threads_changed.disconnect(_on_threads_changed)
		phone.message_received.disconnect(_on_message_received)
		phone.call_changed.disconnect(_on_call_changed)
	phone = link
	if phone != null:
		phone.threads_changed.connect(_on_threads_changed)
		phone.message_received.connect(_on_message_received)
		phone.call_changed.connect(_on_call_changed)
		_calls_seen_missed = PhoneLogic.missed_count(phone.call_log())   # историю звонков до подключения считаем виденной
		_last_phase = phone.call_state()["phase"]
	_chat.bind(phone)
	_calls.bind(phone)
	_apply_tabs()
	if phone == null or _tab != TAB_DECK and not _tab_available(_tab):
		_show_tab(TAB_DECK)
	_update_badges()
	_dirty = true


func has_phone() -> bool:
	return phone != null


## Есть ли на деке что нажимать (вкладки ДОБЫЧА, ЧАТ и ЗВОНКИ) и видна ли она: без телефона или с невидимой декой указатель не нужен.
func is_interactive() -> bool:
	return (phone != null or _loot_known or _rows_chargeable or _charge.visible) and is_visible_in_tree()   # деку на запястье прячут, пока у руки нет позы: по невидимой не целимся


func active_tab() -> String:
	return _tab


func tab_ids() -> Array:
	return _tabs.items.map(func(it): return it["id"])


func tab_badge(id: String) -> int:
	return _tabs.badge(id)


func select_tab(id: String) -> void:
	if not _tab_available(id):
		return
	_show_tab(id)


func chat() -> DeckChat:
	return _chat


func calls() -> DeckCalls:
	return _calls


func tabs() -> MbTabs:
	return _tabs


func _tab_available(id: String) -> bool:
	return id == TAB_DECK or (id == TAB_LOOT and _loot_known) or (phone != null and (id == TAB_CHAT or id == TAB_CALLS))


func _apply_tabs() -> void:
	var items := [{"id": TAB_DECK, "text": "ДЕКА", "badge": 0}]
	if _loot_known:
		items.append({"id": TAB_LOOT, "text": "ДОБЫЧА", "badge": 0})
	if phone != null:
		items.append({"id": TAB_CHAT, "text": "ЧАТ", "badge": 0})
		items.append({"id": TAB_CALLS, "text": "ЗВОНКИ", "badge": 0})
	_tabs.set_items(items)
	_tabs.select(_tab)
	_update_badges()


func _show_tab(id: String) -> void:
	_tab = id
	if _charge != null and _charge.visible:
		return   # сетка заряда занимает всю деку; вкладка появится, когда она закроется (_end_charge_view)
	_tabs.select(id)
	if _give != null and _give.is_open() and id != TAB_LOOT:
		_give.close()   # ушли с вкладки — выбор получателя отменён
	_deck_scroll.visible = id == TAB_DECK
	_loot_scroll.visible = id == TAB_LOOT and not (_give != null and _give.is_open())
	_chat.visible = id == TAB_CHAT
	_calls.visible = id == TAB_CALLS
	if id == TAB_CALLS and phone != null:
		_calls_seen_missed = PhoneLogic.missed_count(phone.call_log())   # открыли журнал — пропущенные увидели
		_calls.refresh()
	elif id == TAB_CHAT:
		_chat.refresh()
	elif id == TAB_LOOT and not _loot_new.is_empty():
		_loot_new.clear()   # открыли ДОБЫЧУ — новое увидели; строки мигают дальше до конца срока
		_build_loot(_loot_rows, _loot_eddies)
	_update_badges()
	_dirty = true
	tab_changed.emit(id)


## Бейджи: ЧАТ — непрочитанные во всех диалогах; ЗВОНКИ — пропущенные, которых ещё не видели (на открытой вкладке их нет).
func _update_badges() -> void:
	_tabs.set_badge(TAB_LOOT, _loot_new.size())
	if phone == null:
		return
	_tabs.set_badge(TAB_CHAT, PhoneLogic.unread_total(phone.threads()))
	_tabs.set_badge(TAB_CALLS, 0 if _tab == TAB_CALLS else PhoneLogic.missed_unseen(phone.call_log(), _calls_seen_missed))


func _on_threads_changed() -> void:
	_chat.refresh()
	_update_badges()


func _on_message_received(thread_id: String, _msg: Dictionary) -> void:
	_chat.on_message_received(thread_id)
	_update_badges()


func _on_call_changed(state: Dictionary) -> void:
	var phase: String = state["phase"]
	var started := _last_phase == PhoneLink.PHASE_IDLE and (phase == PhoneLink.PHASE_INCOMING or phase == PhoneLink.PHASE_OUTGOING)
	_last_phase = phase
	if _tab == TAB_CALLS:
		_calls_seen_missed = PhoneLogic.missed_count(phone.call_log())   # смотрим журнал, пока звонок кончается: пропущенный уже виден
	_calls.refresh()
	_chat.refresh()   # кнопка «позвонить» в шапке диалога занята, пока идёт звонок
	if started:
		_show_tab(TAB_CALLS)   # звонок выводит вкладку на экран сам: входящий — чтобы ответить, исходящий — чтобы видеть вызов
	_update_badges()


# ---------------------------------------------------------------- заряд демона (К6)

## Началась мини-игра заряда (`bk` с mode = charge): сетка заменяет вкладки и список. Увеличение деки до масштаба 1 делает WorldUI по is_charging().
func begin_charge(m: BreachMirror) -> bool:
	var name_: String = str(m.targets[0]["name"]) if m != null and not m.targets.is_empty() else ""
	if not _charge.begin(m, name_):
		return false
	_set_charge_layout(true)
	return true


func apply_charge_tick(ev: Dictionary) -> void:
	_charge.apply_tick(ev)
	_dirty = true


func apply_charge_end(ev: Dictionary) -> void:
	if not _charge.visible:
		return   # сетка уже убрана (деку перестроили): итог показывать не на чем
	_charge.apply_end(ev)
	_dirty = true


## Сервер не начал заряд (`bk_no` с mode = charge): причина строкой на деке.
func show_charge_denied(reason: String, left: int = 0) -> void:
	show_notice(HudLogic.charge_denied_text(reason, left))


## Уведомление над списком (отказ запуска или заряда); пропадает через NOTICE_SEC.
func show_notice(text: String) -> void:
	_notice.text = text
	_notice.visible = true
	_notice_left = NOTICE_SEC
	_dirty = true


func notice_text() -> String:
	return _notice.text if _notice.visible else ""


## Идёт заряд (сетка или итог на экране): дека показывает только его.
func is_charging() -> bool:
	return _charge.visible


func charge_view() -> DeckCharge:
	return _charge


func _set_charge_layout(on: bool) -> void:
	_tabs.visible = not on
	_notice.visible = false if on else _notice.visible
	if on:
		_deck_scroll.visible = false
		_loot_scroll.visible = false
		_chat.visible = false
		_calls.visible = false
	_dirty = true


func _end_charge_view() -> void:
	_charge.hide_all()
	_tabs.visible = true
	_show_tab(TAB_DECK)
	_dirty = true


# ---------------------------------------------------------------- указатель

## Размер текстуры панели, px (указатель переводит попадание луча в пиксель этого размера).
func view_size() -> Vector2i:
	return VIEW_SIZE


## Глобальная поза поверхности панели (центр, лицом к +Z): по ней указатель считает попадание луча.
func surface_transform() -> Transform3D:
	return _surface.global_transform


## Размер панели в метрах в её собственной системе координат, до масштаба деки: именно его ждёт DeckPointerMath вместе с глобальной
## трансформацией поверхности (в ней уже есть масштаб).
func panel_size_m() -> Vector2:
	return Vector2(VIEW_SIZE) * _surface.pixel_size


## Настоящий размер панели в мире, м: с учётом масштаба деки (на запястье — × WorldUI.WRIST_DECK_SCALE).
func panel_world_size_m() -> Vector2:
	var sc := _surface.global_transform.basis.get_scale()
	return panel_size_m() * Vector2(sc.x, sc.y)


## Физический размер в сантиметрах участка в px: для проверки, что кнопки не мельче ~2 см. scale — масштаб деки (1 или WRIST_DECK_SCALE).
static func px_to_cm(px: float, scale: float = 1.0) -> float:
	return px * PANEL_WIDTH_M / VIEW_SIZE.x * scale * 100.0


## Событие мыши (в пикселях SubViewport) — в интерфейс деки.
func push_pointer_event(event: InputEvent) -> void:
	_viewport.push_input(event, true)


## Двигает список видимой вкладки (стик, колесо мыши).
func scroll_by(px: float) -> void:
	match _tab:
		TAB_CHAT:
			_chat.scroll_by(px)
		TAB_CALLS:
			_calls.scroll_by(px)
		TAB_LOOT:
			if _give.is_open():
				_give.scroll_by(px)
			else:
				_loot_scroll.scroll_vertical += roundi(px)
		_:
			_deck_scroll.scroll_vertical += roundi(px)
	_dirty = true
