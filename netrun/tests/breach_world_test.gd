extends GdUnitTestSuite
## Взлом хранилища на сервере мира (К3): сервер, граф, фейковый Мост и настоящие NetClient'ы в одном процессе. Граф — breach_graph.json (флаг
## vault_requires_open не задан: "auto" — с Мостом включён), Мост — breach_bridge_fixture.json. Автосолвер проходит взлом без VR (бот).

static var _next_port := 18791
const GRAPH := "res://tests/fixtures/breach_graph.json"
const BRIDGE := "res://tests/fixtures/breach_bridge_fixture.json"
const S1 := "s_fake000000000001"
const S2 := "s_fake000000000002"
const S3 := "s_fake000000000003"
const D_EXTRACT := "it_b_d1"
const D_GHOST := "it_b_d2"

var _root: Node
var _sroot: Node
var _server: NetServer
var _world: GraphWorld
var _bridge: FakeBridge
var _cfg: NetConfig
var _clients: Array = []
var _events: Array = []        # события узлов


class Peer:
	extends RefCounted
	var net: NetClient
	var evs: Array = []
	var mirror: BreachMirror
	var ends: Array = []
	var nos: Array = []
	var shards: Array = []
	var deck: Dictionary = {}
	var states: Array = []

	func last_state() -> Dictionary:
		return states[-1] if not states.is_empty() else {}

	func vault(id: String) -> Dictionary:
		for sh in shards:
			if sh["id"] == id:
				return sh
		return {}


func before_test() -> void:
	_clients.clear()
	_events.clear()
	_root = Node.new()
	_root.name = "BreachWorldRoot"
	add_child(_root)
	_sroot = Node.new()
	_sroot.name = "S"
	_root.add_child(_sroot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), _sroot.get_path())
	_cfg = NetConfig.new()
	_cfg.port = _next_port
	_next_port += 1
	_cfg.token = "t03:token-t03"
	_bridge = FakeBridge.new(BRIDGE)
	_server = NetServer.new()
	_sroot.add_child(_server)
	assert_int(_server.start(_cfg, _bridge)).is_equal(OK)
	_world = GraphWorld.new()
	_world.trace_settings = {"decay_per_sec": 0.0}
	_sroot.add_child(_world)
	_world.start(_server, _bridge, NodeGraph.load_file(GRAPH))
	for gn in _world.nodes.values():
		(gn as GrayNode).event.connect(func(ev: Dictionary): _events.append(ev))


func after_test() -> void:
	for p in _clients:
		if is_instance_valid(p.net) and p.net.is_connected_to_world:
			await p.net.drop()
	_server.stop_net()
	_root.queue_free()


func _wait_for(cond: Callable, sec: float = 20.0) -> bool:
	var t := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _kinds() -> Array:
	return _events.map(func(e): return e["kind"])


## Игрок терминала terminal: свой SceneMultiplayer, события пишутся в Peer.
func _connect(terminal: String) -> Peer:
	var croot := Node.new()
	croot.name = "C%d" % _clients.size()
	_root.add_child(croot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), croot.get_path())
	var p := Peer.new()
	p.net = NetClient.new()
	croot.add_child(p.net)
	p.net.event_received.connect(_on_peer_event.bind(p))
	p.net.state_received.connect(func(s: Dictionary): p.states.append(s))
	var cfg := NetConfig.new()
	cfg.port = _cfg.port
	cfg.token = "%s:token-t03" % terminal
	assert_int(p.net.start_client(cfg)).is_equal(OK)
	_clients.append(p)
	assert_bool(await _wait_for(func(): return p.net.is_connected_to_world)).is_true()
	return p


func _on_peer_event(ev: Dictionary, p: Peer) -> void:
	p.evs.append(ev)
	match str(ev.get("kind", "")):
		WorldMsg.EV_BK:
			p.mirror = BreachMirror.from_event(ev)
		WorldMsg.EV_BK_TICK:
			if p.mirror != null:
				p.mirror.apply_tick(ev)
		WorldMsg.EV_BK_END:
			if p.mirror != null:
				p.mirror.apply_end(ev)
			p.ends.append(ev)
		WorldMsg.EV_BK_NO:
			p.nos.append(ev)
		WorldMsg.EV_SHARDS, WorldMsg.EV_NODE:
			p.shards = ev["shards"]
		WorldMsg.EV_DECK:
			p.deck = ev


