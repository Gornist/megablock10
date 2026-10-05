extends GdUnitTestSuite
## Контрактные кадры связи очков с телефоном (tests/fixtures/phone_frames.json, docs/netrun-phone-link.md, раздел 2): все кадры телефона принимает
## RemotePhoneLink.on_frame с ожидаемым эффектом, все кадры очков — валидный JSON известного типа. Тот же файл питает инструмент tools/fake_phone.gd.

const FRAMES_PATH := "res://tests/fixtures/phone_frames.json"
const PHONE_TYPES: Array[String] = ["hello", "threads", "messages", "message", "call", "call_log", "contacts", "sound"]
const GLASSES_TYPES: Array[String] = ["hello_ack", "send_text", "mark_read", "accept", "decline", "hangup", "mute", "start_call", "resync"]

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
