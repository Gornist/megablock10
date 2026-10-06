extends GdUnitTestSuite
## Серый узел целиком (N7): сервер (NetServer + GrayNode + фейковый Мост) и бот в одном процессе.
## Бот с GHOST проходит чисто: шард на телефоне. Бот без GHOST: ICE выбрасывает, шард остаётся в узле.

static var _next_port := 18191
const SESSION := "s_fake000000000001"
const SHARD_ITEM := "it_fake00000000a001"

var _root: Node
var _server: NetServer
var _node: GrayNode
var _bridge: FakeBridge
var _bot: BotClient
var _events: Array = []


func before_test() -> void:
	_root = Node.new()
	_root.name = "GrayTestRoot"
	add_child(_root)
	var sroot := Node.new()
	sroot.name = "S"
	var croot := Node.new()
	croot.name = "C"
	_root.add_child(sroot)
	_root.add_child(croot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), sroot.get_path())
	get_tree().set_multiplayer(SceneMultiplayer.new(), croot.get_path())
	var cfg := NetConfig.new()
	cfg.port = _next_port
	_next_port += 1
	cfg.token = "t03:token-t03"
	_bridge = FakeBridge.new()
	_server = NetServer.new()
	sroot.add_child(_server)
	assert_int(_server.start(cfg, _bridge)).is_equal(OK)
	_node = GrayNode.new()
	sroot.add_child(_node)
	_node.start(_server, _bridge)
	_events = []
	_node.event.connect(func(ev: Dictionary): _events.append(ev))
	_bot = BotClient.new()
	croot.add_child(_bot)
	_cfg = cfg


var _cfg: NetConfig


func after_test() -> void:
	if _bot.net != null:
		await _bot.net.drop()
	_server.stop_net()
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


func _item_owner(id: String) -> String:
	return str(_bridge.doc(BridgeApi.T_ITEM, id)["data"]["owner"])


func _session_data() -> Dictionary:
	return _bridge.doc(BridgeApi.T_SESSION, SESSION)["data"]


func test_bot_with_ghost_passes_node_cleanly() -> void:
	_bot.start(_cfg, BotClient.Scenario.GHOST_RUN)
	assert_bool(await _wait_for(func(): return not _bot.result.is_empty())).is_true()
	assert_str(_bot.result).is_equal("clean")
	assert_bool(_bot.shard_taken).is_true()
	assert_bool(await _wait_for(func(): return "finished" in _kinds())).is_true()
	# ICE не заметил бота: trace ни разу не выходил из спокойного уровня.
	assert_array(_kinds()).not_contains(["ice_eject"])
	assert_array(_kinds()).not_contains(["level"])
	assert_str(_item_owner(SHARD_ITEM)).is_equal("outbox:KEY_ALICE")
	assert_str(str(_session_data()["state"])).is_equal("closed")
	assert_str(str(_session_data()["outcome"])).is_equal("clean")
	assert_bool(_server.has_avatar(SESSION)).is_false()


func test_bot_without_ghost_is_ejected_and_shard_stays() -> void:
	# Тест проверяет цепочку «заметили → выброс → исход», а не укрытия: бот идёт по x = -1 и с востока патруля прятался бы за колонной (3; −5).
	# Колонны закрывают взгляд отдельно (ice_brain_test), здесь ICE смотрят без препятствий.
	for ice in _node.ices():
		ice.brain.grid = null
	_bot.hold_after_grab = 4.0   # бот постоит у шарда на виду: поиск ICE дойдёт до последней замеченной точки (без случайности пути)
	_bot.start(_cfg, BotClient.Scenario.EXPOSED_RUN)
	assert_bool(await _wait_for(func(): return not _bot.result.is_empty())).is_true()
	assert_str(_bot.result).is_equal("ejected")
	assert_bool(await _wait_for(func(): return "finished" in _kinds())).is_true()
	assert_array(_kinds()).contains(["ice_eject"])
	assert_str(str(_session_data()["outcome"])).is_equal("soft_ice")
	# Шард — на постаменте и в Мосте остался в узле (взять его бот не успел или вернул при выбросе).
	assert_str(_item_owner(SHARD_ITEM)).is_equal("node:node_07")
	assert_str(_server.holder_of(NetConfig.PICKUP_ID)).is_empty()


