extends GdUnitTestSuite
## Клиент в плоской сборке стартует с `--phone=off` (на деке одна вкладка ДЕКА) и без него (ДЕКА | ЧАТ | ЗВОНКИ на фиктивной связи).
## Настоящий ProtoClient, без сети: токена нет, журнал пишется.


func _client(args: PackedStringArray) -> ProtoClient:
	var proto: ProtoClient = auto_free(ProtoClient.new())
	proto.config_paths = PackedStringArray()
	add_child(proto)
	proto.start(args, "flat", false)
	return proto


func _log(proto: ProtoClient) -> String:
	return FileAccess.get_file_as_string(proto.log_file.path)


func test_phone_mode_parses_the_argument() -> void:
	assert_str(ProtoClient.phone_mode(PackedStringArray())["mode"]).is_equal(ProtoClient.PHONE_FAKE)
	assert_str(ProtoClient.phone_mode(PackedStringArray(["--phone=off"]))["mode"]).is_equal(ProtoClient.PHONE_OFF)
	assert_str(ProtoClient.phone_mode(PackedStringArray(["--phone=fake"]))["mode"]).is_equal(ProtoClient.PHONE_FAKE)
	assert_str(ProtoClient.phone_mode(PackedStringArray(["--phone=off"]))["warning"]).is_empty()


func test_unknown_phone_value_falls_back_to_fake_with_a_warning() -> void:
	var m := ProtoClient.phone_mode(PackedStringArray(["--phone=wrong"]))
	assert_str(m["mode"]).is_equal(ProtoClient.PHONE_FAKE)
	assert_str(m["warning"]).contains("wrong")


func test_flat_client_has_all_three_tabs_by_default() -> void:
	var proto := _client(PackedStringArray())
	var deck: DeckPanel = proto.scene.world_ui.deck
	assert_array(deck.tab_ids()).is_equal([DeckPanel.TAB_DECK, DeckPanel.TAB_CHAT, DeckPanel.TAB_CALLS])
	assert_bool(proto.phone is FakePhoneLink).is_true()
	assert_str(_log(proto)).contains("phone link=fake tabs=3")


func test_phone_off_hides_chat_and_calls_but_the_deck_stays_as_it_was() -> void:
	var proto := _client(PackedStringArray(["--phone=off"]))
	var ui: WorldUI = proto.scene.world_ui
	assert_array(ui.deck.tab_ids()).is_equal([DeckPanel.TAB_DECK])
	assert_object(proto.phone).is_null()
	assert_object(ui.phone).is_null()
	assert_bool(ui.deck.is_interactive()).is_false()
	assert_str(_log(proto)).contains("phone link=off tabs=1")
	# Дека показывает демонов, как раньше.
	proto.scene.apply_state({"trace": 0.0, "level": 0, "ice": [], "cd": [{"id": "ghost_1", "name": "Призрак", "left": 0.0}]})
	assert_str(ui.deck.row_texts()[1]).is_equal("> 1 Призрак  готово")


func test_unknown_phone_value_is_reported_in_the_log() -> void:
	var proto := _client(PackedStringArray(["--phone=wrong"]))
	assert_str(_log(proto)).contains("phone.warn")
	assert_int(proto.scene.world_ui.deck.tab_ids().size()).is_equal(3)


func test_events_of_the_phone_reach_the_log() -> void:
	var proto := _client(PackedStringArray())
	var link: FakePhoneLink = proto.phone
	link.receive_message(FakePhoneLink.ID_VOBLA, "ВОБЛА", "Эй")
	link.incoming_call("ВОБЛА")
	proto.scene.world_ui.deck.chat().open_thread(FakePhoneLink.ID_SHERSHEN)
	proto.scene.world_ui.deck.chat().chip_buttons()[0].click()
	var text := _log(proto)
	assert_str(text).contains("phone.msg thread=dm:ВОБЛА")
	assert_str(text).contains("phone.call phase=incoming peer=ВОБЛА")
	assert_str(text).contains("deck.tab id=calls")
	assert_str(text).contains("phone.reply thread=dm:ШЕРШЕНЬ text=Да")


func test_perf_line_reports_the_deck_redraws() -> void:
	var proto := _client(PackedStringArray())
	await get_tree().process_frame
	proto._log_perf()
	var line := ""
	for l in _log(proto).split("\n"):
		if l.contains(" perf "):
			line = l
	assert_str(line).contains("deck_redraws=")
