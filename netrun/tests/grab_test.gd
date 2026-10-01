extends GdUnitTestSuite
## Взятие объекта через сервер: клиент просит, решает сервер. Сервер и клиенты в одном процессе (как net_reconnect_test).

static var _next_port := 18391

var _server: NetServer
var _alice: NetClient
var _bob: NetClient
var _root: Node


func _add_side(name: String) -> Node:
	var n := Node.new()
	n.name = name
	_root.add_child(n)
	get_tree().set_multiplayer(SceneMultiplayer.new(), n.get_path())
	return n


func before_test() -> void:
	_root = Node.new()
	_root.name = "GrabTestRoot"
	add_child(_root)
	var cfg := NetConfig.new()
	cfg.port = _next_port
	_next_port += 1
	_server = NetServer.new()
	_add_side("S").add_child(_server)
	assert_int(_server.start(cfg, DictTokenVerifier.new({"tok-a": "alice", "tok-b": "bob"}))).is_equal(OK)
	_alice = _client("A", cfg, "tok-a")
	_bob = _client("B", cfg, "tok-b")


func _client(name: String, cfg: NetConfig, token: String) -> NetClient:
	var c := NetClient.new()
	_add_side(name).add_child(c)
	var own := NetConfig.new()
	own.port = cfg.port
	own.token = token
	c.start_client(own)
	return c


func after_test() -> void:
	await _alice.drop()
	await _bob.drop()
	_server.stop_net()
	_root.queue_free()


func _wait_for(cond: Callable, sec: float = 5.0) -> bool:
	var t := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _both_online() -> bool:
	return await _wait_for(func(): return _alice.is_connected_to_world and _bob.is_connected_to_world)


func test_server_confirms_grab_and_records_holder() -> void:
	assert_bool(await _both_online()).is_true()
	var got: Array[String] = []
	_alice.grab_confirmed.connect(func(id): got.append(id))
	assert_str(_server.holder_of(NetConfig.PICKUP_ID)).is_empty()
	assert_bool(_alice.request_grab(NetConfig.PICKUP_ID)).is_true()
	assert_bool(await _wait_for(func(): return got.size() == 1)).is_true()
	assert_str(got[0]).is_equal(NetConfig.PICKUP_ID)
	assert_str(_server.holder_of(NetConfig.PICKUP_ID)).is_equal("alice")


func test_second_player_is_denied_while_held() -> void:
	assert_bool(await _both_online()).is_true()
	var ok: Array[String] = []
	_alice.grab_confirmed.connect(func(id): ok.append(id))
	_alice.request_grab(NetConfig.PICKUP_ID)
	assert_bool(await _wait_for(func(): return ok.size() == 1)).is_true()
	var denied: Array[String] = []
	_bob.grab_denied.connect(func(_id, reason): denied.append(reason))
	_bob.request_grab(NetConfig.PICKUP_ID)
	assert_bool(await _wait_for(func(): return denied.size() == 1)).is_true()
	assert_str(denied[0]).is_equal(WorldMsg.REASON_HELD)
	assert_str(_server.holder_of(NetConfig.PICKUP_ID)).is_equal("alice")


func test_unknown_object_is_denied() -> void:
	assert_bool(await _both_online()).is_true()
	var denied: Array[String] = []
	_alice.grab_denied.connect(func(_id, reason): denied.append(reason))
	_alice.request_grab("no_such_object")
	assert_bool(await _wait_for(func(): return denied.size() == 1)).is_true()
	assert_str(denied[0]).is_equal(WorldMsg.REASON_UNKNOWN)


func test_request_without_connection_is_not_sent() -> void:
	await _alice.drop()
	assert_bool(_alice.request_grab(NetConfig.PICKUP_ID)).is_false()
	assert_str(_server.holder_of(NetConfig.PICKUP_ID)).is_empty()


func test_scene_object_moves_only_after_confirm() -> void:
	var scene: Node3D = preload("res://client/rig_test_scene.gd").new()
	_root.add_child(scene)
	var requested: Array[String] = []
	scene.grab_requested.connect(func(id): requested.append(id))
	var near: Vector3 = scene.pickup.global_position
	assert_bool(scene.try_grab(near, 0.4, scene.rig.camera)).is_true()
	assert_array(requested).is_equal([NetConfig.PICKUP_ID])
	assert_bool(scene.held).is_false()
	assert_object(scene.pickup.get_parent()).is_same(scene)
	scene.deny_grab()
	assert_bool(scene.held).is_false()
	scene.try_grab(near, 0.4, scene.rig.camera)
	scene.confirm_grab()
	assert_bool(scene.held).is_true()
	assert_object(scene.pickup.get_parent()).is_same(scene.rig.camera)


func test_scene_far_object_is_not_requested() -> void:
	var scene: Node3D = preload("res://client/rig_test_scene.gd").new()
	_root.add_child(scene)
	assert_bool(scene.try_grab(Vector3(50, 0, 50), 3.0, scene.rig.camera)).is_false()
