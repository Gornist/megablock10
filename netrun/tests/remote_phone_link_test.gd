extends GdUnitTestSuite
## Настоящая связь очков с телефоном (client/remote_phone_link.gd, docs/netrun-phone-link.md): разбор кадров и живое WebSocket-соединение (телефон в тесте — WebSocketPeer-клиент
## в том же процессе): токен в query, hello и hello_ack, замена телефона, обрыв, команды деки кадрами.

const TOKEN := "tok-123"
static var _next_port := 17420

var _link: RemotePhoneLink
var _port := 0
var _clients: Array[WebSocketPeer] = []


func before_test() -> void:
	_link = RemotePhoneLink.new()
	_port = _next_port
	_next_port += 1
	assert_int(_link.start(_port, TOKEN)).is_equal(OK)


func after_test() -> void:
	for c in _clients:
		c.close()
	_clients.clear()
	_link.stop()


# ---------------------------------------------------------------- вспомогательное

## Крутим такт связи и опрос клиентов, пока условие не выполнится (до limit кадров).
func _pump(cond: Callable, limit: int = 300) -> bool:
	for i in limit:
		_link.advance(0.02)
		for c in _clients:
			c.poll()
		if cond.call():
			return true
		await get_tree().process_frame
	return false


func _connect(query: String = "?token=" + TOKEN) -> WebSocketPeer:
	var ws := WebSocketPeer.new()
	assert_int(ws.connect_to_url("ws://127.0.0.1:%d/%s" % [_port, query])).is_equal(OK)
	_clients.append(ws)
	return ws


func _open(ws: WebSocketPeer) -> bool:
	return await _pump(func(): return ws.get_ready_state() == WebSocketPeer.STATE_OPEN)


func _say(ws: WebSocketPeer, frame: Dictionary) -> void:
	ws.send_text(JSON.stringify(frame))


## Принять от очков все кадры, пришедшие к клиенту, как словари.
func _frames(ws: WebSocketPeer) -> Array:
	var out: Array = []
	while ws.get_available_packet_count() > 0:
		var parsed: Variant = JSON.parse_string(ws.get_packet().get_string_from_utf8())
		if parsed is Dictionary:
			out.append(parsed)
	return out


## Телефон подключился с токеном и представился: возвращает клиента и пришедшие от очков кадры.
func _online_phone() -> Array:
	var ws := _connect()
	assert_bool(await _open(ws)).is_true()
	_say(ws, {"t": "hello", "v": 1, "callsign": "Призрак"})
	assert_bool(await _pump(func(): return _link.is_online())).is_true()
	assert_bool(await _pump(func(): return ws.get_available_packet_count() >= 2)).is_true()
	return [ws, _frames(ws)]


func _thread(id: String, kind: String = "DM", title: String = "ЛИС", unread: int = 0) -> Dictionary:
	return {"id": id, "kind": kind, "title": title, "last_text": "привет", "last_ts": 100, "unread": unread}


func _msg(id: String, thread: String, mine: bool, text: String, status: String = "sent") -> Dictionary:
	return {"id": id, "thread": thread, "mine": mine, "text": text, "ts": 100, "status": status, "from": "" if mine else "ЛИС"}


# ---------------------------------------------------------------- кадры

func test_threads_and_messages_frames_fill_the_link() -> void:
	var changed := [0]
	_link.threads_changed.connect(func(): changed[0] += 1)
	_link.on_frame({"t": "threads", "items": [_thread("k1", "DM", "ЛИС", 2), _thread("faction", "FACTION", "ВОЛЬНЫЕ")]})
	assert_int(_link.threads().size()).is_equal(2)
	var lis: Dictionary = _link.threads().filter(func(t): return t["id"] == "k1")[0]
	assert_int(lis["unread"]).is_equal(2)
	assert_str(lis["kind"]).is_equal("DM")
	_link.on_frame({"t": "messages", "thread": "k1", "items": [_msg("m1", "k1", false, "один"), _msg("m2", "k1", true, "два", "delivered")]})
	var m: Array = _link.messages("k1")
	assert_array(m.map(func(x): return x["text"])).is_equal(["один", "два"])
	assert_str(m[1]["status"]).is_equal("delivered")
	assert_bool(m[1]["mine"]).is_true()
	assert_int(changed[0]).is_equal(2)
	assert_array(_link.messages("nope")).is_empty()


