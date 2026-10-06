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


# ---------------------------------------------------------------- настоящая связь: --phone=remote

const SECRET := "sekret-phone-token-42"


func _free_port() -> int:
	var probe := TCPServer.new()
	probe.listen(0)
	var p := probe.get_local_port()
	probe.stop()
	return p


func test_phone_mode_defaults_for_port_and_token() -> void:
	var m := ProtoClient.phone_mode(PackedStringArray())
	assert_int(m["port"]).is_equal(RemotePhoneLink.DEFAULT_PORT)
	assert_str(m["token"]).is_empty()
	assert_str(m["warning"]).is_empty()


func test_phone_mode_remote_from_arguments() -> void:
	var m := ProtoClient.phone_mode(PackedStringArray(["--phone=remote", "--phone-port=7431", "--phone-token=" + SECRET]))
	assert_str(m["mode"]).is_equal(ProtoClient.PHONE_REMOTE)
	assert_int(m["port"]).is_equal(7431)
	assert_str(m["token"]).is_equal(SECRET)
	assert_str(m["warning"]).is_empty()


func test_phone_mode_remote_without_a_token_is_allowed() -> void:
	var m := ProtoClient.phone_mode(PackedStringArray(["--phone=remote"]))
	assert_str(m["mode"]).is_equal(ProtoClient.PHONE_REMOTE)
	assert_str(m["token"]).is_empty()
	assert_str(m["warning"]).is_empty()


func test_phone_mode_takes_the_file_values_and_arguments_win() -> void:
	var cfg := {"mode": "remote", "port": 7500, "token": "from-file"}
	var from_file := ProtoClient.phone_mode(PackedStringArray(), cfg)
	assert_str(from_file["mode"]).is_equal(ProtoClient.PHONE_REMOTE)
	assert_int(from_file["port"]).is_equal(7500)
	assert_str(from_file["token"]).is_equal("from-file")
	var args := ProtoClient.phone_mode(PackedStringArray(["--phone=off", "--phone-port=7600", "--phone-token=from-args"]), cfg)
	assert_str(args["mode"]).is_equal(ProtoClient.PHONE_OFF)
	assert_int(args["port"]).is_equal(7600)
	assert_str(args["token"]).is_equal("from-args")


func test_phone_mode_garbage_gives_fake_and_a_warning() -> void:
	var m := ProtoClient.phone_mode(PackedStringArray(["--phone=remot", "--phone-port=abc"]))
	assert_str(m["mode"]).is_equal(ProtoClient.PHONE_FAKE)
	assert_int(m["port"]).is_equal(RemotePhoneLink.DEFAULT_PORT)
	assert_str(m["warning"]).contains("remot")
	assert_str(m["warning"]).contains("abc")
	var from_file := ProtoClient.phone_mode(PackedStringArray(), {"mode": "xyz", "port": 70000})
	assert_str(from_file["mode"]).is_equal(ProtoClient.PHONE_FAKE)
	assert_str(from_file["warning"]).contains("xyz")
	assert_str(from_file["warning"]).contains("70000")


