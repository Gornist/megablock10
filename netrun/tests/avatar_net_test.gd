extends GdUnitTestSuite
## Поза тела чужого нетраннера по сети: клиент шлёт её в `pos` (поле `b`), сервер проверяет и пересылает в записи `av` (пятое поле) игрокам
## того же узла, приёмник рисует голову и руки (AvatarView.apply_pose). Кодек позы — avatar_body_test.gd. Сервер, GrayNode и боты — в одном
## процессе, у каждого свой MultiplayerAPI (поддерево сцены), как в multi_client_test.gd.

static var _next_port := 18791

var _root: Node
var _server: NetServer
var _node: GrayNode
var _bots: Array[BotClient] = []
var _sessions: Array[String] = []


func _start(count: int) -> void:
	_root = Node.new()
	_root.name = "AvatarNetRoot"
	add_child(_root)
	var sroot := Node.new()
	sroot.name = "S"
	_root.add_child(sroot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), sroot.get_path())
	var cfg := NetConfig.new()
	cfg.port = _next_port
	_next_port += 1
	var tokens := {}
	for i in count:
		tokens["tok%d" % i] = "s_bot%d" % i
		_sessions.append("s_bot%d" % i)
	_server = NetServer.new()
	sroot.add_child(_server)
	assert_int(_server.start(cfg, DictTokenVerifier.new(tokens))).is_equal(OK)
	_node = GrayNode.new()
	_node.ice_settings = {"sight_range": 0.5}
	sroot.add_child(_node)
	_node.start(_server)
	for i in count:
		var croot := Node.new()
		croot.name = "C%d" % i
		_root.add_child(croot)
		get_tree().set_multiplayer(SceneMultiplayer.new(), croot.get_path())
		var c := NetConfig.new()
		c.port = cfg.port
		c.token = "tok%d" % i
		var bot := BotClient.new()
		bot.loiter_center = Vector3(-6.0 + i * 1.2, 0, -2.0)
		croot.add_child(bot)
		bot.start(c, BotClient.Scenario.LOITER)
		_bots.append(bot)


func after_test() -> void:
	for b in _bots:
		if b.net != null:
			await b.net.drop()
	if _server != null:
		_server.stop_net()
	if _root != null:
		_root.queue_free()
	_bots.clear()
	_sessions.clear()
	_server = null
	_root = null


func _wait_for(cond: Callable, sec: float = 10.0) -> bool:
	var t := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _sleep(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _pose(head_y: float = 1.6, with_left: bool = true, with_right: bool = true) -> AvatarPose:
	var p := AvatarPose.new()
	p.head = Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.1, head_y, -0.2))
	if with_left:
		p.set_hand(AvatarPose.LEFT, Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(-0.25, 1.1, -0.45)), 0.3, 0.8)
	if with_right:
		p.set_hand(AvatarPose.RIGHT, Transform3D(Basis(Vector3.UP, -0.3), Vector3(0.3, 1.2, -0.5)), 1.0, 0.0)
	return p


## Сырая позиция с произвольным полем `b` (как мог бы прислать кривой или злой клиент).
func _send_raw(bot: BotClient, b: Variant) -> void:
	bot.net._send(WorldMsg.encode_fields(WorldMsg.POS, {"p": [-6.0, 0.0, -2.0], "b": b}), false)


func _head_y(session: String) -> float:
	return float(_server.pose_of(session)["h"][1])


# ---------------------------------------------------------------- сборка позы и сообщения

func test_from_world_subtracts_the_floor_point_and_skips_missing_hands() -> void:
	var floor_pt := Vector3(3.0, 0.0, -2.0)
	var head := Transform3D(Basis(Vector3.UP, 0.7) * 2.0, Vector3(3.2, 1.7, -2.3))  # масштаб в рамке не едет
	var right := {"frame": Transform3D(Basis.IDENTITY, Vector3(3.4, 1.1, -2.6)), "trigger": 0.4, "hold": 1.5}
	var pose := AvatarPose.from_world(head, floor_pt, [null, right])
	assert_vector(pose.head.origin).is_equal_approx(Vector3(0.2, 1.7, -0.3), Vector3.ONE * 0.0001)
	assert_float(pose.head.basis.get_scale().x).is_equal_approx(1.0, 0.001)
	assert_bool(pose.has_hand[AvatarPose.LEFT]).is_false()   # контроллера нет — руки нет
	assert_bool(pose.has_hand[AvatarPose.RIGHT]).is_true()
	assert_vector(pose.palm[AvatarPose.RIGHT].origin).is_equal_approx(Vector3(0.4, 1.1, -0.6), Vector3.ONE * 0.0001)
	assert_float(pose.hold[AvatarPose.RIGHT]).is_equal(1.0)  # сгиб ограничен 0..1
	var enc := pose.encode()
	assert_bool(enc.has("l")).is_false()
	assert_bool(enc.has("r")).is_true()