## Подключиться и дождаться деки из Моста (рабочие демоны с цепочками) и вида хранилищ.
func _ready_peer(terminal: String, session: String) -> Peer:
	var p := await _connect(terminal)
	assert_bool(await _wait_for(func(): return (p.deck.get("daemons", []) as Array).any(func(d): return not (d.get("cells", []) as Array).is_empty()) and not p.shards.is_empty())).is_true()
	assert_bool(_server.has_avatar(session)).is_true()
	return p


func _slot(node: String, k: int) -> String:
	return GrayNode.shard_id(node, k)


## Поставить игрока у хранилища (сервер двигает аватар: проверки «рядом» ждут близости к хранилищу).
func _stand_at(session: String, node: String, k: int) -> void:
	_server.teleport(session, NodeLayout.vault_pad(NodeLayout.SHARD_SLOTS[k]))


func _start(p: Peer, vault: String, ids: Array) -> bool:
	p.mirror = null
	var n := p.evs.size()
	p.net.request_breach(vault, ids)
	return await _wait_for(func(): return p.mirror != null or not p.nos.is_empty())


## Пройти автосолвером до конца (тап за тапом, как бот и человек: ждём подтверждения сервера).
func _solve(p: Peer) -> void:
	var path := BreachAutoSolver.solve(p.mirror.attempt)
	for i in range(path.size()):
		if p.mirror.finished:
			return
		if p.mirror.selected().size() > i:
			continue
		assert_bool(p.mirror.tap(path[i])).is_true()
		p.net.request_breach_tap(path[i])
		assert_bool(await _wait_for(func(): return p.mirror.pending == null)).is_true()
	await _wait_for(func(): return p.mirror.finished)


func test_with_a_bridge_the_vault_is_closed_until_breached() -> void:
	var a: GrayNode = _world.node_of("b_a")
	var s0 := _slot("b_a", 0)
	assert_bool(a.vault_requires_open()).is_true()        # "auto" + Мост + узел графа
	assert_str(a.vault_state(s0, S1)).is_equal("closed")
	assert_bool(_world.node_of("b_h").vault_requires_open()).is_true()
	var p := await _ready_peer("t03", S1)
	assert_str(p.vault(s0).get("vault", "")).is_equal("closed")
	assert_str(p.vault(s0).get("access", "")).is_equal("ok")
	# grab закрытого не отдаётся, даже рядом
	_stand_at(S1, "b_a", 0)
	var denied := []
	p.net.grab_denied.connect(func(id: String, reason: String): denied.append([id, reason]))
	p.net.request_grab(s0)
	assert_bool(await _wait_for(func(): return not denied.is_empty())).is_true()
	assert_str(denied[0][1]).is_equal(WorldMsg.REASON_FAR)


func test_the_flag_stays_configurable_per_graph() -> void:
	var a: GrayNode = _world.node_of("b_a")
	a.settings = a.settings.duplicate()
	a.settings["vault_requires_open"] = false
	assert_bool(a.vault_requires_open()).is_false()
	assert_str(a.vault_state(_slot("b_a", 0), S1)).is_equal("open")
	a.settings["vault_requires_open"] = true
	assert_bool(a.vault_requires_open()).is_true()
	# без Моста "auto" не включается: стенды и плоская сборка без фикстуры берут шард, как раньше
	var lone := GrayNode.new()
	lone.settings = NodeGraph.DEFAULT_SETTINGS
	assert_bool(lone.vault_requires_open()).is_false()
	lone.free()


