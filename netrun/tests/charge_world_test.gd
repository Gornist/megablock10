extends GdUnitTestSuite
## Заряд защитных демонов (К6): сервер узла, фейковый Мост и настоящий плоский клиент в одном процессе. Автосолвер (BreachAutoSolver) собирает сетку заряда
## на запястье, как бот и человек: клиент подсвечивает клетки сам, сервер подтверждает каждый тап. Один заряд — один запуск; окна TIMESKEW и BLACKOUT
## открываются запуском и попадают в active_effects (то, что узел отдаёт Мосту для SecAlertRules).

static var _next_port := 18391
const SESSION := "s_fake000000000001"
const FIXTURE := "res://tests/fixtures/charge_bridge_fixture.json"
const GHOST := "it_c_ghost"
const SKEW := "it_c_skew"
const BLACK := "it_c_black"
const EXTRACT := "it_c_extract"

var _root: Node
var _server: NetServer
var _node: GrayNode
var _bridge: FakeBridge
var _cfg: NetConfig
var _events: Array = []


class Peer:
	extends RefCounted
	var net: NetClient
	var evs: Array = []
	var mirror: BreachMirror
	var ends: Array = []
	var nos: Array = []
	var daemon_replies: Array = []
	var states: Array = []

	func cd(id: String) -> Dictionary:
		for s in states.slice(-1):
			for e in s.get("cd", []):
				if e["id"] == id:
					return e
		return {}


func before_test() -> void:
	_events.clear()
	_root = Node.new()
	_root.name = "ChargeWorldRoot"
	add_child(_root)
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
	_cfg.token = "t03:token-t03"
	_bridge = FakeBridge.new(FIXTURE)
	_server = NetServer.new()
	sroot.add_child(_server)
	assert_int(_server.start(_cfg, _bridge)).is_equal(OK)
	_node = GrayNode.new()
	sroot.add_child(_node)
	_node.trace_settings = {"decay_per_sec": 0.0}
	_node.event.connect(func(ev: Dictionary): _events.append(ev))
	_node.start(_server, _bridge)


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


## Сырой клиент: события и снимки пишутся в Peer.
func _peer() -> Peer:
	var p := Peer.new()
	p.net = NetClient.new()
	_root.get_node("C").add_child(p.net)
	p.net.event_received.connect(func(ev: Dictionary):
		p.evs.append(ev)
		var kind := str(ev.get("kind", ""))
		if kind == WorldMsg.EV_BK:
			p.mirror = BreachMirror.from_event(ev)
		elif kind == WorldMsg.EV_BK_TICK and p.mirror != null:
			p.mirror.apply_tick(ev)
		elif kind == WorldMsg.EV_BK_END:
			if p.mirror != null:
				p.mirror.apply_end(ev)
			p.ends.append(ev)
		elif kind == WorldMsg.EV_BK_NO:
			p.nos.append(ev)
		elif kind == WorldMsg.EV_DAEMON:
			p.daemon_replies.append(ev))
	p.net.state_received.connect(func(s: Dictionary): p.states.append(s))
	var cfg := NetConfig.new()
	cfg.port = _cfg.port
	cfg.token = _cfg.token
	assert_int(p.net.start_client(cfg)).is_equal(OK)
	return p


## Подключённый игрок, у которого дека из Моста уже на сервере.
func _ready_peer() -> Peer:
	var p := _peer()
	assert_bool(await _wait_for(func(): return p.net.is_connected_to_world)).is_true()
	assert_bool(await _wait_for(func(): return _node.session_state(SESSION) != null and _node.session_state(SESSION).deck.has(GHOST) and _node.session_state(SESSION).deck_meta.has(BLACK))).is_true()
	return p


func _start(p: Peer, id: String) -> bool:
	p.mirror = null
	p.nos.clear()
	p.net.request_charge(id)
	await _wait_for(func(): return p.mirror != null or not p.nos.is_empty())
	return p.mirror != null


## Пройти автосолвером до конца.
func _solve(p: Peer) -> void:
	var path := BreachAutoSolver.solve(p.mirror.attempt)
	for i in range(path.size()):
		if p.mirror.finished:
			return
		assert_bool(p.mirror.tap(path[i])).is_true()
		p.net.request_breach_tap(path[i])
		assert_bool(await _wait_for(func(): return p.mirror.pending == null or p.mirror.finished)).is_true()
	await _wait_for(func(): return p.mirror.finished)


func _charge_and_solve(p: Peer, id: String) -> void:
	assert_bool(await _start(p, id)).is_true()
	assert_int(p.nos.size()).is_equal(0)
	await _solve(p)
	assert_bool(await _wait_for(func(): return not p.ends.is_empty())).is_true()


# ---------------------------------------------------------------- сервер

