extends GdUnitTestSuite
## Вкладки деки ДЕКА | ЧАТ | ЗВОНКИ (DeckPanel + DeckChat + DeckCalls) на фиктивной связи: переключение, бейджи, заготовки ответа,
## кнопки звонка, и стоимость — дека не рисуется без изменений и не чаще MAX_FPS. Часы связи двигает сам тест.

const T0 := 1_700_000_000.0

var _d: DeckPanel
var _link: FakePhoneLink


func _setup_panel(with_phone: bool = true) -> void:
	_d = auto_free(DeckPanel.new())
	add_child(_d)
	_link = FakePhoneLink.new(T0, false)
	_link.auto_reply = false
	if with_phone:
		_d.set_phone(_link)
	await _settle()


## Дать контейнерам раскладку и первую отрисовку.
func _settle(frames: int = 4) -> void:
	for i in frames:
		await get_tree().process_frame


func _chat_unread() -> int:
	return PhoneLogic.unread_total(_link.threads())


# ---------------------------------------------------------------- вкладки

func test_without_phone_only_the_deck_tab_exists() -> void:
	await _setup_panel(false)
	assert_array(_d.tab_ids()).is_equal([DeckPanel.TAB_DECK])
	assert_bool(_d.has_phone()).is_false()
	assert_bool(_d.is_interactive()).is_false()
	_d.select_tab(DeckPanel.TAB_CHAT)   # вкладки нет — выбор молча игнорируется
	assert_str(_d.active_tab()).is_equal(DeckPanel.TAB_DECK)


func test_with_phone_the_three_tabs_are_deck_chat_calls() -> void:
	await _setup_panel()
	assert_array(_d.tab_ids()).is_equal([DeckPanel.TAB_DECK, DeckPanel.TAB_CHAT, DeckPanel.TAB_CALLS])
	assert_bool(_d.is_interactive()).is_true()
	assert_str(_d.active_tab()).is_equal(DeckPanel.TAB_DECK)


func test_tab_switch_shows_only_that_screen() -> void:
	await _setup_panel()
	_d.select_tab(DeckPanel.TAB_CHAT)
	assert_bool(_d.chat().visible).is_true()
	assert_bool(_d.calls().visible).is_false()
	_d.select_tab(DeckPanel.TAB_CALLS)
	assert_bool(_d.calls().visible).is_true()
	assert_bool(_d.chat().visible).is_false()
	_d.select_tab(DeckPanel.TAB_DECK)
	assert_bool(_d.chat().visible or _d.calls().visible).is_false()


func test_clicking_a_tab_selects_it() -> void:
	await _setup_panel()
	_d.tabs().choose(DeckPanel.TAB_CHAT)
	assert_str(_d.active_tab()).is_equal(DeckPanel.TAB_CHAT)


func test_deck_tab_keeps_the_daemon_rows() -> void:
	await _setup_panel()
	_d.set_deck({"daemons": [{"id": "x", "name": "Взлом", "cooldown_left": 0.0}], "selected": "x"})
	assert_str(_d.row_texts()[1]).is_equal("> Взлом  готово")
	_d.select_tab(DeckPanel.TAB_CHAT)
	_d.select_tab(DeckPanel.TAB_DECK)
	assert_str(_d.row_texts()[1]).is_equal("> Взлом  готово")


func test_phone_off_after_on_goes_back_to_deck_only() -> void:
	await _setup_panel()
	_d.select_tab(DeckPanel.TAB_CALLS)
	_d.set_phone(null)
	assert_array(_d.tab_ids()).is_equal([DeckPanel.TAB_DECK])
	assert_str(_d.active_tab()).is_equal(DeckPanel.TAB_DECK)


# ---------------------------------------------------------------- бейджи

func test_chat_badge_counts_unread_and_drops_when_the_thread_is_opened() -> void:
	await _setup_panel()
	assert_int(_d.tab_badge(DeckPanel.TAB_CHAT)).is_equal(1)   # в истории один непрочитанный во фракционном
	_link.receive_message(FakePhoneLink.ID_VOBLA, "ВОБЛА", "Эй")
	assert_int(_d.tab_badge(DeckPanel.TAB_CHAT)).is_equal(2)
	_d.select_tab(DeckPanel.TAB_CHAT)
	_d.chat().open_thread(FakePhoneLink.ID_VOBLA)
	assert_int(_d.tab_badge(DeckPanel.TAB_CHAT)).is_equal(1)
	_d.chat().open_thread(FakePhoneLink.ID_FACTION)
	assert_int(_d.tab_badge(DeckPanel.TAB_CHAT)).is_equal(0)


