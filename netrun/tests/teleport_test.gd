extends GdUnitTestSuite
## Телепорт по сети: клиент просит (WorldMsg.TELEPORT), решает сервер. Сервер и клиент в одном процессе, у каждого свой
## MultiplayerAPI (поддерево сцены), как в net_exit_test.gd. Правила — RigMath.teleport_verdict (дальность, перезарядка, тоннель, комната).

static var _next_port := 19191
const SESSION := "alice"

var _server: NetServer
var _client: NetClient
var _root: Node
var _denied: Array = []   # [{reason, pos, left}]
var _cfg_port := 0


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
	_cfg_port = cfg.port
	_server = NetServer.new()
	sroot.add_child(_server)
	assert_int(_server.start(cfg, DictTokenVerifier.new({"tok-a": SESSION, "tok-b": "bob"}))).is_equal(OK)
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
	var target := _c(10, 13)   # центр клетки в 3 м от входа
	assert_bool(_client.request_teleport(target)).is_true()
	assert_bool(await _wait_for(func(): return _at(target))).is_true()
	assert_array(_denied).is_empty()
	assert_int(_server.teleport_count(SESSION)).is_equal(1)


## Центр клетки (ix; iz) — куда прыгает игрок (NodeGrid).
func _c(ix: int, iz: int) -> Vector3:
	return NodeGrid.center(Vector2i(ix, iz))


func test_arbitrary_point_is_snapped_to_the_cell_center() -> void:
	assert_bool(_client.request_teleport(Vector3(2.9, 0, -0.9))).is_true()   # внутри клетки (10;13), не в центре
	assert_bool(await _wait_for(func(): return _at(_c(10, 13)))).is_true()
	assert_array(_denied).is_empty()


func test_cell_of_a_pillar_is_denied_as_cell() -> void:
	var from := _c(10, 13)
	assert_bool(_client.request_teleport(from)).is_true()
	assert_bool(await _wait_for(func(): return _at(from))).is_true()
	await _sleep(RigMath.TELEPORT_COOLDOWN_LIMIT + 0.05)
	assert_bool(_client.request_teleport(_c(10, 9))).is_true()   # колонна (3;−5): клетки x 10–11, z 8–9
	assert_bool(await _wait_for(func(): return _denied.size() == 1)).is_true()
	assert_str(_denied[0]["reason"]).is_equal(WorldMsg.REASON_CELL)
	assert_bool(_at(from)).is_true()


func test_jump_through_a_pillar_is_denied_as_blocked() -> void:
	var from := _c(10, 12)
	assert_bool(_client.request_teleport(from)).is_true()
	assert_bool(await _wait_for(func(): return _at(from))).is_true()
	await _sleep(RigMath.TELEPORT_COOLDOWN_LIMIT + 0.05)
	assert_bool(_client.request_teleport(_c(10, 7))).is_true()   # 5 клеток вдоль колонны: линия через её клетки
	assert_bool(await _wait_for(func(): return _denied.size() == 1)).is_true()
	assert_str(_denied[0]["reason"]).is_equal(WorldMsg.REASON_BLOCKED)
	assert_bool(_at(from)).is_true()


func test_cell_too_far_is_denied_as_range_and_a_cell_with_the_slack_passes() -> void:
	# Допуск клеток 0,5 м: ровно 5 клеток (5,0 м) — проходит, 6 клеток — дальность. Вход — клетка (7;13).
	var far := _c(12, 13)
	assert_bool(_client.request_teleport(far)).is_true()
	assert_bool(await _wait_for(func(): return _at(far))).is_true()
	await _sleep(RigMath.TELEPORT_COOLDOWN_LIMIT + 0.05)
	assert_bool(_client.request_teleport(_c(6, 13))).is_true()   # от (12;13) до (6;13) — 6 клеток
	assert_bool(await _wait_for(func(): return _denied.size() == 1)).is_true()
	assert_str(_denied[0]["reason"]).is_equal(WorldMsg.REASON_RANGE)
	assert_bool(_at(far)).is_true()


func test_cell_of_another_avatar_in_the_same_node_is_denied() -> void:
	# Второй аватар стоит в клетке (10;13) — туда нельзя; в соседнюю — можно.
	var other := "bob"
	var broot := Node.new()
	broot.name = "B"
	_root.add_child(broot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), broot.get_path())
	var bob := NetClient.new()
	broot.add_child(bob)
	var cfg := NetConfig.new()
	cfg.port = _cfg_port
	cfg.token = "tok-b"
	assert_int(bob.start_client(cfg)).is_equal(OK)
	assert_bool(await _wait_for(func(): return _server.has_avatar(other))).is_true()
	_server.teleport(other, _c(10, 13))
	assert_bool(_client.request_teleport(_c(10, 13))).is_true()
	assert_bool(await _wait_for(func(): return _denied.size() == 1)).is_true()
	assert_str(_denied[0]["reason"]).is_equal(WorldMsg.REASON_CELL)
	assert_bool(_at(NodeLayout.SPAWN)).is_true()
	await _sleep(RigMath.TELEPORT_COOLDOWN_LIMIT + 0.05)
	assert_bool(_client.request_teleport(_c(10, 12))).is_true()
	assert_bool(await _wait_for(func(): return _at(_c(10, 12)))).is_true()
	await bob.drop()


