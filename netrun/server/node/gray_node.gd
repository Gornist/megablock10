class_name GrayNode
extends Node
## Серый узел node_07 (N7): собирает N1–N6 в одну играбельную сцену на сервере.
## На сессию — TraceMeter и DaemonSession; ICE шагает 10 раз/с (IceNode), видимость учитывает GHOST;
## игрокам раз в 0.1 с уходит снимок (trace, ICE, перезарядки), события — отдельными сообщениями.
## Добыча: взяли шард — op.take_from_node (в деку); выход — одна операция run.finish: при чистом выходе добыча на телефон,
## при выбросе/флэтлайне/обрыве остаётся в узле (и физически лежит на постаменте). Без Моста ценности не трогаем.

## Что произошло в узле: {kind: ice_eject|flatline|exit|shard_taken|daemon|level, session, ...}. Для журнала и тестов.
signal event(ev: Dictionary)

const STATE_INTERVAL := 0.1
const NODE_ID := "node_07"

var net: NetServer
var bridge: BridgeApi
var daemons := DaemonService.new()
## Настройки ICE и trace (подбираются на этапе 2); пусто — значения по умолчанию.
var ice_settings: Dictionary = {}
var trace_settings: Dictionary = {}

var _now := 0.0
var _state_acc := 0.0
var _ices: Array[IceNode] = []
var _sessions: Dictionary = {}       # сессия -> DaemonSession (в нём trace)
var _shard_items: Dictionary = {}    # id объекта -> id предмета в Мосте
var _takes_inflight: Dictionary = {} # сессия -> число незавершённых op.take_from_node
var _ready_done := false


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
	_bind_shard()
	set_physics_process(true)
	_ready_done = true


func now() -> float:
	return _now


func session_state(session: String) -> DaemonSession:
	return _sessions.get(session)


func ices() -> Array[IceNode]:
	return _ices


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


## Какой предмет Моста лежит на постаменте: первый шард узла. Нет Моста или предмета — шард только игровой.
func _bind_shard() -> void:
	if bridge == null or not bridge.is_ready():
		return
	@warning_ignore("redundant_await")
	var r: Dictionary = await bridge.list_docs(BridgeApi.T_ITEM)
	for d in r.get("docs", []):
		var data: Dictionary = d.get("data", {})
		if data.get("kind") == "SHARD" and data.get("owner") == "node:" + NODE_ID:
			_shard_items[NetConfig.PICKUP_ID] = str(d["id"])
			return
	push_warning("[gray-node] в Мосте нет шарда в узле %s: добыча останется только игровой" % NODE_ID)


func _physics_process(delta: float) -> void:
	_now += delta
	var targets := {}
	var meters := {}
	for session in _sessions:
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
	if _state_acc >= STATE_INTERVAL:
		_state_acc = 0.0
		_tick_traces()
		_broadcast_state()


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
	for session in _sessions:
		var ds: DaemonSession = _sessions[session]
		var cd: Array = []
		for id in ds.deck:
			cd.append({"id": id, "name": NodeLayout.DAEMON_NAMES.get(id, id), "left": ds.cooldown_left(id, _now)})
		var msg := WorldMsg.encode_fields(WorldMsg.STATE, {
			"trace": ds.trace.value(),
			"level": ds.trace.level(),
			"ghost": ds.is_ghost(_now),
			"ice": ice_list,
			"cd": cd,
		})
		net.send_to(session, msg, false)


func _on_joined(session: String, _peer: int, _resumed: bool) -> void:
	if _sessions.has(session):
		return
	var meter := TraceMeter.new(trace_settings)
	meter.reset(_now)
	meter.level_changed.connect(_on_level_changed.bind(session))
	_sessions[session] = DaemonSession.new(NodeLayout.DEFAULT_DECK, meter)
	print("[gray-node] ", session, " вошёл в ", NODE_ID)


func _on_avatar_removed(session: String) -> void:
	_sessions.erase(session)
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
	@warning_ignore("redundant_await")
	var r: Dictionary = await bridge.op_take_from_node(session, NODE_ID, item)
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


func _finish_in_bridge(ev: Dictionary) -> void:
	if bridge == null or not bridge.is_ready():
		return
	var session: String = ev["session"]
	while int(_takes_inflight.get(session, 0)) > 0:
		await get_tree().process_frame
	var plan := outcome_plan(ev)
	@warning_ignore("redundant_await")
	var listed: Dictionary = await bridge.list_docs(BridgeApi.T_ITEM)
	var moves: Array = []
	for d in listed.get("docs", []):
		var data: Dictionary = d.get("data", {})
		if data.get("owner") != "deck:" + session or data.get("protected", false):
			continue
		var is_loot := str(data.get("origin", "")).begins_with("node:")
		moves.append({"item": str(d["id"]), "to": plan["loot"] if is_loot else plan["daemon"]})
	@warning_ignore("redundant_await")
	var r: Dictionary = await bridge.run_finish(session, plan["outcome"], NODE_ID, plan["disconnect"], moves)
	print("[gray-node] run.finish ", session, " ", plan["outcome"], ": ", "ok" if r.get("ok", false) else BridgeApi.err_code(r))
	event.emit({"kind": "finished", "session": session, "outcome": plan["outcome"], "ok": r.get("ok", false)})
