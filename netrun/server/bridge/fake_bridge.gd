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
## «Ждём мастера»: ключ "<kind>:<ref>" -> "wait" | "approve" | "deny"; число вызовов master_gate по тому же ключу.
var gates: Dictionary = {}
var gate_calls: Dictionary = {}
## Тест: связь с Мостом «пропала» — master_gate отвечает unavailable. finish_calls — сколько раз run_finish реально выполнился.
var gate_offline := false
var finish_calls := 0
var finish_attempts: Array = []  # [{session, outcome}] — все вызовы, в том числе повторы и отказы
## Тест: связь на запись «пропала» — put_doc отвечает unavailable. put_log — все вызовы put_doc (и отказы): [{type, id, ok, data}].
var put_offline := false
var put_log: Array = []


## run.breach (раздел 6.6): сколько раз запрос реально выполнился (повтор по rid не считается) и журнал итогов [{session, n, outcome}].
var breach_calls := 0
var breach_log: Array = []
## Числа фейка вместо `ContainerEddies`/`MockBreach` из :rules (случайность там зависит от rid; здесь фиксированная середина диапазона): эдди за взлом
## по тиру, бонус MINER и остывание узла, с. Настоящие числа считает Мост.
const FAKE_BREACH_EDDIES := {"BASE": 2, "HARD": 5, "NIGHTMARE": 8}
const FAKE_MINER_BONUS := {"BASE": 15, "HARD": 30, "NIGHTMARE": 60}
const FAKE_COOLDOWN_S := 1800
const BREACH_TIERS: Array = ["BASE", "HARD", "NIGHTMARE"]
const BREACH_ACTIVE: Array = ["GHOST", "TIMESKEW", "BLACKOUT"]


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
	var sections := {"nodes": T_NODE, "terminals": T_TERMINAL, "sessions": T_SESSION, "items": T_ITEM, "settings": "settings", "runners": T_RUNNER}
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
	# Как Мост: bad_request и not_found — ошибка запроса, записи rid нет (протокол 6.5, 6.7); повтор с исправленными параметрами разрешён.
	if BridgeApi.err_code(resp) in ["bad_request", "not_found"]:
		return resp
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
		if _opened_by_other(item, session):
			return err("claimed", "хранилище открыто взломом другой сессии", it.duplicate(true))
		var d: Dictionary = (it["data"] as Dictionary).duplicate()
		d["owner"] = "deck:" + session
		return ok({"item": _put(T_ITEM, item, d).duplicate(true)}))


## Предмет есть в живом `session.opened` другой незакрытой сессии (раздел 6.2: `claimed`).
func _opened_by_other(item: String, session: String) -> bool:
	var now_ms := _now_ms()
	for id in _docs.get(T_SESSION, {}):
		var s: Dictionary = _docs[T_SESSION][id]
		if id == session or s["data"].get("state") == "closed":
			continue
		for o in s["data"].get("opened", []):
			if str(o.get("item", "")) == item and int(o.get("until", 0)) > now_ms:
				return true
	return false


static func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


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


## Как op.give_item Моста (6.7): проверки в порядке таблицы отказов, rid с версией предмета, повтор — сохранённый ответ. Рабочим считается id из
## session.loaded (нет поля — предмет с origin phone:<игрок>). Колод в фейке нет: меняется только владелец предмета. give_calls — сколько раз операция
## выполнялась по-настоящему (повторы по rid не считаются), give_attempts — все вызовы; give_offline — тест: связь «пропала» (unavailable).
var give_calls := 0
var give_attempts := 0
var give_offline := false
## Тест: после этого числа успешных отдач ответ теряется (unavailable), хотя запись выполнена — обрыв после коммита.
var give_drop_reply := false


## Тест: первый запрос отдачи «застрял» в Мосте — клиент видит обрыв (unavailable), а запись ложится через это число секунд (задержанный коммит).
## Пока она не легла, остальные запросы отдачи тоже получают unavailable; ложится при первом обращении к фейку после срока.
var give_late_commit_sec := 0.0
var _late_give: Dictionary = {}


func _apply_late_give() -> void:
	if _late_give.is_empty() or Time.get_ticks_msec() < int(_late_give["due"]):
		return
	var a: Array = _late_give["args"]
	_late_give = {}
	op_give_item(a[0], a[1], a[2], a[3], a[4])
	give_attempts -= 1


