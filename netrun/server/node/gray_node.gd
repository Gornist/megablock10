class_name GrayNode
extends Node
## Серый узел node_07 (N7): собирает N1–N6 в одну играбельную сцену на сервере.
## На сессию — TraceMeter и DaemonSession; ICE шагает 10 раз/с (IceNode), видимость учитывает GHOST;
## игрокам раз в 0.1 с уходит снимок (trace, ICE, перезарядки), события — отдельными сообщениями.
## Добыча: взяли шард — op.take_from_node (в деку); выход — одна операция run.finish: при чистом выходе добыча на телефон,
## при выбросе/флэтлайне/обрыве остаётся в узле (и физически лежит на постаменте). Без Моста ценности не трогаем.
## Сервер мира одноразовый (M5): всё, что должно пережить рестарт, лежит в Мосте. При старте узел подписывается на
## session/deck/node/item, берёт снимок и продолжает: активные сессии ждут возврата игрока, шард на месте или у держателя,
## локдаун узла запомнен. Своё состояние узел пишет в node.data.world, связь игрока — в session.data.world.

## Что произошло в узле: {kind: ice_eject|flatline|exit|shard_taken|daemon|level, session, ...}. Для журнала и тестов.
signal event(ev: Dictionary)

const STATE_INTERVAL := 0.1
## Позиции других аватаров — вдвое чаще (docs/netrun.md: ~20 раз/с).
const AVATAR_INTERVAL := 0.05
## Допуск на дробное число физических тиков в интервале (60 Гц: 0.1 с — 6 тиков с погрешностью).
const TICK_EPS := 0.001
const NODE_ID := "node_07"
## Исход забега не теряем, если Мост недоступен: повтор с тем же rid (finish:<сессия>) раз в FINISH_RETRY_SEC.
const FINISH_ATTEMPTS := 60
const FINISH_RETRY_SEC := 2.0
## Типы документов, на которые узел подписывается в Мосте.
const SYNC_TYPES: Array = ["session", "deck", "node", "item"]

var net: NetServer
## Узел, которому служит этот GrayNode: снимки и аватары получают только сессии, чей узел (NetServer.node_of) — он.
var node_id: String = NODE_ID
var bridge: BridgeApi
var daemons := DaemonService.new()
## Настройки ICE и trace (подбираются на этапе 2); пусто — значения по умолчанию.
var ice_settings: Dictionary = {}
var trace_settings: Dictionary = {}

var _now := 0.0
var _state_acc := 0.0
var _avatar_acc := 0.0
var _step_count := 0
var _step_us_total := 0
var _step_us_max := 0
var _ices: Array[IceNode] = []
var _sessions: Dictionary = {}       # сессия -> DaemonSession (в нём trace)
var _shard_items: Dictionary = {}    # id объекта -> id предмета в Мосте
var _takes_inflight: Dictionary = {} # сессия -> число незавершённых op.take_from_node
var _ready_done := false
## Снимок Моста принят (после рестарта — активные сессии и шард восстановлены).
var synced := false
## Сессии, взятые из снимка Моста: ждали возврата игрока.
var recovered_sessions: Array[String] = []
## Конец локдауна узла (мс Unix, время Моста; 0 — нет) — из документа node.
var lockdown_until := 0
var node_writes := 0
var _node_write_busy := false
var _node_write_again := false


func start(server: NetServer, bridge_api: BridgeApi = null) -> void:
	net = server
	bridge = bridge_api
	daemons.load_dir()
	net.place_object(NetConfig.PICKUP_ID, NodeLayout.SHARD_POS)
	net.grab_check = _can_grab
	net.session_joined.connect(_on_joined)
	net.avatar_removed.connect(_on_avatar_removed)
	net.object_taken.connect(_on_object_taken)
	net.exit_event.connect(_on_exit_event)
	net.daemon_requested.connect(_on_daemon_requested)
	net.leave_requested.connect(_on_leave_requested)
	for d in NodeLayout.ICE:
		_add_ice(d["id"], d["waypoints"])
	net.session_lost.connect(_on_session_lost)
	if bridge != null:
		bridge.doc_changed.connect(_on_doc_changed)
	_sync_from_bridge()
	set_physics_process(true)
	_ready_done = true