func test_missed_call_badge_stays_until_the_calls_tab_is_opened() -> void:
	await _setup_panel()
	assert_int(_d.tab_badge(DeckPanel.TAB_CALLS)).is_equal(0)   # старый пропущенный в истории уже «виден»
	_link.incoming_call("ЛИС")
	assert_str(_d.active_tab()).is_equal(DeckPanel.TAB_CALLS)   # входящий выводит вкладку
	_d.select_tab(DeckPanel.TAB_DECK)                           # игрок ушёл на деку и не ответил
	_link.advance(FakePhoneLink.RING_TIMEOUT_S + 1.0)
	assert_int(_d.tab_badge(DeckPanel.TAB_CALLS)).is_equal(1)
	_d.select_tab(DeckPanel.TAB_CALLS)
	assert_int(_d.tab_badge(DeckPanel.TAB_CALLS)).is_equal(0)


func test_missed_call_while_watching_the_calls_tab_leaves_no_badge() -> void:
	await _setup_panel()
	_link.incoming_call("ЛИС")
	_link.advance(FakePhoneLink.RING_TIMEOUT_S + 1.0)
	assert_int(_d.tab_badge(DeckPanel.TAB_CALLS)).is_equal(0)


# ---------------------------------------------------------------- переписка и заготовки

func test_opening_a_thread_marks_it_read() -> void:
	await _setup_panel()
	_d.select_tab(DeckPanel.TAB_CHAT)
	_d.chat().open_thread(FakePhoneLink.ID_FACTION)
	assert_int(_chat_unread()).is_equal(0)
	assert_str(_d.chat().current_thread()).is_equal(FakePhoneLink.ID_FACTION)


func test_chat_list_has_four_rows_and_pressing_a_row_opens_it() -> void:
	await _setup_panel()
	_d.select_tab(DeckPanel.TAB_CHAT)
	await _settle()
	assert_int(_d.chat().row_titles().size()).is_equal(4)
	assert_str(_d.chat().row_titles()[0]).is_equal("ВОЛЬНЫЕ")   # непрочитанные сверху
	_d.chat().press_row(FakePhoneLink.ID_SHERSHEN)
	assert_str(_d.chat().current_thread()).is_equal(FakePhoneLink.ID_SHERSHEN)
	_d.chat().close_thread()
	assert_bool(_d.chat().is_list_shown()).is_true()


func test_six_quick_reply_chips_and_pressing_one_sends_it_to_the_open_thread() -> void:
	await _setup_panel()
	_d.select_tab(DeckPanel.TAB_CHAT)
	_d.chat().open_thread(FakePhoneLink.ID_SHERSHEN)
	await _settle()
	var chips := _d.chat().chip_buttons()
	assert_int(chips.size()).is_equal(6)
	var texts: Array = chips.map(func(b): return b.text)
	assert_array(texts).is_equal(PhoneLogic.QUICK_REPLIES)
	var sent: Array = []
	_d.reply_sent.connect(func(tid, text): sent.append([tid, text]))
	(chips[1] as MbButton).click()   # «Нет»
	assert_array(sent).is_equal([[FakePhoneLink.ID_SHERSHEN, "Нет"]])
	var last: Dictionary = _link.messages(FakePhoneLink.ID_SHERSHEN, 1)[0]
	assert_str(last["text"]).is_equal("Нет")
	assert_bool(last["mine"]).is_true()
	# другой диалог — тот же ряд заготовок, но текст уходит в него
	_d.chat().open_thread(FakePhoneLink.ID_VOBLA)
	(chips[4] as MbButton).click()   # «Привет»
	assert_str(_link.messages(FakePhoneLink.ID_VOBLA, 1)[0]["text"]).is_equal("Привет")


