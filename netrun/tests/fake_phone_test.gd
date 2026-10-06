extends GdUnitTestSuite
## Контрактные кадры связи очков с телефоном (tests/fixtures/phone_frames.json, docs/netrun-phone-link.md, раздел 2): все кадры телефона принимает
## RemotePhoneLink.on_frame с ожидаемым эффектом, все кадры очков — валидный JSON известного типа. Тот же файл питает инструмент tools/fake_phone.gd.

const FRAMES_PATH := "res://tests/fixtures/phone_frames.json"
const PHONE_TYPES: Array[String] = ["hello", "threads", "messages", "message", "call", "call_log", "contacts", "sound", "voice"]
const GLASSES_TYPES: Array[String] = ["hello_ack", "send_text", "mark_read", "accept", "decline", "hangup", "mute", "start_call", "resync", "voice_ready"]

var _link: RemotePhoneLink


func before_test() -> void:
	_link = RemotePhoneLink.new()


# ---------------------------------------------------------------- вспомогательное

func _all() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FRAMES_PATH))
	assert_bool(parsed is Dictionary).is_true()
	return parsed


func _phone() -> Dictionary:
	return (_all()["phone_to_glasses"] as Dictionary)


func _glasses() -> Dictionary:
	return (_all()["glasses_to_phone"] as Dictionary)


## Фикстура целиком: кадры телефона, которые должны быть в наборе, не пропали (иначе тест ниже пройдёт вхолостую).
func _feed_dialogs() -> void:
	var f := _phone()
	_link.on_frame(f["threads"])
	_link.on_frame(f["messages_lis"])
	_link.on_frame(f["messages_faction"])


# ---------------------------------------------------------------- телефон → очки

func test_every_phone_type_has_a_canonical_example() -> void:
	var seen: Array[String] = []
	for name in _phone():
		seen.append(str((_phone()[name] as Dictionary)["t"]))
	for t in PHONE_TYPES:
		assert_bool(seen.has(t)).override_failure_message("в phone_frames.json нет кадра типа «%s»" % t).is_true()
	for t in seen:
		assert_bool(PHONE_TYPES.has(t)).override_failure_message("лишний тип кадра «%s»" % t).is_true()
	# звонок — по кадру на каждую фазу, звук — на каждый вид
	var phases: Array = []
	var kinds: Array = []
	for name in _phone():
		var fr: Dictionary = _phone()[name]
		if fr["t"] == "call":
			phases.append(fr["phase"])
		elif fr["t"] == "sound":
			kinds.append(fr["kind"])
	phases.sort()
	kinds.sort()
	var want_phases: Array = RemotePhoneLink.PHASES.duplicate()
	want_phases.sort()
	var want_kinds: Array = RemotePhoneLink.SOUND_KINDS.duplicate()
	want_kinds.sort()
	assert_array(phases).is_equal(want_phases)
	assert_array(kinds).is_equal(want_kinds)


func test_threads_and_messages_frames_fill_the_dialogs() -> void:
	_feed_dialogs()
	var th: Array = _link.threads()
	assert_int(th.size()).is_equal(2)
	var lis: Dictionary = th.filter(func(t): return t["title"] == "ЛИС")[0]
	assert_str(lis["kind"]).is_equal(PhoneLink.KIND_DM)
	assert_int(lis["unread"]).is_equal(2)
	var fac: Dictionary = th.filter(func(t): return t["kind"] == PhoneLink.KIND_FACTION)[0]
	assert_str(fac["id"]).is_equal("faction")
	assert_str(fac["title"]).is_equal("ВОЛЬНЫЕ")
	var m_lis: Array = _link.messages(str(lis["id"]))
	assert_int(m_lis.size()).is_equal(3)
	assert_bool(m_lis[1]["mine"]).is_true()
	assert_str(m_lis[1]["status"]).is_equal(PhoneLink.STATUS_SENT)
	assert_str(m_lis[0]["from"]).is_equal("ЛИС")
	var m_fac: Array = _link.messages("faction")
	assert_array(m_fac.map(func(m): return m["from"])).is_equal(["ВОБЛА", "ШЕРШЕНЬ"])