func test_teleport_beyond_range_is_denied_and_avatar_stays() -> void:
	assert_bool(_client.request_teleport(NodeLayout.SPAWN + Vector3(7.5, 0, 0))).is_true()
	assert_bool(await _wait_for(func(): return _denied.size() == 1)).is_true()
	assert_str(_denied[0]["reason"]).is_equal(WorldMsg.REASON_RANGE)
	assert_float(NodeLayout.flat_distance(_denied[0]["pos"], NodeLayout.SPAWN)).is_less(0.01)   # ответ несёт позицию сервера
	assert_bool(_at(NodeLayout.SPAWN)).is_true()
	assert_int(_server.teleport_count(SESSION)).is_equal(0)


func test_second_teleport_too_soon_is_denied_then_allowed_after_cooldown() -> void:
	var a := _c(10, 13)
	assert_bool(_client.request_teleport(a)).is_true()
	assert_bool(await _wait_for(func(): return _at(a))).is_true()
	assert_bool(_client.request_teleport(_c(10, 10))).is_true()
	assert_bool(await _wait_for(func(): return _denied.size() == 1)).is_true()
	assert_str(_denied[0]["reason"]).is_equal(WorldMsg.REASON_COOLDOWN)
	assert_float(_denied[0]["left"]).is_greater(0.0)
	assert_bool(_at(a)).is_true()
	await _sleep(RigMath.TELEPORT_COOLDOWN_LIMIT + 0.05)
	var b := _c(10, 10)
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
	var edge := _c(3, 13)   # центр клетки у края; (−5; −1) привязался бы к ней же
	assert_bool(_client.request_teleport(edge)).is_true()
	assert_bool(await _wait_for(func(): return _at(edge))).is_true()
	await _sleep(RigMath.TELEPORT_COOLDOWN_LIMIT + 0.05)
	assert_bool(_client.request_teleport(Vector3(-8.6, 0, -1))).is_true()
	assert_bool(await _wait_for(func(): return _denied.size() == 1)).is_true()
	assert_str(_denied[0]["reason"]).is_equal(WorldMsg.REASON_ROOM)
	assert_bool(_at(edge)).is_true()


func test_vault_pad_still_snaps_after_the_cell_is_checked() -> void:
	# Площадка у хранилища: клетка проверяется как обычно (центр клетки), затем точка переставляется на площадку.
	_server.teleport_snap = func(_s: String, to: Vector3) -> Dictionary: return NodeLayout.snap_to_vault_pad(to, [NodeLayout.SHARD_POS])
	assert_bool(_client.request_teleport(_c(7, 9))).is_true()   # далеко от хранилища (−1; −9): без привязки
	assert_bool(await _wait_for(func(): return _at(_c(7, 9)))).is_true()
	await _sleep(RigMath.TELEPORT_COOLDOWN_LIMIT + 0.05)
	assert_bool(_client.request_teleport(_c(7, 6))).is_true()   # 1,6 м от хранилища — в радиусе привязки
	var pad := NodeLayout.vault_pad(NodeLayout.SHARD_POS)
	assert_bool(await _wait_for(func(): return _at(pad))).is_true()
	assert_array(_denied).is_empty()


func test_stale_pose_after_teleport_does_not_drag_avatar_back() -> void:
	# Раньше сервер считал допустимый сдвиг от времени последней позы: после прыжка запоздавшая поза со старого места
	# (до 1 с давности — до 8,3 м) втянула бы аватар обратно. Телепорт сбрасывает базовую точку.
	assert_bool(_client.send_pos(NodeLayout.SPAWN)).is_true()
	await _sleep(0.5)
	var target := _c(10, 13)
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
	var target := _c(7, 10)
	assert_bool(_client.request_teleport(target)).is_true()
	assert_bool(await _wait_for(func(): return _at(target))).is_true()
	var e1 := _server.avatar_entry(SESSION)
	assert_int(e1.size()).is_equal(4)
	assert_int(e1[3]).is_equal(1)
	assert_float(e1[2]).is_equal_approx(-3.5, 0.01)


func test_server_side_teleport_also_counts_as_a_jump() -> void:
	# Переход через портал (NetServer.teleport) — тоже скачок для тех, кто видит аватар.
	_server.teleport(SESSION, Vector3(2, 0, -3))
	assert_int(_server.teleport_count(SESSION)).is_equal(1)
	assert_bool(_at(Vector3(2, 0, -3))).is_true()


func test_teleport_state_is_forgotten_when_the_avatar_leaves() -> void:
	var target := _c(9, 13)
	assert_bool(_client.request_teleport(target)).is_true()
	assert_bool(await _wait_for(func(): return _at(target))).is_true()
	_server.end_session(SESSION, ExitLogic.REASON_CLEAN)
	assert_bool(await _wait_for(func(): return not _server.has_avatar(SESSION))).is_true()
	assert_int(_server.teleport_count(SESSION)).is_equal(0)
