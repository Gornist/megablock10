extends GdUnitTestSuite
## Исходы забега в графе узлов (P2): то, что одиночный узел не показывает, — выход в тоннеле между узлами и локдаун после Soft ICE.
## Сервер (NetServer + GraphWorld) и бот в одном процессе, граф — tests/fixtures/graph_test.json (короткие времена:
## тоннель 0,4 с, локдаун 2 с), как в graph_world_test.gd. Без Моста локдаун ставит сервер мира, с Мостом — сам Мост
## (run.finish soft_ice, ValueOpsTest) и узел узнаёт о нём по подписке.

static var _next_port := 18791
const SESSION := "s_fake000000000001"
const NO_BRIDGE_SESSION := "s_nobridge"
const GRAPH := "res://tests/fixtures/graph_test.json"
const BRIDGE := "res://tests/fixtures/graph_bridge_fixture.json"

var _root: Node
var _server: NetServer
var _world: GraphWorld
var _bridge: FakeBridge
var _bot: BotClient
var _cfg: NetConfig
var _events: Array = []


## with_bridge = false — «токены из словаря», Моста нет (так сервер мира работал до M5 и может работать в тесте).
func _setup(with_bridge: bool = true) -> void:
	_events = []
	_bridge = null  # поля набора живут между тестами: «без Моста» не должно подхватить Мост прошлого теста
	_root = Node.new()
	_root.name = "OutcomesGraphRoot"
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
	_server = NetServer.new()
	sroot.add_child(_server)
	if with_bridge:
		_cfg.token = "t03:token-t03"
		_bridge = FakeBridge.new(BRIDGE)
		assert_int(_server.start(_cfg, _bridge)).is_equal(OK)
	else:
		_cfg.token = "tok"
		assert_int(_server.start(_cfg, DictTokenVerifier.new({"tok": NO_BRIDGE_SESSION}))).is_equal(OK)
	_world = GraphWorld.new()
	_world.trace_settings = {"decay_per_sec": 0.0}
	_world.ice_settings = {"sight_range": 0.0}
	sroot.add_child(_world)
	_world.start(_server, _bridge, NodeGraph.load_file(GRAPH))
	for gn in _world.nodes.values():
		(gn as GrayNode).event.connect(func(ev: Dictionary): _events.append(ev))
	_bot = BotClient.new()
	croot.add_child(_bot)


func after_test() -> void:
	if _bot != null and _bot.net != null:
		await _bot.net.drop()
	if _server != null:
		_server.stop_net()
	if _root != null:
		_root.queue_free()


func _wait_for(cond: Callable, sec: float = 30.0) -> bool:
	var t := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _kinds() -> Array:
	return _events.map(func(e): return e["kind"])


func _session_data() -> Dictionary:
	return _bridge.doc(BridgeApi.T_SESSION, SESSION)["data"]


## Обычный выход по причине из тоннеля: игрок в «тоннеле» между узлами, ни в одном узле его нет.
func test_exit_inside_the_tunnel_still_closes_the_run() -> void:
	_setup()
	_world.transit_started.connect(func(_s: String, _from: String, _to: String):
		_bot.net.request_exit(ExitLogic.REASON_HEADSET_OFF))
	_bot.route.assign(["g_b", "g_c"])
	_bot.start(_cfg, BotClient.Scenario.GRAPH_RUN)
	assert_bool(await _wait_for(func(): return _world.in_tunnel(SESSION) or "exit" in _kinds(), 10.0)).is_true()
	# Забег закрыт в Мосте (одним run.finish), а не повис active: терминал не застрянет за мёртвой сессией
	assert_bool(await _wait_for(func(): return str(_session_data()["state"]) == "closed", 10.0)).is_true()
	assert_str(str(_session_data()["outcome"])).is_equal("emergency")
	assert_bool(bool(_session_data()["disconnect"])).is_false()
	assert_int(_bridge.finish_calls).is_equal(1)
	assert_bool(_server.has_avatar(SESSION)).is_false()


func test_soft_ice_without_bridge_locks_the_node_for_lockdown_sec() -> void:
	_setup(false)
	var ga := _world.node_of("g_a")
	_bot.start(_cfg, BotClient.Scenario.LOITER)
	assert_bool(await _wait_for(func(): return ga.session_state(NO_BRIDGE_SESSION) != null and _bot.net.is_connected_to_world)).is_true()
	assert_bool(ga.is_locked_down()).is_false()
	(ga.session_state(NO_BRIDGE_SESSION) as DaemonSession).trace.add_action("door_forced", _world.clock.now, 10.0)  # trace 100
	assert_bool(await _wait_for(func(): return not _bot.result.is_empty())).is_true()
	assert_str(_bot.result).is_equal("ejected")
	assert_array(_kinds()).contains(["ice_eject", "lockdown"])
	# узел закрыт на lockdown_sec графа (2 с) и виден закрытым в порталах соседей
	assert_bool(ga.is_locked_down()).is_true()
	assert_float(ga.lockdown_left_sec()).is_between(0.5, 2.0)
	var gb_portals: Array = _world.node_event("g_b")["portals"]
	assert_bool(gb_portals.filter(func(p): return p["to"] == "g_a")[0]["open"]).is_false()
	# локдаун не вечный: кончился — узел открыт
	assert_bool(await _wait_for(func(): return not ga.is_locked_down(), 5.0)).is_true()
	assert_bool(_world.node_event("g_b")["portals"].filter(func(p): return p["to"] == "g_a")[0]["open"]).is_true()


func test_soft_ice_with_bridge_leaves_lockdown_to_the_bridge() -> void:
	_setup()
	var ga := _world.node_of("g_a")
	_bot.start(_cfg, BotClient.Scenario.LOITER)
	assert_bool(await _wait_for(func(): return ga.session_state(SESSION) != null and _bot.net.is_connected_to_world)).is_true()
	(ga.session_state(SESSION) as DaemonSession).trace.add_action("door_forced", _world.clock.now, 10.0)
	assert_bool(await _wait_for(func(): return "finished" in _kinds())).is_true()
	assert_str(str(_session_data()["outcome"])).is_equal("soft_ice")
	# Сервер мира не заводит свой локдаун рядом с Мостовым (иначе два срока на один узел): lockdown_until приходит из Моста
	assert_array(_kinds()).not_contains(["lockdown"])
	assert_bool(ga.is_locked_down()).is_false()
