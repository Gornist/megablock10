class_name DeckPanel
extends Node3D
## Дека на руке: панель в мире; 2D-содержимое рисуется только в SubViewport и показывается на поверхности (Sprite3D).
## Вкладки ДЕКА | ЧАТ | ЗВОНКИ: ДЕКА — список демонов (данные с сервера: {"daemons": [{id, name, cooldown_left}], "selected": id}), ЧАТ и ЗВОНКИ —
## мессенджер и звонки из PhoneLink (сейчас фиктивный FakePhoneLink). Без связи с телефоном (set_phone не вызван или --phone=off)
## вкладки ЧАТ и ЗВОНКИ скрыты, остаётся одна ДЕКА, как раньше.
## Нажимает указатель правого контроллера (DeckPointer): события мыши идут прямо в SubViewport (push_pointer_event).

## Размер текстуры панели, px, и физическая ширина панели при масштабе 1, м (высота — по соотношению сторон): единственное место, где их
## подгоняют. На запястье WorldUI уменьшает деку ещё в WRIST_DECK_SCALE раз (0,75): 32 см → 24 см, кнопка 48 px ≈ 2,25 см. Изменив VIEW_SIZE,
## пересмотрите размеры в DeckTheme (они в пикселях).
const VIEW_SIZE := Vector2i(512, 384)
const PANEL_WIDTH_M := 0.32
const PANEL_HEIGHT_M := PANEL_WIDTH_M * 384.0 / 512.0
## Не чаще стольких перерисовок деки в секунду: на Pico кадр рендерится дважды, а текст деки меняется раз в секунду.
const MAX_FPS := 30.0

const TAB_DECK := "deck"
const TAB_CHAT := "chat"
const TAB_CALLS := "calls"

signal tab_changed(id: String)
## Нажата заготовка ответа (диалог, текст) — для журнала клиента.
signal reply_sent(thread_id: String, text: String)

## Сколько раз содержимое деки рисовалось в текстуру (для проверки).
var redraw_count := 0
var phone: PhoneLink

var _viewport: SubViewport
var _surface: Sprite3D
var _frame: MbFrame
var _tabs: MbTabs
var _deck_scroll: ScrollContainer
var _list: VBoxContainer
var _chat: DeckChat
var _calls: DeckCalls
var _tab := TAB_DECK
var _row_texts := PackedStringArray()
var _shown_rows: Array = []
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
	_deck_scroll = ScrollContainer.new()
	_deck_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	DeckUi.expand(_deck_scroll, true)
	_list = DeckUi.vbox(4)
	DeckUi.expand(_list)
	_deck_scroll.add_child(_list)
	col.add_child(_deck_scroll)
	_chat = DeckChat.new()
	DeckUi.expand(_chat, true)
	_chat.reply_sent.connect(func(tid: String, text: String): reply_sent.emit(tid, text))
	col.add_child(_chat)
	_calls = DeckCalls.new()
	DeckUi.expand(_calls, true)
	col.add_child(_calls)
	_surface = Sprite3D.new()
	_surface.texture = _viewport.get_texture()
	_surface.pixel_size = PANEL_WIDTH_M / VIEW_SIZE.x
	_surface.shaded = false
	_surface.double_sided = false
	add_child(_surface)
	_apply_tabs()
	_show_tab(TAB_DECK)
	set_deck({"daemons": [], "selected": ""})


## Перерисовка по требованию, не чаще MAX_FPS: UPDATE_ALWAYS гнал бы лишний рендер каждого кадра в обоих глазах.
func _process(delta: float) -> void:
	if phone != null and _calls.tick(delta):
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
	# Сервер шлёт состояние чаще, чем меняется текст: то же самое не перестраиваем и не перерисовываем.
	if rows == _shown_rows and _list.get_child_count() > 0:
		return
	_shown_rows = rows
	_dirty = true
	DeckUi.clear(_list)
	_row_texts = PackedStringArray(["ДЕМОНЫ"])
	_list.add_child(DeckUi.section_title("ДЕМОНЫ", str(rows.size())))
	for row in rows:
		var text: String = ("> " if row["selected"] else "  ") + row["text"]
		_row_texts.append(text)
		var plate := MbFrame.make(DeckTheme.PLATE, DeckTheme.ACC if row["selected"] else DeckTheme.PLATE_EDGE, MbShape.Form.TAB, DeckTheme.CUT_SMALL, 10, 5)
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := DeckUi.label(text, DeckTheme.V_NAME)
		l.add_theme_color_override("font_color", DeckTheme.OK if row["ready"] else DeckTheme.INK2)
		plate.add_child(l)
		_list.add_child(plate)
	if rows.is_empty():
		_list.add_child(DeckUi.label("Демонов нет", DeckTheme.V_DIM, false))


## Для проверки: что рисует вкладка ДЕКА (заголовок и строки демонов).
func row_texts() -> PackedStringArray:
	return _row_texts


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


## Есть ли на деке что нажимать (вкладки ЧАТ и ЗВОНКИ) и видна ли она: без телефона или с невидимой декой указатель не нужен.
func is_interactive() -> bool:
	return phone != null and is_visible_in_tree()   # деку на запястье прячут, пока у руки нет позы: по невидимой не целимся


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
	return id == TAB_DECK or (phone != null and (id == TAB_CHAT or id == TAB_CALLS))


func _apply_tabs() -> void:
	var items := [{"id": TAB_DECK, "text": "ДЕКА", "badge": 0}]
	if phone != null:
		items.append({"id": TAB_CHAT, "text": "ЧАТ", "badge": 0})
		items.append({"id": TAB_CALLS, "text": "ЗВОНКИ", "badge": 0})
	_tabs.set_items(items)
	_tabs.select(_tab)


func _show_tab(id: String) -> void:
	_tab = id
	_tabs.select(id)
	_deck_scroll.visible = id == TAB_DECK
	_chat.visible = id == TAB_CHAT
	_calls.visible = id == TAB_CALLS
	if id == TAB_CALLS and phone != null:
		_calls_seen_missed = PhoneLogic.missed_count(phone.call_log())   # открыли журнал — пропущенные увидели
		_calls.refresh()
	elif id == TAB_CHAT:
		_chat.refresh()
	_update_badges()
	_dirty = true
	tab_changed.emit(id)


## Бейджи: ЧАТ — непрочитанные во всех диалогах; ЗВОНКИ — пропущенные, которых ещё не видели (на открытой вкладке их нет).
func _update_badges() -> void:
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


# ---------------------------------------------------------------- указатель

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
		_:
			_deck_scroll.scroll_vertical += roundi(px)
	_dirty = true