func test_incoming_message_frames_signal_and_status_frame_replaces() -> void:
	_feed_dialogs()
	var lis_id := str((_phone()["threads"]["items"] as Array)[0]["id"])
	var got: Array = []
	_link.message_received.connect(func(tid, msg): got.append([tid, msg["text"]]))
	_link.on_frame(_phone()["message_incoming"])
	_link.on_frame(_phone()["message_faction"])
	assert_array(got).is_equal([[lis_id, "Иду к тебе, держись"], ["faction", "Патруль у третьего входа, обходите"]])
	assert_int(_link.messages(lis_id).size()).is_equal(4)
	assert_int(_link.messages("faction").size()).is_equal(3)
	# смена статуса своего сообщения: тот же id, без нового сигнала и без второго сообщения
	_link.on_frame(_phone()["message_status"])
	assert_array(got).has_size(2)
	assert_int(_link.messages(lis_id).size()).is_equal(4)
	var mine: Dictionary = _link.messages(lis_id).filter(func(m): return m["id"] == "m_lis_2")[0]
	assert_str(mine["status"]).is_equal(PhoneLink.STATUS_DELIVERED)


func test_call_frames_cover_every_phase() -> void:
	var phases: Array = []
	_link.call_changed.connect(func(st): phases.append(st["phase"]))
	for name in ["call_outgoing", "call_incoming", "call_in_call", "call_idle"]:
		_link.on_frame(_phone()[name])
		assert_str(_link.call_state()["phase"]).is_equal(_phone()[name]["phase"])
	assert_array(phases).is_equal(["outgoing", "incoming", "in_call", "idle"])
	_link.on_frame(_phone()["call_incoming"])
	assert_str(_link.call_state()["peer"]).is_equal("ЛИС")
	assert_float(_link.call_state()["since_ts"]).is_equal(1791200500.0)
	assert_bool(_link.call_state()["muted"]).is_false()


func test_call_log_and_contacts_frames() -> void:
	_link.on_frame(_phone()["call_log"])
	assert_array(_link.call_log().map(func(e): return e["peer"])).is_equal(["ЛИС", "ВОБЛА", "ШЕРШЕНЬ"])
	assert_array(_link.call_log().map(func(e): return e["dir"])).is_equal(["missed", "in", "out"])
	assert_float(_link.call_log()[1]["duration_s"]).is_equal(74.0)
	_link.on_frame(_phone()["contacts"])
	assert_array(_link.contacts().map(func(c): return c["title"])).is_equal(["ЛИС", "ВОБЛА", "ШЕРШЕНЬ"])
	# ключ ЛС в контактах совпадает с id диалога ЛИС: по нему дека связывает позывной и диалог
	assert_str(_link.contacts()[0]["key"]).is_equal(str((_phone()["threads"]["items"] as Array)[0]["id"]))


func test_sound_frames_request_every_kind() -> void:
	var sounds: Array = []
	_link.sound_requested.connect(func(k): sounds.append(k))
	for name in ["sound_ring", "sound_ringback", "sound_message", "sound_stop"]:
		_link.on_frame(_phone()[name])
	assert_array(sounds).is_equal(["ring", "ringback", "message", "stop"])


func test_hello_frame_is_a_valid_handshake() -> void:
	var hello: Dictionary = _phone()["hello"]
	assert_int(int(hello["v"])).is_equal(RemotePhoneLink.PROTOCOL_VERSION)
	assert_str(hello["callsign"]).is_not_empty()


# ---------------------------------------------------------------- очки → телефон

func test_glasses_frames_are_valid_json_of_known_types() -> void:
	var types: Array[String] = []
	for name in _glasses():
		var fr: Dictionary = _glasses()[name]
		# туда и обратно через текст: именно так кадр идёт по WebSocket
		var parsed: Variant = JSON.parse_string(JSON.stringify(fr))
		assert_bool(parsed is Dictionary).is_true()
		var t := str((parsed as Dictionary).get("t", ""))
		assert_bool(GLASSES_TYPES.has(t)).override_failure_message("неизвестный тип кадра очков «%s» в «%s»" % [t, name]).is_true()
		types.append(t)
	for t in GLASSES_TYPES:
		assert_bool(types.has(t)).override_failure_message("в phone_frames.json нет кадра очков «%s»" % t).is_true()