func test_charge_with_the_auto_solver_charges_and_one_launch_spends_it() -> void:
	var p := await _ready_peer()
	var ds := _node.session_state(SESSION)
	assert_bool(ds.is_charged(GHOST)).is_false()
	assert_bool(await _start(p, GHOST)).is_true()
	# Режим движка for_charge: сетка и таймер по тиру демона (тир 1 → 5×5, 45 с), буфер = длина цепочки + 2, ловушек нет.
	assert_str(p.mirror.mode).is_equal("charge")
	assert_str(p.mirror.tier).is_equal("BASE")
	assert_int(p.mirror.grid.size).is_equal(5)
	assert_int(p.mirror.timer_sec).is_equal(45)
	assert_int(p.mirror.buffer_size).is_equal(4)
	assert_array(p.mirror.targets[0]["cells"]).is_equal(["1C", "BD"])
	assert_int((p.evs.filter(func(e): return e["kind"] == WorldMsg.EV_BK)[0]["grid"]["traps"] as Array).size()).is_equal(0)
	await _solve(p)
	assert_bool(await _wait_for(func(): return not p.ends.is_empty())).is_true()
	assert_str(p.ends[0]["mode"]).is_equal("charge")
	assert_str(p.ends[0]["outcome"]).is_equal("SUCCESS")
	assert_bool(p.ends[0]["charged"]).is_true()
	assert_str(p.ends[0]["daemon"]).is_equal(GHOST)
	assert_bool(ds.is_charged(GHOST)).is_true()
	assert_bool(await _wait_for(func(): return p.cd(GHOST).get("st", "") == "charged")).is_true()
	# Запуск: окно открыто, заряд ушёл, перезарядка из effects/GHOST.json (тир 1: 60 с).
	p.net.request_use(GHOST)
	assert_bool(await _wait_for(func(): return not p.daemon_replies.is_empty())).is_true()
	assert_bool(p.daemon_replies[0]["ok"]).is_true()
	assert_bool(ds.is_charged(GHOST)).is_false()
	assert_array(ds.active_effects(_node.now())).is_equal(["GHOST"])
	assert_bool(ds.is_ghost(_node.now() + 9.0)).is_true()   # тир 1: 10 с (W1-Ч1)
	assert_bool(await _wait_for(func(): return p.cd(GHOST).get("st", "") == "active")).is_true()
	assert_float(ds.cooldown_left(GHOST, _node.now())).is_greater(55.0)
	# Второй запуск тем же зарядом невозможен.
	p.net.request_use(GHOST)
	assert_bool(await _wait_for(func(): return p.daemon_replies.size() >= 2)).is_true()
	assert_str(p.daemon_replies[1]["error"]).is_equal("cooldown")
	var ended := _events.filter(func(e): return e["kind"] == "charge_end")
	assert_int(ended.size()).is_equal(1)
	assert_bool(ended[0]["charged"]).is_true()


func test_use_without_a_charge_is_refused_and_starts_nothing() -> void:
	var p := await _ready_peer()
	p.net.request_use(GHOST)
	assert_bool(await _wait_for(func(): return not p.daemon_replies.is_empty())).is_true()
	assert_bool(p.daemon_replies[0]["ok"]).is_false()
	assert_str(p.daemon_replies[0]["error"]).is_equal("not_charged")
	var ds := _node.session_state(SESSION)
	assert_array(ds.active_effects(_node.now())).is_empty()
	assert_float(ds.cooldown_left(GHOST, _node.now())).is_equal(0.0)


func test_every_protective_daemon_charges_and_a_bigger_tier_means_a_bigger_grid() -> void:
	var p := await _ready_peer()
	await _charge_and_solve(p, BLACK)   # тир 3: 7×7, 75 с
	assert_bool(p.ends[0]["charged"]).is_true()
	var begin: Dictionary = p.evs.filter(func(e): return e["kind"] == WorldMsg.EV_BK)[0]
	assert_int(int(begin["grid"]["size"])).is_equal(7)
	assert_int(int(begin["sec"])).is_equal(75)
	assert_int(int(begin["buffer"])).is_equal(4)
	p.ends.clear()
	await _charge_and_solve(p, SKEW)    # тир 2: 6×6, 60 с
	assert_bool(p.ends[0]["charged"]).is_true()
	var ds := _node.session_state(SESSION)
	assert_array(ds.charged_ids()).is_equal([SKEW, BLACK] if ds.deck.find(SKEW) < ds.deck.find(BLACK) else [BLACK, SKEW])


func test_extract_shard_is_not_chargeable() -> void:
	var p := await _ready_peer()
	assert_bool(await _start(p, EXTRACT)).is_false()
	assert_int(p.nos.size()).is_equal(1)
	assert_str(p.nos[0]["reason"]).is_equal("not_chargeable")
	assert_str(p.nos[0]["mode"]).is_equal("charge")
	assert_bool(_node.charge.has_attempt(SESSION)).is_false()


