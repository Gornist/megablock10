class_name GraphWorld
extends Node
## Граф узлов Сети (W1): по GrayNode на узел из data/graph.json, одна сеть и один Мост на всех.
## Вход: узел зависит от терминала (graph.entries). Переход: игрок постоял у портала → сессия уходит в «тоннель» (узел
## NetServer.TUNNEL_NODE: снимков и ICE нет, trace стоит), клиент показывает тоннель, через tunnel_sec сессия приходит в новый
## узел — с тем же trace, декой и перезарядками (те же объекты DaemonSession). Закрытый (локдаун) узел не принимает,
## пока идёт охота Black ICE — портал не открывается. Выход и вынос добычи — как в одиночном узле (GrayNode).

signal transit_started(session: String, from: String, to: String)
signal transit_finished(session: String, from: String, to: String)
signal transit_denied(session: String, to: String, reason: String)

var net: NetServer
var bridge: BridgeApi
var graph: NodeGraph
var clock := GraphClock.new()
var nodes: Dictionary = {}                 # id узла -> GrayNode
## Один набор демонов на все узлы: демон из деки (id предмета) должен работать и после перехода.
var daemons := DaemonService.new()
var ice_settings: Dictionary = {}
var trace_settings: Dictionary = {}
var black_ice_settings: Dictionary = {}

var _takes: Dictionary = {}                # сессия -> число незавершённых take (общий для узлов)
var _where: Dictionary = {}                # сессия -> узел, где игрок был, когда закончится выход
var _transits: Dictionary = {}             # сессия -> {from, to, due} (due — по общим часам)
var _object_node: Dictionary = {}          # id слота шарда -> узел


func start(server: NetServer, bridge_api: BridgeApi, node_graph: NodeGraph) -> void:
	net = server
	bridge = bridge_api
	graph = node_graph
	net.remove_object(NetConfig.PICKUP_ID)  # одиночный шард прототипа: в графе шарды у каждого узла свои
	net.entry_node_for = _entry_node
	net.grab_check = _can_grab
	net.teleport_snap = func(session: String, to: Vector3) -> Dictionary:
		var gn: GrayNode = nodes.get(net.node_of(session))
		return gn.snap_teleport(to) if gn != null else {"p": to, "look": null}
	net.join_check = func(session: String) -> bool: return not join_blocked(session)
	net.session_joined.connect(_on_joined)
	net.exit_event.connect(_on_exit)
	for id in graph.nodes:
		var gn := GrayNode.new()
		gn.name = str(id)
		gn.manage_net_hooks = false
		gn.manage_sync = false
		gn.shared_clock = clock
		gn.daemons = daemons
		gn.ice_settings = ice_settings
		gn.trace_settings = trace_settings
		gn.black_ice_settings = black_ice_settings
		gn.share_takes_inflight(_takes)
		gn.apply_def(id, graph.nodes[id], graph.settings, graph)
		add_child(gn)
		nodes[id] = gn
		gn.start(net, bridge)
		gn.portal_requested.connect(_on_portal_requested.bind(id))
		for slot in gn.slot_ids():
			_object_node[slot] = id
	_sync_all()
	print("[graph] узлов ", nodes.size(), ", входов по терминалам ", graph.entries.size(), ", по умолчанию ", graph.default_entry)


## Один снимок Моста на весь граф: подписка на типы, затем каждый узел берёт из него своё (сессии, шарды, локдаун).
func _sync_all() -> void:
	if bridge == null:
		return
	while not bridge.is_ready():
		await get_tree().create_timer(0.1).timeout
		if not is_inside_tree():
			return
	@warning_ignore("redundant_await")
	var snap: Dictionary = await bridge.subscribe(GrayNode.SYNC_TYPES)
	if not is_inside_tree():
		return
	if not snap.get("ok", false):
		push_warning("[graph] подписка на Мост не удалась: %s" % BridgeApi.err_code(snap))
		return
	for gn in nodes.values():
		(gn as GrayNode).apply_snapshot(snap.get("docs", []))


func _physics_process(delta: float) -> void:
	clock.now += delta  # родитель шагает раньше детей: узлы в этом тике видят уже новое время
	_finish_due_transits()


func node_of(id: String) -> GrayNode:
	return nodes.get(id)


## Где игрок для графа: узел, откуда он ушёл в тоннель, пока тоннель идёт.
func where(session: String) -> String:
	if _transits.has(session):
		return str(_transits[session]["from"])
	return str(_where.get(session, net.node_of(session)))


func in_tunnel(session: String) -> bool:
	return _transits.has(session)


func join_blocked(session: String) -> bool:
	for gn in nodes.values():
		if (gn as GrayNode).join_blocked(session):
			return true
	return false


## Узел входа: Мост поставил сессии учебный узел (первый вход новичка) — идём туда, иначе узел по терминалу (graph.entries).
func _entry_node(terminal: String, session: String) -> String:
	var hint := str(net.session_node_hint.get(session, ""))
	var id := hint if graph.is_tutorial(hint) else graph.entry_for(terminal)
	_where[session] = id
	return id


func _can_grab(session: String, object_id: String) -> bool:
	var gn: GrayNode = nodes.get(_object_node.get(object_id, ""))
	return gn != null and gn.can_grab(session, object_id)