func test_pos_message_carries_the_pose_only_when_given() -> void:
	var plain := WorldMsg.decode(WorldMsg.encode_pos(Vector3(1, 0, 2)))
	assert_bool(plain.has("b")).is_false()
	var bytes := WorldMsg.encode_pos(Vector3(1, 0, 2), _pose())
	var msg := WorldMsg.decode(bytes)
	assert_bool(AvatarPose.decode(msg.get("b")) != null).is_true()
	print("[AVATAR-NET] pos с позой (обе руки): %d Б, без позы: %d Б" % [bytes.size(), WorldMsg.encode_pos(Vector3(1, 0, 2)).size()])
	assert_int(bytes.size()).is_less(300)


# ---------------------------------------------------------------- приёмник (без сети)

func test_remote_tracks_keep_the_pose_from_the_fifth_field() -> void:
	var rt := RemoteTracks.new()
	var b: Dictionary = _pose().encode()
	rt.on_avatars({"k": 1.0, "a": [[5, 1.0, 2.0, 0, b], [6, 0.0, 0.0]]}, 1.0)
	assert_bool(rt.poses.has("5")).is_true()
	assert_bool(rt.poses.has("6")).is_false()
	assert_vector(rt.poses["5"].head.origin).is_equal_approx(Vector3(0.1, 1.6, -0.2), Vector3.ONE * 0.002)
	# в следующем пакете позы нет — старая не залипает
	rt.on_avatars({"k": 1.05, "a": [[5, 1.0, 2.0], [6, 0.0, 0.0]]}, 1.05)
	assert_bool(rt.poses.has("5")).is_false()
	# мусор в пятом поле — позы нет, аватар на месте
	rt.on_avatars({"k": 1.1, "a": [[5, 1.0, 2.0, 0, {"h": [1, 2]}], [6, 0.0, 0.0]]}, 1.1)
	assert_bool(rt.poses.has("5")).is_false()
	assert_bool(rt.avatars.has("5")).is_true()
	# вышедший из узла забывается вместе с позой
	rt.on_avatars({"k": 1.15, "a": [[5, 1.0, 2.0, 0, b]]}, 1.15)
	rt.on_avatars({"k": 1.2, "a": []}, 1.2)
	assert_bool(rt.poses.is_empty()).is_true()


func test_scene_draws_the_body_from_the_pose_and_hides_it_without() -> void:
	var scene: Node3D = auto_free(preload("res://client/rig_test_scene.gd").new())
	add_child(scene)
	scene.apply_avatars({"k": 1.0, "a": [[3, -1.0, -3.0, 0, _pose().encode()]]})
	var av: AvatarView = scene.avatar_node("3")
	assert_bool(av.body.has_pose()).is_true()
	av.body._process(0.016)
	av._process(0.016)
	assert_bool(av.get_node("Model").visible).is_false()   # вместо runner.glb — голова и руки
	scene.apply_avatars({"k": 1.05, "a": [[3, -1.0, -3.0]]})  # сервер позу не прислал (клиент замолчал)
	assert_bool(av.body.has_pose()).is_false()
	av._process(0.016)
	assert_bool(av.get_node("Model").visible).is_true()


# ---------------------------------------------------------------- сервер: проверка и хранение

