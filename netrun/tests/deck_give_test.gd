extends GdUnitTestSuite
## Отправка добычи (К5б), клиент: кнопка «ОТПРАВИТЬ» на строках ДОБЫЧИ, выбор получателя (нетраннеры в Сети первыми, затем контакты PhoneLink),
## подтверждение и строка с итогом. Без сервера: данные и ответы подаёт тест.

const T0 := 1_700_000_000.0

var _d: DeckPanel
var _lists := 0
var _sent: Array = []


func _setup_panel(phone: bool = true) -> void:
	_d = auto_free(DeckPanel.new())
	add_child(_d)
	await _settle()
	if phone:
		_d.set_phone(FakePhoneLink.new(T0, false))
	_d.give_list_requested.connect(func(): _lists += 1)
	_d.give_requested.connect(func(item: String, to: Dictionary): _sent.append([item, to]))
	_lists = 0
	_sent = []


func _settle(frames: int = 4) -> void:
	for i in frames:
		await get_tree().process_frame


func _loot() -> Array:
	return [
		{"id": "s1", "kind": "shard", "tier": 2, "title": "Чертежи склада", "enc": true, "give": true},
		{"id": "d1", "kind": "daemon", "tier": 3, "title": "Дрожь", "enc": false, "give": true},
		{"id": "c1", "kind": "shard", "tier": 1, "title": "Принесён с телефона", "enc": false, "give": false},
	]


func _open_loot() -> void:
	_d.set_loot(_loot(), 10)
	_d.select_tab(DeckPanel.TAB_LOOT)
	await _settle()


func _texts() -> String:
	return "\n".join(DeckUi.texts(_d))


func _send_buttons() -> Array:
	return DeckUi.buttons(_d._loot_scroll).filter(func(b: MbButton) -> bool: return b.text == "ОТПРАВИТЬ")


func test_only_sendable_loot_rows_get_a_button() -> void:
	await _setup_panel()
	await _open_loot()
	var ids := _send_buttons().map(func(b: MbButton) -> String: return b.get_meta("item_id"))
	assert_array(ids).is_equal(["s1", "d1"])   # шард, принесённый с телефона, отдавать нельзя
	assert_int(_d.loot_texts().size()).is_equal(5)   # тексты прежние: заголовок, эдди, три строки


func test_rows_without_the_flag_have_no_buttons_for_older_servers() -> void:
	await _setup_panel()
	_d.set_loot([{"id": "1", "kind": "shard", "tier": 1, "title": "Старый сервер", "enc": false}], 0)
	_d.select_tab(DeckPanel.TAB_LOOT)
	await _settle()
	assert_array(_send_buttons()).is_empty()


func test_the_button_is_big_enough_for_the_wrist() -> void:
	await _setup_panel()
	await _open_loot()
	var b: MbButton = _send_buttons()[0]
	assert_float(DeckPanel.px_to_cm(b.button_height, 0.75)).is_greater_equal(2.0)


func test_pressing_send_opens_the_picker_and_asks_the_server_for_runners() -> void:
	await _setup_panel()
	await _open_loot()
	(_send_buttons()[0] as MbButton).click()
	await _settle()
	assert_int(_lists).is_equal(1)
	assert_bool(_d.give_view().is_open()).is_true()
	assert_bool(_d._loot_scroll.visible).is_false()
	assert_str(_texts()).contains("Отправить: Чертежи склада").contains("Ищу игроков в Сети")
	# контакты телефона видны сразу, до ответа сервера
	assert_str(_texts()).contains("КОНТАКТЫ ТЕЛЕФОНА").contains("ВОБЛА").contains("ШЕРШЕНЬ").contains("ЛИС")