func test_phone_file_values_read_the_phone_section() -> void:
	var path := "user://phone_client_test.cfg"
	var cf := ConfigFile.new()
	cf.set_value("net", "host", "10.10.0.10")
	cf.set_value("phone", "mode", "remote")
	cf.set_value("phone", "port", 7433)
	cf.set_value("phone", "token", "file-token")
	cf.save(path)
	var v := ProtoClient.phone_file_values(PackedStringArray(["user://no_such_phone_client_test.cfg", path]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_str(v["mode"]).is_equal("remote")
	assert_int(v["port"]).is_equal(7433)
	assert_str(v["token"]).is_equal("file-token")
	assert_dict(ProtoClient.phone_file_values(PackedStringArray(["user://no_such_phone_client_test.cfg"]))).is_empty()


func test_remote_client_starts_the_real_link_and_logs_without_the_token() -> void:
	var port := _free_port()
	var proto := _client(PackedStringArray(["--phone=remote", "--phone-port=%d" % port, "--phone-token=" + SECRET]))
	assert_bool(proto.phone is RemotePhoneLink).is_true()
	assert_int((proto.phone as RemotePhoneLink).listen_port()).is_equal(port)
	assert_array(proto.scene.world_ui.deck.tab_ids()).is_equal([DeckPanel.TAB_DECK, DeckPanel.TAB_CHAT, DeckPanel.TAB_CALLS])
	var text := _log(proto)
	assert_str(text).contains("phone link=remote port=%d token=set" % port)
	assert_str(text).contains("--phone-token=" + NetConfig.REDACTED)
	assert_bool(text.contains(SECRET)).is_false()


func test_remote_client_logs_online_and_sound_events() -> void:
	var proto := _client(PackedStringArray(["--phone=remote", "--phone-port=%d" % _free_port()]))
	var link: RemotePhoneLink = proto.phone
	link.phone_callsign = "ВОБЛА"
	link.online_changed.emit(true)
	link.sound_requested.emit("ring")
	link.online_changed.emit(false)
	var text := _log(proto)
	assert_str(text).contains("phone.online online=true callsign=ВОБЛА")
	assert_str(text).contains("phone.sound kind=ring")
	assert_str(text).contains("phone.online online=false")
	assert_str(text).contains("token=none")


func test_remote_client_falls_back_to_fake_when_the_port_is_busy() -> void:
	var busy := TCPServer.new()
	busy.listen(0)
	var port := busy.get_local_port()
	var proto := _client(PackedStringArray(["--phone=remote", "--phone-port=%d" % port, "--phone-token=" + SECRET]))
	busy.stop()
	assert_bool(proto.phone is FakePhoneLink).is_true()
	var text := _log(proto)
	assert_str(text).contains("phone.warn")
	assert_str(text).contains("связь с телефоном не поднялась")
	assert_str(text).contains("phone link=fake tabs=3")
	assert_bool(text.contains(SECRET)).is_false()


func test_remote_mode_comes_from_netrun_cfg() -> void:
	var path := "user://phone_client_test_cfg.cfg"
	var port := _free_port()
	var cf := ConfigFile.new()
	cf.set_value("phone", "mode", "remote")
	cf.set_value("phone", "port", port)
	cf.set_value("phone", "token", SECRET)
	cf.save(path)
	var proto: ProtoClient = auto_free(ProtoClient.new())
	proto.config_paths = PackedStringArray([path])
	add_child(proto)
	proto.start(PackedStringArray(), "flat", false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_bool(proto.phone is RemotePhoneLink).is_true()
	var text := _log(proto)
	assert_str(text).contains("phone link=remote port=%d token=set" % port)
	assert_bool(text.contains(SECRET)).is_false()


# ---------------------------------------------------------------- пауза очков: настоящая связь закрывает порт, фиктивной всё равно

func test_pause_and_resume_close_and_reopen_the_real_link() -> void:
	var port := _free_port()
	var proto := _client(PackedStringArray(["--phone=remote", "--phone-port=%d" % port, "--phone-token=" + SECRET]))
	var link: RemotePhoneLink = proto.phone
	assert_int(link.listen_port()).is_equal(port)
	proto.pause_phone()
	assert_int(link.listen_port()).is_equal(0)   # порт закрыт: телефон не принимается ядром за живое приложение
	proto.resume_phone()
	assert_int(link.listen_port()).is_equal(port)
	var text := _log(proto)
	assert_str(text).contains("phone.pause")
	assert_str(text).contains("phone.resume ok=true port=%d" % port)
	assert_bool(text.contains(SECRET)).is_false()


func test_pause_does_not_touch_the_fake_link() -> void:
	var proto := _client(PackedStringArray())
	proto.pause_phone()
	proto.resume_phone()
	assert_bool(proto.phone is FakePhoneLink).is_true()
	assert_bool(_log(proto).contains("phone.pause")).is_false()


# ---------------------------------------------------------------- голос телефона: узел PhoneVoice и журнал

## Узел голоса с «найденным» микрофоном: на машине без входа (headless) настоящий отвечает отказом.
class MicVoice extends PhoneVoice:
	func _input_ready() -> bool:
		return true

	func _input_close() -> void:
		pass

	func _pull_input(_max_frames: int) -> PackedVector2Array:
		return PackedVector2Array()


func test_remote_client_has_the_voice_node_and_the_fake_one_does_not() -> void:
	var remote := _client(PackedStringArray(["--phone=remote", "--phone-port=%d" % _free_port()]))
	assert_object(remote.phone_voice).is_not_null()
	assert_bool(remote.phone_voice.get_parent() == remote).is_true()
	assert_bool(remote.phone_voice.is_active()).is_false()
	var fake := _client(PackedStringArray())
	assert_object(fake.phone_voice).is_null()
	var off := _client(PackedStringArray(["--phone=off"]))
	assert_object(off.phone_voice).is_null()


func test_voice_request_is_logged_with_the_answer_and_without_the_token() -> void:
	var proto := _client(PackedStringArray(["--phone=remote", "--phone-port=%d" % _free_port(), "--phone-token=" + SECRET]))
	var link: RemotePhoneLink = proto.phone
	link.voice_requested.emit(true, 44100)
	var text := _log(proto)
	assert_str(text).contains("phone.voice on=true rate=44100 ready=")   # true на устройстве с микрофоном, false без него — оба допустимы
	assert_str(text).contains("reason=")
	link.voice_requested.emit(false, 44100)
	assert_str(_log(proto)).contains("phone.voice on=false rate=44100")
	assert_bool(_log(proto).contains(SECRET)).is_false()


func test_voice_stat_line_appears_only_while_voice_is_active() -> void:
	var proto := _client(PackedStringArray(["--phone=remote", "--phone-port=%d" % _free_port()]))
	var link: RemotePhoneLink = proto.phone
	proto.phone_voice.bind(null)
	var mic := MicVoice.new()
	proto.add_child(mic)
	mic.bind(link)
	proto.phone_voice = mic
	proto._log_voice_stat()
	assert_bool(_log(proto).contains("phone.voice.stat")).is_false()
	link.voice_requested.emit(true, 44100)
	assert_bool(mic.is_active()).is_true()
	proto._log_voice_stat()
	assert_str(_log(proto)).contains("phone.voice.stat sent=0 recv=0 lost=0 late=0 overflow=0 ducked_ms=0")


func test_pause_switches_voice_off_and_logs_it() -> void:
	var port := _free_port()
	var proto := _client(PackedStringArray(["--phone=remote", "--phone-port=%d" % port]))
	var link: RemotePhoneLink = proto.phone
	proto.phone_voice.bind(null)
	var mic := MicVoice.new()
	proto.add_child(mic)
	mic.bind(link)
	proto.phone_voice = mic
	# Настоящее соединение телефона: пауза закрывает связь только при подключённом телефоне.
	var ws := WebSocketPeer.new()
	assert_int(ws.connect_to_url("ws://127.0.0.1:%d/" % port)).is_equal(OK)
	for i in 300:
		link.advance(0.02)
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			break
		await get_tree().process_frame
	ws.send_text(JSON.stringify({"t": "hello", "v": 1, "callsign": "Призрак"}))
	for i in 300:
		link.advance(0.02)
		ws.poll()
		if link.is_online():
			break
		await get_tree().process_frame
	assert_bool(link.is_online()).is_true()
	ws.send_text(JSON.stringify({"t": "voice", "on": true, "rate": 44100}))
	for i in 300:
		link.advance(0.02)
		ws.poll()
		if link.voice_active():
			break
		await get_tree().process_frame
	assert_bool(link.voice_active()).is_true()
	assert_bool(mic.is_active()).is_true()
	proto.pause_phone()
	assert_bool(link.voice_active()).is_false()
	assert_bool(mic.is_active()).is_false()
	assert_str(_log(proto)).contains("phone.voice on=false rate=44100")
	ws.close()


func test_long_thread_id_is_shortened_for_the_log() -> void:
	var key := "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAESjebZ4jiWwcsJ0HcajLBlnQlwhDJjDTy3jPh6J0EqJOfDx/7JYLzL/uw8+NA77OS8HFvqMKWh0h3LWhpep+BwA=="
	assert_str(ProtoClient.short_thread(key)).is_equal("…ep+BwA==")
	assert_str(ProtoClient.short_thread("dm:ВОБЛА")).is_equal("dm:ВОБЛА")
	assert_str(ProtoClient.short_thread("faction")).is_equal("faction")