func test_new_incoming_message_signals_once_and_status_change_replaces_it() -> void:
	var got: Array = []
	_link.message_received.connect(func(tid, msg): got.append([tid, msg["text"]]))
	_link.on_frame({"t": "threads", "items": [_thread("k1")]})
	_link.on_frame({"t": "message", "msg": _msg("m1", "k1", false, "эй")})
	assert_array(got).is_equal([["k1", "эй"]])
	# тот же id снова (смена статуса) — замена, не второе сообщение и не новый сигнал
	_link.on_frame({"t": "message", "msg": _msg("m1", "k1", false, "эй", "delivered")})
	assert_int(_link.messages("k1").size()).is_equal(1)
	assert_array(got).has_size(1)
	# своё сообщение сигнала не даёт
	_link.on_frame({"t": "message", "msg": _msg("m2", "k1", true, "ответ")})
	assert_array(got).has_size(1)
	assert_int(_link.messages("k1").size()).is_equal(2)


func test_messages_are_capped_and_limit_returns_the_latest() -> void:
	var items: Array = []
	for i in RemotePhoneLink.MAX_MESSAGES + 20:
		items.append(_msg("m%d" % i, "k1", false, "t%d" % i))
	_link.on_frame({"t": "messages", "thread": "k1", "items": items})
	assert_int(_link.messages("k1", 1000).size()).is_equal(RemotePhoneLink.MAX_MESSAGES)
	assert_str(_link.messages("k1", 1)[0]["text"]).is_equal("t%d" % (RemotePhoneLink.MAX_MESSAGES + 19))


func test_call_frame_updates_state_and_rejects_unknown_phase() -> void:
	var states: Array = []
	_link.call_changed.connect(func(st): states.append(st["phase"]))
	_link.on_frame({"t": "call", "phase": "incoming", "peer": "ЛИС", "since_ts": 500, "muted": false})
	assert_str(_link.call_state()["phase"]).is_equal("incoming")
	assert_str(_link.call_state()["peer"]).is_equal("ЛИС")
	assert_float(_link.call_state()["since_ts"]).is_equal(500.0)
	_link.on_frame({"t": "call", "phase": "ringing_wtf", "peer": "ЛИС"})   # неизвестная фаза — игнор
	assert_str(_link.call_state()["phase"]).is_equal("incoming")
	_link.on_frame({"t": "call", "phase": "in_call", "peer": "ЛИС", "since_ts": 510, "muted": true})
	assert_bool(_link.call_state()["muted"]).is_true()
	assert_array(states).is_equal(["incoming", "in_call"])


func test_call_log_contacts_and_sounds() -> void:
	_link.on_frame({"t": "call_log", "items": [{"peer": "ЛИС", "dir": "missed", "ts": 90, "duration_s": 0}, {"peer": "ВОБЛА", "dir": "in", "ts": 80, "duration_s": 12}]})
	assert_array(_link.call_log().map(func(e): return e["dir"])).is_equal(["missed", "in"])
	assert_float(_link.call_log()[1]["duration_s"]).is_equal(12.0)
	_link.on_frame({"t": "contacts", "items": [{"key": "KEY_A", "title": "ЛИС"}, {"title": "без ключа"}]})
	assert_array(_link.contacts().map(func(c): return c["key"])).is_equal(["KEY_A"])
	var sounds: Array = []
	_link.sound_requested.connect(func(k): sounds.append(k))
	for kind in ["ring", "ringback", "message", "stop", "boom"]:
		_link.on_frame({"t": "sound", "kind": kind})
	assert_array(sounds).is_equal(["ring", "ringback", "message", "stop"])   # неизвестный звук не играем


func test_garbage_frames_are_ignored() -> void:
	_link.on_frame({})
	_link.on_frame({"t": "что-то новое", "x": 1})
	_link.on_frame({"t": "threads", "items": "не массив"})
	_link.on_frame({"t": "threads", "items": [5, null, {"kind": "DM"}, {"id": ""}]})
	_link.on_frame({"t": "message", "msg": "строка"})
	_link.on_frame({"t": "messages", "thread": "", "items": []})
	assert_array(_link.threads()).is_empty()
	assert_bool(_link.is_online()).is_false()


# ---------------------------------------------------------------- соединение

