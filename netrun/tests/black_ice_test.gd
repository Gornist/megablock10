extends GdUnitTestSuite
## Black ICE (P4): охота, флэтлайн с «ждём мастера», мёртвая дека, сожжённая дека при выходе под охотой.
## Сервер (NetServer + GrayNode + фейковый Мост) и бот в одном процессе, как в gray_node_test.gd.
## Все ICE слепы (sight_range 0), кроме случаев, где зрение нужно Black ICE: охоту ведёт только trace.

static var _next_port := 18391
const SESSION := "s_fake000000000001"
const NODE := "node_07"
const DEAD_DECK := "it_fake000000d002"   # обычный демон: при флэтлайне остаётся в узле
const PROTECTED := "it_fake000000d001"   # защищённый: на телефон при любом исходе

var _root: Node
var _server: NetServer
var _node: GrayNode
var _bridge: FakeBridge
var _bot: BotClient
var _cfg: NetConfig
var _events: Array = []


var _croot: Node
var _sroot: Node
var _boots := 0


## Узел NIGHTMARE с Black ICE. black_extra — настройки Black ICE; blind_black=false — Black ICE видит (Soft ICE слепы всегда).
func _setup(black_extra: Dictionary = {}, blind_black: bool = true) -> void:
	_root = Node.new()
	_root.name = "BlackTestRoot"
	add_child(_root)
	_croot = Node.new()
	_croot.name = "C"
	_root.add_child(_croot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), _croot.get_path())
	_cfg = NetConfig.new()
	_cfg.port = _next_port
	_next_port += 1
	_cfg.token = "t03:token-t03"
	_bridge = FakeBridge.new()
	_boot(black_extra, blind_black)
	_bot = BotClient.new()
	_croot.add_child(_bot)


## Поднять сервер мира на общем Мосте (при «рестарте» — второй раз, на том же Мосте).
func _boot(black_extra: Dictionary = {}, blind_black: bool = true) -> void:
	_boots += 1
	_sroot = Node.new()
	_sroot.name = "S%d" % _boots
	_root.add_child(_sroot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), _sroot.get_path())
	_server = NetServer.new()
	_sroot.add_child(_server)
	assert_int(_server.start(_cfg, _bridge)).is_equal(OK)
	_node = GrayNode.new()
	_sroot.add_child(_node)
	_node.ice_settings = {"sight_range": 0.0}
	_node.trace_settings = {"decay_per_sec": 0.0}
	var bs := black_extra.duplicate()
	if not blind_black:
		bs["sight_range"] = 12.0
	_node.black_ice_settings = bs
	_events = []
	_node.event.connect(func(ev: Dictionary): _events.append(ev))  # до start: с фейковым Мостом recover идёт синхронно
	_node.start(_server, _bridge)
	_node.enable_black_ice()


## «Убийство» сервера мира: сокет закрыт без прощания, сопрограммы исчезают вместе с узлами.
func _kill_server() -> void:
	if _sroot != null and is_instance_valid(_sroot):
		_server.stop_net()
		_root.remove_child(_sroot)
		_sroot.free()
	_sroot = null


func after_test() -> void:
	if _bot != null and _bot.net != null:
		await _bot.net.drop()
	if _server != null and _sroot != null:
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


func _owner(id: String) -> String:
	return str(_bridge.doc(BridgeApi.T_ITEM, id)["data"]["owner"])


func _session_data() -> Dictionary:
	return _bridge.doc(BridgeApi.T_SESSION, SESSION)["data"]


## Бот на связи, сессия узла создана; поднять trace до уровня TRACE (охота) без зрения.
func _bot_in_node_with_trace(value: float) -> void:
	_bot.start(_cfg, BotClient.Scenario.LOITER)
	assert_bool(await _wait_for(func(): return _node.session_state(SESSION) != null)).is_true()
	(_node.session_state(SESSION) as DaemonSession).trace.add_action("door_forced", _node.now(), value / 10.0)


func test_black_ice_lives_only_in_nightmare_tier() -> void:
	_setup()
	var plain := GrayNode.new()
	auto_free(plain)
	assert_bool(plain.has_black_ice()).is_false()
	assert_bool(_node.has_black_ice()).is_true()
	# Узел из Моста с tier NIGHTMARE поселяет Black ICE сам.
	var by_tier := GrayNode.new()
	by_tier.net = _server
	by_tier.recover([{"type": "node", "id": "node_07", "ver": 1, "data": {"tier": "NIGHTMARE", "lockdown_until": 0}}])
	auto_free(by_tier)
	assert_bool(by_tier.has_black_ice()).is_true()
	var std := GrayNode.new()
	std.net = _server
	std.recover([{"type": "node", "id": "node_07", "ver": 1, "data": {"tier": "STANDARD", "lockdown_until": 0}}])
	auto_free(std)
	assert_bool(std.has_black_ice()).is_false()


