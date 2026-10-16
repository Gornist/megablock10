extends GdUnitTestSuite
## Вскрытие барьера Soft ICE (ice.md §5): сервер узла (раскладка core, NIGHTMARE) и сырой клиент в одном процессе. «charge» — мини-игра заряда (цепочка 5 кодов, сетка 5×5,
## автосолвер как у заряда), «force» — удержание 2 такта: открыт, trace +10 и тревога +10; отмена, прыжок, «далеко», «занят другой мини-игрой», уже открыт.

static var _next_port := 19500
const SESSION := "s_a"

var _root: Node
var _server: NetServer
var _world: GraphWorld
var _cfg: NetConfig


class Peer:
	extends RefCounted
	var net: NetClient
	var mirror: BreachMirror
	var ends: Array = []
	var nos: Array = []
	var starts: Array = []
	var ticks: Array = []
	var states: Array = []


func before_test() -> void:
	_root = Node.new()
	add_child(_root)
	var d := {"default_entry": "x_core", "entries": {}, "settings": {"time_mode": "tick", "vault_requires_open": false}, "nodes": {
		"x_core": {"title": "Ядро", "tier": "NIGHTMARE", "ice": 2, "shards": 1, "layout": "core", "links": []},
	}}
	var sroot := Node.new()
	sroot.name = "S"
	var croot := Node.new()
	croot.name = "C"
	_root.add_child(sroot)
	_root.add_child(croot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), sroot.get_path())
	get_tree().set_multiplayer(SceneMultiplayer.new(), croot.get_path())
	_cfg = NetConfig.new()
	_cfg.port = _next_port
	_next_port += 1
	_cfg.token = "tok_a"
	_server = NetServer.new()
	sroot.add_child(_server)
	assert_int(_server.start(_cfg, DictTokenVerifier.new({"tok_a": SESSION}))).is_equal(OK)
	_world = GraphWorld.new()
	sroot.add_child(_world)
	_world.start(_server, null, NodeGraph.from_dict(d))


func after_test() -> void:
	_server.stop_net()
	_root.queue_free()


func _wait_for(cond: Callable, sec: float = 15.0) -> bool:
	var t := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _node() -> GrayNode:
	return _world.node_of("x_core")


func _peer() -> Peer:
	var p := Peer.new()
	p.net = NetClient.new()
	_root.get_node("C").add_child(p.net)
	p.net.event_received.connect(func(ev: Dictionary):
		var kind := str(ev.get("kind", ""))
		if str(ev.get("mode", "")) != "barrier":
			return
		if kind == WorldMsg.EV_BK:
			p.starts.append(ev)
			if ev.has("grid"):
				p.mirror = BreachMirror.from_event(ev)
		elif kind == WorldMsg.EV_BK_TICK:
			p.ticks.append(ev)
			if p.mirror != null and ev.has("cell"):
				p.mirror.apply_tick(ev)
		elif kind == WorldMsg.EV_BK_END:
			if p.mirror != null:
				p.mirror.apply_end(ev)
			p.ends.append(ev)
		elif kind == WorldMsg.EV_BK_NO:
			p.nos.append(ev))
	p.net.state_received.connect(func(s: Dictionary): p.states.append(s))
	assert_int(p.net.start_client(_cfg)).is_equal(OK)
	return p


## Игрок на связи и в узле; near — поставить его у барьера (клетка (5,4) соседняя с блоком (3,2)), иначе остаётся на входе.
func _ready_peer(near: bool) -> Peer:
	var p := _peer()
	assert_bool(await _wait_for(func(): return _server.has_avatar(SESSION) and _node().session_state(SESSION) != null)).is_true()
	if near:
		_server.teleport(SESSION, NodeGrid.center(Vector2i(5, 4)))
	return p


func _request(p: Peer, how: String) -> void:
	p.nos.clear()
	p.starts.clear()
	p.net.request_barrier("bar1", how)
	await _wait_for(func(): return not p.starts.is_empty() or not p.nos.is_empty())


func _solve(p: Peer) -> void:
	var path := BreachAutoSolver.solve(p.mirror.attempt)
	for i in range(path.size()):
		if p.mirror.finished:
			return
		assert_bool(p.mirror.tap(path[i])).is_true()
		p.net.request_breach_tap(path[i])
		assert_bool(await _wait_for(func(): return p.mirror.pending == null or p.mirror.finished)).is_true()
	await _wait_for(func(): return p.mirror.finished)