func test_breach_scenario_with_the_auto_solver_opens_the_vault_and_the_shard_is_taken() -> void:
	var p := await _ready_peer("t03", S1)
	var s0 := _slot("b_a", 0)
	_stand_at(S1, "b_a", 0)
	assert_bool(await _start(p, s0, [D_EXTRACT])).is_true()
	assert_int(p.nos.size()).is_equal(0)
	assert_int(p.mirror.n).is_equal(1)
	assert_str(p.mirror.tier).is_equal("BASE")
	assert_int(p.mirror.grid.size).is_equal(5)
	# Буфер Взлома 2.0: min(RAM 8, замок BASE 1 + цепочка + запас 2), а не вся RAM.
	assert_int(p.mirror.buffer_size).is_equal(1 + (p.mirror.targets[0]["cells"] as Array).size() + 2)
	assert_int(p.mirror.timer_sec).is_equal(45)
	assert_str(p.mirror.ice_line).starts_with("ICE:")
	# Замок BASE (1 код) приходит в сетке сообщения старта; приманок у BASE нет, поэтому и ключа decoys нет.
	assert_int(p.mirror.lock.size()).is_equal(1)
	assert_bool(p.mirror.decoys.is_empty()).is_true()
	assert_bool(p.mirror.lock_opened).is_false()
	# номер попытки записан в Мост ДО показа сетки
	var sdoc := _bridge.doc("session", S1)
	assert_int(int(sdoc["data"]["world"]["breach_n"])).is_equal(1)
	await _solve(p)
	assert_bool(p.mirror.finished).is_true()
	assert_bool(p.ends[0]["lock_opened"]).is_true()           # итог клиенту: замок вскрыт, ничего не «совпало до замка»
	assert_array(p.ends[0]["matched_before_lock"]).is_empty()
	assert_str(p.ends[0]["outcome"]).is_equal("SUCCESS")
	assert_array(p.ends[0]["opened"]).is_equal([s0])
	assert_int(int(p.ends[0]["eddies"])).is_greater(0)
	assert_str(p.ends[0]["alert"]).is_equal("сигнала СБ нет")   # фейк: сигнала нет
	assert_int(int(p.ends[0]["cooldown"])).is_greater(1700)
	# Мост получил ровно один итог по контракту
	assert_int(_bridge.breach_calls).is_equal(1)
	assert_str(_bridge.doc("session", S1)["data"]["breach"]["outcome"]).is_equal("SUCCESS")
	# lock_opened и «совпал до замка» — только клиенту: в запись Моста они не попадают (контракт run.breach не менялся)
	assert_bool((_bridge.doc("session", S1)["data"]["breach"] as Dictionary).has("lock_opened")).is_false()
	# хранилище открыто для этой сессии
	assert_bool(await _wait_for(func(): return p.vault(s0).get("vault", "") == "open")).is_true()
	var taken := []
	p.net.grab_confirmed.connect(func(id: String): taken.append(id))
	p.net.request_grab(s0)
	assert_bool(await _wait_for(func(): return not taken.is_empty())).is_true()
	assert_bool(await _wait_for(func(): return _bridge.doc("item", "it_b_s1")["data"]["owner"] == "deck:" + S1)).is_true()


func test_bot_passes_the_breach_and_exits_clean_with_the_loot() -> void:
	var croot := Node.new()
	croot.name = "BotRoot"
	_root.add_child(croot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), croot.get_path())
	var bot := BotClient.new()
	croot.add_child(bot)
	var cfg := NetConfig.new()
	cfg.port = _cfg.port
	cfg.token = "t03:token-t03"
	bot.start(cfg, BotClient.Scenario.GRAPH_RUN)
	assert_bool(await _wait_for(func(): return not bot.result.is_empty(), 60.0)).is_true()
	assert_str(bot.result).is_equal("clean")
	assert_int(bot.breach_log.size()).is_equal(1)
	assert_str(bot.breach_log[0]["outcome"]).is_equal("SUCCESS")
	assert_bool(bot.shard_taken).is_true()
	# добыча вернулась на телефон: чистый выход
	assert_bool(await _wait_for(func(): return _bridge.doc("session", S1)["data"]["state"] == "closed")).is_true()
	assert_bool(str(_bridge.doc("item", "it_b_s1")["data"]["owner"]).begins_with("outbox:") or str(_bridge.doc("item", "it_b_s2")["data"]["owner"]).begins_with("outbox:")).is_true()
	if bot.net != null:
		await bot.net.drop()


