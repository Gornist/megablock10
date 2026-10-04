class_name BridgeClient
extends BridgeApi
## Клиент настоящего Моста по WebSocket (docs/netrun-bridge-protocol.md): hello ролью world, запросы с cid, подписка на
## документы, переподключение с повторным hello и sub. Владелец зовёт poll() каждый кадр (WorldServer._process).
## Разбор сообщений — статические parse_message/build_request, чтобы тестировать без сети.

const PROTO := 1
const ROLE := "world"
## Роль в hello: world (сервер мира); test — только стенды и долгий прогон (Мост с --test), tools/soak_run.gd.
var role := ROLE
const WS_BUFFER_BYTES := 1 << 24  # 16 МиБ
const REQUEST_TIMEOUT_MS := 4000
const RECONNECT_MS := 2000
const PING_SEC := 10.0

enum State { IDLE, CONNECTING, HELLO, READY }

## Ответ на запрос ушёл/пришёл — для await (внутренний тип).
class Pending:
	extends RefCounted
	signal done(resp: Dictionary)
	var deadline_ms := 0
	var finished := false

	func finish(resp: Dictionary) -> void:
		if finished:
			return
		finished = true
		done.emit(resp)

var url: String
var key: String
var client_name: String
var state: State = State.IDLE
var world_pub := ""
## Локальная копия подписанных документов: тип -> {id -> документ}. Заменяется снимком, правится пушами.
var docs: Dictionary = {}
var last_seq := 0

var _ws := WebSocketPeer.new()
var _pending: Dictionary = {}       # cid -> Pending
var _next_cid := 0
var _sub_types: Dictionary = {}     # типы, на которые подписывались (для повторной подписки)
var _reconnect_at_ms := 0
var _was_open := false

signal became_ready
signal lost


func _init(bridge_url: String = "ws://127.0.0.1:7410/netrun/v1", role_key: String = "", name_of_client: String = "world-main") -> void:
	url = bridge_url
	key = role_key
	client_name = name_of_client
	_ws = new_socket()


## Сокет с буферами под снимок всех документов. У Godot входной буфер по умолчанию 64 КиБ, а подписка `sub` присылает снимок
## одним кадром: с тысячей документов он больше, Godot закрывал соединение кодом 1009 («слишком большое»), и сервер мира не мог
## взять снимок вовсе (нашёл долгий прогон, P7).
static func new_socket() -> WebSocketPeer:
	var ws := WebSocketPeer.new()
	ws.heartbeat_interval = PING_SEC
	ws.inbound_buffer_size = WS_BUFFER_BYTES
	ws.outbound_buffer_size = WS_BUFFER_BYTES
	ws.max_queued_packets = 8192
	return ws


## Разбор кадра Моста: {"kind": "reply"|"push"|"invalid", ...}. reply — с полем "re" (cid) и полным телом;
## push — {"push": "chg", "doc", "seq", "last", "deleted"}.
static func parse_message(text: String) -> Dictionary:
	var json := JSON.new()  # parse(), а не parse_string: мусорный кадр не должен сыпать ошибками движка
	if json.parse(text) != OK or not (json.data is Dictionary):
		return {"kind": "invalid", "reason": "не JSON-объект"}
	var m: Dictionary = json.data
	if m.has("re"):
		return {"kind": "reply", "re": str(m["re"]), "body": m}
	if m.has("push"):
		return {
			"kind": "push", "push": str(m["push"]), "seq": int(m.get("seq", 0)), "last": bool(m.get("last", true)),
			"deleted": bool(m.get("deleted", false)), "doc": m.get("doc", {}),
		}
	return {"kind": "invalid", "reason": "ни re, ни push"}


## Ответ Моста -> словарь формы BridgeApi: ok с полями или {"ok": false, "err": {...}}.
static func to_response(body: Dictionary) -> Dictionary:
	if body.get("ok", false):
		var r := body.duplicate()
		r.erase("v")
		r.erase("re")
		return r
	var e: Variant = body.get("err", {})
	if e is Dictionary and e.has("code"):
		return {"ok": false, "err": e}
	return BridgeApi.err("internal", "ответ без err")