func test_server_keeps_a_valid_pose_and_puts_it_into_the_avatar_entry() -> void:
	_start(1)
	assert_bool(await _wait_for(func(): return _server.has_avatar(_sessions[0]))).is_true()
	assert_object(_server.pose_of(_sessions[0])).is_null()
	assert_int(_server.avatar_entry(_sessions[0]).size()).is_less(5)   # без позы запись прежняя: [id, x, z] и счётчик скачков, если бот прыгал
	_bots[0].net.send_pos(Vector3(-6, 0, -2), _pose())
	assert_bool(await _wait_for(func(): return _server.pose_of(_sessions[0]) != null)).is_true()
	var e := _server.avatar_entry(_sessions[0])
	assert_int(e.size()).is_equal(5)
	assert_int(e[3]).is_equal(_server.teleport_count(_sessions[0]))   # четвёртое поле есть всегда, когда есть поза
	assert_bool(AvatarPose.decode(e[4]) != null).is_true()


func test_server_drops_garbage_poses() -> void:
	_start(1)
	assert_bool(await _wait_for(func(): return _server.has_avatar(_sessions[0]))).is_true()
	var good: Array = _pose().encode()["h"]
	var bad: Array = [
		"мусор", 42, [1, 2, 3], {}, {"h": "x"}, {"h": [1, 2, 3]},                                  # не поза
		{"h": ["a", 1.6, 0, 0, 0, 0, 1]},                                                           # не числа
		{"h": [0, 5.0, 0, 0, 0, 0, 1]},                                                             # голова дальше 4 м от точки пола
		{"h": [0, 1.6, 0, 0, 0, 0, 0]},                                                             # нулевой кватернион
		{"l": good + [0.1, 0.1]},                                                                   # нет головы
	]
	for b in bad:
		_send_raw(_bots[0], b)
		await _sleep(0.05)
	await _sleep(0.15)
	assert_object(_server.pose_of(_sessions[0])).is_null()
	assert_int(_server.avatar_entry(_sessions[0]).size()).is_less(5)
	# битая рука выпадает, голова остаётся; лишние поля не ходят дальше сервера
	_send_raw(_bots[0], {"h": good, "l": [0, 0, 0], "r": [9.0, 0, 0, 0, 0, 0, 1, 0, 0], "junk": "x".repeat(500)})
	assert_bool(await _wait_for(func(): return _server.pose_of(_sessions[0]) != null)).is_true()
	var kept: Dictionary = _server.pose_of(_sessions[0])
	assert_array(kept.keys()).contains_exactly_in_any_order(["h"])


func test_garbage_does_not_replace_a_good_pose() -> void:
	_start(1)
	assert_bool(await _wait_for(func(): return _server.has_avatar(_sessions[0]))).is_true()
	_bots[0].net.send_pos(Vector3(-6, 0, -2), _pose(1.6))
	assert_bool(await _wait_for(func(): return _server.pose_of(_sessions[0]) != null)).is_true()
	await _sleep(0.06)
	_send_raw(_bots[0], {"h": [0, 9.0, 0, 0, 0, 0, 1]})
	await _sleep(0.15)
	assert_float(_head_y(_sessions[0])).is_equal_approx(1.6, 0.001)


func test_server_accepts_poses_no_more_often_than_the_minimum_gap() -> void:
	_start(1)
	assert_bool(await _wait_for(func(): return _server.has_avatar(_sessions[0]))).is_true()
	_bots[0].net.send_pos(Vector3(-6, 0, -2), _pose(1.6))
	_bots[0].net.send_pos(Vector3(-6, 0, -2), _pose(1.7))   # сразу следом: поток, лишнее
	_bots[0].net.send_pos(Vector3(-6, 0, -2), _pose(1.8))
	assert_bool(await _wait_for(func(): return _server.pose_of(_sessions[0]) != null)).is_true()
	await _sleep(0.02)
	assert_float(_head_y(_sessions[0])).is_equal_approx(1.6, 0.001)
	await _sleep(NetServer.POSE_MIN_GAP_MS / 1000.0 + 0.05)
	_bots[0].net.send_pos(Vector3(-6, 0, -2), _pose(1.9))   # через положенный интервал — принята
	assert_bool(await _wait_for(func(): return is_equal_approx(_head_y(_sessions[0]), 1.9))).is_true()


