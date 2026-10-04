class_name GiveService
extends Node
## Отправка добычи другому игроку во время забега (К5б; docs/netrun-deck-design.md §9.2, контракт Моста — docs/netrun-bridge-protocol.md, 6.7).
## Клиент просит `give {item, to}` — отдать шард или демона из ГРУЗа нетраннеру в Сети (`to.runner` — короткий id аватара из списка получателей)
## или контакту телефона (`to.phone` — ключ). Сервер мира проверяет то, что видит сам (предмет в ГРУЗе сессии и его можно отдать, получатель
## в Сети и не в исходе, ключ похож на ключ, не свой), а ценность двигает Мост одной операцией `op.give_item`: он же последний судья
## (защищённый и рабочие демоны, версия предмета, состояние сессий). Эдди не отдаются.
##
## Повтор безопасен: rid = give:<сессия>:<предмет>:<версия> (BridgeApi.give_rid); после обрыва без ответа предмет перечитывается, и если он уже у
## получателя, отдача считается состоявшейся. Исход забега отправителя и получателя ждёт отдачу в полёте (GrayNode.begin_inflight, как take).

signal given(session: String, item: String, to: Dictionary)

## Столько раз повторяем запрос при обрыве связи с Мостом (пауза RETRY_SEC) и при устаревшей версии предмета.
const NET_ATTEMPTS := 5
const RETRY_SEC := 0.6
const VERSION_ATTEMPTS := 3
## Ключ телефона — обычный base64 SPKI (около 124 символов); границы нужны, чтобы мусор не уходил в Мост.
const KEY_MIN := 16
const KEY_MAX := 200

var net: NetServer
var bridge: BridgeApi
## Callable(session: String) -> GrayNode, где сейчас сессия (в тоннеле — узел, откуда ушла); null — такой сессии в узлах нет.
var node_of: Callable
## Callable() -> Array, все узлы мира (слоты шардов, отданных другому, пересчитывает каждый).
var all_nodes: Callable

## Пауза между повторами при обрыве связи с Мостом, с (тест ставит поменьше).
var retry_sec := RETRY_SEC
var _busy_items: Dictionary = {}   # id предмета, который отдаётся прямо сейчас


func start(server: NetServer, bridge_api: BridgeApi, node_lookup: Callable, nodes_lookup: Callable) -> void:
	net = server
	bridge = bridge_api
	node_of = node_lookup
	all_nodes = nodes_lookup
	net.give_requested.connect(_on_give)
	net.give_list_requested.connect(_on_list)


## Строка в ключе телефона допустима: base64 без пробелов, разумной длины.
static func valid_phone_key(key: String) -> bool:
	if key.length() < KEY_MIN or key.length() > KEY_MAX:
		return false
	var re := RegEx.new()
	re.compile("^[A-Za-z0-9+/]+={0,2}$")
	return re.search(key) != null


## Получатель из сообщения клиента: {runner: int} или {phone: String} (ровно одно). Пустой словарь — не разобралось.
static func parse_target(to: Dictionary) -> Dictionary:
	var has_runner := to.has("runner") and (to["runner"] is int or to["runner"] is float)
	var has_phone := to.has("phone") and to["phone"] is String
	if has_runner == has_phone:
		return {}
	if has_runner:
		return {"runner": int(to["runner"])}
	return {"phone": str(to["phone"])}


## Причина, по которой отправлять нельзя, видимая без Моста: "" — можно. loot — строка ГРУЗа {id, give, ...} или пустой словарь.
static func check_row(row: Dictionary) -> String:
	if row.is_empty() or not bool(row.get("give", false)):
		return WorldMsg.GIVE_NOT_LOOT
	return ""


# ---------------------------------------------------------------- список получателей

func _on_list(session: String) -> void:
	var gn: GrayNode = node_of.call(session)
	if gn == null:
		return
	var names := await _callsigns()
	var runners: Array = []
	var my_node := net.node_of(session)
	for s in net.sessions():
		if s == session or net.peer_of(s) == -1:
			continue
		var other: GrayNode = node_of.call(s)
		if other == null or not other.can_exchange(s):
			continue
		runners.append({"id": net.avatar_id(s), "name": str(names.get(s, s)), "same": net.node_of(s) == my_node})
	runners.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["same"] != b["same"]:
			return a["same"]
		return str(a["name"]) < str(b["name"]))
	net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, {"kind": WorldMsg.EV_GIVE_LIST, "runners": runners}))


