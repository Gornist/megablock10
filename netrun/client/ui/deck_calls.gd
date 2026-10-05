class_name DeckCalls
extends VBoxContainer
## Вкладка ЗВОНКИ: карточка текущего звонка сверху (входящий — пульсирующая рамка, ПРИНЯТЬ / ОТКЛОНИТЬ; в разговоре — таймер, ЗАГЛУШИТЬ,
## ЗАВЕРШИТЬ; исходящий — «вызываем…», ОТМЕНА) и журнал звонков ниже: из строки журнала можно позвонить. Фазы и порядок кнопок — как в
## CallManager / CallOverlay приложения (отменяющая слева, подтверждающая справа). Голос звонка здесь не идёт: это интерфейс, голос —
## следующий этап (микрофон и динамики очков).

signal log_call_requested(peer: String)

## Ступеней у пульсирующей рамки входящего: рисуем не чаще, чем меняется ступень (дёшево для редких перерисовок деки).
const PULSE_STEPS := 6
const PULSE_PERIOD_S := 1.2

var link: PhoneLink
var _card: MbFrame
var _card_box: VBoxContainer
var _log_title_holder: VBoxContainer
var _scroll: ScrollContainer
var _log_box: VBoxContainer
var _phase := PhoneLink.PHASE_IDLE
var _peer := ""
var _muted := false
var _timer_label: Label
var _timer_shown := ""
var _log_sig := ""
var _pulse_step := 0
var _pulse_t := 0.0
var _log_buttons: Array = []
var _offline_banner: Control


func _init() -> void:
	add_theme_constant_override("separation", DeckTheme.GAP)
	_offline_banner = DeckChat.make_offline_banner()
	add_child(_offline_banner)
	_card = MbFrame.make(DeckTheme.DLG_FILL, DeckTheme.OK, MbShape.Form.DLG, 10.0, 12, 8)
	_card.border = 2.0
	_card_box = DeckUi.vbox(4)
	_card.add_child(_card_box)
	_card.visible = false
	add_child(_card)
	_log_title_holder = DeckUi.vbox(0)
	add_child(_log_title_holder)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	DeckUi.expand(_scroll, true)
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_log_box = DeckUi.vbox(0)
	DeckUi.expand(_log_box)
	_scroll.add_child(_log_box)
	add_child(_scroll)


func bind(phone: PhoneLink) -> void:
	link = phone
	_log_sig = ""
	_phase = ""    # заставляет refresh() собрать карточку заново
	refresh()
	apply_online()


## Телефон не на связи: сверху строка-предупреждение, кнопки (ПРИНЯТЬ, ЗАВЕРШИТЬ, «ПОЗВОНИТЬ» в журнале…) недоступны, карточка и журнал — последние известные.
func is_offline() -> bool:
	return link != null and not link.is_online()


## Пересчитать строку и доступность кнопок по link.is_online() (панель зовёт по сигналу online_changed): карточка и журнал собираются заново.
func apply_online() -> void:
	_offline_banner.visible = is_offline()
	if link == null:
		return
	_phase = ""
	_log_sig = ""
	refresh()


func offline_banner() -> Control:
	return _offline_banner


func phase() -> String:
	return _phase


func card_visible() -> bool:
	return _card.visible


func timer_text() -> String:
	return _timer_shown


func log_row_count() -> int:
	return _log_buttons.size()


## Кнопка по подписи (в карточке звонка и в журнале) — для проверок.
func find_button(text: String) -> MbButton:
	for b in DeckUi.buttons(self):
		if (b as MbButton).text == text:
			return b
	return null


func button_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for b in DeckUi.buttons(_card):
		out.append((b as MbButton).text)
	return out


func scroll_by(px: float) -> void:
	_scroll.scroll_vertical += roundi(px)


## Перестроить карточку звонка и журнал, если изменились. Одинаковое состояние ничего не перерисовывает.
func refresh() -> void:
	if link == null:
		return
	var st := link.call_state()
	var phase_now: String = st["phase"]
	var peer: String = st["peer"]
	var muted: bool = st["muted"]
	if phase_now != _phase or peer != _peer or muted != _muted:
		_phase = phase_now
		_peer = peer
		_muted = muted
		_build_card(st)
	_refresh_log()


## Часы: таймер разговора (раз в секунду) и пульс рамки входящего. Возвращает true, если что-то поменялось на экране.
func tick(delta: float) -> bool:
	if link == null:
		return false
	var changed := false
	if _phase == PhoneLink.PHASE_IN_CALL and _timer_label != null:
		var text := PhoneLogic.duration_text(PhoneLogic.call_elapsed(link.call_state(), link.now()))
		if text != _timer_shown:
			_timer_shown = text
			_timer_label.text = text
			changed = true
	elif _phase == PhoneLink.PHASE_INCOMING:
		_pulse_t = fmod(_pulse_t + delta, PULSE_PERIOD_S)
		var step := int(floorf(_pulse_t / PULSE_PERIOD_S * PULSE_STEPS))
		if step != _pulse_step:
			_pulse_step = step
			var k := absf(float(step) / (PULSE_STEPS - 1) * 2.0 - 1.0)   # 1 → 0 → 1 за период: рамка то яркая, то тусклая
			_card.edge = DeckTheme.OK.lerp(DeckTheme.CHROME_DIM, 1.0 - k)
			changed = true
	return changed