func test_phone_with_token_and_hello_goes_online_and_gets_ack_and_resync() -> void:
	var states: Array = []
	_link.online_changed.connect(func(on): states.append(on))
	var r := await _online_phone()
	var frames: Array = r[1]
	assert_array(frames.map(func(f): return f["t"])).is_equal(["hello_ack", "resync"])
	assert_int(int(frames[0]["v"])).is_equal(1)   # JSON отдаёт числа как float
	assert_str(_link.phone_callsign).is_equal("Призрак")
	assert_array(states).is_equal([true])


func test_wrong_token_is_closed_before_hello() -> void:
	var ws := _connect("?token=чужой")
	assert_bool(await _pump(func(): return ws.get_ready_state() == WebSocketPeer.STATE_CLOSED)).is_true()
	assert_int(ws.get_close_code()).is_equal(RemotePhoneLink.CLOSE_BAD_TOKEN)
	assert_bool(_link.is_online()).is_false()
	var ws2 := _connect("")   # без токена в адресе
	assert_bool(await _pump(func(): return ws2.get_ready_state() == WebSocketPeer.STATE_CLOSED)).is_true()
	assert_int(ws2.get_close_code()).is_equal(RemotePhoneLink.CLOSE_BAD_TOKEN)


func test_empty_server_token_accepts_any_phone() -> void:
	_link.token = ""
	var ws := _connect("")
	assert_bool(await _open(ws)).is_true()
	_say(ws, {"t": "hello", "v": 1, "callsign": "X"})
	assert_bool(await _pump(func(): return _link.is_online())).is_true()


func test_bad_hello_is_closed() -> void:
	for bad in [{"t": "threads", "items": []}, {"t": "hello", "v": 99, "callsign": "X"}, {"t": "hello", "callsign": "X"}]:
		var ws := _connect()
		assert_bool(await _open(ws)).is_true()
		_say(ws, bad)
		assert_bool(await _pump(func(): return ws.get_ready_state() == WebSocketPeer.STATE_CLOSED)).is_true()
		assert_int(ws.get_close_code()).is_equal(RemotePhoneLink.CLOSE_BAD_HELLO)
	assert_bool(_link.is_online()).is_false()


func test_silent_client_is_closed_after_hello_timeout() -> void:
	var ws := _connect()
	assert_bool(await _open(ws)).is_true()
	_link.advance(RemotePhoneLink.HELLO_TIMEOUT_SEC + 1.0)   # молчит дольше срока
	assert_bool(await _pump(func(): return ws.get_ready_state() == WebSocketPeer.STATE_CLOSED)).is_true()
	assert_bool(_link.is_online()).is_false()


func test_new_phone_replaces_the_old_one() -> void:
	var first: WebSocketPeer = (await _online_phone())[0]
	var second := _connect()
	assert_bool(await _open(second)).is_true()
	_say(second, {"t": "hello", "v": 1, "callsign": "Другой"})
	assert_bool(await _pump(func(): return first.get_ready_state() == WebSocketPeer.STATE_CLOSED)).is_true()
	assert_int(first.get_close_code()).is_equal(RemotePhoneLink.CLOSE_REPLACED)
	assert_bool(_link.is_online()).is_true()
	assert_str(_link.phone_callsign).is_equal("Другой")


func test_frames_flow_over_the_socket_and_disconnect_stops_sounds_and_goes_offline() -> void:
	var ws: WebSocketPeer = (await _online_phone())[0]
	var sounds: Array = []
	_link.sound_requested.connect(func(k): sounds.append(k))
	_say(ws, {"t": "threads", "items": [_thread("k1", "DM", "ЛИС", 1)]})
	_say(ws, {"t": "call", "phase": "incoming", "peer": "ЛИС", "since_ts": 1, "muted": false})
	_say(ws, {"t": "sound", "kind": "ring"})
	assert_bool(await _pump(func(): return sounds == ["ring"])).is_true()
	assert_int(_link.threads().size()).is_equal(1)
	assert_str(_link.call_state()["phase"]).is_equal("incoming")
	ws.close()
	assert_bool(await _pump(func(): return not _link.is_online())).is_true()
	assert_array(sounds).is_equal(["ring", "stop"])   # петля рингтона гаснет, когда телефон пропал
	assert_int(_link.threads().size()).is_equal(1)   # данные остаются последними известными