func test_message_arriving_in_the_open_visible_thread_is_read_at_once() -> void:
	await _setup_panel()
	_d.select_tab(DeckPanel.TAB_CHAT)
	_d.chat().open_thread(FakePhoneLink.ID_VOBLA)
	var before := _d.chat().bubble_count()
	_link.receive_message(FakePhoneLink.ID_VOBLA, "ВОБЛА", "Тут?")
	await _settle()
	assert_int(int(_link.threads().filter(func(t): return t["id"] == FakePhoneLink.ID_VOBLA)[0]["unread"])).is_equal(0)
	assert_int(_d.chat().bubble_count()).is_equal(before + 1)


func test_message_for_a_thread_on_another_tab_stays_unread() -> void:
	await _setup_panel()
	_d.select_tab(DeckPanel.TAB_CHAT)
	_d.chat().open_thread(FakePhoneLink.ID_VOBLA)
	_d.select_tab(DeckPanel.TAB_DECK)
	_link.receive_message(FakePhoneLink.ID_VOBLA, "ВОБЛА", "Тут?")
	assert_int(_d.tab_badge(DeckPanel.TAB_CHAT)).is_equal(2)


func test_thread_shows_only_the_last_eight_messages() -> void:
	await _setup_panel()
	for i in 12:
		_link.receive_message(FakePhoneLink.ID_VOBLA, "ВОБЛА", "сообщение %d" % i)
	_d.select_tab(DeckPanel.TAB_CHAT)
	_d.chat().open_thread(FakePhoneLink.ID_VOBLA)
	await _settle()
	assert_int(_d.chat().bubble_count()).is_equal(PhoneLogic.MESSAGES_SHOWN)
	assert_array(Array(DeckUi.texts(_d.chat()))).contains(["сообщение 11"])
	assert_array(Array(DeckUi.texts(_d.chat()))).not_contains(["сообщение 0"])


func test_failed_message_says_so_in_words() -> void:
	await _setup_panel()
	_d.select_tab(DeckPanel.TAB_CHAT)
	_d.chat().open_thread(FakePhoneLink.ID_LIS)
	_link.send_text(FakePhoneLink.ID_LIS, "ОК")
	_link.advance(FakePhoneLink.FAIL_AFTER_S + 0.1)
	await _settle()
	var found := false
	for t in DeckUi.texts(_d.chat()):
		found = found or t.begins_with("НЕ ДОСТАВЛЕНО")
	assert_bool(found).is_true()


func test_faction_thread_has_no_call_button_and_shows_the_author() -> void:
	await _setup_panel()
	_d.select_tab(DeckPanel.TAB_CHAT)
	_d.chat().open_thread(FakePhoneLink.ID_FACTION)
	await _settle()
	assert_bool(_d.chat().call_button().visible).is_false()
	assert_array(Array(DeckUi.texts(_d.chat()))).contains(["ШЕРШЕНЬ"])


## Фракционная история в 20 сообщений «м01».."м20", открытая на вкладке ЧАТ.
func _open_long_faction() -> void:
	await _setup_panel()
	for i in range(1, 21):
		_link.receive_message(FakePhoneLink.ID_FACTION, "ШЕРШЕНЬ", "м%02d" % i)
	_d.select_tab(DeckPanel.TAB_CHAT)
	_d.chat().open_thread(FakePhoneLink.ID_FACTION)
	await _settle()


func _has_text(text: String) -> bool:
	return Array(DeckUi.texts(_d.chat())).has(text)


func test_faction_chat_pages_back_two_screens_and_stops_at_the_edges() -> void:
	await _open_long_faction()
	assert_int(_d.chat().page()).is_equal(0)
	assert_int(_d.chat().bubble_count()).is_equal(PhoneLogic.MESSAGES_SHOWN)
	assert_bool(_has_text("м20") and _has_text("м13") and not _has_text("м12")).is_true()
	assert_bool(_d.chat().older_button().disabled).is_false()
	assert_bool(_d.chat().newer_button().disabled).is_true()   # страница 0 — самая новая
	_d.chat().older_button().click()
	await _settle()
	assert_int(_d.chat().page()).is_equal(1)
	assert_int(_d.chat().bubble_count()).is_equal(PhoneLogic.MESSAGES_SHOWN)
	assert_bool(_has_text("м12") and _has_text("м05") and not _has_text("м13") and not _has_text("м04")).is_true()
	assert_bool(_d.chat().older_button().disabled).is_true()   # глубина — две страницы
	assert_bool(_d.chat().newer_button().disabled).is_false()
	_d.chat().newer_button().click()
	await _settle()
	assert_int(_d.chat().page()).is_equal(0)
	assert_bool(_has_text("м20")).is_true()