func test_hunt_starts_at_trace_level_and_marks_session_hunted() -> void:
	_setup({"hunt_speed": 0.2})  # медленный охотник: ловит нескоро
	await _bot_in_node_with_trace(60.0)
	assert_bool(await _wait_for(func(): return "hunt" in _kinds())).is_true()
	var hunt: Dictionary = _events.filter(func(e): return e["kind"] == "hunt")[0]
	assert_bool(hunt["on"]).is_true()
	assert_str(hunt["session"]).is_equal(SESSION)
	var black := _node.ices().filter(func(i: IceNode): return i.brain.is_black())[0] as IceNode
	assert_bool(black.brain.is_hunting(SESSION)).is_true()


func test_black_ice_catch_is_flatline_dead_deck_stays_protected_goes_home() -> void:
	_setup({"hunt_speed": 8.0})
	await _bot_in_node_with_trace(60.0)
	assert_bool(await _wait_for(func(): return not _bot.result.is_empty())).is_true()
	assert_str(_bot.result).is_equal("flatline")
	assert_bool(await _wait_for(func(): return "finished" in _kinds())).is_true()
	assert_array(_kinds()).contains(["flatline"])
	assert_array(_kinds()).not_contains(["ice_eject"])
	assert_str(str(_session_data()["outcome"])).is_equal("black_ice")
	assert_bool(_session_data().get("disconnect", false)).is_false()
	assert_str(_owner(DEAD_DECK)).is_equal("node:" + NODE)  # мёртвая дека — в узле, её может подобрать другой
	assert_str(_owner(PROTECTED)).is_equal("outbox:KEY_ALICE")  # защищённый демон уходит на телефон
	# Код ничего не помечает мёртвым: в документе сессии нет «dead»/«killed», только закрытая сессия с исходом.
	assert_bool(_session_data().has("dead")).is_false()


func test_flatline_waits_for_master_when_enabled_then_approve() -> void:
	_setup({"hunt_speed": 8.0})
	_bridge.doc("settings", "global")["data"]["await_flatline"] = 1
	await _bot_in_node_with_trace(60.0)
	assert_bool(await _wait_for(func(): return "waiting_master" in _kinds())).is_true()
	assert_bool(await _wait_for(func(): return _bridge.gate_calls.get("flatline:" + SESSION, 0) >= 2, 10.0)).is_true()  # опрос идёт
	assert_str(str(_session_data()["state"])).is_equal("active")  # исход не применён, пока мастер не решил
	assert_array(_kinds()).not_contains(["finished"])
	_bridge.decide_gate("flatline", SESSION, "approve")
	assert_bool(await _wait_for(func(): return "finished" in _kinds(), 10.0)).is_true()
	assert_str(str(_session_data()["outcome"])).is_equal("black_ice")
	assert_str(_owner(DEAD_DECK)).is_equal("node:" + NODE)


func test_flatline_denied_by_master_becomes_soft_outcome() -> void:
	_setup({"hunt_speed": 8.0})
	_bridge.doc("settings", "global")["data"]["await_flatline"] = 1
	await _bot_in_node_with_trace(60.0)
	assert_bool(await _wait_for(func(): return "waiting_master" in _kinds())).is_true()
	_bridge.decide_gate("flatline", SESSION, "deny")
	assert_bool(await _wait_for(func(): return "finished" in _kinds(), 10.0)).is_true()
	assert_str(str(_session_data()["outcome"])).is_equal("soft_ice")
	assert_str(_owner(DEAD_DECK)).is_equal("outbox:KEY_ALICE")  # пощадили: дека не мёртвая


func test_emergency_exit_under_hunt_burns_deck_but_not_protected() -> void:
	_setup({"hunt_speed": 0.2})
	await _bot_in_node_with_trace(60.0)
	assert_bool(await _wait_for(func(): return "hunt" in _kinds())).is_true()
	assert_bool(_bot.net.request_exit(ExitLogic.REASON_HEADSET_OFF)).is_true()
	assert_bool(await _wait_for(func(): return "finished" in _kinds())).is_true()
	assert_str(str(_session_data()["outcome"])).is_equal("emergency")
	assert_str(_owner(DEAD_DECK)).is_equal("burned:" + SESSION)
	assert_str(_owner(PROTECTED)).is_equal("outbox:KEY_ALICE")


func test_emergency_exit_without_hunt_keeps_deck() -> void:
	_setup({"hunt_speed": 0.2})
	_bot.start(_cfg, BotClient.Scenario.LOITER)
	assert_bool(await _wait_for(func(): return _node.session_state(SESSION) != null)).is_true()
	assert_bool(await _wait_for(func(): return _bot.net.is_connected_to_world)).is_true()
	assert_bool(_bot.net.request_exit(ExitLogic.REASON_HEADSET_OFF)).is_true()
	assert_bool(await _wait_for(func(): return "finished" in _kinds())).is_true()
	assert_str(_owner(DEAD_DECK)).is_equal("outbox:KEY_ALICE")
	assert_array(_kinds()).not_contains(["hunt"])


