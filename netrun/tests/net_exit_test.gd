extends GdUnitTestSuite
## Выход из забега по сети: manual_hold / headset_off, флаг охоты, обрыв ≠ выход до конца окна.
## Сервер и клиент в одном процессе, у каждого свой MultiplayerAPI (поддерево сцены).

static var _next_port := 17991
const GRACE := 1.5

var _server: NetServer
var _client: NetClient
var _root: Node


func before_test() -> void:
	var root := Node.new()
	root.name = "NetTestRoot"
	_root = root
	add_child(root)
	var sroot := Node.new()
	sroot.name = "S"
	var croot := Node.new()
	croot.name = "C"
	root.add_child(sroot)
	root.add_child(croot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), sroot.get_path())
	get_tree().set_multiplayer(SceneMultiplayer.new(), croot.get_path())
	var cfg := NetConfig.new()
	cfg.port = _next_port
	_next_port += 1
	cfg.grace_sec = GRACE
	cfg.token = "tok-a"
	_server = NetServer.new()
	sroot.add_child(_server)
	assert_int(_server.start(cfg, DictTokenVerifier.new({"tok-a": "alice", "tok-b": "bob"}))).is_equal(OK)
	_client = NetClient.new()
	croot.add_child(_client)
	_client.start_client(cfg)


func after_test() -> void:
	await _client.drop()
	_server.stop_net()
	_root.queue_free()


func _wait_for(cond: Callable, sec: float = 5.0) -> bool:
	var t := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


var _events: Array = []


func _on_exit(ev: Dictionary) -> void:
	_events.append(ev)


func _ready_pair() -> void:
	_events = []
	_server.exit_event.connect(_on_exit)
	assert_bool(await _wait_for(func(): return _server.peer_of("alice") != -1 and _client.is_connected_to_world)).is_true()


func test_manual_hold_exit_event_without_hunt() -> void:
	await _ready_pair()
	assert_bool(_client.request_exit(ExitLogic.REASON_MANUAL_HOLD)).is_true()
	assert_bool(await _wait_for(func(): return _events.size() == 1)).is_true()
	assert_str(_events[0]["reason"]).is_equal("manual_hold")
	assert_str(_events[0]["session"]).is_equal("alice")
	assert_bool(_events[0]["deck_burned"]).is_false()
	assert_bool(_server.has_avatar("alice")).is_false()


func test_headset_off_under_hunt_burns_deck() -> void:
	await _ready_pair()
	_server.set_under_hunt("alice", true)
	_client.request_exit(ExitLogic.REASON_HEADSET_OFF)
	assert_bool(await _wait_for(func(): return _events.size() == 1)).is_true()
	assert_str(_events[0]["reason"]).is_equal("headset_off")
	assert_bool(_events[0]["under_hunt"]).is_true()
	assert_bool(_events[0]["deck_burned"]).is_true()


func test_drop_is_not_exit_until_grace_ends() -> void:
	await _ready_pair()
	await _client.drop()
	assert_bool(await _wait_for(func(): return _server.peer_of("alice") == -1)).is_true()
	await get_tree().create_timer(0.5).timeout
	assert_int(_events.size()).is_equal(0)
	assert_bool(_server.has_avatar("alice")).is_true()
	assert_bool(await _wait_for(func(): return _events.size() == 1, GRACE + 3.0)).is_true()
	assert_str(_events[0]["reason"]).is_equal("connection_lost")


func test_client_cannot_claim_connection_lost() -> void:
	await _ready_pair()
	_client.request_exit(ExitLogic.REASON_CONNECTION_LOST)
	await get_tree().create_timer(0.5).timeout
	assert_int(_events.size()).is_equal(0)
	assert_bool(_server.has_avatar("alice")).is_true()


func test_reconnect_within_grace_gives_no_exit_event() -> void:
	await _ready_pair()
	await _client.drop()
	assert_bool(await _wait_for(func(): return _server.peer_of("alice") == -1)).is_true()
	_client.reconnect()
	assert_bool(await _wait_for(func(): return _server.peer_of("alice") != -1)).is_true()
	await get_tree().create_timer(GRACE + 0.5).timeout
	assert_int(_events.size()).is_equal(0)
