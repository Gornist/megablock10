class_name RemotePhoneLink
extends PhoneLink
## Настоящая связь очков с телефоном (docs/netrun-phone-link.md): очки — WebSocket-сервер, телефон (приложение, `HeadsetMirror`) — клиент.
## Вместо FakePhoneLink; дека не меняется. Данные приходят кадрами JSON с полем `t` (точный формат — в документе, раздел 2), команды деки уходят кадрами обратно.
##
## Подключение: телефон открывает `ws://адрес:порт/?token=<токен>`. Токен читаем из query по `get_requested_url()` (серверный WebSocketPeer заголовки рукопожатия не отдаёт),
## неверный — закрываем (4001). Потом первым кадром должен прийти `hello{v,callsign}` (иначе закрываем за [HELLO_TIMEOUT_SEC]); принятого телефона подтверждаем `hello_ack` и просим
## `resync`. Телефон один: новый принятый подключившийся заменяет прежнего (4003). Обрыв — данные остаются последними известными, [is_online] = false, звуковые петли
## гасятся (`sound_requested("stop")`); пропущенный звонок остаётся на телефоне.
##
## Звуки (рингтон, дозвон, сообщение) приложение просит кадром `sound{kind}`; играет их не эта связь, а подписчик на [signal sound_requested] (PhoneSounds).
## Сама связь работает от внешнего такта `advance(delta)` (его зовёт WorldUi каждый кадр): опрос сокетов и тайм-ауты.

## Приложение просит звук: ring | ringback | message | stop.
signal sound_requested(kind: String)

const PROTOCOL_VERSION := 1
const DEFAULT_PORT := 7420
## Кадр больше этого — нарушение формата (docs/netrun-phone-link.md): соединение закрываем.
const MAX_FRAME_BYTES := 262144
const HELLO_TIMEOUT_SEC := 5.0
## Лимиты хранимого: диалогов и сообщений на диалог (приложение шлёт ЛС 20, фракция 40).
const MAX_THREADS := 200
const MAX_MESSAGES := 100
const SOUND_KINDS: Array[String] = ["ring", "ringback", "message", "stop"]
const STATUSES: Array[String] = [PhoneLink.STATUS_SENT, PhoneLink.STATUS_DELIVERED, PhoneLink.STATUS_FAILED]
const PHASES: Array[String] = [PhoneLink.PHASE_IDLE, PhoneLink.PHASE_OUTGOING, PhoneLink.PHASE_INCOMING, PhoneLink.PHASE_IN_CALL]
## Коды закрытия WebSocket (4000+ — прикладные).
const CLOSE_BAD_TOKEN := 4001
const CLOSE_BAD_HELLO := 4002
const CLOSE_REPLACED := 4003
const CLOSE_TOO_BIG := 1009

var port := DEFAULT_PORT
var token := ""
## Позывной владельца телефона из последнего hello (для журнала).
var phone_callsign := ""

var _server := TCPServer.new()
var _peer: WebSocketPeer = null
var _joining: Array[Dictionary] = []   # [{ws: WebSocketPeer, age: float, token_ok: bool}] — рукопожатие и ожидание hello
var _clock := 0.0
var _threads: Dictionary = {}          # id -> диалог
var _messages: Dictionary = {}         # id диалога -> [сообщение], старые первыми
var _call: Dictionary = PhoneLink.idle_call()
var _call_log: Array = []
var _contacts: Array = []
var _local_seq := 0


## Начать слушать. Токен пустой — принимаем любого (стенд без токена). Ошибка Godot (например порт занят) — как есть.
func start(p_port: int = DEFAULT_PORT, p_token: String = "") -> Error:
	port = p_port
	token = p_token
	return _server.listen(port)


func stop() -> void:
	for j in _joining:
		(j["ws"] as WebSocketPeer).close()
	_joining.clear()
	if _peer != null:
		_peer.close()
		_drop_peer()
	_server.stop()


## Порт, на котором реально слушаем (если start просили порт 0 — выбранный системой).
func listen_port() -> int:
	return _server.get_local_port()


func is_online() -> bool:
	return _peer != null


# ---------------------------------------------------------------- такт и соединения

func advance(delta: float) -> void:
	_clock += delta
	while _server.is_connection_available():
		var tcp := _server.take_connection()
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = MAX_FRAME_BYTES * 2
		ws.max_queued_packets = 256
		if ws.accept_stream(tcp) == OK:
			_joining.append({"ws": ws, "age": 0.0, "token_ok": false})
	_poll_joining(delta)
	_poll_peer()