func now() -> float:
	return _now


func session_state(session: String) -> DaemonSession:
	return _sessions.get(session)


func ices() -> Array[IceNode]:
	return _ices


## Сколько времени занимает шаг сервера узла (_physics_process целиком, мкс): {count, avg_us, max_us}.
func step_stats() -> Dictionary:
	return {"count": _step_count, "avg_us": _step_us_total / maxi(_step_count, 1), "max_us": _step_us_max}


## Сессии, которым сейчас что-то уходит: в этом узле и с аватаром.
func _live_sessions() -> Array:
	var out: Array = []
	for session in _sessions:
		if net.node_of(session) == node_id and net.has_avatar(session):
			out.append(session)
	return out


func _add_ice(id: String, waypoints: Array) -> void:
	var wps: Array[Vector3] = []
	for w in waypoints:
		wps.append(w)
	var ice := IceNode.new()
	ice.name = id
	ice.position = wps[0]
	ice.time_source = now
	ice.setup(ice_settings, wps)
	ice.ejected.connect(_on_ice_ejected)
	add_child(ice)
	_ices.append(ice)


## Снимок Моста: ждём связи, подписываемся, восстанавливаем (после рестарта сервера мира здесь же приходит прошлый забег).
func _sync_from_bridge() -> void:
	if bridge == null:
		return
	while not bridge.is_ready():
		await get_tree().create_timer(0.1).timeout
		if not is_inside_tree():
			return
	@warning_ignore("redundant_await")
	var snap: Dictionary = await bridge.subscribe(SYNC_TYPES)
	if not is_inside_tree():
		return
	if not snap.get("ok", false):
		push_warning("[gray-node] подписка на Мост не удалась: %s" % BridgeApi.err_code(snap))
		return
	recover(snap.get("docs", []))
	synced = true
	_write_node_state()


## Разбор снимка: узел (локдаун), шард, активные сессии этого узла. Публичный — для тестов.
func recover(docs: Array) -> void:
	var shard_node := ""
	var shard_held := ""
	var held_by := ""
	var active: Array[String] = []
	for d in docs:
		var data: Dictionary = d.get("data", {})
		match str(d.get("type", "")):
			BridgeApi.T_NODE:
				if d["id"] == node_id:
					lockdown_until = int(data.get("lockdown_until", 0))
			BridgeApi.T_SESSION:
				if data.get("state") == "active" and str(data.get("node", node_id)) == node_id:
					active.append(str(d["id"]))
			BridgeApi.T_ITEM:
				if data.get("kind") != "SHARD":
					continue
				var owner := str(data.get("owner", ""))
				if owner == "node:" + node_id and shard_node.is_empty():
					shard_node = str(d["id"])
				elif owner.begins_with("deck:") and str(data.get("origin", "")).begins_with("node:") and shard_held.is_empty():
					shard_held = str(d["id"])
					held_by = owner.trim_prefix("deck:")
	# Шард, который игрок уже несёт, остаётся у него: клиент второй раз его не возьмёт, выход вернёт его по moves.
	if not shard_held.is_empty() and held_by in active:
		_shard_items[NetConfig.PICKUP_ID] = shard_held
		net.restore_holder(NetConfig.PICKUP_ID, held_by)
	elif not shard_node.is_empty():
		_shard_items[NetConfig.PICKUP_ID] = shard_node
	else:
		push_warning("[gray-node] в Мосте нет шарда в узле %s: добыча останется только игровой" % node_id)
	for s in active:
		recovered_sessions.append(s)
		net.expect_session(s)
	print("[gray-node] снимок Моста: активных сессий ", active.size(), ", шард ", _shard_items.get(NetConfig.PICKUP_ID, "—"), ", локдаун до ", lockdown_until)


func _on_doc_changed(doc: Dictionary, deleted: bool) -> void:
	if deleted or doc.get("type") != BridgeApi.T_NODE or doc.get("id") != node_id:
		return
	lockdown_until = int((doc.get("data", {}) as Dictionary).get("lockdown_until", 0))