func op_give_item(session: String, item: String, ver: int, to_session: String, to_phone: String) -> Dictionary:
	_apply_late_give()
	give_attempts += 1
	if give_offline:
		return err("unavailable", "Моста нет (тест)")
	if (to_session.is_empty() == to_phone.is_empty()) or ver < 1 or to_session == session:
		return err("bad_request", "нужен ровно один получатель, ver и не сам себе")
	if not _late_give.is_empty():
		return err("unavailable", "запрос застрял (тест)")
	if give_late_commit_sec > 0.0:
		_late_give = {"due": Time.get_ticks_msec() + int(give_late_commit_sec * 1000.0), "args": [session, item, ver, to_session, to_phone]}
		give_late_commit_sec = 0.0
		return err("unavailable", "запрос застрял (тест)")
	var params := {"op": "give_item", "session": session, "item": item, "ver": ver, "to_session": to_session, "to_phone": to_phone}
	var resp := _once(give_rid(session, item, ver, to_session if not to_session.is_empty() else to_phone), params, func():
		var s := doc(T_SESSION, session)
		var it := doc(T_ITEM, item)
		var rs := doc(T_SESSION, to_session) if not to_session.is_empty() else {}
		if s.is_empty() or it.is_empty() or (not to_session.is_empty() and rs.is_empty()):
			return err("not_found", "нет сессии, предмета или получателя")
		if not to_phone.is_empty() and to_phone == str(s["data"].get("runner", "")):
			return err("bad_request", "на свой телефон отдавать нельзя")
		for x in [s, rs]:
			if not x.is_empty() and (x["data"].get("state") != "active" or not str((x["data"].get("world", {}) as Dictionary).get("finish", "")).is_empty()):
				return err("session_state", "сессия не active или в исходе", x.duplicate(true))
		if it["data"].get("owner") != "deck:" + session:
			return err("wrong_owner", "предмет не в деке", it.duplicate(true))
		if int(it["ver"]) != ver:
			return err("version_conflict", "версия %d, а не %d" % [int(it["ver"]), ver], it.duplicate(true))
		if it["data"].get("protected", false):
			return err("protected_item", "защищённого демона нельзя отдать", it.duplicate(true))
		var loaded: Variant = s["data"].get("loaded")
		var working: bool = (item in loaded) if loaded is Array else str(it["data"].get("origin", "")) == "phone:" + str(s["data"].get("runner", ""))
		if working:
			return err("loaded_item", "рабочий демон", it.duplicate(true))
		give_calls += 1
		var d: Dictionary = (it["data"] as Dictionary).duplicate()
		var to := "deck:" + to_session
		var transfer: Variant = null
		if not to_phone.is_empty():
			to = "outbox:" + to_phone
			transfer = "tr_fake_" + item.right(6)
			d["handover"] = "PENDING"
			d["out_transfer"] = transfer
		d["owner"] = to
		return ok({"item": _put(T_ITEM, item, d).duplicate(true), "to": to, "transfer": transfer}))
	if give_drop_reply and resp.get("ok", false) and not resp.get("replayed", false):
		give_drop_reply = false
		return err("unavailable", "ответ потерян (тест)")
	return resp


## Тест: вызывается один раз перед первым run_finish — «дека изменилась между чтением и вызовом» (пришёл предмет по op.give_item).
var before_finish: Callable = Callable()