## Бот-сценарий «попался Black ICE»: Black ICE видит бота сам (зрение), trace не трогаем.
func test_bot_caught_by_black_ice_by_sight() -> void:
	_setup({}, false)
	_bot.start(_cfg, BotClient.Scenario.BLACK_RUN)
	assert_bool(await _wait_for(func(): return not _bot.result.is_empty(), 60.0)).is_true()
	assert_str(_bot.result).is_equal("flatline")
	assert_bool(await _wait_for(func(): return "finished" in _kinds())).is_true()
	assert_str(str(_session_data()["outcome"])).is_equal("black_ice")
	assert_str(_owner(DEAD_DECK)).is_equal("node:" + NODE)


## Узел без Black ICE: trace 100 — выброс Soft ICE, а не флэтлайн.
func test_trace_100_without_black_ice_is_soft_eject() -> void:
	_setup()
	_node.queue_free_black_for_test()
	assert_bool(_node.has_black_ice()).is_false()
	await _bot_in_node_with_trace(100.0)
	assert_bool(await _wait_for(func(): return "finished" in _kinds())).is_true()
	assert_array(_kinds()).contains(["ice_eject"])
	assert_array(_kinds()).not_contains(["flatline"])
	assert_str(str(_session_data()["outcome"])).is_equal("soft_ice")


func test_outcome_plan_marks_disconnect_flatline() -> void:
	var plan := GrayNode.outcome_plan({"reason": "flatline", "disconnect": true})
	assert_str(plan["outcome"]).is_equal("black_ice")
	assert_bool(plan["disconnect"]).is_true()
	assert_bool(GrayNode.outcome_plan({"reason": "flatline"})["disconnect"]).is_false()


## Ждём мастера: бот уже во флэтлайне, ожидание идёт.
func _flatline_waiting(extra: Dictionary = {"hunt_speed": 8.0}) -> void:
	_setup(extra)
	_bridge.doc("settings", "global")["data"]["await_flatline"] = 1
	await _bot_in_node_with_trace(60.0)
	assert_bool(await _wait_for(func(): return "waiting_master" in _kinds())).is_true()


func test_restart_during_master_wait_keeps_flatline_and_finishes_once() -> void:
	await _flatline_waiting()
	# Пометка в Мосте записана ДО ожидания.
	assert_bool(await _wait_for(func(): return (_session_data().get("world", {}) as Dictionary).get("finish", "") == "flatline")).is_true()
	assert_str(str(_session_data()["state"])).is_equal("active")
	_kill_server()
	_boot()
	assert_bool(await _wait_for(func(): return _node.synced)).is_true()
	assert_array(_node.recovered_flatlines).is_equal([SESSION])
	assert_array(_node.recovered_sessions).is_empty()  # окна возврата с emergency нет
	assert_bool(await _wait_for(func(): return "waiting_master" in _kinds())).is_true()
	assert_str(str(_session_data()["state"])).is_equal("active")
	_bridge.decide_gate("flatline", SESSION, "approve")
	assert_bool(await _wait_for(func(): return "finished" in _kinds(), 10.0)).is_true()
	assert_str(str(_session_data()["outcome"])).is_equal("black_ice")
	assert_int(_bridge.finish_calls).is_equal(1)
	assert_array(_bridge.finish_attempts.map(func(a): return a["outcome"])).is_equal(["black_ice"])
	assert_str(_owner(DEAD_DECK)).is_equal("node:" + NODE)


func test_return_of_player_during_master_wait_is_refused() -> void:
	await _flatline_waiting()
	var second := BotClient.new()
	_croot.add_child(second)
	second.start(_cfg, BotClient.Scenario.LOITER)
	await get_tree().create_timer(3.0).timeout
	assert_bool(second.net.is_connected_to_world).is_false()
	assert_bool(_server.has_avatar(SESSION)).is_false()
	_bridge.decide_gate("flatline", SESSION, "approve")
	assert_bool(await _wait_for(func(): return "finished" in _kinds(), 10.0)).is_true()
	assert_array(_bridge.finish_attempts.map(func(a): return a["outcome"])).is_equal(["black_ice"])
	assert_str(str(_session_data()["outcome"])).is_equal("black_ice")
	await second.net.drop()
	# Сессия закрыта: узел снова в доступном состоянии (_finishing снят) — второй вход не заблокирован самим узлом.
	assert_bool(_node.join_blocked(SESSION)).is_false()


func test_bridge_outage_during_master_wait_does_not_approve() -> void:
	await _flatline_waiting()
	_bridge.gate_offline = true
	await get_tree().create_timer(3.5).timeout
	assert_str(str(_session_data()["state"])).is_equal("active")
	assert_array(_bridge.finish_attempts).is_empty()  # самовольного исхода нет
	_bridge.gate_offline = false
	_bridge.decide_gate("flatline", SESSION, "deny")
	assert_bool(await _wait_for(func(): return "finished" in _kinds(), 10.0)).is_true()
	assert_str(str(_session_data()["outcome"])).is_equal("soft_ice")
	assert_str(_owner(DEAD_DECK)).is_equal("outbox:KEY_ALICE")