## node.data.world = {up, players}: что видит мастер. Мост — источник правды, остальные поля узла не трогаем.
func _write_node_state() -> void:
	if bridge == null or not synced:
		return
	if _node_write_busy:
		_node_write_again = true
		return
	_node_write_busy = true
	while true:
		_node_write_again = false
		var ok := await put_field(BridgeApi.T_NODE, node_id, "world", {"up": true, "players": _live_sessions().size()})
		if ok:
			node_writes += 1
		if not _node_write_again or not is_inside_tree():
			break
	_node_write_busy = false


## Чтение-правка-запись одного поля data документа с повтором при version_conflict. false — не вышло (документа нет, отказ).
func put_field(type: String, id: String, key: String, value: Variant) -> bool:
	for attempt in 3:
		@warning_ignore("redundant_await")
		var g: Dictionary = await bridge.get_doc(type, id)
		if not g.get("ok", false):
			return false
		var cur: Dictionary = g["doc"]
		var data: Dictionary = (cur.get("data", {}) as Dictionary).duplicate(true)
		data[key] = value
		@warning_ignore("redundant_await")
		var r: Dictionary = await bridge.put_doc(type, id, int(cur["ver"]), data)
		if r.get("ok", false):
			return true
		if BridgeApi.err_code(r) != "version_conflict":
			push_warning("[gray-node] put %s/%s: %s" % [type, id, BridgeApi.err_code(r)])
			return false
	return false


## Дека игрока из Моста: id демонов из payload предметов deck:<сессия>. Формат payload (ItemPayload) серверу мира пока не
## известен — берём демонов, чей id встречается в payload; не нашли ни одного — дека по умолчанию.
static func deck_from_items(items: Array, session: String, known_ids: Array) -> Array[String]:
	var out: Array[String] = []
	for d in items:
		var data: Dictionary = d.get("data", {})
		if data.get("owner") != "deck:" + session or data.get("kind") != "DAEMON":
			continue
		for id in known_ids:
			if str(data.get("payload", "")).contains(str(id)) and not out.has(str(id)):
				out.append(str(id))
	return out


func _load_deck(session: String) -> void:
	if bridge == null or not bridge.is_ready():
		return
	@warning_ignore("redundant_await")
	var r: Dictionary = await bridge.list_docs(BridgeApi.T_ITEM)
	var ds: DaemonSession = _sessions.get(session)
	if ds == null or not r.get("ok", false):
		return
	var ids := deck_from_items(r.get("docs", []), session, NodeLayout.DAEMON_NAMES.keys())
	if not ids.is_empty():
		ds.deck = ids


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_step(delta)
	var us := Time.get_ticks_usec() - t0
	_step_count += 1
	_step_us_total += us
	_step_us_max = maxi(_step_us_max, us)


func _step(delta: float) -> void:
	_now += delta
	var targets := {}
	var meters := {}
	for session in _live_sessions():
		var avatar := net.get_avatar(session)
		if avatar == null:
			continue
		var ds: DaemonSession = _sessions[session]
		meters[session] = ds.trace
		if not ds.is_ghost(_now):
			targets[session] = avatar.position
	for ice in _ices:
		ice.netrunner_count = meters.size()
		ice.targets = targets
		ice.meters = meters
	_state_acc += delta
	if _state_acc >= STATE_INTERVAL - TICK_EPS:
		_state_acc = maxf(_state_acc - STATE_INTERVAL, 0.0)
		_tick_traces()
		_broadcast_state()
	_avatar_acc += delta
	if _avatar_acc >= AVATAR_INTERVAL - TICK_EPS:
		_avatar_acc = maxf(_avatar_acc - AVATAR_INTERVAL, 0.0)
		_broadcast_avatars()


## Спад trace, пока никто из ICE не следит за игроком.
func _tick_traces() -> void:
	for session in _sessions.keys():
		var watched := false
		for ice in _ices:
			if ice.brain != null and ice.brain.target() == session:
				watched = true
		(_sessions[session] as DaemonSession).trace.tick(_now, not watched)