func test_faction_page_resets_on_new_thread_and_on_new_incoming_message() -> void:
	await _open_long_faction()
	_d.chat().older_button().click()
	await _settle()
	assert_int(_d.chat().page()).is_equal(1)
	_link.receive_message(FakePhoneLink.ID_FACTION, "ШЕРШЕНЬ", "м21")
	await _settle()
	assert_int(_d.chat().page()).is_equal(0)
	assert_bool(_has_text("м21")).is_true()
	_d.chat().older_button().click()
	await _settle()
	_d.chat().close_thread()
	_d.chat().open_thread(FakePhoneLink.ID_FACTION)
	await _settle()
	assert_int(_d.chat().page()).is_equal(0)


func test_dm_thread_has_no_paging_and_shows_the_last_eight() -> void:
	await _setup_panel()
	for i in range(1, 21):
		_link.receive_message(FakePhoneLink.ID_VOBLA, "ВОБЛА", "л%02d" % i)
	_d.select_tab(DeckPanel.TAB_CHAT)
	_d.chat().open_thread(FakePhoneLink.ID_VOBLA)
	await _settle()
	assert_bool(_d.chat().older_button().is_visible_in_tree()).is_false()
	assert_int(_d.chat().bubble_count()).is_equal(PhoneLogic.MESSAGES_SHOWN)
	assert_bool(_has_text("л20") and _has_text("л13") and not _has_text("л12")).is_true()


func test_call_button_in_a_dm_thread_starts_a_call() -> void:
	await _setup_panel()
	_d.select_tab(DeckPanel.TAB_CHAT)
	_d.chat().open_thread(FakePhoneLink.ID_VOBLA)
	_d.chat().call_button().click()
	assert_str(_link.call_state()["phase"]).is_equal(PhoneLink.PHASE_OUTGOING)
	assert_str(_d.active_tab()).is_equal(DeckPanel.TAB_CALLS)


# ---------------------------------------------------------------- звонки

func test_incoming_call_shows_decline_and_accept_and_works_like_call_manager() -> void:
	await _setup_panel()
	_d.select_tab(DeckPanel.TAB_CHAT)
	_link.incoming_call("ВОБЛА")
	await _settle()
	assert_str(_d.active_tab()).is_equal(DeckPanel.TAB_CALLS)
	assert_array(Array(_d.calls().button_texts())).is_equal(["ОТКЛОНИТЬ", "ПРИНЯТЬ"])   # отменяющая слева, подтверждающая справа
	assert_array(Array(DeckUi.texts(_d.calls()))).contains(["ВХОДЯЩИЙ ВЫЗОВ", "ВОБЛА"])
	_d.calls().find_button("ПРИНЯТЬ").click()
	assert_str(_link.call_state()["phase"]).is_equal(PhoneLink.PHASE_IN_CALL)
	assert_array(Array(_d.calls().button_texts())).is_equal(["ЗАГЛУШИТЬ", "ЗАВЕРШИТЬ"])
	_d.calls().find_button("ЗАГЛУШИТЬ").click()
	assert_bool(_link.call_state()["muted"]).is_true()
	assert_array(Array(_d.calls().button_texts())).is_equal(["СНЯТЬ ЗАГЛУШКУ", "ЗАВЕРШИТЬ"])
	var log_before := _link.call_log().size()
	_d.calls().find_button("ЗАВЕРШИТЬ").click()
	assert_str(_link.call_state()["phase"]).is_equal(PhoneLink.PHASE_IDLE)
	assert_bool(_d.calls().card_visible()).is_false()
	assert_int(_link.call_log().size()).is_equal(log_before + 1)


func test_decline_button_ends_the_ringing() -> void:
	await _setup_panel()
	_link.incoming_call("ШЕРШЕНЬ")
	_d.calls().find_button("ОТКЛОНИТЬ").click()
	assert_str(_link.call_state()["phase"]).is_equal(PhoneLink.PHASE_IDLE)
	assert_str(_link.call_log()[0]["dir"]).is_equal(PhoneLink.DIR_IN)