func test_заряд_цепочка_5_кодов_на_сетке_5x5_и_барьер_открыт_тихо() -> void:
	var p := await _ready_peer(true)
	var alarm := _node().alarm
	await _request(p, "charge")
	assert_int(p.nos.size()).is_equal(0)
	assert_str(p.mirror.mode).is_equal("barrier")
	assert_int(p.mirror.grid.size).is_equal(5)
	assert_int((p.mirror.targets[0]["cells"] as Array).size()).is_equal(5)   # NIGHTMARE: 5 кодов
	assert_int((p.starts[0]["grid"]["traps"] as Array).size()).is_equal(0)
	await _solve(p)
	assert_bool(await _wait_for(func(): return not p.ends.is_empty())).is_true()
	assert_bool(p.ends[0]["opened"]).is_true()
	assert_str(p.ends[0]["how"]).is_equal("charge")
	assert_bool(_node().barrier_closed("bar1")).is_false()
	assert_float(_node().alarm - alarm).is_equal_approx(0.0, 0.001)   # мини-игра — тихо
	assert_bool(await _wait_for(func(): return not p.states.is_empty() and int((p.states[-1].get("br", [{}]) as Array)[0].get("open", 0)) == 1)).is_true()


func test_силой_два_такта_удержания_барьер_открыт_trace_и_тревога_плюс_10() -> void:
	var p := await _ready_peer(true)
	var ds := _node().session_state(SESSION)
	var trace := ds.trace.value()
	var alarm := _node().alarm
	await _request(p, "force")
	assert_int(p.nos.size()).is_equal(0)
	assert_int(int(p.starts[0]["ticks"])).is_equal(2)
	_node().barrier.on_node_tick()
	assert_bool(_node().barrier_closed("bar1")).is_true()   # один такт — ещё закрыт
	_node().barrier.on_node_tick()
	assert_bool(await _wait_for(func(): return not p.ends.is_empty())).is_true()
	assert_bool(p.ends[0]["opened"]).is_true()
	assert_str(p.ends[0]["how"]).is_equal("force")
	assert_bool(_node().barrier_closed("bar1")).is_false()
	assert_float(ds.trace.value() - trace).is_greater_equal(10.0)
	assert_float(_node().alarm - alarm).is_equal_approx(10.0, 0.001)


func test_отпущенный_курок_и_прыжок_бросают_силовое_вскрытие() -> void:
	var p := await _ready_peer(true)
	await _request(p, "force")
	p.net.request_breach_cancel()
	assert_bool(await _wait_for(func(): return not p.ends.is_empty())).is_true()
	assert_str(p.ends[0]["early"]).is_equal("cancel")
	assert_bool(p.ends[0]["opened"]).is_false()
	assert_bool(_node().barrier_closed("bar1")).is_true()
	await _request(p, "force")
	p.ends.clear()
	_server.teleported.emit(SESSION, NodeGrid.center(Vector2i(5, 4)), NodeGrid.center(Vector2i(5, 5)))   # прыжок
	assert_bool(await _wait_for(func(): return not p.ends.is_empty())).is_true()
	assert_str(p.ends[0]["early"]).is_equal("teleport")
	_node().barrier.on_node_tick()
	_node().barrier.on_node_tick()
	assert_bool(_node().barrier_closed("bar1")).is_true()


func test_далеко_занят_открыт_и_неизвестный_барьер_отказ() -> void:
	var p := await _ready_peer(false)
	await _request(p, "charge")
	assert_str(str(p.nos[0]["reason"])).is_equal("far")        # игрок на входе
	_server.teleport(SESSION, NodeGrid.center(Vector2i(5, 4)))
	await _request(p, "charge")
	assert_int(p.nos.size()).is_equal(0)
	await _request(p, "force")
	assert_str(str(p.nos[0]["reason"])).is_equal("active")      # уже идёт мини-игра
	p.net.request_breach_cancel()
	assert_bool(await _wait_for(func(): return not p.ends.is_empty())).is_true()
	p.nos.clear()
	p.net.request_barrier("нет такого", "charge")
	assert_bool(await _wait_for(func(): return not p.nos.is_empty())).is_true()
	assert_str(str(p.nos[0]["reason"])).is_equal("no_barrier")
	_node().open_barrier("bar1", "pick", SESSION)
	await _request(p, "charge")
	assert_str(str(p.nos[0]["reason"])).is_equal("open")
