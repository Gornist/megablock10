extends GdUnitTestSuite
## Состояние очков по сети (P6): клиент -> сервер мира -> terminal.beat в фейковом Мосте. Всё в одном процессе.
## Терминал t03 — с сессией, t05 — без (очки на стойке ждут игрока): должен быть на связи, но без аватара.

static var _next_port := 18291
const BEAT_SEC := 0.3

var _root: Node
var _server: NetServer
var _bridge: FakeBridge
var _relay: TerminalBeatRelay
var _client: NetClient


func before_test() -> void:
	_root = Node.new()
	add_child(_root)
	var sroot := Node.new()
	sroot.name = "S"
	var croot := Node.new()
	croot.name = "C"
	_root.add_child(sroot)
	_root.add_child(croot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), sroot.get_path())
	get_tree().set_multiplayer(SceneMultiplayer.new(), croot.get_path())
	_bridge = FakeBridge.new()
	_server = NetServer.new()
	sroot.add_child(_server)
	_client = NetClient.new()
	croot.add_child(_client)


func after_test() -> void:
	await _client.drop()
	_server.stop_net()
	_root.queue_free()


func _start(token: String) -> NetConfig:
	var cfg := NetConfig.new()
	cfg.port = _next_port
	_next_port += 1
	cfg.beat_sec = BEAT_SEC
	cfg.token = token
	assert_int(_server.start(cfg, _bridge)).is_equal(OK)
	_relay = TerminalBeatRelay.new(_server, _bridge)
	_client.battery.provider = func(): return {"percent": 64, "charging": true}
	_client.start_client(cfg)
	return cfg


func _wait_for(cond: Callable, sec: float = 5.0) -> bool:
	var t := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func test_beat_reaches_bridge_from_terminal_with_session() -> void:
	_start("t03:token-t03")
	assert_bool(await _wait_for(func(): return _bridge.beat_count.get("t03", 0) >= 1)).is_true()
	var b: Dictionary = _bridge.last_beat["t03"]
	assert_int(b["battery"]).is_equal(64)
	assert_int(b["fps"]).is_greater_equal(0)
	assert_int(b["link"]).is_between(0, 100)
	assert_dict(_client.last_beat_sent).contains_keys(["term", "fps", "worst", "bat", "chg", "rtt"])
	assert_bool(_client.last_beat_sent["chg"]).is_true()
	assert_bool(_server.has_avatar("s_fake000000000001")).is_true()


func test_beat_from_idle_terminal_without_session() -> void:
	_start("t05:token-t03")
	assert_bool(await _wait_for(func(): return _bridge.beat_count.get("t05", 0) >= 1)).is_true()
	assert_array(_server.sessions()).is_empty()  # аватара нет
	assert_bool(_client.is_connected_to_world).is_true()
	assert_int(_bridge.doc(BridgeApi.T_TERMINAL, "t05")["data"]["battery"]).is_equal(64)


func test_beats_are_rate_limited_per_terminal() -> void:
	_start("t03:token-t03")
	assert_bool(await _wait_for(func(): return _bridge.beat_count.get("t03", 0) >= 1)).is_true()
	# Клиент шлёт сразу ещё пять состояний подряд: сервер пропускает не чаще раза в 0.8 периода.
	for i in 5:
		_client.send_beat()
	await get_tree().create_timer(0.1).timeout
	assert_int(_bridge.beat_count["t03"]).is_equal(1)
	await _wait_for(func(): return _bridge.beat_count["t03"] >= 2)  # следующий — по расписанию
	assert_bool(_bridge.beat_count["t03"] >= 2).is_true()


func test_wrong_token_rejected_no_beat() -> void:
	_start("t05:чужой")
	await get_tree().create_timer(0.8).timeout
	assert_bool(_client.is_connected_to_world).is_false()
	assert_bool(_bridge.beat_count.is_empty()).is_true()


func test_token_without_terminal_sends_no_beat() -> void:
	var cfg := NetConfig.from_args(PackedStringArray(["--token=t1"]))
	assert_str(cfg.terminal_id()).is_empty()