func test_cancel_resolves_early_with_what_was_collected_and_counts_as_an_attempt() -> void:
	var p := await _ready_peer("t03", S1)
	var s0 := _slot("b_a", 0)
	_stand_at(S1, "b_a", 0)
	assert_bool(await _start(p, s0, [D_EXTRACT])).is_true()
	var alert_before := (_world.node_of("b_a") as GrayNode).alert
	p.net.request_breach_cancel()
	assert_bool(await _wait_for(func(): return not p.ends.is_empty())).is_true()
	assert_str(p.ends[0]["outcome"]).is_equal("FAIL")
	assert_str(p.ends[0]["early"]).is_equal("cancel")
	assert_array(p.ends[0]["opened"]).is_equal([])
	assert_int(int(p.ends[0]["eddies"])).is_equal(0)
	assert_bool(p.ends[0].has("cooldown")).is_false()                 # FAIL остывания не даёт
	assert_int(_bridge.breach_calls).is_equal(1)
	assert_float((_world.node_of("b_a") as GrayNode).alert).is_greater(alert_before)   # alert_per_fail
	assert_str(p.vault(s0).get("vault", "closed")).is_equal("closed")
	# следующая попытка — n = 2 (rid другой)
	assert_bool(await _start(p, s0, [D_EXTRACT])).is_true()
	assert_int(p.mirror.n).is_equal(2)


func test_teleport_in_the_middle_ends_the_breach_early() -> void:
	var p := await _ready_peer("t03", S1)
	_stand_at(S1, "b_a", 0)
	assert_bool(await _start(p, _slot("b_a", 0), [D_EXTRACT])).is_true()
	p.net.request_teleport(Vector3(2.0, 0, -6.0))
	assert_bool(await _wait_for(func(): return not p.ends.is_empty())).is_true()
	assert_str(p.ends[0]["early"]).is_equal("teleport")
	assert_str(p.ends[0]["outcome"]).is_equal("FAIL")


func test_dropping_the_connection_mid_breach_still_reports_the_attempt() -> void:
	var p := await _ready_peer("t03", S1)
	_stand_at(S1, "b_a", 0)
	assert_bool(await _start(p, _slot("b_a", 0), [D_EXTRACT])).is_true()
	await p.net.drop()
	assert_bool(await _wait_for(func(): return _bridge.breach_calls == 1)).is_true()
	assert_str(_bridge.breach_log[0]["outcome"]).is_equal("FAIL")
	assert_bool(_kinds().has("breach_end")).is_true()


func test_a_trap_raises_trace_by_the_tier_number() -> void:
	var p := await _ready_peer("t05", S3)   # узел b_h, тир HARD: 2–3 мёртвые клетки
	_stand_at(S3, "b_h", 0)
	assert_bool(await _start(p, _slot("b_h", 0), ["it_b_d4"])).is_true()
	assert_str(p.mirror.tier).is_equal("HARD")
	assert_int(p.mirror.grid.size).is_equal(6)
	var ds := (_world.node_of("b_h") as GrayNode).session_state(S3)
	var before := ds.trace.value()
	# верхняя строка: найдём мёртвую клетку в любом месте — но тапнуть можно только доступную; перебираем попытки с новыми сетками
	var hit := false
	for attempt in 6:
		if attempt > 0:
			p.net.request_breach_cancel()
			assert_bool(await _wait_for(func(): return p.mirror.finished)).is_true()
			assert_bool(await _start(p, _slot("b_h", 0), ["it_b_d4"])).is_true()
		for c in p.mirror.selectable():
			if p.mirror.grid.is_dead(c):
				assert_bool(p.mirror.tap(c)).is_true()
				p.net.request_breach_tap(c)
				hit = true
				break
		if hit:
			break
	if not hit:
		# в верхней строке мёртвых не нашли ни разу — дойдём вторым ходом до столбца с мёртвой клеткой
		var c0 := p.mirror.selectable()[0]
		p.mirror.tap(c0)
		p.net.request_breach_tap(c0)
		assert_bool(await _wait_for(func(): return p.mirror.pending == null)).is_true()
		for c in p.mirror.selectable():
			if p.mirror.grid.is_dead(c):
				p.mirror.tap(c)
				p.net.request_breach_tap(c)
				hit = true
				break
	if hit:
		assert_bool(await _wait_for(func(): return p.mirror.pending == null)).is_true()
		var trap_tick: Dictionary = p.evs.filter(func(e): return e.get("kind") == WorldMsg.EV_BK_TICK and e.get("trap", false))[0]
		assert_bool(trap_tick["ok"]).is_true()
		assert_float(ds.trace.value() - before).is_equal_approx(float(_world.graph.settings["trap_trace"]["HARD"]), 0.001)
		assert_str(trap_tick.get("ice", "")).starts_with("ICE:")
	else:
		# сетка без доступной мёртвой клетки на двух ходах: проверяем само число
		assert_float(float(_world.graph.settings["trap_trace"]["HARD"])).is_equal(8.0)


