class_name FakePhone
extends RefCounted
## Логика «фальшивого телефона» (tools/fake_phone.gd) без сети: что телефон отвечает на кадры очков и какие кадры шлёт по сценарию.
## Вынесено отдельно, чтобы проверять тестом (tests/fake_phone_test.gd) без WebSocket. Кадры берутся из tests/fixtures/phone_frames.json (раздел `phone_to_glasses`).
## Ответ — массив `{"delay": секунды, "frame": Dictionary}`: delay 0 — отдать сразу, иначе через столько секунд (счёт ведёт вызывающий, не sleep).

const FRAMES_PATH := "res://tests/fixtures/phone_frames.json"
## Через сколько секунд после отправки сообщение считается доставленным.
const DELIVERED_AFTER_SEC := 1.0
## Через сколько секунд исходящий звонок «берут трубку».
const ANSWER_AFTER_SEC := 5.0

static var _seq := 0


## Кадры телефона (раздел `phone_to_glasses` файла). Пустой словарь — файл не прочитан.
static func load_frames(path: String = FRAMES_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and (parsed as Dictionary).get("phone_to_glasses") is Dictionary:
		return (parsed as Dictionary)["phone_to_glasses"]
	return {}


static func _out(frame: Dictionary, delay: float = 0.0) -> Dictionary:
	return {"delay": delay, "frame": frame}


## Копия кадра из набора с подменой полей.
static func _frame(frames: Dictionary, name: String, over: Dictionary = {}) -> Dictionary:
	var f: Dictionary = (frames.get(name, {}) as Dictionary).duplicate(true)
	for k in over:
		f[k] = over[k]
	return f


## Unix-секунды целым числом: приложение отдаёт ts секундами без дробной части.
static func _now() -> float:
	return floorf(Time.get_unix_time_from_system())


## Целые числа в кадре — как целые (JSON.stringify пишет float 1 как «1.0», а телефон шлёт «1»): вызывается перед отправкой.
static func normalize(v: Variant) -> Variant:
	if v is float and is_equal_approx(v, roundf(v)) and absf(v) < 1.0e15:
		return int(v)
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = normalize(v[k])
		return d
	if v is Array:
		return (v as Array).map(func(x): return normalize(x))
	return v


## Кадры «полной синхронизации»: диалоги, сообщения по каждому диалогу, журнал звонков, контакты.
static func resync(frames: Dictionary) -> Array:
	var names: Array = ["threads"]
	var dialogs: Array = frames.keys().filter(func(n): return str(n).begins_with("messages_"))
	dialogs.sort()
	names.append_array(dialogs)
	names.append_array(["call_log", "contacts"])
	var out: Array = []
	for name in names:
		if frames.has(name):
			out.append(_out(_frame(frames, str(name))))
	return out


## Ответ телефона на кадр очков. Неизвестные кадры (hello_ack и прочее) — без ответа.
static func reply_to(frame: Dictionary, frames: Dictionary) -> Array:
	match str(frame.get("t", "")):
		"resync":
			return resync(frames)
		"send_text":
			return _reply_send_text(frame)
		"mark_read":
			return _reply_mark_read(str(frame.get("thread", "")), frames)
		"accept":
			return [_out(_call_frame(frames, "call_in_call", {"since_ts": _now()}))]
		"decline", "hangup":
			return [_out(_frame(frames, "call_idle")), _out(_frame(frames, "sound_stop"))]
		"mute":
			return [_out(_call_frame(frames, "call_in_call", {"muted": bool(frame.get("on", false))}))]
		"start_call":
			var peer := str(frame.get("peer", ""))
			return [
				_out(_call_frame(frames, "call_outgoing", {"peer": peer, "since_ts": _now()})),
				_out(_frame(frames, "sound_ringback")),
				_out(_frame(frames, "sound_stop"), ANSWER_AFTER_SEC),
				_out(_call_frame(frames, "call_in_call", {"peer": peer, "since_ts": _now() + ANSWER_AFTER_SEC}), ANSWER_AFTER_SEC),
			]
	return []


static func _call_frame(frames: Dictionary, name: String, over: Dictionary) -> Dictionary:
	return _frame(frames, name, over)


## send_text{thread,preset} → message{mine, text по заготовке, status:"sent"}, через секунду тот же id со status:"delivered".
static func _reply_send_text(frame: Dictionary) -> Array:
	var i := PhoneLogic.QUICK_REPLY_IDS.find(str(frame.get("preset", "")))
	if i < 0:
		return []   # неизвестная заготовка телефон не отправляет
	_seq += 1
	var msg := {"id": "fp_%d_%d" % [int(_now()), _seq], "thread": str(frame.get("thread", "")), "mine": true, "text": PhoneLogic.QUICK_REPLIES[i],
		"ts": _now(), "status": PhoneLink.STATUS_SENT, "from": ""}
	var done := msg.duplicate()
	done["status"] = PhoneLink.STATUS_DELIVERED
	return [_out({"t": "message", "msg": msg}), _out({"t": "message", "msg": done}, DELIVERED_AFTER_SEC)]


## mark_read{thread} → threads, где у этого диалога unread = 0 (остальные как в наборе).
static func _reply_mark_read(thread_id: String, frames: Dictionary) -> Array:
	var f := _frame(frames, "threads")
	var items: Array = f.get("items", [])
	for it in items:
		if it is Dictionary and str(it.get("id", "")) == thread_id:
			it["unread"] = 0
	return [_out(f)]


## Сценарии по таймеру: массив `{"at": секунды от начала, "frame": ...}`. Идут от получения hello_ack.
## chat — входящее ЛС и ещё одно во фракцию; call — входящий звонок, потом отбой; all — чат, затем звонок.
static func scenario(name: String, frames: Dictionary) -> Array:
	match name:
		"idle":
			return []
		"chat":
			return _chat(frames, 0.0)
		"call":
			return _call(frames, 0.0)
		"all":
			return _chat(frames, 0.0) + _call(frames, 10.0)
	return []


static func _chat(frames: Dictionary, base: float) -> Array:
	return [
		{"at": base + 3.0, "frame": _frame(frames, "message_incoming", {"msg": _stamp(frames, "message_incoming")})},
		{"at": base + 3.0, "frame": _frame(frames, "sound_message")},
		{"at": base + 8.0, "frame": _frame(frames, "message_faction", {"msg": _stamp(frames, "message_faction")})},
		{"at": base + 8.0, "frame": _frame(frames, "sound_message")},
	]


static func _call(frames: Dictionary, base: float) -> Array:
	return [
		{"at": base + 3.0, "frame": _call_frame(frames, "call_incoming", {"since_ts": _now() + base + 3.0})},
		{"at": base + 3.0, "frame": _frame(frames, "sound_ring")},
		{"at": base + 12.0, "frame": _frame(frames, "call_idle")},
		{"at": base + 12.0, "frame": _frame(frames, "sound_stop")},
	]


## Сообщение кадра `message` с ts «сейчас» (id остаётся канонический: повторный запуск сценария заменит то же сообщение, а не добавит новое).
static func _stamp(frames: Dictionary, name: String) -> Dictionary:
	var msg: Dictionary = ((frames.get(name, {}) as Dictionary).get("msg", {}) as Dictionary).duplicate()
	msg["ts"] = _now()
	return msg


## Время последнего события сценария (для паузы на ответы очков в конце).
static func scenario_end(events: Array) -> float:
	var t := 0.0
	for e in events:
		t = maxf(t, float((e as Dictionary)["at"]))
	return t