func run_finish(session: String, outcome: String, node: String, disconnect: bool, moves: Array) -> Dictionary:
	if before_finish.is_valid():
		var hook := before_finish
		before_finish = Callable()
		hook.call()
	var params := {"op": "finish", "session": session, "outcome": outcome, "node": node, "disconnect": disconnect, "moves": moves}
	finish_attempts.append({"session": session, "outcome": outcome})
	return _once(finish_rid(session), params, func():
		finish_calls += 1
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


## Итог взлома по контракту 6.6: исход, эдди из запаса узла, открытие хранилищ (`session.opened`), остывание (`runner.breach_cooldown`), `session.breach`.
## Без правил :rules: эдди — по таблице выше, сигнала СБ нет (alert: null). Отказы и повтор по rid — как у Моста.
func run_breach(session: String, node: String, req: Dictionary) -> Dictionary:
	var bad := _breach_request_error(session, node, req)
	if bad != "":
		return err("bad_request", bad)
	var s := doc(T_SESSION, session)
	if s.is_empty():
		return err("not_found", "сессии нет")
	if doc(T_NODE, node).is_empty():
		return err("not_found", "узла нет")
	return _once(breach_rid(session, int(req["n"])), {"op": "breach", "session": session, "node": node, "req": req}, func():
		return _breach_once(session, node, req))


## Строка с ошибкой разбора запроса или "" (раздел 6.6, первая строка таблицы отказов); сюда же — «не рабочий демон» и «не влезает в RAM».
func _breach_request_error(session: String, node: String, req: Dictionary) -> String:
	if session.is_empty() or node.is_empty() or int(req.get("n", 0)) < 1:
		return "нет session, node или n >= 1"
	if not (str(req.get("tier", "")) in BREACH_TIERS):
		return "неизвестный tier"
	var sel: Variant = req.get("selected")
	var mat: Variant = req.get("matched")
	var act: Variant = req.get("active")
	var vaults: Variant = req.get("vaults")
	if not (sel is Array) or (sel as Array).is_empty() or not (mat is Array) or not (act is Array) or not (vaults is Array):
		return "selected/matched/active/vaults: нужны массивы, selected не пуст"
	if (sel as Array).size() != _unique(sel).size() or (mat as Array).size() != _unique(mat).size():
		return "повторы в selected или matched"
	for m in mat:
		if not (m in sel):
			return "matched не подмножество selected"
	for a in act:
		if not (a in BREACH_ACTIVE):
			return "неизвестный эффект в active"
	var open_s := int(req.get("open_s", 0))
	if open_s < 1 or open_s > 600:
		return "open_s вне 1..600"
	var s := doc(T_SESSION, session)
	if s.is_empty():
		return ""   # not_found скажет вызывающий
	var cells := 0
	var loaded: Variant = s["data"].get("loaded")
	for id in sel:
		var it := doc(T_ITEM, str(id))
		var d: Dictionary = it.get("data", {})
		var working: bool = (str(id) in loaded) if loaded is Array else str(d.get("origin", "")).begins_with("phone:")
		if it.is_empty() or d.get("owner") != "deck:" + session or d.get("kind") != "DAEMON" or not working:
			return "%s: не рабочий демон этой сессии" % id
		cells += ((d.get("daemon", {}) as Dictionary).get("cells", []) as Array).size()
	if cells > int(s["data"].get("ram", 6)):
		return "цепочки (%d) не влезают в RAM" % cells
	return ""


static func _unique(a: Array) -> Array:
	var out: Array = []
	for x in a:
		if not (x in out):
			out.append(x)
	return out


func _breach_once(session: String, node: String, req: Dictionary) -> Dictionary:
	var s := doc(T_SESSION, session)
	var sd: Dictionary = (s["data"] as Dictionary).duplicate(true)
	var n := int(req["n"])
	var world: Dictionary = sd.get("world", {}) if sd.get("world") is Dictionary else {}
	var prev: Dictionary = sd.get("breach", {}) if sd.get("breach") is Dictionary else {}
	var nd := doc(T_NODE, node)
	if sd.get("state") != "active" or world.has("finish") or n <= int(prev.get("n", 0)) or bool(nd["data"].get("tutorial", false)):
		return err("session_state", "взлом сейчас невозможен", s.duplicate(true))
	var now_ms := _now_ms()
	var runner := _runner_doc(str(sd.get("runner", "")))
	var cooldowns: Dictionary = (runner.get("data", {}) as Dictionary).get("breach_cooldown", {})
	if int(cooldowns.get(node, 0)) > now_ms:
		return err("cooldown", "узел остывает", runner.duplicate(true))
	var tier := str(req["tier"])
	var matched: Array = req["matched"]
	var outcome := "FAIL" if matched.is_empty() else ("SUCCESS" if matched.size() == (req["selected"] as Array).size() else "PARTIAL")
	var effects: Array = []
	var extract: Array = []   # [{effect, tier}] совпавших EXTRACT_* в порядке selected
	var miner := false
	for id in req["selected"]:
		if not (id in matched):
			continue
		var dd: Dictionary = (doc(T_ITEM, str(id))["data"].get("daemon", {}) as Dictionary)
		var eff := str(dd.get("effect", ""))
		if eff != "" and not (eff in effects):
			effects.append(eff)
		miner = miner or eff == "MINER"
		if eff == "EXTRACT_SHARD" or eff == "EXTRACT_DAEMON":
			extract.append({"effect": eff, "tier": int(dd.get("tier", 1))})
	for a in req["active"]:
		if not (a in effects):
			effects.append(a)
	var eddies := 0
	var opened: Array = []
	var exhausted := false
	var cooldown_until := 0
	if outcome != "FAIL":
		var stock := int(nd["data"].get("eddies", 0))
		eddies = mini(int(FAKE_BREACH_EDDIES[tier]) + (int(FAKE_MINER_BONUS[tier]) if miner else 0), stock)
		var picked: Array = []
		for e in extract:
			var found := ""
			for v in req["vaults"]:
				var it := doc(T_ITEM, str(v))
				if it.is_empty() or str(v) in picked or it["data"].get("owner") != "node:" + node or _opened_by_other(str(v), session):
					continue
				var want := "SHARD" if e["effect"] == "EXTRACT_SHARD" else "DAEMON"
				var info: Dictionary = it["data"].get("shard" if want == "SHARD" else "daemon", {})
				if it["data"].get("kind") == want and int(info.get("tier", 1)) <= int(e["tier"]):
					found = str(v)
					break
			if found == "":
				exhausted = true
			else:
				picked.append(found)
				opened.append({"item": found, "node": node, "until": now_ms + int(req["open_s"]) * 1000})
		if eddies > 0:
			var ndata: Dictionary = (nd["data"] as Dictionary).duplicate(true)
			ndata["eddies"] = stock - eddies
			_put(T_NODE, node, ndata)
		cooldown_until = now_ms + FAKE_COOLDOWN_S * 1000
		_set_cooldown(str(sd.get("runner", "")), node, cooldown_until, now_ms)
	var live: Array = []
	for o in sd.get("opened", []):
		if int(o.get("until", 0)) > now_ms:
			live.append(o)
	live.append_array(opened)
	sd["opened"] = live
	sd["loot_eddies"] = int(sd.get("loot_eddies", 0)) + eddies
	sd["breach"] = {"n": n, "node": node, "tier": tier, "outcome": outcome, "effects": effects, "eddies": eddies, "opened_n": opened.size(),
		"exhausted": exhausted, "alert": null, "at": now_ms}
	_put(T_SESSION, session, sd)
	breach_calls += 1
	breach_log.append({"session": session, "n": n, "outcome": outcome})
	var shown: Array = opened.map(func(o): return {"item": o["item"], "until": o["until"]})
	return ok({"outcome": outcome, "effects": effects, "eddies": eddies, "loot_eddies": sd["loot_eddies"], "opened": shown, "exhausted": exhausted,
		"cooldown_until": cooldown_until, "alert": null})


## Документ runner по ключу игрока (data.key); пусто, если нет.
func _runner_doc(key: String) -> Dictionary:
	for id in _docs.get(T_RUNNER, {}):
		if _docs[T_RUNNER][id]["data"].get("key") == key:
			return _docs[T_RUNNER][id]
	return {}


func _set_cooldown(key: String, node: String, until_ms: int, now_ms: int) -> void:
	var r := _runner_doc(key)
	var data: Dictionary = (r["data"] as Dictionary).duplicate(true) if not r.is_empty() else {"key": key, "callsign": "", "runs": 0, "tutorial_done": true}
	var cds: Dictionary = {}
	for k in data.get("breach_cooldown", {}):
		if int(data["breach_cooldown"][k]) > now_ms:
			cds[k] = data["breach_cooldown"][k]
	cds[node] = until_ms
	data["breach_cooldown"] = cds
	var rid := str(r.get("id", "r_" + key.sha256_text().substr(0, 32)))
	if not _docs.has(T_RUNNER):
		_docs[T_RUNNER] = {}
	if r.is_empty():
		_docs[T_RUNNER][rid] = {"type": T_RUNNER, "id": rid, "ver": 0, "data": {}}
	_put(T_RUNNER, rid, data)


## Как master.gate Моста, но без таймаутов: await_<kind> в settings/global (1 — ждём), решение — decide_gate().
func master_gate(kind: String, ref: String, _node: String, _summary: String) -> Dictionary:
	if gate_offline:
		return err("unavailable", "Мост недоступен")
	var key := "%s:%s" % [kind, ref]
	gate_calls[key] = int(gate_calls.get(key, 0)) + 1
	if int(doc("settings", "global").get("data", {}).get("await_" + kind, 0)) != 1:
		return ok({"mode": "auto", "decision": "approve", "req": null})
	if not gates.has(key):
		gates[key] = "wait"
	var st: String = gates[key]
	if st == "wait":
		return ok({"mode": "wait", "decision": null, "req": {"id": key}})
	return ok({"mode": "decided", "decision": st, "req": {"id": key}})


## Мастер решил (master.decide): approve | deny. Запроса ещё нет — решение будет ждать его.
func decide_gate(kind: String, ref: String, decision: String) -> void:
	gates["%s:%s" % [kind, ref]] = decision


## Как put Моста: ver 0 — создать, иначе версия должна совпасть; eddies узла и всё, кроме data.world сессии, не меняются.
func put_doc(type: String, id: String, ver: int, data: Dictionary) -> Dictionary:
	var r := _put_doc(type, id, ver, data)
	put_log.append({"type": type, "id": id, "ok": r.get("ok", false), "data": data.duplicate(true)})
	return r


func _put_doc(type: String, id: String, ver: int, data: Dictionary) -> Dictionary:
	if put_offline:
		return err("unavailable", "Моста нет (тест)")
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
	_apply_late_give()
	var d := doc(type, id)
	if d.is_empty():
		return err("not_found", "документа нет")
	return ok({"doc": d.duplicate(true)})


func list_docs(type: String) -> Dictionary:
	_apply_late_give()
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