func test_deck_commands_go_out_as_frames() -> void:
	var ws: WebSocketPeer = (await _online_phone())[0]
	_link.on_frame({"t": "threads", "items": [_thread("k1", "DM", "ЛИС", 3)]})
	_link.send_text("k1", "Позже")
	_link.mark_read("k1")
	_link.accept_call()
	_link.decline_call()
	_link.hangup()
	_link.set_muted(true)
	_link.start_call("ЛИС")
	assert_bool(await _pump(func(): return ws.get_available_packet_count() >= 7)).is_true()
	var frames := _frames(ws)
	assert_array(frames.map(func(f): return f["t"])).is_equal(["send_text", "mark_read", "accept", "decline", "hangup", "mute", "start_call"])
	assert_str(frames[0]["preset"]).is_equal("later")
	assert_str(frames[0]["thread"]).is_equal("k1")
	assert_str(frames[1]["thread"]).is_equal("k1")
	assert_bool(frames[5]["on"]).is_true()
	assert_str(frames[6]["peer"]).is_equal("ЛИС")
	assert_int(int(_link.threads()[0]["unread"])).is_equal(0)   # прочитано локально сразу, не ждём телефон


func test_free_text_is_not_sent_and_start_call_is_ignored_during_a_call() -> void:
	var ws: WebSocketPeer = (await _online_phone())[0]
	_link.send_text("k1", "свободный текст")
	_link.on_frame({"t": "call", "phase": "in_call", "peer": "ЛИС", "since_ts": 1, "muted": false})
	_link.start_call("ВОБЛА")
	for i in 20:
		await _pump(func(): return false, 1)
	assert_array(_frames(ws)).is_empty()


func test_send_text_without_a_phone_leaves_a_failed_message() -> void:
	_link.on_frame({"t": "threads", "items": [_thread("k1")]})
	_link.send_text("k1", "Да")
	var m: Array = _link.messages("k1")
	assert_int(m.size()).is_equal(1)
	assert_str(m[0]["status"]).is_equal("failed")
	assert_bool(m[0]["mine"]).is_true()
	assert_str(m[0]["text"]).is_equal("Да")


# ---------------------------------------------------------------- пауза очков (сняли — телефон должен увидеть обрыв)

func test_pause_closes_the_phone_and_the_port_and_resume_opens_it_again() -> void:
	var ws: WebSocketPeer = (await _online_phone())[0]
	var sounds: Array = []
	_link.sound_requested.connect(func(k): sounds.append(k))
	_link.pause()
	assert_bool(_link.is_online()).is_false()
	assert_array(sounds).is_equal(["stop"])   # петля рингтона гаснет вместе со связью
	# телефон узнаёт о паузе: пришёл кадр закрытия с кодом 1001
	assert_bool(await _pump(func(): return ws.get_ready_state() == WebSocketPeer.STATE_CLOSED)).is_true()
	assert_int(ws.get_close_code()).is_equal(RemotePhoneLink.CLOSE_GOING_AWAY)
	# порт закрыт: новое соединение не открывается
	var late := _connect()
	assert_bool(await _pump(func(): return late.get_ready_state() == WebSocketPeer.STATE_CLOSED, 60)).is_true()
	# очки надели: порт открыт снова с тем же токеном, телефон возвращается
	assert_int(_link.resume()).is_equal(OK)
	var back := _connect()
	assert_bool(await _open(back)).is_true()
	_say(back, {"t": "hello", "v": 1, "callsign": "Призрак"})
	assert_bool(await _pump(func(): return _link.is_online())).is_true()


func test_pause_without_a_phone_is_harmless() -> void:
	_link.pause()
	assert_bool(_link.is_online()).is_false()
	assert_int(_link.resume()).is_equal(OK)


# ---------------------------------------------------------------- голос (docs/netrun-phone-link.md, «Голос»)

func _pcm(samples: Array) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(samples.size() * 2)
	for i in samples.size():
		b.encode_s16(i * 2, int(samples[i]))
	return b


func _say_binary(ws: WebSocketPeer, bytes: PackedByteArray) -> void:
	ws.send(bytes, WebSocketPeer.WRITE_MODE_BINARY)


## Телефон шлёт voice{on:true,rate} и ждёт, пока очки его примут.
func _voice_on(ws: WebSocketPeer, rate: int = 44100) -> void:
	_say(ws, {"t": "voice", "on": true, "rate": rate})
	assert_bool(await _pump(func(): return _link.voice_active())).is_true()