func test_send_text_frame_carries_a_known_preset() -> void:
	var fr: Dictionary = _glasses()["send_text"]
	assert_bool(PhoneLogic.QUICK_REPLY_IDS.has(str(fr["preset"]))).is_true()
	assert_str(fr["thread"]).is_not_empty()
	assert_bool(fr.has("text")).is_false()   # текст по id подставляет телефон, очки его не шлют


func test_glasses_frames_match_what_the_link_really_sends() -> void:
	# Контракт со стороны очков: поля кадров из файла — те же, что собирает RemotePhoneLink (набор полей, не значения).
	var g := _glasses()
	assert_array((g["mark_read"] as Dictionary).keys()).contains_exactly_in_any_order(["t", "thread"])
	assert_array((g["send_text"] as Dictionary).keys()).contains_exactly_in_any_order(["t", "thread", "preset"])
	assert_array((g["mute"] as Dictionary).keys()).contains_exactly_in_any_order(["t", "on"])
	assert_array((g["start_call"] as Dictionary).keys()).contains_exactly_in_any_order(["t", "peer"])
	assert_array((g["hello_ack"] as Dictionary).keys()).contains_exactly_in_any_order(["t", "v"])


# ---------------------------------------------------------------- ответы фальшивого телефона (tools/fake_phone_logic.gd, без сети)

## Ответы без задержки как кадры.
func _now_frames(replies: Array) -> Array:
	return replies.filter(func(r): return float(r["delay"]) == 0.0).map(func(r): return r["frame"])


func test_reply_send_text_makes_my_message_with_preset_text_then_delivered() -> void:
	var replies := FakePhone.reply_to(_glasses()["send_text"], _phone())   # preset callback
	assert_int(replies.size()).is_equal(2)
	var first: Dictionary = replies[0]["frame"]["msg"]
	assert_str(replies[0]["frame"]["t"]).is_equal("message")
	assert_bool(first["mine"]).is_true()
	assert_str(first["text"]).is_equal("Перезвоню")
	assert_str(first["status"]).is_equal(PhoneLink.STATUS_SENT)
	assert_str(first["thread"]).is_equal(_glasses()["send_text"]["thread"])
	assert_float(replies[1]["delay"]).is_equal(FakePhone.DELIVERED_AFTER_SEC)
	var second: Dictionary = replies[1]["frame"]["msg"]
	assert_str(second["id"]).is_equal(first["id"])
	assert_str(second["status"]).is_equal(PhoneLink.STATUS_DELIVERED)
	# и очки это принимают: одно сообщение, статус сменился
	_link.on_frame(replies[0]["frame"])
	_link.on_frame(replies[1]["frame"])
	var list: Array = _link.messages(str(first["thread"]))
	assert_int(list.size()).is_equal(1)
	assert_str(list[0]["status"]).is_equal(PhoneLink.STATUS_DELIVERED)


func test_reply_send_text_covers_every_quick_reply_and_ignores_unknown_preset() -> void:
	for i in PhoneLogic.QUICK_REPLY_IDS.size():
		var r := FakePhone.reply_to({"t": "send_text", "thread": "k", "preset": PhoneLogic.QUICK_REPLY_IDS[i]}, _phone())
		assert_str(r[0]["frame"]["msg"]["text"]).is_equal(PhoneLogic.QUICK_REPLIES[i])
	assert_array(FakePhone.reply_to({"t": "send_text", "thread": "k", "preset": "нет_такой"}, _phone())).is_empty()


func test_reply_accept_gives_in_call() -> void:
	var r := _now_frames(FakePhone.reply_to(_glasses()["accept"], _phone()))
	assert_int(r.size()).is_equal(1)
	assert_str(r[0]["t"]).is_equal("call")
	assert_str(r[0]["phase"]).is_equal(PhoneLink.PHASE_IN_CALL)
	assert_str(r[0]["peer"]).is_equal("ЛИС")