func test_server_stops_forwarding_a_pose_older_than_the_ttl() -> void:
	_start(1)
	assert_bool(await _wait_for(func(): return _server.has_avatar(_sessions[0]))).is_true()
	_bots[0].net.send_pos(Vector3(-6, 0, -2), _pose())
	assert_bool(await _wait_for(func(): return _server.pose_of(_sessions[0]) != null)).is_true()
	await _sleep(NetServer.POSE_TTL_MS / 1000.0 + 0.15)
	assert_object(_server.pose_of(_sessions[0])).is_null()
	assert_int(_server.avatar_entry(_sessions[0]).size()).is_less(5)


# ---------------------------------------------------------------- рассылка

func test_others_get_the_pose_and_the_owner_does_not() -> void:
	_start(3)
	_bots[0].pose = _pose(1.65)
	assert_bool(await _wait_for(func(): return _bots[1].remote.poses.size() == 1 and _bots[2].remote.poses.size() == 1)).is_true()
	var id0 := str(_server.avatar_id(_sessions[0]))
	for i in [1, 2]:
		assert_bool(_bots[i].remote.poses.has(id0)).is_true()
		assert_float(_bots[i].remote.poses[id0].head.origin.y).is_equal_approx(1.65, 0.002)
	# себе своей позы сервер не шлёт (в списке нет и самого владельца), чужих поз нет — боты 1 и 2 их не присылают
	await _sleep(0.3)
	assert_bool(_bots[0].remote.poses.is_empty()).is_true()
	assert_bool(_bots[0].remote.avatars.has(id0)).is_false()


func test_pose_does_not_cross_to_another_node() -> void:
	_start(3)
	assert_bool(await _wait_for(func(): return _bots.all(func(b): return b.remote.avatars.size() == 2))).is_true()
	_server.set_node(_sessions[2], "node_08")
	assert_bool(await _wait_for(func(): return _bots[0].remote.avatars.size() == 1 and _bots[1].remote.avatars.size() == 1)).is_true()
	await _sleep(0.3)   # дошло всё, отправленное до переключения
	_bots[2].pose = _pose(1.7)   # чужой узел шлёт позу: не доходит
	_bots[1].pose = _pose(1.5)   # свой узел — доходит
	var id1 := str(_server.avatar_id(_sessions[1]))
	var id2 := str(_server.avatar_id(_sessions[2]))
	assert_bool(await _wait_for(func(): return _bots[0].remote.poses.has(id1))).is_true()
	await _sleep(0.3)
	assert_bool(_bots[0].remote.poses.has(id2)).is_false()
	assert_bool(_bots[1].remote.poses.has(id2)).is_false()
	assert_bool(_bots[2].remote.poses.is_empty()).is_true()   # а из первого узла тому, что в node_08, ничего


func test_pose_disappears_for_others_after_the_sender_goes_quiet() -> void:
	_start(2)
	_bots[0].pose = _pose()
	assert_bool(await _wait_for(func(): return _bots[1].remote.poses.size() == 1)).is_true()
	_bots[0].pose = null   # очки сняли / клиент завис: позиции идут, поза — нет
	assert_bool(await _wait_for(func(): return _bots[1].remote.poses.is_empty(), NetServer.POSE_TTL_MS / 1000.0 + 2.0)).is_true()
	assert_bool(_bots[1].remote.avatars.size() == 1).is_true()   # аватар на месте, пропало только тело


func test_pose_stream_keeps_about_twenty_updates_per_second_and_a_small_packet() -> void:
	_start(2)
	_bots[0].pose = _pose()
	assert_bool(await _wait_for(func(): return _bots[1].remote.poses.size() == 1)).is_true()
	var count := [0]
	var sizes: Array[int] = []
	var rx0: int = _bots[1].net.rx_bytes
	_bots[1].net.avatars_received.connect(func(m: Dictionary):
		for e in m.get("a", []):
			if e.size() > 4:
				count[0] += 1
				sizes.append(JSON.stringify(m).length()))
	var sec := 2.0
	await _sleep(sec)
	var hz: float = count[0] / sec
	print("[AVATAR-NET] пакетов av с позой: %.1f в с; пакет av с одной позой ~%d Б; приём %.0f Б/с" % [hz, sizes.max() if not sizes.is_empty() else 0, (_bots[1].net.rx_bytes - rx0) / sec])
	assert_float(hz).is_between(14.0, 24.0)
	assert_int(sizes.max()).is_less(350)