func _broadcast_state() -> void:
	var ice_list: Array = []
	for ice in _ices:
		var b := ice.brain
		ice_list.append({
			"id": str(ice.name),
			"p": [ice.position.x, ice.position.y, ice.position.z],
			"f": [b.facing.x, b.facing.z],
			"s": b.state(),
		})
	for session in _live_sessions():
		var ds: DaemonSession = _sessions[session]
		var cd: Array = []
		for id in ds.deck:
			cd.append({"id": id, "name": NodeLayout.DAEMON_NAMES.get(id, id), "left": ds.cooldown_left(id, _now)})
		var msg := WorldMsg.encode_fields(WorldMsg.STATE, {
			"trace": ds.trace.value(),
			"level": ds.trace.level(),
			"ghost": ds.is_ghost(_now),
			"k": snappedf(_now, 0.001),
			"ice": ice_list,
			"cd": cd,
		})
		net.send_to(session, msg, false)


## Позиции аватаров узла: каждому игроку — все остальные в его узле (себя клиент знает сам).
func _broadcast_avatars() -> void:
	var live := _live_sessions()
	var entries := {}
	for session in live:
		var p := net.get_avatar(session).position
		entries[session] = [net.avatar_id(session), snappedf(p.x, 0.01), snappedf(p.z, 0.01)]
	var k := snappedf(_now, 0.001)
	for session in live:
		var others: Array = []
		for other in live:
			if other != session:
				others.append(entries[other])
		net.send_to(session, WorldMsg.encode_fields(WorldMsg.AVATARS, {"k": k, "a": others}), false)


func _on_joined(session: String, _peer: int, _resumed: bool) -> void:
	if _sessions.has(session):
		if bridge != null and synced:
			put_field(BridgeApi.T_SESSION, session, "world", {"connected": true, "trace": 0})
		return
	var meter := TraceMeter.new(trace_settings)
	meter.reset(_now)
	meter.level_changed.connect(_on_level_changed.bind(session))
	_sessions[session] = DaemonSession.new(NodeLayout.DEFAULT_DECK, meter)
	print("[gray-node] ", session, " вошёл в ", NODE_ID)
	if bridge != null:
		_load_deck(session)
		put_field(BridgeApi.T_SESSION, session, "world", {"connected": true, "trace": 0})
		_write_node_state()


func _on_session_lost(session: String) -> void:
	if bridge != null and synced:
		put_field(BridgeApi.T_SESSION, session, "world", {"connected": false, "trace": 0})


func _on_avatar_removed(session: String) -> void:
	_sessions.erase(session)
	_write_node_state()
	for ice in _ices:
		if ice.brain != null:
			ice.brain.forget(session)


func _on_level_changed(old_level: int, new_level: int, value: float, session: String) -> void:
	event.emit({"kind": "level", "session": session, "from": old_level, "to": new_level, "value": value})
	if new_level == TraceMeter.Level.FLATLINE:
		_end(session, ExitLogic.REASON_FLATLINE, "flatline")


func _on_ice_ejected(session: String, reason: String) -> void:
	if reason == "flatline":
		_end(session, ExitLogic.REASON_FLATLINE, "flatline")
	else:
		_end(session, ExitLogic.REASON_EJECTED, "ice_eject")


func _end(session: String, exit_reason: String, kind: String) -> void:
	if not net.has_avatar(session):
		return
	event.emit({"kind": kind, "session": session})
	net.end_session(session, exit_reason)


func _on_leave_requested(session: String) -> void:
	var avatar := net.get_avatar(session)
	if avatar == null or not NodeLayout.on_exit_pad(avatar.position):
		return
	net.end_session(session, ExitLogic.REASON_CLEAN)


func _on_daemon_requested(session: String, daemon_id: String) -> void:
	var ds: DaemonSession = _sessions.get(session)
	if ds == null:
		return
	var res := daemons.apply(ds, daemon_id, {}, _now)
	var reply := {"kind": WorldMsg.EV_DAEMON, "daemon": daemon_id, "ok": bool(res.get("ok", false))}
	if not reply["ok"]:
		reply["error"] = str(res.get("error", ""))
	net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, reply))
	event.emit({"kind": "daemon", "session": session, "daemon": daemon_id, "ok": reply["ok"]})