func test_voice_frame_turns_voice_on_and_off_and_signals_once() -> void:
	var ws: WebSocketPeer = (await _online_phone())[0]
	var got: Array = []
	_link.voice_requested.connect(func(on, rate): got.append([on, rate]))
	assert_bool(_link.voice_active()).is_false()
	assert_int(_link.voice_rate()).is_equal(44100)
	_say(ws, {"t": "voice", "on": true, "rate": 16000})
	assert_bool(await _pump(func(): return _link.voice_active())).is_true()
	assert_int(_link.voice_rate()).is_equal(16000)
	_say(ws, {"t": "voice", "on": true, "rate": 16000})   # то же состояние — без повторного сигнала
	_say(ws, {"t": "voice", "on": true, "rate": 48000})   # другая частота — новый сигнал
	assert_bool(await _pump(func(): return got.size() == 2)).is_true()
	_say(ws, {"t": "voice", "on": false})
	assert_bool(await _pump(func(): return not _link.voice_active())).is_true()
	_say(ws, {"t": "voice", "on": false})
	await _pump(func(): return false, 10)
	assert_array(got).is_equal([[true, 16000], [true, 48000], [false, 48000]])


func test_voice_default_rate_and_bad_rate_is_ignored() -> void:
	var got: Array = []
	_link.voice_requested.connect(func(on, rate): got.append([on, rate]))
	for bad in [{"t": "voice", "on": true, "rate": 100}, {"t": "voice", "on": true, "rate": 96000}, {"t": "voice", "on": true, "rate": "много"}]:
		_link.on_frame(bad)
	assert_bool(_link.voice_active()).is_false()
	assert_array(got).is_empty()
	_link.on_frame({"t": "voice", "on": true})
	assert_bool(_link.voice_active()).is_true()
	assert_int(_link.voice_rate()).is_equal(RemotePhoneLink.VOICE_DEFAULT_RATE)
	_link.on_frame({"t": "voice", "on": true, "rate": 8000})   # границы допустимого
	_link.on_frame({"t": "voice", "on": true, "rate": 48000})
	assert_array(got).is_equal([[true, 44100], [true, 8000], [true, 48000]])


func test_peer_audio_frame_reaches_the_signal_but_mic_type_and_garbage_do_not() -> void:
	var ws: WebSocketPeer = (await _online_phone())[0]
	await _voice_on(ws)
	var got: Array = []
	_link.voice_frame_received.connect(func(seq, pcm): got.append([seq, pcm]))
	var pcm := _pcm([0, 1000, -1000, 32767])
	_say_binary(ws, PhoneVoiceCodec.encode(PhoneVoiceCodec.TYPE_MIC, 1, pcm))   # чужой тип
	_say_binary(ws, PackedByteArray([2, 0, 0, 0]))                              # короче заголовка
	_say_binary(ws, PackedByteArray([2, 0, 0, 0, 0, 1, 2, 3]))                  # нечётная полезная часть
	_say_binary(ws, PackedByteArray([9, 0, 0, 0, 0, 1, 2]))                     # неизвестный тип
	_say_binary(ws, PhoneVoiceCodec.encode(PhoneVoiceCodec.TYPE_PEER, 5, pcm))
	assert_bool(await _pump(func(): return got.size() == 1)).is_true()
	assert_int(got[0][0]).is_equal(5)
	assert_array(got[0][1]).is_equal(pcm)
	assert_int(_link.voice_dropped).is_equal(4)


func test_peer_audio_is_dropped_while_voice_is_off() -> void:
	var ws: WebSocketPeer = (await _online_phone())[0]
	var got: Array = []
	_link.voice_frame_received.connect(func(seq, pcm): got.append(seq))
	_say_binary(ws, PhoneVoiceCodec.encode(PhoneVoiceCodec.TYPE_PEER, 1, _pcm([1, 2])))
	assert_bool(await _pump(func(): return _link.voice_dropped == 1)).is_true()
	assert_array(got).is_empty()