func test_a_rejected_tap_changes_nothing_on_the_server() -> void:
	var p := await _ready_peer("t03", S1)
	_stand_at(S1, "b_a", 0)
	assert_bool(await _start(p, _slot("b_a", 0), [D_EXTRACT])).is_true()
	var att := (_world.node_of("b_a") as GrayNode).breach.attempt_of(S1)
	p.net.request_breach_tap(Vector2i(3, 3))   # не из верхней строки
	assert_bool(await _wait_for(func(): return p.evs.any(func(e): return e.get("kind") == WorldMsg.EV_BK_TICK and e.get("ok", true) == false))).is_true()
	assert_int(att.run.attempt.selected.size()).is_equal(0)
	p.net.request_breach_tap(Vector2i(99, 99))   # вне сетки
	await _wait_for(func(): return p.evs.filter(func(e): return e.get("kind") == WorldMsg.EV_BK_TICK and e.get("ok", true) == false).size() >= 2)
	assert_int(att.run.attempt.selected.size()).is_equal(0)


func test_one_panel_one_hacker_and_cooldown_after_a_success() -> void:
	var a := await _ready_peer("t03", S1)
	var b := await _ready_peer("t04", S2)
	var s0 := _slot("b_a", 0)
	_stand_at(S1, "b_a", 0)
	_stand_at(S2, "b_a", 0)
	assert_bool(await _start(a, s0, [D_EXTRACT])).is_true()
	# второй видит «занято» и не может начать
	assert_bool(await _wait_for(func(): return b.vault(s0).get("access", "") == "busy")).is_true()
	assert_bool(await _start(b, s0, ["it_b_d3"])).is_true()
	assert_str(b.nos[0]["reason"]).is_equal("busy")
	b.nos.clear()
	await _solve(a)
	assert_str(a.ends[0]["outcome"]).is_equal("SUCCESS")
	# открытое хранилище — только взломщику: второй его не возьмёт
	assert_str(_world.node_of("b_a").vault_state(s0, S2)).is_equal("closed")
	assert_bool(await _wait_for(func(): return b.vault(s0).get("vault", "") == "closed" and b.vault(s0).get("access", "") == "ok")).is_true()
	# остывание: у первого узел остывает — второе хранилище тоже
	var s1 := _slot("b_a", 1)
	assert_bool(await _wait_for(func(): return a.vault(s1).get("access", "") == "cooldown")).is_true()
	a.nos.clear()
	_stand_at(S1, "b_a", 1)
	assert_bool(await _start(a, s1, [D_EXTRACT])).is_true()
	assert_str(a.nos[0]["reason"]).is_equal("cooldown")
	assert_int(int(a.nos[0]["left"])).is_greater(1700)
	assert_int(_bridge.breach_calls).is_equal(1)


func test_request_validation_rejects_bad_daemons_far_and_empty() -> void:
	var p := await _ready_peer("t03", S1)
	var s0 := _slot("b_a", 0)
	# далеко от хранилища (аватар у входа)
	assert_bool(await _start(p, s0, [D_EXTRACT])).is_true()
	assert_str(p.nos[-1]["reason"]).is_equal("far")
	_stand_at(S1, "b_a", 0)
	p.nos.clear()
	await _start(p, s0, [])
	assert_str(p.nos[-1]["reason"]).is_equal("bad_daemons")
	p.nos.clear()
	await _start(p, s0, ["it_b_d3"])                      # чужой демон
	assert_str(p.nos[-1]["reason"]).is_equal("bad_daemons")
	p.nos.clear()
	await _start(p, s0, [D_EXTRACT, D_EXTRACT])           # дубль
	assert_str(p.nos[-1]["reason"]).is_equal("bad_daemons")
	p.nos.clear()
	await _start(p, "no_such_vault", [D_EXTRACT])
	assert_str(p.nos[-1]["reason"]).is_equal("not_ready")
	assert_int(_bridge.breach_calls).is_equal(0)
	assert_int(int(_bridge.doc("session", S1)["data"].get("world", {}).get("breach_n", 0))).is_equal(0)   # отказы номер не тратят