func _build_card(st: Dictionary) -> void:
	DeckUi.clear(_card_box)
	_timer_label = null
	_timer_shown = ""
	_pulse_step = 0
	_pulse_t = 0.0
	_card.visible = _phase != PhoneLink.PHASE_IDLE
	if not _card.visible:
		return
	var head := DeckUi.hbox(8)
	var headline := DeckUi.label(PhoneLogic.call_headline(st), DeckTheme.V_OK if _phase != PhoneLink.PHASE_OUTGOING else DeckTheme.V_ACC, false)
	if _phase == PhoneLink.PHASE_IN_CALL:
		headline.text = "• " + headline.text
	DeckUi.expand(headline)
	head.add_child(headline)
	if _phase == PhoneLink.PHASE_IN_CALL and _muted:
		head.add_child(DeckUi.tag("МИКРОФОН ВЫКЛ", "warn", true))
	_card_box.add_child(head)
	_card_box.add_child(DeckUi.label(_peer, DeckTheme.V_BIG))
	if _phase == PhoneLink.PHASE_IN_CALL:
		_timer_label = DeckUi.label(PhoneLogic.duration_text(PhoneLogic.call_elapsed(st, link.now())), DeckTheme.V_TIMER, false)
		_timer_shown = _timer_label.text
		_card_box.add_child(_timer_label)
	var buttons := DeckUi.hbox(DeckTheme.GAP)
	match _phase:
		PhoneLink.PHASE_INCOMING:
			buttons.add_child(_btn("ОТКЛОНИТЬ", "danger", func(): link.decline_call()))
			buttons.add_child(_btn("ПРИНЯТЬ", "success", func(): link.accept_call()))
			_card.edge = DeckTheme.OK
		PhoneLink.PHASE_OUTGOING:
			buttons.add_child(_btn("ОТМЕНА", "danger", func(): link.hangup()))
			_card.edge = DeckTheme.ACC
		PhoneLink.PHASE_IN_CALL:
			buttons.add_child(_btn("СНЯТЬ ЗАГЛУШКУ" if _muted else "ЗАГЛУШИТЬ", "quiet" if _muted else "ghost", func(): link.set_muted(not _muted)))
			buttons.add_child(_btn("ЗАВЕРШИТЬ", "alert", func(): link.hangup()))
			_card.edge = DeckTheme.OK
	_card_box.add_child(buttons)


func _btn(text: String, kind: String, action: Callable) -> MbButton:
	var b := MbButton.new(text, kind)
	DeckUi.expand(b)
	b.disabled = is_offline()
	b.pressed.connect(action)
	return b


func _refresh_log() -> void:
	var entries := link.call_log()
	var busy := _phase != PhoneLink.PHASE_IDLE or is_offline()
	var sig := str([entries.map(func(e): return [e["peer"], e["dir"], e["ts"], e["duration_s"]]), busy])
	if sig == _log_sig:
		return
	_log_sig = sig
	DeckUi.clear(_log_title_holder)
	_log_title_holder.add_child(DeckUi.section_title("ЖУРНАЛ", str(entries.size())))
	DeckUi.clear(_log_box)
	_log_buttons.clear()
	for e in entries:
		_log_box.add_child(_log_row(e, busy))
	if entries.is_empty():
		_log_box.add_child(DeckUi.label("Звонков пока не было.", DeckTheme.V_DIM, false))


func _log_row(e: Dictionary, busy: bool) -> MbRow:
	var dir: String = e["dir"]
	var row := MbRow.new()
	row.interactive = false
	var h := DeckUi.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glyph := {"in": "↙", "out": "↗", "missed": "↙"}.get(dir, "↙") as String
	var tone := {"in": "ok", "out": "acc", "missed": "bad"}.get(dir, "dim") as String
	var g := DeckUi.label(glyph, DeckTheme.tone_variation(tone), false)
	g.custom_minimum_size.x = 22
	g.add_theme_font_size_override("font_size", 22)
	g.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(g)
	var mid := DeckUi.vbox(0)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	DeckUi.expand(mid)
	var name_l := DeckUi.label(str(e["peer"]), DeckTheme.V_NAME)
	if dir == PhoneLink.DIR_MISSED:
		name_l.add_theme_color_override("font_color", DeckTheme.BAD)
	mid.add_child(name_l)
	var sub := "%s · %s" % [PhoneLogic.dir_text(dir), PhoneLogic.clock_text(float(e["ts"]))]
	if float(e["duration_s"]) > 0.0:
		sub += " · " + PhoneLogic.duration_text(float(e["duration_s"]))
	mid.add_child(DeckUi.label(sub, DeckTheme.tone_variation("bad" if dir == PhoneLink.DIR_MISSED else "dim"), true))
	h.add_child(mid)
	var call := MbButton.new("ПОЗВОНИТЬ", "ghost")
	call.button_height = DeckTheme.BTN_SMALL_H
	call.disabled = busy
	var peer := str(e["peer"])
	call.pressed.connect(func():
		link.start_call(peer)
		log_call_requested.emit(peer))
	call.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(call)
	_log_buttons.append(call)
	row.add_child(h)
	return row