func test_reply_hangup_and_decline_give_idle_and_sound_stop() -> void:
	for cmd in ["hangup", "decline"]:
		var r := _now_frames(FakePhone.reply_to(_glasses()[cmd], _phone()))
		assert_int(r.size()).is_equal(2)
		assert_str(r[0]["phase"]).is_equal(PhoneLink.PHASE_IDLE)
		assert_str(r[1]["t"]).is_equal("sound")
		assert_str(r[1]["kind"]).is_equal("stop")


func test_reply_mark_read_zeroes_unread_of_that_thread() -> void:
	var lis_id := str((_phone()["threads"]["items"] as Array)[0]["id"])
	var r := FakePhone.reply_to({"t": "mark_read", "thread": lis_id}, _phone())
	assert_int(r.size()).is_equal(1)
	assert_str(r[0]["frame"]["t"]).is_equal("threads")
	var items: Array = r[0]["frame"]["items"]
	assert_int(int(items.filter(func(t): return t["id"] == lis_id)[0]["unread"])).is_equal(0)
	assert_int(items.size()).is_equal(2)
	# сам набор кадров не испорчен: у ЛИС по-прежнему 2 непрочитанных (JSON отдаёт числа как float)
	assert_int(int((_phone()["threads"]["items"] as Array)[0]["unread"])).is_equal(2)


func test_reply_mute_keeps_the_call_and_sets_muted() -> void:
	var r := _now_frames(FakePhone.reply_to({"t": "mute", "on": true}, _phone()))
	assert_str(r[0]["phase"]).is_equal(PhoneLink.PHASE_IN_CALL)
	assert_bool(r[0]["muted"]).is_true()
	assert_bool(_now_frames(FakePhone.reply_to({"t": "mute", "on": false}, _phone()))[0]["muted"]).is_false()


func test_reply_start_call_rings_back_then_connects_after_five_seconds() -> void:
	var r := FakePhone.reply_to(_glasses()["start_call"], _phone())
	var now := _now_frames(r)
	assert_str(now[0]["phase"]).is_equal(PhoneLink.PHASE_OUTGOING)
	assert_str(now[0]["peer"]).is_equal("ВОБЛА")
	assert_str(now[1]["kind"]).is_equal("ringback")
	var later: Array = r.filter(func(x): return float(x["delay"]) == FakePhone.ANSWER_AFTER_SEC).map(func(x): return x["frame"])
	assert_array(later.map(func(f): return f["phase"] if f["t"] == "call" else f["kind"])).is_equal(["stop", PhoneLink.PHASE_IN_CALL])


func test_reply_resync_gives_threads_every_dialog_log_and_contacts() -> void:
	var r := FakePhone.reply_to(_glasses()["resync"], _phone())
	var names: Array = r.map(func(x): return str(x["frame"]["t"]) + ":" + str(x["frame"].get("thread", "")))
	assert_int(names.size()).is_equal(5)
	assert_str(names[0]).is_equal("threads:")
	assert_bool(names.has("messages:faction")).is_true()
	assert_array(r.map(func(x): return x["frame"]["t"]).slice(3)).is_equal(["call_log", "contacts"])
	# все ответы принимаются очками
	for x in r:
		_link.on_frame(x["frame"])
	assert_int(_link.threads().size()).is_equal(2)
	assert_int(_link.contacts().size()).is_equal(3)


func test_reply_to_hello_ack_and_junk_is_silent() -> void:
	assert_array(FakePhone.reply_to(_glasses()["hello_ack"], _phone())).is_empty()
	assert_array(FakePhone.reply_to({}, _phone())).is_empty()
	assert_array(FakePhone.reply_to({"t": "что-то новое"}, _phone())).is_empty()