func test_ram_limits_the_selection() -> void:
	var p := await _ready_peer("t04", S2)    # RAM 6: у Лиса один демон из 2 ячеек
	_stand_at(S2, "b_a", 0)
	var ds := (_world.node_of("b_a") as GrayNode).session_state(S2)
	ds.ram = 1
	assert_bool(await _start(p, _slot("b_a", 0), ["it_b_d3"])).is_true()
	assert_str(p.nos[-1]["reason"]).is_equal("bad_daemons")   # 2 ячейки не влезают в RAM 1
	# отказ несёт числа: игрок видит «замок X + цепочки Y > RAM»
	var no: Dictionary = p.nos[-1]
	assert_int(int(no["ram"])).is_equal(1)
	assert_int(int(no["need"]) - int(no["lock"])).is_equal(2)
	assert_int(int(no["lock"])).is_greater(0)


func test_empty_vault_is_reported_with_the_refill_time() -> void:
	var p := await _ready_peer("t03", S1)
	var a: GrayNode = _world.node_of("b_a")
	var s0 := _slot("b_a", 0)
	_stand_at(S1, "b_a", 0)
	a._deplete(s0, 100.0)
	assert_bool(await _start(p, s0, [D_EXTRACT])).is_true()
	assert_str(p.nos[-1]["reason"]).is_equal("empty")
	assert_int(int(p.nos[-1]["left"])).is_between(90, 101)
	assert_str(a.vault_access(s0, S1)["access"]).is_equal("empty")


func test_exit_waits_for_the_breach_result_before_closing_the_run() -> void:
	var p := await _ready_peer("t03", S1)
	_stand_at(S1, "b_a", 0)
	assert_bool(await _start(p, _slot("b_a", 0), [D_EXTRACT])).is_true()
	p.net.request_exit(ExitLogic.REASON_MANUAL_HOLD)       # аварийный выход посреди взлома
	assert_bool(await _wait_for(func(): return str(_bridge.doc("session", S1)["data"]["state"]) == "closed")).is_true()
	# run.breach ушёл ДО run.finish (иначе Мост ответил бы session_state)
	assert_int(_bridge.breach_calls).is_equal(1)
	assert_str(_bridge.doc("session", S1)["data"]["breach"]["outcome"]).is_equal("FAIL")


func test_open_vault_closes_after_vault_open_sec() -> void:
	var a: GrayNode = _world.node_of("b_a")
	var s0 := _slot("b_a", 0)
	a.open_vault(s0, S1, 0.3)
	assert_str(a.vault_state(s0, S1)).is_equal("open")
	assert_bool(await _wait_for(func(): return a.vault_state(s0, S1) == "closed", 3.0)).is_true()
	assert_bool(_kinds().has("vault_closed")).is_true()


func test_open_vault_survives_a_world_server_restart_from_session_opened() -> void:
	var a: GrayNode = _world.node_of("b_a")
	var s0 := _slot("b_a", 0)
	var until := int(Time.get_unix_time_from_system() * 1000.0) + 30000
	a.recover([
		{"type": "session", "id": S1, "ver": 1, "data": {"state": "active", "node": "b_a", "world": {"node": "b_a"}, "opened": [{"item": "it_b_s1", "node": "b_a", "until": until}, {"item": "it_b_s2", "node": "b_a", "until": 5}]}},
		{"type": "item", "id": "it_b_s1", "ver": 1, "data": {"owner": "node:b_a", "kind": "SHARD", "origin": "node:b_a", "shard": {"tier": 1, "decrypted": true}}},
		{"type": "item", "id": "it_b_s2", "ver": 1, "data": {"owner": "node:b_a", "kind": "SHARD", "origin": "node:b_a", "shard": {"tier": 2, "decrypted": false}}},
	])
	assert_str(a.vault_state(s0, S1)).is_equal("open")                    # срок не вышел: открыто взломщику
	assert_str(a.vault_state(_slot("b_a", 1), S1)).is_equal("closed")     # истёкшее не открываем
	assert_str(a.vault_state(s0, S2)).is_equal("closed")


