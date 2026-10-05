extends GdUnitTestSuite
## «ТЕЛЕФОН НЕ НА СВЯЗИ» на вкладках ЧАТ и ЗВОНКИ деки: у фиктивной связи (всегда на связи) строки нет; у настоящей без телефона она есть,
## заготовки и кнопки звонков недоступны; сигнал online_changed возвращает всё обратно.

const T0 := 1_700_000_000.0


## Фиктивная связь с переключаемой «связью с телефоном» — как у RemotePhoneLink.
class SwitchLink extends FakePhoneLink:
	var online := true

	func is_online() -> bool:
		return online

	func set_online(on: bool) -> void:
		online = on
		online_changed.emit(on)


var _d: DeckPanel


func _setup(link: PhoneLink) -> void:
	_d = auto_free(DeckPanel.new())
	add_child(_d)
	_d.set_phone(link)
	await _settle()


func _settle(frames: int = 4) -> void:
	for i in frames:
		await get_tree().process_frame


func _switch_link(online: bool) -> SwitchLink:
	var link := SwitchLink.new(T0, false)
	link.auto_reply = false
	link.online = online
	return link


func test_fake_link_has_no_offline_banner_and_buttons_work() -> void:
	var link := FakePhoneLink.new(T0, false)
	await _setup(link)
	assert_bool(_d.chat().offline_banner().visible).is_false()
	assert_bool(_d.calls().offline_banner().visible).is_false()
	_d.chat().open_thread(FakePhoneLink.ID_VOBLA)
	assert_bool((_d.chat().chip_buttons()[0] as MbButton).disabled).is_false()


func test_remote_link_without_phone_shows_the_banner_and_disables_actions() -> void:
	var link := RemotePhoneLink.new()
	await _setup(link)
	assert_bool(link.is_online()).is_false()
	assert_bool(_d.chat().offline_banner().visible).is_true()
	assert_bool(_d.calls().offline_banner().visible).is_true()
	assert_str(DeckUi.texts(_d.chat().offline_banner())[0]).is_equal("ТЕЛЕФОН НЕ НА СВЯЗИ")


func test_offline_disables_quick_replies_and_chat_call_button() -> void:
	var link := _switch_link(false)
	await _setup(link)
	_d.chat().open_thread(FakePhoneLink.ID_VOBLA)
	await _settle()
	assert_bool(_d.chat().offline_banner().visible).is_true()
	for b in _d.chat().chip_buttons():
		assert_bool((b as MbButton).disabled).is_true()
	assert_bool(_d.chat().call_button().disabled).is_true()


func test_going_online_removes_the_banner_and_enables_buttons() -> void:
	var link := _switch_link(false)
	await _setup(link)
	_d.chat().open_thread(FakePhoneLink.ID_VOBLA)
	await _settle()
	link.set_online(true)
	await _settle()
	assert_bool(_d.chat().offline_banner().visible).is_false()
	assert_bool(_d.calls().offline_banner().visible).is_false()
	for b in _d.chat().chip_buttons():
		assert_bool((b as MbButton).disabled).is_false()
	assert_bool(_d.chat().call_button().disabled).is_false()


func test_connection_lost_marks_the_tabs_offline_and_keeps_the_data() -> void:
	var link := _switch_link(true)
	await _setup(link)
	_d.chat().open_thread(FakePhoneLink.ID_VOBLA)
	var shown := _d.chat().bubble_count()
	var rows := _d.calls().log_row_count()
	link.set_online(false)
	await _settle()
	assert_bool(_d.chat().offline_banner().visible).is_true()
	assert_int(_d.chat().bubble_count()).is_equal(shown)   # данные остаются последними известными
	assert_int(_d.calls().log_row_count()).is_equal(rows)
	assert_bool(_d.chat().call_button().disabled).is_true()


func test_offline_disables_call_log_buttons_and_incoming_card_buttons() -> void:
	var link := _switch_link(false)
	await _setup(link)
	assert_int(_d.calls().log_row_count()).is_greater(0)
	assert_bool(_d.calls().find_button("ПОЗВОНИТЬ").disabled).is_true()
	link.incoming_call("ВОБЛА")
	await _settle()
	assert_bool(_d.calls().find_button("ПРИНЯТЬ").disabled).is_true()
	assert_bool(_d.calls().find_button("ОТКЛОНИТЬ").disabled).is_true()
	link.set_online(true)
	await _settle()
	assert_bool(_d.calls().find_button("ПРИНЯТЬ").disabled).is_false()
	assert_bool(_d.calls().find_button("ОТКЛОНИТЬ").disabled).is_false()