func test_mic_chunks_go_to_the_phone_as_binary_type_1_with_rising_seq_reset_by_voice_on() -> void:
	var ws: WebSocketPeer = (await _online_phone())[0]
	await _voice_on(ws)
	var pcm := _pcm([7, -7, 300])
	assert_bool(_link.send_voice_chunk(pcm)).is_true()
	assert_bool(_link.send_voice_chunk(pcm)).is_true()
	assert_bool(await _pump(func(): return ws.get_available_packet_count() >= 2)).is_true()
	var first := ws.get_packet()
	assert_bool(ws.was_string_packet()).is_false()
	var d1 := PhoneVoiceCodec.decode(first)
	var d2 := PhoneVoiceCodec.decode(ws.get_packet())
	assert_int(d1["type"]).is_equal(PhoneVoiceCodec.TYPE_MIC)
	assert_int(d1["seq"]).is_equal(0)
	assert_int(d2["seq"]).is_equal(1)
	assert_array(d1["pcm"]).is_equal(pcm)
	# новое voice{on:true} начинает счёт заново
	_say(ws, {"t": "voice", "on": true, "rate": 44100})
	await _pump(func(): return false, 10)
	assert_bool(_link.send_voice_chunk(pcm)).is_true()
	assert_bool(await _pump(func(): return ws.get_available_packet_count() >= 1)).is_true()
	assert_int(PhoneVoiceCodec.decode(ws.get_packet())["seq"]).is_equal(0)


func test_voice_chunk_fails_without_a_phone_or_with_a_bad_chunk() -> void:
	assert_bool(_link.send_voice_chunk(_pcm([1, 2]))).is_false()   # телефона нет
	var ws: WebSocketPeer = (await _online_phone())[0]
	assert_bool(_link.send_voice_chunk(PackedByteArray())).is_false()
	assert_bool(_link.send_voice_chunk(PackedByteArray([1, 2, 3]))).is_false()
	var big := PackedByteArray()
	big.resize(PhoneVoiceCodec.MAX_PAYLOAD + 2)
	assert_bool(_link.send_voice_chunk(big)).is_false()
	await _pump(func(): return false, 10)
	assert_int(ws.get_available_packet_count()).is_equal(0)


func test_voice_ready_goes_out_as_json() -> void:
	var ws: WebSocketPeer = (await _online_phone())[0]
	_link.send_voice_ready(true)
	_link.send_voice_ready(false)
	assert_bool(await _pump(func(): return ws.get_available_packet_count() >= 2)).is_true()
	assert_array(_frames(ws)).is_equal([{"t": "voice_ready", "on": true}, {"t": "voice_ready", "on": false}])


func test_disconnect_while_voice_is_on_switches_voice_off() -> void:
	var ws: WebSocketPeer = (await _online_phone())[0]
	await _voice_on(ws, 16000)
	var got: Array = []
	_link.voice_requested.connect(func(on, rate): got.append([on, rate]))
	ws.close()
	assert_bool(await _pump(func(): return not _link.is_online())).is_true()
	assert_bool(_link.voice_active()).is_false()
	assert_array(got).is_equal([[false, 16000]])


func test_pause_while_voice_is_on_switches_voice_off() -> void:
	var ws: WebSocketPeer = (await _online_phone())[0]
	await _voice_on(ws)
	var got: Array = []
	_link.voice_requested.connect(func(on, rate): got.append([on, rate]))
	_link.pause()
	assert_bool(_link.voice_active()).is_false()
	assert_array(got).is_equal([[false, 44100]])


func test_binary_frame_before_hello_is_closed() -> void:
	var ws := _connect()
	assert_bool(await _open(ws)).is_true()
	_say_binary(ws, PhoneVoiceCodec.encode(PhoneVoiceCodec.TYPE_PEER, 1, _pcm([1, 2])))
	assert_bool(await _pump(func(): return ws.get_ready_state() == WebSocketPeer.STATE_CLOSED)).is_true()
	assert_int(ws.get_close_code()).is_equal(RemotePhoneLink.CLOSE_BAD_HELLO)
	assert_bool(_link.is_online()).is_false()


func test_oversized_binary_frame_closes_the_connection() -> void:
	var ws: WebSocketPeer = (await _online_phone())[0]
	ws.outbound_buffer_size = RemotePhoneLink.MAX_FRAME_BYTES * 2
	var big := PackedByteArray()
	big.resize(RemotePhoneLink.MAX_FRAME_BYTES + 16)
	big[0] = PhoneVoiceCodec.TYPE_PEER
	_say_binary(ws, big)
	assert_bool(await _pump(func(): return ws.get_ready_state() == WebSocketPeer.STATE_CLOSED)).is_true()
	assert_int(ws.get_close_code()).is_equal(RemotePhoneLink.CLOSE_TOO_BIG)
