extends GdUnitTestSuite
## Телепорт по сети: клиент просит (WorldMsg.TELEPORT), решает сервер. Сервер и клиент в одном процессе, у каждого свой
## MultiplayerAPI (поддерево сцены), как в net_exit_test.gd. Правила — RigMath.teleport_verdict (дальность, перезарядка, тоннель, комната).

static var _next_port := 19191
const SESSION := "alice"

var _server: NetServer
var _client: NetClient
var _root: Node
var _denied: Array = []   # [{reason, pos, left}]


func before_test() -> void:
	_root = Node.new()
	_root.name = "TpTestRoot"
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
	cfg.token = "tok-a"
	_server = NetServer.new()
	sroot.add_child(_server)
	assert_int(_server.start(cfg, DictTokenVerifier.new({"tok-a": SESSION}))).is_equal(OK)
	_client = NetClient.new()
	croot.add_child(_client)
	_denied = []
	_client.teleport_denied.connect(func(reason: String, pos: Vector3, left: float): _denied.append({"reason": reason, "pos": pos, "left": left}))
	_client.start_client(cfg)
	assert_bool(await _wait_for(func(): return _client.is_connected_to_world and _server.has_avatar(SESSION))).is_true()


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


func _sleep(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _pos() -> Vector3:
	return _server.get_avatar(SESSION).position


func _at(p: Vector3) -> bool:
	return NodeLayout.flat_distance(_pos(), p) < 0.01


func test_teleport_in_range_moves_avatar_at_once() -> void:
	var target := NodeLayout.SPAWN + Vector3(3, 0, 0)
	assert_bool(_client.request_teleport(target)).is_true()
	assert_bool(await _wait_for(func(): return _at(target))).is_true()
	assert_array(_denied).is_empty()
	assert_int(_server.teleport_count(SESSION)).is_equal(1)


func test_teleport_beyond_range_is_denied_and_avatar_stays() -> void:
	assert_bool(_client.request_teleport(NodeLayout.SPAWN + Vector3(7.5, 0, 0))).is_true()
	assert_bool(await _wait_for(func(): return _denied.size() == 1)).is_true()
	assert_str(_denied[0]["reason"]).is_equal(WorldMsg.REASON_RANGE)
	assert_float(NodeLayout.flat_distance(_denied[0]["pos"], NodeLayout.SPAWN)).is_less(0.01)   # ответ несёт позицию сервера
	assert_bool(_at(NodeLayout.SPAWN)).is_true()
	assert_int(_server.teleport_count(SESSION)).is_equal(0)


func test_server_tolerates_small_overshoot_but_not_more() -> void:
	# Допуск 0,5 м на запаздывание позы: предел сервера + 0,4 проходит, + 0,6 нет.
	var near := NodeLayout.SPAWN + Vector3(RigMath.TELEPORT_RANGE_LIMIT + 0.4, 0, 0)
	assert_bool(_client.request_teleport(near)).is_true()
	assert_bool(await _wait_for(func(): return _at(near))).is_true()
	await _sleep(RigMath.TELEPORT_COOLDOWN_LIMIT + 0.05)
	assert_bool(_client.request_teleport(near + Vector3(-RigMath.TELEPORT_RANGE_LIMIT - 0.6, 0, 0))).is_true()
	assert_bool(await _wait_for(func(): return _denied.size() == 1)).is_true()
	assert_str(_denied[0]["reason"]).is_equal(WorldMsg.REASON_RANGE)


func test_second_teleport_too_soon_is_denied_then_allowed_after_cooldown() -> void:
	var a := NodeLayout.SPAWN + Vector3(3, 0, 0)
	assert_bool(_client.request_teleport(a)).is_true()
	assert_bool(await _wait_for(func(): return _at(a))).is_true()
	assert_bool(_client.request_teleport(a + Vector3(0, 0, -3))).is_true()
	assert_bool(await _wait_for(func(): return _denied.size() == 1)).is_true()
	assert_str(_denied[0]["reason"]).is_equal(WorldMsg.REASON_COOLDOWN)
	assert_float(_denied[0]["left"]).is_greater(0.0)
	assert_bool(_at(a)).is_true()
	await _sleep(RigMath.TELEPORT_COOLDOWN_LIMIT + 0.05)
	var b := a + Vector3(0, 0, -3)
	assert_bool(_client.request_teleport(b)).is_true()
	assert_bool(await _wait_for(func(): return _at(b))).is_true()
	assert_int(_server.teleport_count(SESSION)).is_equal(2)


func test_teleport_in_tunnel_is_denied() -> void:
	_server.set_node(SESSION, NetServer.TUNNEL_NODE)
	assert_bool(_client.request_teleport(NodeLayout.SPAWN + Vector3(2, 0, 0))).is_true()
	assert_bool(await _wait_for(func(): return _denied.size() == 1)).is_true()
	assert_str(_denied[0]["reason"]).is_equal(WorldMsg.REASON_TUNNEL)
	assert_bool(_at(NodeLayout.SPAWN)).is_true()


func test_teleport_outside_the_room_is_denied() -> void:
	var edge := Vector3(-5, 0, -1)
	assert_bool(_client.request_teleport(edge)).is_true()
	assert_bool(await _wait_for(func(): return _at(edge))).is_true()
	await _sleep(RigMath.TELEPORT_COOLDOWN_LIMIT + 0.05)
	assert_bool(_client.request_teleport(Vector3(-8.6, 0, -1))).is_true()
	assert_bool(await _wait_for(func(): return _denied.size() == 1)).is_true()
	assert_str(_denied[0]["reason"]).is_equal(WorldMsg.REASON_ROOM)
	assert_bool(_at(edge)).is_true()


func test_stale_pose_after_teleport_does_not_drag_avatar_back() -> void:
	# Раньше сервер считал допустимый сдвиг от времени последней позы: после прыжка запоздавшая поза со старого места
	# (до 1 с давности — до 8,3 м) втянула бы аватар обратно. Телепорт сбрасывает базовую точку.
	assert_bool(_client.send_pos(NodeLayout.SPAWN)).is_true()
	await _sleep(0.5)
	var target := NodeLayout.SPAWN + Vector3(3.5, 0, 0)
	assert_bool(_client.request_teleport(target)).is_true()
	assert_bool(await _wait_for(func(): return _at(target))).is_true()
	assert_bool(_client.send_pos(NodeLayout.SPAWN)).is_true()   # «старая» поза приходит позже телепорта
	await _sleep(0.3)
	assert_float(NodeLayout.flat_distance(_pos(), target)).is_less(0.8)


func test_pose_stream_still_obeys_speed_limit() -> void:
	# Телепорт не отменяет предел скорости потока поз: прыжок позой на 5 м за один пакет сервер урезает.
	assert_bool(_client.send_pos(NodeLayout.SPAWN)).is_true()
	await _sleep(0.1)
	assert_bool(_client.send_pos(NodeLayout.SPAWN + Vector3(5, 0, 0))).is_true()
	await _sleep(0.2)
	assert_float(NodeLayout.flat_distance(_pos(), NodeLayout.SPAWN)).is_less(3.0)


func test_avatar_entry_carries_jump_counter_only_after_a_teleport() -> void:
	var e0 := _server.avatar_entry(SESSION)
	assert_int(e0.size()).is_equal(3)
	assert_int(e0[0]).is_equal(_server.avatar_id(SESSION))
	var target := NodeLayout.SPAWN + Vector3(0, 0, -3)
	assert_bool(_client.request_teleport(target)).is_true()
	assert_bool(await _wait_for(func(): return _at(target))).is_true()
	var e1 := _server.avatar_entry(SESSION)
	assert_int(e1.size()).is_equal(4)
	assert_int(e1[3]).is_equal(1)
	assert_float(e1[2]).is_equal_approx(-4.0, 0.01)


func test_server_side_teleport_also_counts_as_a_jump() -> void:
	# Переход через портал (NetServer.teleport) — тоже скачок для тех, кто видит аватар.
	_server.teleport(SESSION, Vector3(2, 0, -3))
	assert_int(_server.teleport_count(SESSION)).is_equal(1)
	assert_bool(_at(Vector3(2, 0, -3))).is_true()


func test_teleport_state_is_forgotten_when_the_avatar_leaves() -> void:
	var target := NodeLayout.SPAWN + Vector3(2, 0, 0)
	assert_bool(_client.request_teleport(target)).is_true()
	assert_bool(await _wait_for(func(): return _at(target))).is_true()
	_server.end_session(SESSION, ExitLogic.REASON_CLEAN)
	assert_bool(await _wait_for(func(): return not _server.has_avatar(SESSION))).is_true()
	assert_int(_server.teleport_count(SESSION)).is_equal(0)