func test_scenarios_follow_the_card_timeline() -> void:
	var f := _phone()
	assert_array(FakePhone.scenario("idle", f)).is_empty()
	var chat := FakePhone.scenario("chat", f)
	assert_array(chat.map(func(e): return e["at"])).is_equal([3.0, 3.0, 8.0, 8.0])
	assert_str(chat[0]["frame"]["msg"]["from"]).is_equal("ЛИС")
	assert_str(chat[2]["frame"]["msg"]["thread"]).is_equal("faction")
	assert_str(chat[1]["frame"]["kind"]).is_equal("message")
	var call := FakePhone.scenario("call", f)
	assert_array(call.map(func(e): return e["at"])).is_equal([3.0, 3.0, 12.0, 12.0])
	assert_str(call[0]["frame"]["phase"]).is_equal(PhoneLink.PHASE_INCOMING)
	assert_str(call[1]["frame"]["kind"]).is_equal("ring")
	assert_str(call[2]["frame"]["phase"]).is_equal(PhoneLink.PHASE_IDLE)
	assert_str(call[3]["frame"]["kind"]).is_equal("stop")
	# all: чат, затем звонок; звонок не раньше конца чата
	var all := FakePhone.scenario("all", f)
	assert_int(all.size()).is_equal(8)
	assert_float(all[4]["at"]).is_greater(8.0)
	assert_float(FakePhone.scenario_end(all)).is_equal(22.0)


func test_scenario_frames_are_accepted_by_the_link() -> void:
	var sounds: Array = []
	_link.sound_requested.connect(func(k): sounds.append(k))
	_feed_dialogs()
	for e in FakePhone.scenario("all", _phone()):
		_link.on_frame(e["frame"])
	assert_array(sounds).is_equal(["message", "message", "ring", "stop"])
	assert_str(_link.call_state()["phase"]).is_equal(PhoneLink.PHASE_IDLE)
	assert_int(_link.messages("faction").size()).is_equal(3)


func test_load_frames_reads_the_contract_file() -> void:
	assert_bool(FakePhone.load_frames().has("hello")).is_true()
	assert_dict(FakePhone.load_frames("res://tests/fixtures/нет_такого.json")).is_empty()


func test_normalize_writes_whole_numbers_as_integers() -> void:
	var text := JSON.stringify(FakePhone.normalize({"t": "hello", "v": 1.0, "items": [{"ts": 1791198000.0, "x": 1.5}]}), "", true)
	assert_str(text).is_equal('{"items":[{"ts":1791198000,"x":1.5}],"t":"hello","v":1}')
	# сообщение, собранное телефоном в ответ на send_text, — с целым ts
	var r := FakePhone.reply_to(_glasses()["send_text"], _phone())
	assert_bool(JSON.stringify(FakePhone.normalize(r[0]["frame"])).contains(".0,")).is_false()


# ---------------------------------------------------------------- голос: бинарные кадры (раздел «Голос» документа)

func _decode_voice(hex: String) -> Dictionary:
	var bytes := hex.hex_decode()
	var samples: Array = []
	for i in range(5, bytes.size() - 1, 2):
		samples.append(bytes.decode_s16(i))
	return {"type": bytes[0], "seq": bytes.decode_u32(1), "samples": samples, "size": bytes.size()}


func test_voice_binary_samples_match_the_documented_layout() -> void:
	var b: Dictionary = _all()["binary"]
	var mic := _decode_voice(str(b["voice_mic_hex"]))
	var peer := _decode_voice(str(b["voice_peer_hex"]))
	assert_int(mic["type"]).is_equal(1)    # микрофон очков → телефон
	assert_int(peer["type"]).is_equal(2)   # звук собеседника телефон → очки
	assert_int(mic["seq"]).is_equal(int(b["seq"]))
	assert_int(peer["seq"]).is_equal(int(b["seq"]))
	var want: Array = (b["samples"] as Array).map(func(v): return int(v))   # JSON отдаёт числа как float
	assert_array(mic["samples"]).is_equal(want)
	assert_array(peer["samples"]).is_equal(want)
	assert_int(mic["size"]).is_equal(5 + 2 * (b["samples"] as Array).size())


func test_voice_json_frames_are_ignored_by_the_link_until_voice_is_implemented() -> void:
	# до среза 3 очки не должны падать на кадре voice и не должны менять состояние звонка
	_link.on_frame(_phone()["voice_on"])
	_link.on_frame(_phone()["voice_off"])
	assert_str(_link.call_state()["phase"]).is_equal("idle")
	assert_bool(_glasses()["voice_ready_on"]["on"]).is_true()
	assert_bool(_glasses()["voice_ready_off"]["on"]).is_false()