func _poll_joining(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for j in _joining:
		var ws: WebSocketPeer = j["ws"]
		ws.poll()
		j["age"] = float(j["age"]) + delta
		var state := ws.get_ready_state()
		if state == WebSocketPeer.STATE_CLOSED or state == WebSocketPeer.STATE_CLOSING:
			continue
		if float(j["age"]) > HELLO_TIMEOUT_SEC:
			ws.close(CLOSE_BAD_HELLO, "hello timeout")
			continue
		if state == WebSocketPeer.STATE_OPEN:
			if not bool(j["token_ok"]):
				if not _token_matches(ws.get_requested_url()):
					ws.close(CLOSE_BAD_TOKEN, "token")
					continue
				j["token_ok"] = true
			if ws.get_available_packet_count() > 0:
				if _accept_hello(ws, ws.get_packet()):
					continue   # принят: из очереди рукопожатия ушёл, теперь это _peer
				ws.close(CLOSE_BAD_HELLO, "hello")
				continue
		keep.append(j)
	_joining = keep


func _accept_hello(ws: WebSocketPeer, packet: PackedByteArray) -> bool:
	var frame := _parse(packet)
	if str(frame.get("t", "")) != "hello":
		return false
	var v := int(frame.get("v", 0))
	if v < 1 or v > PROTOCOL_VERSION:
		return false
	if _peer != null:
		_peer.close(CLOSE_REPLACED, "replaced")
		_peer = null
	_peer = ws
	phone_callsign = str(frame.get("callsign", ""))
	_send({"t": "hello_ack", "v": PROTOCOL_VERSION})
	_send({"t": "resync"})
	online_changed.emit(true)
	return true


func _poll_peer() -> void:
	if _peer == null:
		return
	_peer.poll()
	var state := _peer.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while _peer.get_available_packet_count() > 0:
			var packet := _peer.get_packet()
			if packet.size() > MAX_FRAME_BYTES:
				_peer.close(CLOSE_TOO_BIG, "too big")
				break
			on_frame(_parse(packet))
	elif state == WebSocketPeer.STATE_CLOSED:
		_drop_peer()


func _drop_peer() -> void:
	_peer = null
	sound_requested.emit("stop")
	online_changed.emit(false)
	call_changed.emit(call_state())


## query адреса: `...?token=abc&x=1` → токен совпал. Токен пуст — совпадает всё.
func _token_matches(url: String) -> bool:
	if token.is_empty():
		return true
	var q := url.get_slice("?", 1) if url.contains("?") else ""
	for pair in q.split("&"):
		if pair.begins_with("token=") and pair.trim_prefix("token=").uri_decode() == token:
			return true
	return false


static func _parse(packet: PackedByteArray) -> Dictionary:
	var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


func _send(frame: Dictionary) -> bool:
	if _peer == null or _peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	return _peer.send_text(JSON.stringify(frame)) == OK


# ---------------------------------------------------------------- кадры от телефона

## Разбор одного кадра от телефона (публичный: тесты подают кадры напрямую). Неизвестные типы и поля игнорируются.
func on_frame(frame: Dictionary) -> void:
	match str(frame.get("t", "")):
		"threads":
			_threads.clear()
			for raw in _items(frame):
				var th := _norm_thread(raw)
				if not th.is_empty() and _threads.size() < MAX_THREADS:
					_threads[th["id"]] = th
			threads_changed.emit()
		"messages":
			var tid := str(frame.get("thread", ""))
			if tid.is_empty():
				return
			var list: Array = []
			for raw in _items(frame):
				var m := _norm_message(raw, tid)
				if not m.is_empty():
					list.append(m)
			_messages[tid] = list.slice(maxi(list.size() - MAX_MESSAGES, 0))
			threads_changed.emit()
		"message":
			var raw: Variant = frame.get("msg")
			var m := _norm_message(raw, str((raw as Dictionary).get("thread", "")) if raw is Dictionary else "")
			if m.is_empty():
				return
			var fresh := _upsert_message(m)
			threads_changed.emit()
			if fresh and not bool(m["mine"]):
				message_received.emit(str(m["thread"]), m.duplicate())
		"call":
			var phase := str(frame.get("phase", ""))
			if not PHASES.has(phase):
				return
			_call = {"phase": phase, "peer": str(frame.get("peer", "")), "since_ts": float(frame.get("since_ts", 0)), "muted": bool(frame.get("muted", false))}
			call_changed.emit(call_state())
		"call_log":
			_call_log.clear()
			for raw in _items(frame):
				if raw is Dictionary:
					_call_log.append({"peer": str(raw.get("peer", "")), "dir": str(raw.get("dir", PhoneLink.DIR_OUT)), "ts": float(raw.get("ts", 0)),
						"duration_s": float(raw.get("duration_s", 0))})
			call_changed.emit(call_state())
		"contacts":
			_contacts.clear()
			for raw in _items(frame):
				if raw is Dictionary and not str(raw.get("key", "")).is_empty():
					_contacts.append({"key": str(raw["key"]), "title": str(raw.get("title", ""))})
		"sound":
			var kind := str(frame.get("kind", ""))
			if SOUND_KINDS.has(kind):
				sound_requested.emit(kind)


static func _items(frame: Dictionary) -> Array:
	var v: Variant = frame.get("items")
	return v if v is Array else []


static func _norm_thread(raw: Variant) -> Dictionary:
	if not raw is Dictionary or str((raw as Dictionary).get("id", "")).is_empty():
		return {}
	var d: Dictionary = raw
	var kind := str(d.get("kind", PhoneLink.KIND_DM))
	if kind != PhoneLink.KIND_DM and kind != PhoneLink.KIND_FACTION:
		kind = PhoneLink.KIND_DM
	return {"id": str(d["id"]), "kind": kind, "title": str(d.get("title", "")), "last_text": str(d.get("last_text", "")),
		"last_ts": float(d.get("last_ts", 0)), "unread": maxi(int(d.get("unread", 0)), 0)}


static func _norm_message(raw: Variant, thread_id: String) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var d: Dictionary = raw
	var tid := str(d.get("thread", thread_id))
	if str(d.get("id", "")).is_empty() or tid.is_empty():
		return {}
	var status := str(d.get("status", PhoneLink.STATUS_SENT))
	return {"id": str(d["id"]), "thread": tid, "mine": bool(d.get("mine", false)), "text": str(d.get("text", "")), "ts": float(d.get("ts", 0)),
		"status": status if STATUSES.has(status) else PhoneLink.STATUS_SENT, "from": str(d.get("from", ""))}


## Добавить сообщение или заменить по id (смена статуса). true — сообщение новое.
func _upsert_message(m: Dictionary) -> bool:
	var tid := str(m["thread"])
	var list: Array = _messages.get(tid, [])
	for i in list.size():
		if str((list[i] as Dictionary)["id"]) == str(m["id"]):
			list[i] = m
			_messages[tid] = list
			return false
	list.append(m)
	if list.size() > MAX_MESSAGES:
		list = list.slice(list.size() - MAX_MESSAGES)
	_messages[tid] = list
	return true


# ---------------------------------------------------------------- PhoneLink: данные

func threads() -> Array:
	return _threads.values().map(func(t: Dictionary) -> Dictionary: return t.duplicate())


func messages(thread_id: String, limit: int = PhoneLogic.MESSAGES_SHOWN) -> Array:
	var list: Array = _messages.get(thread_id, [])
	return list.slice(maxi(list.size() - limit, 0)).map(func(m: Dictionary) -> Dictionary: return m.duplicate())


func call_state() -> Dictionary:
	return _call.duplicate()


func call_log() -> Array:
	return _call_log.duplicate(true)


func contacts() -> Array:
	return _contacts.duplicate(true)


# ---------------------------------------------------------------- PhoneLink: команды деки

## Только заготовки: текст из PhoneLogic.QUICK_REPLIES уходит телефону как id (он подставляет текст сам). Нет связи — в диалоге остаётся сообщение «не доставлено».
func send_text(thread_id: String, text: String) -> void:
	var id := PhoneLogic.quick_reply_id(text.strip_edges())
	if id.is_empty():
		push_warning("[remote-phone] не заготовка, не отправляю: «%s»" % text)
		return
	if not _send({"t": "send_text", "thread": thread_id, "preset": id}):
		_local_seq += 1
		_upsert_message({"id": "local_%d" % _local_seq, "thread": thread_id, "mine": true, "text": text.strip_edges(), "ts": now(), "status": PhoneLink.STATUS_FAILED, "from": ""})
		threads_changed.emit()


func mark_read(thread_id: String) -> void:
	if _threads.has(thread_id) and int((_threads[thread_id] as Dictionary)["unread"]) > 0:
		(_threads[thread_id] as Dictionary)["unread"] = 0
		threads_changed.emit()
	_send({"t": "mark_read", "thread": thread_id})


func accept_call() -> void:
	_send({"t": "accept"})


func decline_call() -> void:
	_send({"t": "decline"})


func hangup() -> void:
	_send({"t": "hangup"})


func set_muted(muted: bool) -> void:
	_send({"t": "mute", "on": muted})


func start_call(peer_id: String) -> void:
	if str(_call["phase"]) != PhoneLink.PHASE_IDLE:
		return
	_send({"t": "start_call", "peer": peer_id})