func test_runners_in_the_net_come_first_then_phone_contacts() -> void:
	await _setup_panel()
	await _open_loot()
	_d.open_give("s1")
	_d.set_give_runners([{"id": 7, "name": "Яга", "same": false}, {"id": 3, "name": "Лис", "same": true}])
	await _settle()
	var labels := _d.give_view().targets().map(func(t: Dictionary) -> String: return t["label"])
	assert_array(labels).is_equal(["Лис", "Яга", "ВОБЛА", "ЛИС", "ШЕРШЕНЬ"])
	assert_str(_d.give_view().targets()[0]["tag"]).is_equal("ЗДЕСЬ")
	assert_dict(_d.give_view().targets()[0]["target"]).is_equal({"runner": 3})
	assert_dict(_d.give_view().targets()[2]["target"]).is_equal({"phone": FakePhoneLink.fake_key("ВОБЛА")})
	assert_str(_texts()).contains("В СЕТИ").contains("КОНТАКТЫ ТЕЛЕФОНА")
	assert_str(_texts()).not_contains("Ищу игроков")


func test_no_phone_means_only_runners_and_an_honest_empty_state() -> void:
	await _setup_panel(false)
	await _open_loot()
	_d.open_give("s1")
	_d.set_give_runners([])
	await _settle()
	assert_str(_texts()).contains("Получателей нет")


func test_choosing_a_runner_asks_for_confirmation_with_the_consequences() -> void:
	await _setup_panel()
	await _open_loot()
	_d.open_give("d1")
	_d.set_give_runners([{"id": 3, "name": "Лис", "same": true}])
	_d.give_view().choose(0)
	await _settle()
	assert_str(_d.give_view().step_name()).is_equal("confirm")
	assert_str(_texts()).contains("ДЕМОН  Дрожь  тир 3  >  Лис").contains("ГРУЗЕ").contains("Вернуть нельзя")
	assert_array(_sent).is_empty()   # без подтверждения ничего не уходит


func test_a_phone_contact_confirmation_says_the_item_leaves_the_run() -> void:
	await _setup_panel()
	await _open_loot()
	_d.open_give("s1")
	_d.set_give_runners([])
	_d.give_view().choose(0)   # ВОБЛА
	await _settle()
	assert_str(_texts()).contains("ШАРД  Чертежи склада  тир 2  >  ВОБЛА").contains("на его телефон").contains("покинет забег")


func test_cancel_goes_back_and_back_closes_without_sending() -> void:
	await _setup_panel()
	await _open_loot()
	_d.open_give("s1")
	_d.set_give_runners([{"id": 3, "name": "Лис", "same": true}])
	_d.give_view().choose(0)
	var cancel: MbButton = DeckUi.buttons(_d.give_view()).filter(func(b: MbButton) -> bool: return b.text == "ОТМЕНА")[0]
	cancel.click()
	await _settle()
	assert_str(_d.give_view().step_name()).is_equal("pick")
	var back: MbButton = DeckUi.buttons(_d.give_view()).filter(func(b: MbButton) -> bool: return b.text == "‹ НАЗАД")[0]
	back.click()
	await _settle()
	assert_bool(_d.give_view().is_open()).is_false()
	assert_bool(_d._loot_scroll.visible).is_true()
	assert_array(_sent).is_empty()


func test_confirming_sends_the_request_and_shows_progress_then_the_result() -> void:
	await _setup_panel()
	await _open_loot()
	_d.open_give("s1")
	_d.set_give_runners([{"id": 3, "name": "Лис", "same": true}])
	_d.give_view().choose(0)
	_d.give_view().confirm()
	await _settle()
	assert_array(_sent).is_equal([["s1", {"runner": 3}]])
	assert_bool(_d.give_view().is_open()).is_false()
	assert_str(_d.give_status()).contains("Отправляю").contains("Лис")
	assert_str(_texts()).contains("Отправляю")
	_d.show_give_result({"kind": "give", "dir": "out", "ok": true, "item": "s1", "title": "Чертежи склада", "via": "runner", "who": "Лис"})
	await _settle()
	assert_str(_d.give_status()).is_equal("ОТПРАВЛЕНО: Чертежи склада > Лис")
	assert_str(_texts()).contains("ОТПРАВЛЕНО: Чертежи склада > Лис")


func test_phone_result_uses_the_contact_name_the_player_picked() -> void:
	await _setup_panel()
	await _open_loot()
	_d.open_give("d1")
	_d.set_give_runners([])
	_d.give_view().choose(0)
	_d.give_view().confirm()
	assert_array(_sent).is_equal([["d1", {"phone": FakePhoneLink.fake_key("ВОБЛА")}]])
	_d.show_give_result({"kind": "give", "dir": "out", "ok": true, "item": "d1", "title": "Дрожь", "via": "phone"})
	assert_str(_d.give_status()).is_equal("ОТПРАВЛЕНО: Дрожь > ВОБЛА")


