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


func _connected_and_kicked() -> int:
	## Ждёт связь и обрывает её со стороны сервера (как пропавший Wi-Fi, но сразу); возвращает прежний peer id.
	assert_bool(await _wait_for(func(): return _server.peer_of("alice") != -1 and _client.is_connected_to_world)).is_true()
	var first_peer := _server.peer_of("alice")
	(_server.multiplayer as SceneMultiplayer).disconnect_peer(first_peer)
	assert_bool(await _wait_for(func(): return not _client.is_connected_to_world)).is_true()
	return first_peer


## V6а, пункт 8: настоящий клиент (ProtoClient) раньше после обрыва только писал net.disconnected и не возвращался;
## автопереподключение возвращает того же игрока, пока не вышло окно возврата сервера.
func test_auto_reconnect_returns_to_the_same_avatar() -> void:
	_client.auto_reconnect_sec = 0.3
	var seen := {"attempts": []}
	_client.reconnecting.connect(func(n: int): seen["attempts"].append(n))
	assert_bool(await _wait_for(func(): return _server.peer_of("alice") != -1 and _client.is_connected_to_world)).is_true()
	var avatar := _server.get_avatar("alice")
	var first_peer := await _connected_and_kicked()
	# клиент «вернулся» раньше, чем сервер дочитал оборвавшийся peer: ждём именно нового peer id, а не любого != -1
	assert_bool(await _wait_for(func(): return _client.is_connected_to_world and not _server.peer_of("alice") in [-1, first_peer], 5.0)).is_true()
	assert_object(_server.get_avatar("alice")).is_same(avatar)
	assert_array(seen["attempts"]).is_equal([1])


func test_no_auto_reconnect_by_default() -> void:
	assert_float(_client.auto_reconnect_sec).is_equal(0.0)
	await _connected_and_kicked()
	await get_tree().create_timer(1.0).timeout
	assert_bool(_client.is_connected_to_world).is_false()


func test_stop_reconnect_keeps_client_offline() -> void:
	_client.auto_reconnect_sec = 0.3
	var first_peer := await _connected_and_kicked()
	_client.stop_reconnect()  # забег закончился или игрок вышел сам: сервер всё равно не пустит
	await get_tree().create_timer(1.2).timeout
	assert_bool(_client.is_connected_to_world).is_false()
	assert_bool(_server.peer_of("alice") in [-1, first_peer]).is_true()  # нового соединения нет


func test_reconnect_gives_up_after_attempts() -> void:
	_client.auto_reconnect_sec = 0.2
	_client.auto_reconnect_attempts = 2
	var seen := {"gave_up": false, "attempts": []}
	_client.reconnect_gave_up.connect(func(): seen["gave_up"] = true)
	_client.reconnecting.connect(func(n: int): seen["attempts"].append(n))
	assert_bool(await _wait_for(func(): return _client.is_connected_to_world)).is_true()
	_client.config.token = "nope"  # сервер отвечает отказом: попытки идут быстро
	await _connected_and_kicked()
	assert_bool(await _wait_for(func(): return seen["gave_up"], 8.0)).is_true()
	assert_array(seen["attempts"]).is_equal([1, 2])
	assert_bool(_client.is_connected_to_world).is_false()
	assert_bool(_server.has_avatar("nope")).is_false()
