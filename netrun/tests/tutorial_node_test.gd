extends GdUnitTestSuite
## Учебный узел (W2): первый вход новичка. Мост ставит сессии учебный узел (session.node) — сервер мира ведёт игрока туда,
## а не в узел терминала; таблички приходят в событии node; шард — заглушка без ценности; чистый выход закрывает забег
## одним run.finish(clean) — по нему Мост ставит runner.tutorial_done (ValueOps.doFinish), отдельной записи от мира нет.

static var _next_port := 18591
const SESSION := "s_fake000000000001"
const GRAPH := "res://tests/fixtures/tutorial_graph.json"
const BRIDGE := "res://tests/fixtures/tutorial_bridge_fixture.json"

var _root: Node
var _sroot: Node
var _croot: Node
var _server: NetServer
var _world: GraphWorld
var _bridge: FakeBridge
var _bot: BotClient
var _cfg: NetConfig
var _events: Array = []


func before_test() -> void:
	_root = Node.new()
	add_child(_root)
	_sroot = Node.new()
	_sroot.name = "S"
	_croot = Node.new()
	_croot.name = "C"
	_root.add_child(_sroot)
	_root.add_child(_croot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), _sroot.get_path())
	get_tree().set_multiplayer(SceneMultiplayer.new(), _croot.get_path())
	_cfg = NetConfig.new()
	_cfg.port = _next_port
	_next_port += 1
	_cfg.token = "t03:token-t03"
	_bridge = FakeBridge.new(BRIDGE)
	_server = NetServer.new()
	_sroot.add_child(_server)
	assert_int(_server.start(_cfg, _bridge)).is_equal(OK)
	_world = GraphWorld.new()
	_sroot.add_child(_world)
	_world.start(_server, _bridge, NodeGraph.load_file(GRAPH))
	for gn in _world.nodes.values():
		(gn as GrayNode).event.connect(func(ev: Dictionary): _events.append(ev))
	_bot = BotClient.new()
	_croot.add_child(_bot)


func after_test() -> void:
	if _bot.net != null:
		await _bot.net.drop()
	_server.stop_net()
	_root.queue_free()


func _wait_for(cond: Callable, sec: float = 40.0) -> bool:
	var t := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func test_real_graph_has_isolated_gentle_tutorial_node() -> void:
	var g := NodeGraph.load_file()
	assert_array(g.errors()).is_empty()
	assert_bool(g.is_tutorial("node_00")).is_true()
	assert_array(g.nodes["node_00"]["links"]).is_empty()
	assert_str(g.tier_of("node_00")).is_not_equal("NIGHTMARE")
	assert_int((g.nodes["node_00"]["signs"] as Array).size()).is_greater_equal(5)
	for id in g.nodes:
		assert_bool("node_00" in (g.nodes[id]["links"] as Array)).is_false()  # в учебный узел из графа не ведёт ни один тоннель
	assert_bool(g.entry_for("t03") == "node_00").is_false()


func test_tutorial_node_has_no_black_ice_and_one_gentle_soft_ice() -> void:
	var gn := _world.node_of("g_00")
	assert_bool(gn.has_black_ice()).is_false()
	assert_int(gn.ices().size()).is_equal(1)
	assert_float(float(gn.ices()[0].brain._s["sight_range"])).is_less(float(IceBrain.DEFAULT_SETTINGS["sight_range"]))
	assert_int(gn.slot_ids().size()).is_equal(1)


func test_newbie_runs_tutorial_node() -> void:
	_bot.read_signs = true
	_bot.use_ghost = true
	_bot.start(_cfg, BotClient.Scenario.GRAPH_RUN)
	assert_bool(await _wait_for(func(): return not _bot.result.is_empty())).is_true()
	# Вход — по session.node из Моста (узел терминала t03 — g_a, но сессия новичка учебная)
	assert_str(_bot.result).is_equal("clean")
	assert_array(_bot.visited).is_equal(["g_00"])
	assert_int(_bot.signs_read).is_equal(5)
	assert_int(_bot.tunnels_seen).is_equal(0)
	assert_bool(_bot.shard_taken).is_true()
	assert_bool(await _wait_for(func(): return _events.any(func(e): return e["kind"] == "finished"))).is_true()
	# Один run.finish(clean) в учебном узле: по нему Мост ставит tutorial_done
	assert_int(_bridge.finish_calls).is_equal(1)
	assert_str(str(_bridge.doc(BridgeApi.T_SESSION, SESSION)["data"]["outcome"])).is_equal("clean")
	assert_str(str(_bridge.finish_attempts[0]["outcome"])).is_equal("clean")
	# Шард-заглушка не уходит в Мост и слот остаётся живым
	var pk := GrayNode.shard_id("g_00", 0)
	assert_bool(_server.is_object_locked(pk)).is_false()
	assert_str(_server.holder_of(pk)).is_empty()
	assert_int(_world.node_of("g_00").empty_slots()).is_equal(0)
	for id in _bridge._docs[BridgeApi.T_ITEM]:
		var d: Dictionary = _bridge.doc(BridgeApi.T_ITEM, id)["data"]
		if d["kind"] == "SHARD":
			assert_bool(str(d["owner"]).begins_with("node:")).is_true()  # ни один шард Моста не ушёл на телефон