func _can_grab(session: String, object_id: String) -> bool:
	var avatar := net.get_avatar(session)
	if avatar == null:
		return false
	return NodeLayout.flat_distance(avatar.position, net.object_position(object_id)) <= NodeLayout.GRAB_REACH


## Шард взят: игровая часть уже сделана (NetServer), в Мосте он переходит из узла в деку.
func _on_object_taken(object_id: String, session: String) -> void:
	event.emit({"kind": "shard_taken", "session": session, "id": object_id})
	var item: String = _shard_items.get(object_id, "")
	if bridge == null or item.is_empty():
		return
	_takes_inflight[session] = int(_takes_inflight.get(session, 0)) + 1
	var r: Dictionary = {}
	for attempt in FINISH_ATTEMPTS:
		@warning_ignore("redundant_await")
		r = await bridge.op_take_from_node(session, NODE_ID, item)
		if not is_transient(r) or not is_inside_tree():
			break
		await get_tree().create_timer(FINISH_RETRY_SEC).timeout
	_takes_inflight[session] = int(_takes_inflight[session]) - 1
	if not r.get("ok", false):
		push_warning("[gray-node] take %s: %s" % [item, BridgeApi.err_code(r)])


func _on_exit_event(ev: Dictionary) -> void:
	event.emit({"kind": "exit", "session": ev["session"], "reason": ev["reason"]})
	_finish_in_bridge(ev)


## Исход забега по причине выхода (раздел 6.5 протокола и таблица исходов в netrun.md).
static func outcome_plan(ev: Dictionary) -> Dictionary:
	var reason: String = ev["reason"]
	match reason:
		ExitLogic.REASON_CLEAN:
			return {"outcome": "clean", "disconnect": false, "loot": "phone", "daemon": "phone"}
		ExitLogic.REASON_EJECTED:
			return {"outcome": "soft_ice", "disconnect": false, "loot": "node", "daemon": "phone"}
		ExitLogic.REASON_FLATLINE:
			return {"outcome": "black_ice", "disconnect": false, "loot": "node", "daemon": "node"}
	var daemon := "burned" if ev.get("deck_burned", false) else "phone"
	return {"outcome": "emergency", "disconnect": reason == ExitLogic.REASON_CONNECTION_LOST, "loot": "node", "daemon": daemon}


## Ошибки связи (Мост недоступен, обрыв, таймаут): запрос повторяют с тем же rid; всё остальное — окончательный ответ.
static func is_transient(resp: Dictionary) -> bool:
	return BridgeApi.err_code(resp) in ["unavailable", "timeout", "disconnected", "internal"]


func _finish_in_bridge(ev: Dictionary) -> void:
	if bridge == null:
		return
	var session: String = ev["session"]
	while int(_takes_inflight.get(session, 0)) > 0:
		await get_tree().process_frame
	var plan := outcome_plan(ev)
	var listed: Dictionary = {}
	for attempt in FINISH_ATTEMPTS:
		@warning_ignore("redundant_await")
		listed = await bridge.list_docs(BridgeApi.T_ITEM)
		if listed.get("ok", false) or not is_transient(listed) or not is_inside_tree():
			break
		await get_tree().create_timer(FINISH_RETRY_SEC).timeout
	var moves: Array = []
	for d in listed.get("docs", []):
		var data: Dictionary = d.get("data", {})
		if data.get("owner") != "deck:" + session or data.get("protected", false):
			continue
		var is_loot := str(data.get("origin", "")).begins_with("node:")
		moves.append({"item": str(d["id"]), "to": plan["loot"] if is_loot else plan["daemon"]})
	var r: Dictionary = {}
	for attempt in FINISH_ATTEMPTS:
		@warning_ignore("redundant_await")
		r = await bridge.run_finish(session, plan["outcome"], NODE_ID, plan["disconnect"], moves)
		if not is_transient(r) or not is_inside_tree():
			break
		await get_tree().create_timer(FINISH_RETRY_SEC).timeout
	print("[gray-node] run.finish ", session, " ", plan["outcome"], ": ", "ok" if r.get("ok", false) else BridgeApi.err_code(r))
	event.emit({"kind": "finished", "session": session, "outcome": plan["outcome"], "ok": r.get("ok", false)})