## Игрок вошёл (или вернулся после обрыва): рассказываем ему узел, где он стоит.
func _on_joined(session: String, _peer: int, _resumed: bool) -> void:
	if _transits.has(session):
		return  # тоннель идёт: узел ему расскажет конец перехода
	var id := net.node_of(session)
	_where[session] = id
	if nodes.has(id):
		_send_node(session, id, false)


## Описание узла для клиента (WorldMsg.EV_NODE): шарды, порталы, тревога. arrive — куда поставить риг после перехода.
func node_event(id: String, arrive: Variant = null, session: String = "") -> Dictionary:
	var gn: GrayNode = nodes[id]
	var portals: Array = []
	for pt in gn.portals():
		var pos: Vector3 = pt["pos"]
		portals.append({"to": pt["to"], "title": pt["title"], "tier": pt["tier"], "p": [pos.x, pos.z], "open": not (nodes[pt["to"]] as GrayNode).is_locked_down()})
	var ev := {
		"kind": WorldMsg.EV_NODE, "node": id, "title": graph.title_of(id), "tier": graph.tier_of(id),
		"alert": snappedf(gn.alert, 0.01), "shards": gn.shard_view(session), "portals": portals, "r": float(graph.settings["portal_radius"]),
	}
	var signs: Array = graph.nodes[id].get("signs", [])
	if not signs.is_empty():
		ev["signs"] = signs  # таблички учебного узла: [{p: [x, z], text}], клиент рисует их в мире
	if arrive is Vector3:
		ev["arrive"] = [arrive.x, arrive.z]
	return ev


func _send_node(session: String, id: String, with_arrive: bool, arrive: Vector3 = NodeLayout.SPAWN) -> void:
	net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, node_event(id, arrive if with_arrive else null, session)))


# ---------------------------------------------------------------- переходы

## Можно ли игроку пройти в узел to. "" — можно; иначе причина: unknown | busy | not_linked | hunt | lockdown.
func transit_check(session: String, to: String) -> String:
	if _transits.has(session):
		return "busy"
	var from := where(session)
	if not nodes.has(from) or not nodes.has(to):
		return "unknown"
	if not graph.is_linked(from, to):
		return "not_linked"
	if (nodes[from] as GrayNode).is_hunted(session):
		return "hunt"  # из охоты Black ICE уходят аварийным отключением, а не порталом
	if (nodes[to] as GrayNode).is_locked_down():
		return "lockdown"
	return ""


func _on_portal_requested(session: String, to: String, from: String) -> void:
	if where(session) != from:
		return
	var reason := transit_check(session, to)
	if reason != "":
		var left := (nodes[to] as GrayNode).lockdown_left_sec() if nodes.has(to) else 0.0
		net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, {"kind": WorldMsg.EV_PORTAL_DENIED, "to": to, "reason": reason, "left": ceili(left)}))
		transit_denied.emit(session, to, reason)
		return
	start_transit(session, from, to)


## Сессия уходит в тоннель; через tunnel_sec она в узле to. Проверки — transit_check.
func start_transit(session: String, from: String, to: String) -> void:
	var sec := float(graph.settings["tunnel_sec"])
	_transits[session] = {"from": from, "to": to, "due": clock.now + sec}
	net.set_node(session, NetServer.TUNNEL_NODE)
	net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, {"kind": WorldMsg.EV_TUNNEL, "from": from, "to": to, "title": graph.title_of(to), "tier": graph.tier_of(to), "sec": sec}))
	print("[graph] ", session, ": ", from, " -> ", to, " (тоннель ", sec, " с)")
	transit_started.emit(session, from, to)


func _finish_due_transits() -> void:
	if _transits.is_empty():
		return
	for session in _transits.keys():
		if clock.now >= float(_transits[session]["due"]):
			_complete_transit(session)


func _complete_transit(session: String) -> void:
	var t: Dictionary = _transits[session]
	_transits.erase(session)
	var from: String = t["from"]
	var to: String = t["to"]
	if not net.has_avatar(session):
		return
	var back := (nodes[to] as GrayNode).is_locked_down()  # узел закрыли, пока шёл тоннель: возвращаем откуда пришёл
	var dest := from if back else to
	var ds := (nodes[from] as GrayNode).release_session(session)
	if ds == null:
		return
	var arrive := NodeLayout.SPAWN if back else NodeLayout.arrival_for_slot(graph.slot_to(to, from))
	net.teleport(session, arrive)
	net.set_node(session, dest)
	_where[session] = dest
	(nodes[dest] as GrayNode).adopt_session(session, ds)
	if back:
		net.send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, {"kind": WorldMsg.EV_PORTAL_DENIED, "to": to, "reason": "lockdown", "left": ceili((nodes[to] as GrayNode).lockdown_left_sec())}))
	_send_node(session, dest, true, arrive)
	transit_finished.emit(session, from, dest)


## Забег закончился: слоты с взятыми игроком шардами пустеют по правилам (GrayNode.settle_shards), переход отменяется.
func _on_exit(ev: Dictionary) -> void:
	var session: String = ev["session"]
	var end := where(session)
	_transits.erase(session)
	_where.erase(session)
	var loot: String = GrayNode.outcome_plan(ev)["loot"]
	for gn in nodes.values():
		(gn as GrayNode).settle_shards(session, end, loot)