## session -> позывной по документам сессий Моста (нет — пустой словарь, список покажет id).
func _callsigns() -> Dictionary:
	var out := {}
	if bridge == null:
		return out
	@warning_ignore("redundant_await")
	var r: Dictionary = await bridge.list_docs(BridgeApi.T_SESSION)
	for d in r.get("docs", []):
		out[str(d["id"])] = str((d.get("data", {}) as Dictionary).get("callsign", ""))
	return out


# ---------------------------------------------------------------- отдача

func _on_give(session: String, item: String, to: Dictionary) -> void:
	var res := await give(session, item, to)
	if res.get("ok", false):
		given.emit(session, item, to)


## Весь путь отдачи; возвращает {ok, error?, title?, ...}. События игрокам отправляет сама. Публичный — для тестов.
func give(session: String, item: String, to_raw: Dictionary) -> Dictionary:
	var row := {}
	var gn: GrayNode = node_of.call(session)
	var target := parse_target(to_raw)
	var fail := ""
	var ds: DaemonSession = gn.session_state(session) if gn != null else null
	if bridge == null or not bridge.is_ready():
		fail = WorldMsg.GIVE_NO_BRIDGE
	elif gn == null or ds == null or not gn.can_exchange(session) or _busy_items.has(item):
		fail = WorldMsg.GIVE_BUSY
	elif target.is_empty():
		fail = WorldMsg.GIVE_NO_RECIPIENT
	else:
		for l in ds.loot_view:
			if str(l.get("id", "")) == item:
				row = l
		fail = check_row(row)
	var recipient := ""
	var rn: GrayNode = null
	if fail == "":
		if target.has("runner"):
			recipient = net.session_of_avatar(int(target["runner"]))
			rn = node_of.call(recipient) if recipient != "" else null
			if recipient == session:
				fail = WorldMsg.GIVE_SELF
			elif rn == null or not rn.can_exchange(recipient):
				fail = WorldMsg.GIVE_NO_RECIPIENT
		elif not valid_phone_key(str(target["phone"])):
			fail = WorldMsg.GIVE_BAD_CONTACT
	if fail != "":
		return _reject(session, item, row, fail)
	# С этого места до конца — один запрос в Мост: исход забега обеих сторон ждёт его.
	_busy_items[item] = true
	gn.begin_inflight(session)
	if rn != null:
		rn.begin_inflight(recipient)
	var via: String = WorldMsg.VIA_RUNNER if target.has("runner") else WorldMsg.VIA_PHONE
	var r := await _ask_bridge(session, item, recipient, str(target.get("phone", "")))
	var names := {}
	if r.get("ok", false):
		for n in all_nodes.call():
			(n as GrayNode).note_given(item)
		await gn.refresh_deck(session)
		if rn != null:
			await rn.refresh_deck(recipient)
			names = await _callsigns()
	gn.end_inflight(session)
	if rn != null:
		rn.end_inflight(recipient)
	_busy_items.erase(item)
	if not r.get("ok", false):
		return _reject(session, item, row, str(r.get("error", WorldMsg.GIVE_REFUSED)))
	var out := {"kind": WorldMsg.EV_GIVE, "dir": WorldMsg.GIVE_OUT, "ok": true, "item": item, "title": str(row.get("title", "")), "via": via}
	if rn != null:
		out["who"] = str(names.get(recipient, recipient))
		net.send_to(recipient, WorldMsg.encode_fields(WorldMsg.EVENT, {"kind": WorldMsg.EV_GIVE, "dir": WorldMsg.GIVE_IN, "ok": true, "item": item,
			"title": str(row.get("title", "")), "tier": int(row.get("tier", 1)), "item_kind": str(row.get("kind", "shard")),
			"from": str(names.get(session, session)), "via": via}))
	net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, out))
	print("[give] ", session, " -> ", recipient if rn != null else "телефон", ": ", item)
	return {"ok": true, "title": out["title"], "via": via}