func test_outgoing_call_says_calling_and_cancel_hangs_up() -> void:
	await _setup_panel()
	_link.start_call("ВОБЛА")
	await _settle()
	assert_array(Array(_d.calls().button_texts())).is_equal(["ОТМЕНА"])
	assert_array(Array(DeckUi.texts(_d.calls()))).contains(["ВЫЗЫВАЕМ…"])
	_d.calls().find_button("ОТМЕНА").click()
	assert_str(_link.call_state()["phase"]).is_equal(PhoneLink.PHASE_IDLE)


func test_calls_log_lists_entries_and_calling_from_it_starts_a_call() -> void:
	await _setup_panel()
	_d.select_tab(DeckPanel.TAB_CALLS)
	await _settle()
	assert_int(_d.calls().log_row_count()).is_equal(4)
	var first: MbButton = _d.calls().log_call_buttons()[0]   # find_button отдал бы кнопку из блока КОНТАКТЫ, он выше журнала
	first.click()
	assert_str(_link.call_state()["phase"]).is_equal(PhoneLink.PHASE_OUTGOING)
	assert_str(_link.call_state()["peer"]).is_equal("ШЕРШЕНЬ")   # первая строка журнала — самый свежий звонок
	await _settle()
	assert_bool((_d.calls().log_call_buttons()[0] as MbButton).disabled).is_true()   # линия занята


func test_call_timer_changes_once_a_second() -> void:
	await _setup_panel()
	_link.incoming_call("ВОБЛА")
	_link.accept_call()
	assert_str(_d.calls().timer_text()).is_equal("00:00")
	_link.advance(0.5)
	assert_bool(_d.calls().tick(0.5)).is_false()
	_link.advance(0.6)
	assert_bool(_d.calls().tick(0.6)).is_true()
	assert_str(_d.calls().timer_text()).is_equal("00:01")
	_link.advance(64.0)
	_d.calls().tick(0.0)
	assert_str(_d.calls().timer_text()).is_equal("01:05")


# ---------------------------------------------------------------- стоимость

func test_idle_deck_is_not_redrawn_at_all() -> void:
	await _setup_panel()
	_d.set_process(false)
	_d._process(1.0)   # то, что накопилось при сборке, дорисовалось
	await _settle()
	_d._process(1.0)
	var settled := _d.redraw_count
	for i in 144:   # две секунды при 72 Гц, без событий
		_d._process(1.0 / 72.0)
	assert_int(_d.redraw_count).is_equal(settled)


func test_redraws_never_exceed_the_frame_cap_even_if_every_frame_changes() -> void:
	await _setup_panel()
	_d.set_process(false)
	_d._process(1.0)
	var start := _d.redraw_count
	for i in 144:   # две секунды при 72 Гц, дека «грязная» в каждом кадре
		_d.mark_dirty()
		_d._process(1.0 / 72.0)
	var drawn := _d.redraw_count - start
	assert_int(drawn).is_less_equal(int(2.0 * DeckPanel.MAX_FPS) + 1)
	assert_int(drawn).is_greater_equal(40)   # и не меньше положенного: кадры по 13,9 мс копят 33,3 мс за три — 24 отрисовки в секунду, а не 0


func test_ringing_pulse_redraws_a_handful_of_times_per_second() -> void:
	await _setup_panel()
	_d.set_process(false)
	_d._process(1.0)
	_link.incoming_call("ВОБЛА")
	await _settle()
	_d._process(1.0)
	var start := _d.redraw_count
	for i in 216:   # три секунды при 72 Гц
		_d._process(1.0 / 72.0)
	var drawn := _d.redraw_count - start
	assert_int(drawn).is_less_equal(18)   # ступеней пульса DeckCalls.PULSE_STEPS за период 1,2 с — около 5 в секунду
	assert_int(drawn).is_greater(3)


func test_call_timer_redraws_once_a_second() -> void:
	await _setup_panel()
	_d.set_process(false)
	_link.incoming_call("ВОБЛА")
	_link.accept_call()
	await _settle()
	_d._process(1.0)
	var start := _d.redraw_count
	for i in 216:   # три секунды: часы связи идут вместе с кадрами
		_link.advance(1.0 / 72.0)
		_d._process(1.0 / 72.0)
	var drawn := _d.redraw_count - start
	assert_int(drawn).is_between(2, 5)


