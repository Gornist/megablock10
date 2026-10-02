class_name FakeBridge
extends BridgeApi
## Фейковый Мост в том же процессе (F1): тот же интерфейс, что у BridgeClient, данные — из JSON-фикстуры.
## Повторяет только то, что нужно серверу мира: токен терминала, сессии, взять/оставить/завершить с повтором по `rid`.
## Правил Моста (локдаун, блокировка, аудитор, таблица исходов) тут нет — это проверяет настоящий Мост.

const DEFAULT_FIXTURE := "res://tests/fixtures/bridge_fixture.json"

var _docs: Dictionary = {}      # тип -> {id -> документ {type,id,ver,data}}
var _rids: Dictionary = {}      # rid -> {"params": String, "resp": Dictionary}
var _subs: Dictionary = {}      # тип -> true
var _seq := 0
var _load_error := ""
## Последнее состояние по терминалу, как оно пришло в terminal.beat (-1 — поле не передано), и число вызовов (P6).
var last_beat: Dictionary = {}
var beat_count: Dictionary = {}


func _init(fixture_path: String = DEFAULT_FIXTURE) -> void:
	_load_fixture(fixture_path)


func load_error() -> String:
	return _load_error


func is_ready() -> bool:
	return _load_error.is_empty()


func _load_fixture(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_load_error = "нет фикстуры %s" % path
		push_error("[fake-bridge] " + _load_error)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		_load_error = "фикстура %s — не JSON-объект" % path
		push_error("[fake-bridge] " + _load_error)
		return
	var sections := {"nodes": T_NODE, "terminals": T_TERMINAL, "sessions": T_SESSION, "items": T_ITEM, "settings": "settings"}
	for section in sections:
		var type: String = sections[section]
		_docs[type] = {}
		for id in (parsed.get(section, {}) as Dictionary):
			_docs[type][id] = {"type": type, "id": id, "ver": 1, "data": (parsed[section][id] as Dictionary).duplicate(true)}


func doc(type: String, id: String) -> Dictionary:
	return (_docs.get(type, {}) as Dictionary).get(id, {})


func _put(type: String, id: String, data: Dictionary) -> Dictionary:
	var d := doc(type, id)
	d["data"] = data
	d["ver"] = int(d["ver"]) + 1
	_seq += 1
	if _subs.has(type):
		doc_changed.emit(d.duplicate(true), false)
	return d


## Идемпотентность по rid: тот же rid с теми же параметрами — сохранённый ответ с replayed, другие параметры — rid_mismatch.
func _once(rid: String, params: Dictionary, fn: Callable) -> Dictionary:
	var key := JSON.stringify(params)
	if _rids.has(rid):
		if _rids[rid]["params"] != key:
			return err("rid_mismatch", "rid %s уже с другими параметрами" % rid)
		var saved: Dictionary = (_rids[rid]["resp"] as Dictionary).duplicate(true)
		saved["replayed"] = true
		return saved
	var resp: Dictionary = fn.call()
	resp["replayed"] = false
	_rids[rid] = {"params": key, "resp": resp.duplicate(true)}
	return resp


func terminal_auth(terminal: String, token: String) -> Dictionary:
	var t := doc(T_TERMINAL, terminal)
	if t.is_empty() or str(t["data"].get("token_sha256", "")) != token.sha256_text():
		return err("bad_token", "токен терминала не сошёлся")
	var open: Variant = null
	for id in _docs[T_SESSION]:
		var s: Dictionary = _docs[T_SESSION][id]
		if s["data"].get("terminal") == terminal and s["data"].get("state") != "closed":
			open = s.duplicate(true)
	return ok({"terminal": t.duplicate(true), "session": open})


func session_confirm(session: String, terminal: String) -> Dictionary:
	var s := doc(T_SESSION, session)
	if s.is_empty():
		return err("not_found", "сессии нет")
	if s["data"].get("terminal") != terminal:
		return err("bad_request", "сессия другого терминала")
	match s["data"].get("state"):
		"active":
			return ok({"session": s.duplicate(true)})
		"pending":
			var d: Dictionary = (s["data"] as Dictionary).duplicate()
			d["state"] = "active"
			return ok({"session": _put(T_SESSION, session, d).duplicate(true)})
	return err("session_state", "сессия закрыта", s.duplicate(true))


func session_abort(session: String, _reason: String) -> Dictionary:
	var s := doc(T_SESSION, session)
	if s.is_empty():
		return err("not_found", "сессии нет")
	if s["data"].get("state") == "closed" and s["data"].get("outcome") == "aborted":
		return ok({"session": s.duplicate(true)})
	if s["data"].get("state") != "pending":
		return err("session_state", "отменить можно только pending", s.duplicate(true))
	var d: Dictionary = (s["data"] as Dictionary).duplicate()
	d["state"] = "closed"
	d["outcome"] = "aborted"
	_return_deck_to_phone(session, d["runner"])
	return ok({"session": _put(T_SESSION, session, d).duplicate(true)})


func terminal_beat(terminal: String, battery: int = -1, fps: int = -1, link: int = -1) -> Dictionary:
	var t := doc(T_TERMINAL, terminal)
	if t.is_empty():
		return err("not_found", "терминала нет")
	beat_count[terminal] = int(beat_count.get(terminal, 0)) + 1
	last_beat[terminal] = {"battery": battery, "fps": fps, "link": link}
	var d: Dictionary = (t["data"] as Dictionary).duplicate()
	d["beat_at"] = Time.get_ticks_msec()
	if battery >= 0:
		d["battery"] = battery
	if fps >= 0:
		d["fps"] = fps
	if link >= 0:
		d["link"] = link
	return ok({"ver": _put(T_TERMINAL, terminal, d)["ver"]})


func op_take_from_node(session: String, node: String, item: String) -> Dictionary:
	return _once(take_rid(session, item), {"op": "take", "session": session, "node": node, "item": item}, func():
		var s := doc(T_SESSION, session)
		if s.is_empty():
			return err("not_found", "сессии нет")
		if s["data"].get("state") != "active":
			return err("session_state", "сессия не active", s.duplicate(true))
		var it := doc(T_ITEM, item)
		if it.is_empty():
			return err("not_found", "предмета нет")
		if it["data"].get("owner") != "node:" + node:
			return err("wrong_owner", "предмет не в узле", it.duplicate(true))
		var d: Dictionary = (it["data"] as Dictionary).duplicate()
		d["owner"] = "deck:" + session
		return ok({"item": _put(T_ITEM, item, d).duplicate(true)}))


func op_leave_in_node(session: String, node: String, item: String) -> Dictionary:
	return _once(leave_rid(session, item), {"op": "leave", "session": session, "node": node, "item": item}, func():
		var it := doc(T_ITEM, item)
		if it.is_empty():
			return err("not_found", "предмета нет")
		if it["data"].get("owner") != "deck:" + session:
			return err("wrong_owner", "предмет не в деке", it.duplicate(true))
		if it["data"].get("protected", false):
			return err("protected_item", "защищённого демона нельзя оставить")
		var d: Dictionary = (it["data"] as Dictionary).duplicate()
		d["owner"] = "node:" + node
		return ok({"item": _put(T_ITEM, item, d).duplicate(true)}))


func run_finish(session: String, outcome: String, node: String, disconnect: bool, moves: Array) -> Dictionary:
	var params := {"op": "finish", "session": session, "outcome": outcome, "node": node, "disconnect": disconnect, "moves": moves}
	return _once(finish_rid(session), params, func():
		var s := doc(T_SESSION, session)
		if s.is_empty():
			return err("not_found", "сессии нет")
		if s["data"].get("state") != "active":
			return err("session_state", "сессия не active", s.duplicate(true))
		if not (outcome in OUTCOMES) or outcome == "aborted":
			return err("bad_request", "неизвестный исход " + outcome)
		var plan := {}
		for m in moves:
			plan[str(m.get("item", ""))] = str(m.get("to", ""))
		var deck: Array = []
		for id in _docs[T_ITEM]:
			if _docs[T_ITEM][id]["data"].get("owner") == "deck:" + session:
				deck.append(id)
		var runner := str(s["data"].get("runner", ""))
		var transfers: Array = []
		for id in deck:
			var it: Dictionary = _docs[T_ITEM][id]
			var to: String = "phone" if it["data"].get("protected", false) else str(plan.get(id, ""))
			if not (to in ["phone", "node", "burned"]):
				return err("bad_request", "предмет %s не упомянут в moves" % id)
			var d: Dictionary = (it["data"] as Dictionary).duplicate()
			d["owner"] = {"phone": "outbox:" + runner, "node": "node:" + node, "burned": "burned:" + session}[to]
			_put(T_ITEM, id, d)
			if to == "phone":
				transfers.append({"item": id, "transfer": "tr_fake_" + id.right(6)})
		var sd: Dictionary = (s["data"] as Dictionary).duplicate()
		sd["state"] = "closed"
		sd["outcome"] = outcome
		sd["disconnect"] = disconnect
		return ok({"session": _put(T_SESSION, session, sd).duplicate(true), "transfers": transfers, "eddies_transfer": null}))


## Как put Моста: ver 0 — создать, иначе версия должна совпасть; eddies узла и всё, кроме data.world сессии, не меняются.
func put_doc(type: String, id: String, ver: int, data: Dictionary) -> Dictionary:
	var d := doc(type, id)
	if ver == 0:
		if not d.is_empty():
			return err("exists", "документ уже есть", d.duplicate(true))
		if not _docs.has(type):
			_docs[type] = {}
		_docs[type][id] = {"type": type, "id": id, "ver": 0, "data": {}}
	elif d.is_empty():
		return err("not_found", "документа нет")
	elif int(d["ver"]) != ver:
		return err("version_conflict", "версия %d, а не %d" % [int(d["ver"]), ver], d.duplicate(true))
	if type == T_NODE and not d.is_empty() and d["data"].get("eddies") != data.get("eddies"):
		return err("value_field", "eddies меняет только операция")
	if type == T_SESSION:
		var a: Dictionary = (d["data"] as Dictionary).duplicate()
		var b := data.duplicate()
		a.erase("world")
		b.erase("world")
		if a != b:
			return err("value_field", "в сессии пишется только data.world")
	return ok({"doc": _put(type, id, ints_of(data.duplicate(true))).duplicate(true)})


func get_doc(type: String, id: String) -> Dictionary:
	var d := doc(type, id)
	if d.is_empty():
		return err("not_found", "документа нет")
	return ok({"doc": d.duplicate(true)})


func list_docs(type: String) -> Dictionary:
	var out: Array = []
	for id in _docs.get(type, {}):
		out.append(_docs[type][id].duplicate(true))
	return ok({"seq": _seq, "docs": out})


func subscribe(types: Array) -> Dictionary:
	var out: Array = []
	for t in types:
		_subs[str(t)] = true
		out.append_array(list_docs(str(t))["docs"])
	return ok({"seq": _seq, "docs": out})


func _return_deck_to_phone(session: String, runner: String) -> void:
	for id in _docs[T_ITEM]:
		var it: Dictionary = _docs[T_ITEM][id]
		if it["data"].get("owner") == "deck:" + session:
			var d: Dictionary = (it["data"] as Dictionary).duplicate()
			d["owner"] = "outbox:" + runner
			_put(T_ITEM, id, d)
