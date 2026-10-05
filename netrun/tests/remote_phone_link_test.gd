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
	_link.connection_changed.connect(func(on): states.append(on))
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