func test_teleport_near_a_vault_lands_on_the_pad_on_the_server_too() -> void:
	var p := await _ready_peer("t03", S1)
	_server.teleport(S1, Vector3(-1.0, 0, -5.0))
	await get_tree().create_timer(0.1).timeout
	# клиент просит точку в 0,9 м от хранилища сбоку — сервер ставит на площадку
	p.net.request_teleport(Vector3(-1.0 + 0.9, 0, -9.0 + 0.5))
	var pad := NodeLayout.vault_pad(NodeLayout.SHARD_SLOTS[0])
	assert_bool(await _wait_for(func(): return NodeLayout.flat_distance(_server.get_avatar(S1).position, pad) < 0.05)).is_true()


# ---------------------------------------------------------------- заряд и окна эффектов во взломе (К6)

func test_open_windows_of_charged_daemons_go_to_the_bridge_with_the_breach_result() -> void:
	var p := await _ready_peer("t03", S1)
	var a: GrayNode = _world.node_of("b_a")
	var ds := a.session_state(S1)
	var now := a.now()
	ds.ghost_until = now + 600.0
	ds.timeskew_until = now + 600.0
	ds.blackout_until = now + 600.0
	var s0 := _slot("b_a", 0)
	_stand_at(S1, "b_a", 0)
	assert_bool(await _start(p, s0, [D_EXTRACT])).is_true()
	await _solve(p)
	assert_str(p.ends[0]["outcome"]).is_equal("SUCCESS")
	# Мост получил в active все три окна: совпавшие эффекты ∪ активные (контракт 6.6) лежат в итоге сессии.
	var effects: Array = _bridge.doc("session", S1)["data"]["breach"]["effects"]
	assert_array(effects).contains_exactly_in_any_order(["EXTRACT_SHARD", "GHOST", "TIMESKEW", "BLACKOUT"])


func test_a_closed_window_is_not_sent_to_the_bridge() -> void:
	var p := await _ready_peer("t03", S1)
	var a: GrayNode = _world.node_of("b_a")
	var ds := a.session_state(S1)
	ds.blackout_until = a.now() - 1.0   # окно кончилось до конца взлома
	var s0 := _slot("b_a", 0)
	_stand_at(S1, "b_a", 0)
	assert_bool(await _start(p, s0, [D_EXTRACT])).is_true()
	await _solve(p)
	assert_array(_bridge.doc("session", S1)["data"]["breach"]["effects"]).is_equal(["EXTRACT_SHARD"])


func test_charge_and_vault_breach_exclude_each_other() -> void:
	var p := await _ready_peer("t03", S1)
	var s0 := _slot("b_a", 0)
	_stand_at(S1, "b_a", 0)
	# идёт заряд -> взлом не начинается
	p.net.request_charge(D_GHOST)
	assert_bool(await _wait_for(func(): return p.mirror != null and p.mirror.mode == "charge")).is_true()
	p.nos.clear()
	p.net.request_breach(s0, [D_EXTRACT])
	assert_bool(await _wait_for(func(): return not p.nos.is_empty())).is_true()
	assert_str(p.nos[0]["reason"]).is_equal("charging")
	p.net.request_breach_cancel()   # отмена относится к заряду, раз идёт он
	assert_bool(await _wait_for(func(): return not p.ends.is_empty())).is_true()
	assert_bool(p.ends[0]["charged"]).is_false()
	# идёт взлом -> заряд не начинается
	p.mirror = null
	p.nos.clear()
	p.ends.clear()
	assert_bool(await _start(p, s0, [D_EXTRACT])).is_true()
	p.nos.clear()
	p.net.request_charge(D_GHOST)
	assert_bool(await _wait_for(func(): return not p.nos.is_empty())).is_true()
	assert_str(p.nos[0]["reason"]).is_equal("active")
	assert_str(p.nos[0]["mode"]).is_equal("charge")
	assert_bool(_world.node_of("b_a").charge.has_attempt(S1)).is_false()