# ---------------------------------------------------------------- размер нажимаемого

## Дека на запястье уменьшена в WorldUI.WRIST_DECK_SCALE (0,75): размеры нажимаемого считаем с этим масштабом.
const WRIST_SCALE := WorldUI.WRIST_DECK_SCALE
## Меньше не нажать уверенно двумя дрожащими руками: ~2 см после уменьшения.
const MIN_TARGET_CM := 2.0


func test_px_to_cm_follows_the_panel_width() -> void:
	assert_float(DeckPanel.px_to_cm(float(DeckPanel.VIEW_SIZE.x))).is_equal_approx(DeckPanel.PANEL_WIDTH_M * 100.0, 0.001)
	assert_float(DeckPanel.px_to_cm(100.0, 0.5)).is_equal_approx(DeckPanel.px_to_cm(50.0), 0.001)


func test_touch_targets_stay_above_2_cm_on_the_wrist() -> void:
	for h in [DeckTheme.TAB_H, DeckTheme.ROW_H, DeckTheme.BTN_H, DeckTheme.BTN_SMALL_H, DeckTheme.CHIP_H]:
		assert_float(DeckPanel.px_to_cm(float(h), WRIST_SCALE)).is_greater_equal(MIN_TARGET_CM)


func test_real_buttons_are_not_smaller_than_the_minimum_after_layout() -> void:
	await _setup_panel()
	_d.select_tab(DeckPanel.TAB_CHAT)
	_d.chat().open_thread(FakePhoneLink.ID_VOBLA)
	await _settle()
	var small := []
	for b in DeckUi.buttons(_d.chat()) + [_d.tabs()]:
		var h: float = (b as Control).size.y
		if DeckPanel.px_to_cm(h, WRIST_SCALE) < MIN_TARGET_CM:
			small.append("%s %.0f px" % [b.get("text") if b is MbButton else "вкладки", h])
	_link.incoming_call("ВОБЛА")
	await _settle()
	for b in DeckUi.buttons(_d.calls()):
		var h: float = (b as Control).size.y
		if DeckPanel.px_to_cm(h, WRIST_SCALE) < MIN_TARGET_CM:
			small.append("%s %.0f px" % [(b as MbButton).text, h])
	assert_array(small).is_empty()


func test_trace_indicator_clears_the_deck_on_the_wrist_and_in_the_flat_build() -> void:
	# Дека с вкладками выше прежней: индикатор trace не должен лечь на её край ни на запястье (ниже, к локтю), ни в плоской сборке (выше).
	# На запястье дека повёрнута на 90°: вдоль предплечья идёт её ширина; trace — за дальним (к локтю) краем.
	var elbow_edge := WorldUI.WRIST_DECK_POS.y - WorldUI.WRIST_DECK_LENGTH_M * 0.5
	assert_float(WorldUI.WRIST_TRACE_POS.y).is_less_equal(elbow_edge - 0.03)
	assert_float(WorldUI.FLAT_TRACE_POS.y).is_greater_equal(DeckPanel.PANEL_HEIGHT_M * 0.5 + 0.015)


func test_wrist_deck_lies_on_the_forearm_and_does_not_cover_the_hand() -> void:
	# Повёрнутая дека: ближний к кисти край — на WRIST_DECK_GAP от запястья (запястье — на WRIST_ANCHOR_ELBOW от якоря к пальцам), дальше к локтю.
	var wrist_y := HandView.WRIST_ANCHOR_ELBOW                      # запястье в системе якоря, вдоль Y к пальцам
	var near_edge := WorldUI.WRIST_DECK_POS.y + WorldUI.WRIST_DECK_LENGTH_M * 0.5
	assert_float(wrist_y - near_edge).is_equal_approx(WorldUI.WRIST_DECK_GAP, 0.0001)
	assert_float(WorldUI.WRIST_DECK_LENGTH_M).is_equal_approx(DeckPanel.PANEL_WIDTH_M * WorldUI.WRIST_DECK_SCALE, 0.0001)
	assert_float(WorldUI.WRIST_DECK_ROLL_DEG).is_equal(90.0)