func test_charge_is_refused_while_charged_while_active_and_for_unknown_daemons() -> void:
	var p := await _ready_peer()
	await _charge_and_solve(p, GHOST)
	assert_bool(await _start(p, GHOST)).is_false()
	assert_str(p.nos[0]["reason"]).is_equal("charged")
	# Уже запущенный: сначала перезарядка (60 с), потом снова заряд.
	p.net.request_use(GHOST)
	assert_bool(await _wait_for(func(): return not p.daemon_replies.is_empty())).is_true()
	assert_bool(await _start(p, GHOST)).is_false()
	assert_str(p.nos[0]["reason"]).is_equal("cooldown")
	assert_int(int(p.nos[0]["left"])).is_greater(50)
	assert_bool(await _start(p, "it_nope")).is_false()
	assert_str(p.nos[0]["reason"]).is_equal("bad_daemon")


func test_a_second_charge_is_refused_while_one_is_running() -> void:
	var p := await _ready_peer()
	assert_bool(await _start(p, GHOST)).is_true()
	p.nos.clear()
	p.net.request_charge(SKEW)
	assert_bool(await _wait_for(func(): return not p.nos.is_empty())).is_true()
	assert_str(p.nos[0]["reason"]).is_equal("active")
	assert_bool(_node.charge.has_attempt(SESSION)).is_true()


func test_cancel_drops_the_attempt_without_a_charge_and_it_can_be_retried_at_once() -> void:
	var p := await _ready_peer()
	assert_bool(await _start(p, GHOST)).is_true()
	var path := BreachAutoSolver.solve(p.mirror.attempt)
	p.mirror.tap(path[0])
	p.net.request_breach_tap(path[0])
	assert_bool(await _wait_for(func(): return p.mirror.pending == null)).is_true()
	p.net.request_breach_cancel()
	assert_bool(await _wait_for(func(): return not p.ends.is_empty())).is_true()
	assert_bool(p.ends[0]["charged"]).is_false()
	assert_str(p.ends[0]["early"]).is_equal("cancel")
	assert_bool(_node.session_state(SESSION).is_charged(GHOST)).is_false()
	assert_bool(_node.charge.has_attempt(SESSION)).is_false()
	p.ends.clear()
	await _charge_and_solve(p, GHOST)   # повтор сразу
	assert_bool(p.ends[0]["charged"]).is_true()


func test_time_running_out_gives_no_charge() -> void:
	var p := await _ready_peer()
	assert_bool(await _start(p, GHOST)).is_true()
	for i in 50:
		_node.charge.tick(1.0)
	assert_bool(await _wait_for(func(): return not p.ends.is_empty())).is_true()
	assert_str(p.ends[0]["outcome"]).is_equal("FAIL")
	assert_bool(p.ends[0]["charged"]).is_false()
	assert_bool(_node.session_state(SESSION).is_charged(GHOST)).is_false()
	assert_bool(_node.charge.has_attempt(SESSION)).is_false()
	# Провал — не штраф: повторить можно сразу.
	p.ends.clear()
	await _charge_and_solve(p, GHOST)
	assert_bool(p.ends[0]["charged"]).is_true()


func test_a_teleport_interrupts_the_charge_with_no_consequences() -> void:
	var p := await _ready_peer()
	assert_bool(await _start(p, GHOST)).is_true()
	p.net.request_teleport(Vector3(1.0, 0.0, -2.0))
	assert_bool(await _wait_for(func(): return not p.ends.is_empty())).is_true()
	assert_str(p.ends[0]["early"]).is_equal("teleport")
	assert_bool(p.ends[0]["charged"]).is_false()
	assert_bool(_node.session_state(SESSION).is_charged(GHOST)).is_false()


func test_a_charge_is_not_a_breach_it_does_not_touch_the_bridge() -> void:
	var p := await _ready_peer()
	await _charge_and_solve(p, GHOST)
	assert_int(_bridge.breach_calls).is_equal(0)   # заряд — не взлом: ни run.breach, ни сигнала СБ (design §9.1)


func test_an_exit_loses_the_charge_with_the_session() -> void:
	var p := await _ready_peer()
	await _charge_and_solve(p, GHOST)
	assert_bool(_node.session_state(SESSION).is_charged(GHOST)).is_true()
	assert_bool(p.net.request_exit(ExitLogic.REASON_MANUAL_HOLD)).is_true()
	assert_bool(await _wait_for(func(): return _node.session_state(SESSION) == null)).is_true()


# ---------------------------------------------------------------- окна эффектов, которые видит Мост

func test_the_node_reports_the_open_windows_to_the_bridge_on_a_trace_level() -> void:
	var p := await _ready_peer()
	var ds := _node.session_state(SESSION)
	var now := _node.now()
	ds.timeskew_until = now + 30.0
	ds.blackout_until = now + 8.0
	ds.ghost_until = now + 20.0
	# Уровень TRACE пишется в session.world вместе с активными эффектами.
	ds.trace.add_amount(55.0, now)
	assert_bool(await _wait_for(func(): return (_bridge.doc("session", SESSION)["data"].get("world", {}) as Dictionary).get("effects", []).size() == 3)).is_true()
	var world: Dictionary = _bridge.doc("session", SESSION)["data"]["world"]
	assert_int(int(world["trace_level"])).is_equal(2)
	assert_array(world["effects"]).is_equal(["GHOST", "TIMESKEW", "BLACKOUT"])
	assert_object(p).is_not_null()