func test_refusal_is_shown_in_words() -> void:
	await _setup_panel()
	await _open_loot()
	_d.show_give_result({"kind": "give", "dir": "out", "ok": false, "item": "s1", "title": "Чертежи склада", "error": "gone"})
	assert_str(_d.give_status()).is_equal("НЕ ОТПРАВЛЕНО: предмета уже нет в деке")
	_d.show_give_result({"kind": "give", "dir": "out", "ok": false, "item": "s1", "error": "unavailable"})
	assert_str(_d.give_status()).contains("нет связи с Мостом")


func test_incoming_item_blinks_and_is_announced() -> void:
	await _setup_panel()
	_d.set_loot([], 0)
	_d.select_tab(DeckPanel.TAB_CHAT)
	_d.set_loot([{"id": "s9", "kind": "shard", "tier": 1, "title": "Накладная", "enc": false, "give": true}], 0)   # приехал от другого игрока
	_d.show_give_result({"kind": "give", "dir": "in", "ok": true, "item": "s9", "title": "Накладная", "from": "Лис"})
	assert_bool(_d.is_blinking()).is_true()
	assert_array(_d.new_loot_ids()).is_equal(["s9"])
	assert_int(_d.tab_badge(DeckPanel.TAB_LOOT)).is_equal(1)
	assert_str(_d.give_status()).is_equal("ПОЛУЧЕНО от Лис: Накладная")


func test_leaving_the_tab_cancels_the_picker() -> void:
	await _setup_panel()
	await _open_loot()
	_d.open_give("s1")
	_d.select_tab(DeckPanel.TAB_DECK)
	await _settle()
	assert_bool(_d.give_view().is_open()).is_false()
	_d.select_tab(DeckPanel.TAB_LOOT)
	await _settle()
	assert_bool(_d._loot_scroll.visible).is_true()


func test_the_item_must_be_sendable_to_open_the_picker() -> void:
	await _setup_panel()
	await _open_loot()
	_d.open_give("c1")   # принесённый с телефона: кнопки нет, и программный вызов её не обходит
	_d.open_give("нет такого")
	assert_bool(_d.give_view().is_open()).is_false()
	assert_int(_lists).is_equal(0)


func test_confirm_lines_and_result_texts_are_plain_logic() -> void:
	var row := {"kind_name": "ШАРД", "title": "Т", "tier": 2}
	var run := HudLogic.give_confirm_lines(row, {"kind": "runner", "label": "Лис"})
	var phone := HudLogic.give_confirm_lines(row, {"kind": "phone", "label": "ВОБЛА"})
	assert_str(run[1]).contains("ГРУЗЕ")
	assert_str(phone[1]).contains("телефон")
	assert_str(HudLogic.give_result_text({"dir": "out", "ok": true, "title": "Т", "who": "Лис"})).is_equal("ОТПРАВЛЕНО: Т > Лис")
	assert_str(HudLogic.give_result_text({"dir": "out", "ok": true, "title": "Т"}, "ВОБЛА")).is_equal("ОТПРАВЛЕНО: Т > ВОБЛА")
	assert_str(HudLogic.give_result_text({"dir": "out", "ok": false, "error": "что-то новое"})).contains("что-то новое")
	assert_array(HudLogic.give_targets([], [{"key": "", "title": "Пустой ключ"}])).is_empty()   # контакт без ключа отправить некуда


func test_loot_cue_makes_a_quiet_signal_and_a_pulse() -> void:
	var fb: DeckFeedback = auto_free(DeckFeedback.new())
	add_child(fb)
	var pulses: Array = []
	fb.pulse_sink = func(hand: String, amp: float, sec: float): pulses.append([hand, amp, sec])
	fb.loot_cue()
	assert_int(fb.loot_cues).is_equal(1)
	assert_array(pulses).has_size(1)
	assert_str(pulses[0][0]).is_equal("left")
	assert_float(pulses[0][1]).is_less(DeckFeedback.MESSAGE_PULSE_AMP)   # тише сообщения