func test_far_grab_is_denied() -> void:
	_bot.start(_cfg, BotClient.Scenario.GHOST_RUN)
	assert_bool(await _wait_for(func(): return _bot.net.is_connected_to_world)).is_true()
	var denied: Array[String] = []
	_bot.net.grab_denied.connect(func(_id, reason): denied.append(reason))
	_bot.net.request_grab(NetConfig.PICKUP_ID)  # бот ещё у входа, шард в 10 м
	assert_bool(await _wait_for(func(): return denied.size() == 1)).is_true()
	assert_str(denied[0]).is_equal(WorldMsg.REASON_FAR)


func test_outcome_plan_by_reason() -> void:
	var clean := GrayNode.outcome_plan({"reason": "clean"})
	assert_str(clean["outcome"]).is_equal("clean")
	assert_str(clean["loot"]).is_equal("phone")
	var ej := GrayNode.outcome_plan({"reason": "ejected"})
	assert_str(ej["outcome"]).is_equal("soft_ice")
	assert_str(ej["loot"]).is_equal("node")
	var fl := GrayNode.outcome_plan({"reason": "flatline"})
	assert_str(fl["outcome"]).is_equal("black_ice")
	assert_str(fl["daemon"]).is_equal("node")
	var lost := GrayNode.outcome_plan({"reason": "connection_lost", "deck_burned": true})
	assert_str(lost["outcome"]).is_equal("emergency")
	assert_bool(lost["disconnect"]).is_true()
	assert_str(lost["daemon"]).is_equal("burned")


## Настоящий клиент (сцена, интерфейс, звук) получает снимки узла с сервера и применяет демона из деки.
func test_flat_client_scene_follows_server_state() -> void:
	var croot := _root.get_node("C")
	var proto := ProtoClient.new()
	croot.add_child(proto)
	proto.start(PackedStringArray(["--token=" + _cfg.token, "--port=%d" % _cfg.port]), "flat", false)
	var scene: Node3D = proto.scene
	assert_bool(await _wait_for(func(): return scene.ice_node("ice_1") != null, 10.0)).is_true()
	assert_int(scene.deck_state.size()).is_equal(2)
	assert_str(scene.world_ui.deck.row_texts()[1]).contains("Призрак")
	var ds := _node.session_state(SESSION)
	ds.set_charged("ghost_1")   # защитный демон вне взлома срабатывает только заряженным (К6; заряд сеткой — charge_client_test)
	scene.use_slot(0)  # ghost_1
	assert_bool(await _wait_for(func(): return ds.is_ghost(_node.now()), 5.0)).is_true()
	assert_bool(await _wait_for(func(): return str(scene.world_ui.deck.row_texts()[1]).contains("с"), 5.0)).is_true()
	await proto.net.drop()


## Бот ходит прыжками по тем же правилам, что игрок: не дальше дальности, с паузой перезарядки, сервер ни одного не отклонил.
func test_bot_moves_by_teleport_hops_that_follow_the_rules() -> void:
	_bot.start(_cfg, BotClient.Scenario.GHOST_RUN)
	assert_bool(await _wait_for(func(): return not _bot.result.is_empty())).is_true()
	assert_str(_bot.result).is_equal("clean")
	assert_int(_bot.hops).is_greater(2)
	assert_array(_bot.tp_denied).is_empty()
	var prev := -INF
	for h in _bot.hop_log:   # [время бота, длина прыжка]
		assert_float(h[1]).is_less_equal(RigMath.TELEPORT_RANGE + 0.001)
		assert_float(h[0] - prev).is_greater_equal(RigMath.TELEPORT_COOLDOWN)
		prev = h[0]