func _reject(session: String, item: String, row: Dictionary, error: String) -> Dictionary:
	net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, {"kind": WorldMsg.EV_GIVE, "dir": WorldMsg.GIVE_OUT, "ok": false, "item": item,
		"title": str(row.get("title", "")), "error": error}))
	print("[give] ", session, " отказ ", item, ": ", error)
	return {"ok": false, "error": error}


## Запрос в Мост с перечитыванием предмета: версия берётся свежей, устаревшая (version_conflict) — новый круг; обрыв — повтор того же запроса.
## {ok} либо {ok: false, error: причина для клиента}.
func _ask_bridge(session: String, item: String, recipient: String, phone: String) -> Dictionary:
	if phone != "":
		@warning_ignore("redundant_await")
		var sr: Dictionary = await bridge.get_doc(BridgeApi.T_SESSION, session)
		if sr.get("ok", false) and str(((sr["doc"] as Dictionary).get("data", {}) as Dictionary).get("runner", "")) == phone:
			return {"ok": false, "error": WorldMsg.GIVE_SELF}   # груз на свой же телефон отдавать нельзя (контракт Моста — bad_request)
	for round_no in VERSION_ATTEMPTS:
		var doc := await _read_item(item)
		if not doc.get("ok", false):
			return {"ok": false, "error": WorldMsg.GIVE_UNAVAILABLE}
		var data: Dictionary = (doc["doc"] as Dictionary).get("data", {})
		if _already_there(str(data.get("owner", "")), recipient, phone):
			return {"ok": true}   # прошлая попытка дошла до Моста, а ответ потерялся
		if str(data.get("owner", "")) != "deck:" + session:
			return {"ok": false, "error": WorldMsg.GIVE_GONE}
		var ver := int((doc["doc"] as Dictionary).get("ver", 0))
		var resp: Dictionary = {}
		for attempt in NET_ATTEMPTS:
			@warning_ignore("redundant_await")
			resp = await bridge.op_give_item(session, item, ver, recipient, phone)
			if not GrayNode.is_transient(resp) or not is_inside_tree():
				break
			await get_tree().create_timer(retry_sec).timeout
		if resp.get("ok", false):
			return {"ok": true}
		var code := BridgeApi.err_code(resp)
		if code == "version_conflict":
			continue
		if GrayNode.is_transient(resp):
			# ответа нет: возможно, запись прошла — перечитаем предмет в следующем круге по owner, а не будем гадать
			var again := await _read_item(item)
			if again.get("ok", false) and _already_there(str(((again["doc"] as Dictionary).get("data", {}) as Dictionary).get("owner", "")), recipient, phone):
				return {"ok": true}
			return {"ok": false, "error": WorldMsg.GIVE_UNAVAILABLE}
		return {"ok": false, "error": error_for(code)}
	return {"ok": false, "error": WorldMsg.GIVE_GONE}


## Предмет уже у получателя: в деке его сессии либо в outbox/на телефоне контакта.
static func _already_there(owner: String, recipient: String, phone: String) -> bool:
	if recipient != "":
		return owner == "deck:" + recipient
	return owner == "outbox:" + phone or owner == "phone:" + phone


func _read_item(item: String) -> Dictionary:
	for attempt in NET_ATTEMPTS:
		@warning_ignore("redundant_await")
		var r: Dictionary = await bridge.get_doc(BridgeApi.T_ITEM, item)
		if r.get("ok", false) or not GrayNode.is_transient(r) or not is_inside_tree():
			return r
		await get_tree().create_timer(retry_sec).timeout
	return BridgeApi.err("unavailable")


## Код ответа Моста -> причина для игрока.
static func error_for(code: String) -> String:
	match code:
		"wrong_owner":
			return WorldMsg.GIVE_GONE
		"protected_item", "loaded_item":
			return WorldMsg.GIVE_NOT_LOOT
		"session_state":
			return WorldMsg.GIVE_BUSY
		"not_found":
			return WorldMsg.GIVE_NO_RECIPIENT
		"bad_request":
			return WorldMsg.GIVE_BAD_CONTACT
	return WorldMsg.GIVE_REFUSED
