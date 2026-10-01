extends GdUnitTestSuite
## Сервер и клиент в одном процессе, у каждого свой MultiplayerAPI (поддерево сцены).

static var _next_port := 17891
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


func test_default_grace_is_20_seconds() -> void:
	assert_float(NetConfig.DEFAULT_GRACE_SEC).is_equal(20.0)


func test_reconnect_within_grace_keeps_same_avatar() -> void:
	assert_bool(await _wait_for(func(): return _server.peer_of("alice") != -1 and _client.is_connected_to_world)).is_true()
	var avatar := _server.get_avatar("alice")
	var first_peer := _server.peer_of("alice")
	assert_str(str(avatar.get_path()).get_file()).is_equal("avatar_alice")
	await _client.drop()
	assert_bool(await _wait_for(func(): return _server.peer_of("alice") == -1)).is_true()
	assert_bool(_server.has_avatar("alice")).is_true()
	_client.reconnect()
	assert_bool(await _wait_for(func(): return _server.peer_of("alice") != -1)).is_true()
	assert_int(_server.peer_of("alice")).is_not_equal(first_peer)
	assert_object(_server.get_avatar("alice")).is_same(avatar)
	# таймер старого обрыва не должен убрать аватар
	await get_tree().create_timer(GRACE + 0.5).timeout
	assert_bool(_server.has_avatar("alice")).is_true()


func test_reconnect_after_grace_gives_new_avatar() -> void:
	assert_bool(await _wait_for(func(): return _server.peer_of("alice") != -1 and _client.is_connected_to_world)).is_true()
	var avatar := _server.get_avatar("alice")
	var avatar_id := avatar.get_instance_id()
	await _client.drop()
	assert_bool(await _wait_for(func(): return not _server.has_avatar("alice"), GRACE + 3.0)).is_true()
	_client.reconnect()
	assert_bool(await _wait_for(func(): return _server.peer_of("alice") != -1 and _client.is_connected_to_world)).is_true()
	assert_int(_server.get_avatar("alice").get_instance_id()).is_not_equal(avatar_id)


func test_bad_token_is_rejected() -> void:
	await _client.drop()
	_client.config.token = "nope"
	_client.reconnect()
	await get_tree().create_timer(1.0).timeout
	assert_bool(_server.has_avatar("nope")).is_false()
	assert_bool(_client.is_connected_to_world).is_false()