## Запрос в виде текста кадра: поля из fields плюс v, cid, op.
static func build_request(cid: String, op: String, fields: Dictionary = {}) -> String:
	var m := {"v": PROTO, "cid": cid, "op": op}
	m.merge(fields)
	return JSON.stringify(m)


func start() -> void:
	_connect()


func is_ready() -> bool:
	return state == State.READY


func _connect() -> void:
	state = State.CONNECTING
	_ws = new_socket()
	var e := _ws.connect_to_url(url)
	if e != OK:
		push_warning("[bridge] не начать соединение с %s: %s" % [url, error_string(e)])
		_schedule_reconnect()


func _schedule_reconnect() -> void:
	state = State.IDLE
	_reconnect_at_ms = Time.get_ticks_msec() + RECONNECT_MS


func poll() -> void:
	var now := Time.get_ticks_msec()
	if state == State.IDLE:
		if _reconnect_at_ms != 0 and now >= _reconnect_at_ms:
			_connect()
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				_handshake()  # сопрограмма: дальше живёт сама
			while _ws.get_available_packet_count() > 0:
				handle_text(_ws.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			var was := _was_open
			_was_open = false
			print("[bridge] соединение закрыто (код %d)" % _ws.get_close_code())
			_fail_all("disconnected")
			_schedule_reconnect()
			if was:
				lost.emit()
	for cid in _pending.keys():
		if now >= (_pending[cid] as Pending).deadline_ms:
			_resolve(cid, BridgeApi.err("timeout", "Мост не ответил"))


## hello, затем повторная подписка (после обрыва снимок заменяет локальную копию).
func _handshake() -> void:
	state = State.HELLO
	var r: Dictionary = await _send("hello", {"proto": PROTO, "role": role, "client": client_name, "key": key})
	if not r.get("ok", false):
		push_error("[bridge] hello отклонён: %s" % str(r.get("err", {})))
		_ws.close()
		return
	world_pub = str(r.get("world_pub", ""))
	state = State.READY
	if not _sub_types.is_empty():
		await subscribe(_sub_types.keys())
	print("[bridge] готов к работе, Мост ", r.get("bridge", "?"))
	became_ready.emit()


## Один запрос — одна запись в _pending. До готовности (кроме hello) ждём готовности не дольше таймаута.
func _request(op: String, fields: Dictionary = {}) -> Dictionary:
	var until := Time.get_ticks_msec() + REQUEST_TIMEOUT_MS
	while state != State.READY:
		if Time.get_ticks_msec() >= until:
			return BridgeApi.err("unavailable", "Мост недоступен")
		await _sleep(0.05)
	return await _send(op, fields)


func _sleep(sec: float) -> void:
	await Engine.get_main_loop().create_timer(sec).timeout


func _send(op: String, fields: Dictionary) -> Dictionary:
	_next_cid += 1
	var cid := "w-%d" % _next_cid
	var p := Pending.new()
	p.deadline_ms = Time.get_ticks_msec() + REQUEST_TIMEOUT_MS
	_pending[cid] = p
	var e := _ws.send_text(build_request(cid, op, fields))
	if e != OK:
		_resolve(cid, BridgeApi.err("unavailable", "не отправить: " + error_string(e)))
	return await p.done


func _resolve(cid: String, resp: Dictionary) -> void:
	var p: Pending = _pending.get(cid)
	if p == null:
		return
	_pending.erase(cid)
	p.finish(resp)


func _fail_all(code: String) -> void:
	for cid in _pending.keys():
		_resolve(cid, BridgeApi.err(code, "связь с Мостом потеряна"))


## Кадр от Моста (вызывается из poll; публичный — для тестов).
func handle_text(text: String) -> void:
	var m := parse_message(text)
	match m["kind"]:
		"reply":
			_resolve(m["re"], to_response(m["body"]))
		"push":
			if m["push"] == "chg":
				_apply_change(m["doc"], m["deleted"], m["seq"])
		_:
			push_warning("[bridge] непонятный кадр: %s" % m.get("reason", ""))


func _apply_change(doc: Dictionary, deleted: bool, seq: int) -> void:
	if doc.is_empty():
		return
	last_seq = max(last_seq, seq)
	var type := str(doc.get("type", ""))
	if not docs.has(type):
		docs[type] = {}
	if deleted:
		(docs[type] as Dictionary).erase(doc.get("id"))
	else:
		docs[type][doc.get("id")] = doc
	doc_changed.emit(doc, deleted)


func terminal_auth(terminal: String, token: String) -> Dictionary:
	return await _request("terminal.auth", {"terminal": terminal, "token": token})


func session_confirm(session: String, terminal: String) -> Dictionary:
	return await _request("session.confirm", {"session": session, "terminal": terminal})


func session_abort(session: String, reason: String) -> Dictionary:
	return await _request("session.abort", {"session": session, "reason": reason})


func terminal_beat(terminal: String, battery: int = -1, fps: int = -1, link: int = -1) -> Dictionary:
	var f := {"terminal": terminal}
	if battery >= 0:
		f["battery"] = battery
	if fps >= 0:
		f["fps"] = fps
	if link >= 0:
		f["link"] = link
	return await _request("terminal.beat", f)


func op_take_from_node(session: String, node: String, item: String) -> Dictionary:
	return await _request("op.take_from_node", {"rid": take_rid(session, item), "session": session, "node": node, "item": item})


func op_leave_in_node(session: String, node: String, item: String) -> Dictionary:
	return await _request("op.leave_in_node", {"rid": leave_rid(session, item), "session": session, "node": node, "item": item})


func op_give_item(session: String, item: String, ver: int, to_session: String, to_phone: String) -> Dictionary:
	var f := {"rid": give_rid(session, item, ver, to_session if not to_session.is_empty() else to_phone), "session": session, "item": item, "ver": ver}
	if not to_session.is_empty():
		f["to_session"] = to_session
	if not to_phone.is_empty():
		f["to_phone"] = to_phone
	return await _request("op.give_item", f)


func op_decrypt_item(session: String, item: String, ver: int) -> Dictionary:
	return await _request("op.decrypt_item", {"rid": decrypt_rid(session, item, ver), "session": session, "item": item, "ver": ver})


func run_finish(session: String, outcome: String, node: String, disconnect: bool, moves: Array) -> Dictionary:
	return await _request("run.finish", {
		"rid": finish_rid(session), "session": session, "outcome": outcome, "node": node, "disconnect": disconnect, "moves": moves,
	})


func run_breach(session: String, node: String, req: Dictionary) -> Dictionary:
	var f := req.duplicate(true)
	f["rid"] = breach_rid(session, int(req.get("n", 0)))
	f["session"] = session
	f["node"] = node
	return await _request("run.breach", f)


func master_gate(kind: String, ref: String, node: String, summary: String) -> Dictionary:
	return await _request("master.gate", {"kind": kind, "ref": ref, "node": node, "summary": summary})


func put_doc(type: String, id: String, ver: int, data: Dictionary) -> Dictionary:
	return await _request("put", {"type": type, "id": id, "ver": ver, "data": ints_of(data)})


func get_doc(type: String, id: String) -> Dictionary:
	return await _request("get", {"type": type, "id": id})


func list_docs(type: String) -> Dictionary:
	return await _request("list", {"type": type})


func subscribe(types: Array) -> Dictionary:
	for t in types:
		_sub_types[str(t)] = true
	var r: Dictionary = await _request("sub", {"types": types})
	if r.get("ok", false):
		# Снимок заменяет локальную копию этих типов.
		for t in types:
			docs[str(t)] = {}
		for d in r.get("docs", []):
			var type := str(d.get("type", ""))
			if not docs.has(type):
				docs[type] = {}
			docs[type][d.get("id")] = d
		last_seq = int(r.get("seq", last_seq))
	return r
