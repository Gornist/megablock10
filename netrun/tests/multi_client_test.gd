extends GdUnitTestSuite
## Несколько клиентов в одном узле (P1): видимость по узлу и нагрузка 10 ботов. Сервер и боты — в одном процессе,
## у каждого участника свой MultiplayerAPI (поддерево сцены), как в gray_node_test.gd. Узел без Моста: токены из словаря.

static var _next_port := 18291
const LOAD_BOTS := 10
const MEASURE_SEC := 8.0

var _root: Node
var _server: NetServer
var _node: GrayNode
var _bots: Array[BotClient] = []
var _sessions: Array[String] = []


func _start(count: int) -> void:
	_root = Node.new()
	_root.name = "MultiTestRoot"
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
	_node.ice_settings = {"sight_range": 0.5}  # ICE ходит по патрулю, но боты у входа ему неинтересны
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
		bot.loiter_omega = 0.8 + 0.1 * i
		croot.add_child(bot)
		bot.start(c, BotClient.Scenario.LOITER)
		_bots.append(bot)


func after_test() -> void:
	for b in _bots:
		if b.net != null:
			await b.net.drop()
	_server.stop_net()
	_root.queue_free()
	_bots.clear()
	_sessions.clear()


func _wait_for(cond: Callable, sec: float = 20.0) -> bool:
	var t := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _sleep(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func test_clients_see_only_own_node() -> void:
	_start(3)
	assert_bool(await _wait_for(func(): return _bots.all(func(b): return b.remote.avatars.size() == 2))).is_true()
	# третьего переводим в другой узел: он пропадает у первых двух и ничего не получает сам
	_server.set_node(_sessions[2], "node_08")
	assert_bool(await _wait_for(func(): return _bots[0].remote.avatars.size() == 1 and _bots[1].remote.avatars.size() == 1)).is_true()
	await _sleep(0.3)  # дойти успели все пакеты, отправленные до переключения
	var rx_before: int = _bots[2].net.rx_bytes
	var other_before: int = _bots[0].net.rx_bytes
	await _sleep(1.0)
	assert_int(_bots[2].net.rx_bytes).is_equal(rx_before)
	assert_int(_bots[0].net.rx_bytes).is_greater(other_before + 1000)
	# а те двое видят друг друга по-прежнему и не видят третьего
	var id2 := str(_server.avatar_id(_sessions[2]))
	assert_bool(_bots[0].remote.avatars.has(id2)).is_false()
	assert_bool(_bots[1].remote.avatars.has(str(_server.avatar_id(_sessions[0])))).is_true()
	assert_array(_server.sessions_in("node_08")).is_equal([_sessions[2]])
	assert_int(_server.sessions_in(NetConfig.WORLD_NODE).size()).is_equal(2)


func test_ten_bots_see_each_other() -> void:
	_start(LOAD_BOTS)
	assert_bool(await _wait_for(func(): return _bots.all(func(b): return b.remote.avatars.size() == LOAD_BOTS - 1))).is_true()
	var bytes0 := {}
	for s in _sessions:
		bytes0[s] = int(_server.bytes_sent.get(s, 0))
	var packets0: Array = _bots.map(func(b): return b.avatar_packets)
	var steps0: Dictionary = _node.step_stats()
	var t0 := Time.get_ticks_msec()
	await _sleep(MEASURE_SEC)
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	# трафик на клиента: сервер -> клиент, байты полезной нагрузки (без заголовков ENet/UDP)
	var rates: Array[float] = []
	for s in _sessions:
		rates.append((int(_server.bytes_sent[s]) - int(bytes0[s])) / secs)
	var tx_rates: Array[float] = []
	for b in _bots:
		tx_rates.append(float(b.net.tx_bytes) / maxf(b.get("_clock"), 1.0))
	var steps1: Dictionary = _node.step_stats()
	var pps: Array[float] = []
	for i in _bots.size():
		pps.append((_bots[i].avatar_packets - int(packets0[i])) / secs)
	print("[P1-LOAD] ботов %d, окно %.1f с: сервер->клиент %.0f..%.0f Б/с (среднее %.0f); клиент->сервер ~%.0f Б/с; пакетов позиций %.1f..%.1f в с" % [
		LOAD_BOTS, secs, rates.min(), rates.max(), _avg(rates), _avg(tx_rates), pps.min(), pps.max()])
	print("[P1-LOAD] шаг сервера (_physics_process узла): среднее %d мкс, максимум %d мкс, шагов %d" % [
		steps1["avg_us"], steps1["max_us"], steps1["count"] - steps0["count"]])
	assert_float(pps.min()).is_greater(15.0)  # ~20 раз/с
	# каждый бот видит всех остальных, и показываемая позиция недалеко от настоящей
	for i in _bots.size():
		var bot := _bots[i]
		assert_int(bot.remote.avatars.size()).is_equal(LOAD_BOTS - 1)
		for j in _bots.size():
			if i == j:
				continue
			var real := _server.get_avatar(_sessions[j]).position
			var pose := bot.remote.avatar_pose(str(_server.avatar_id(_sessions[j])), bot.get("_clock"))
			assert_bool(pose.is_empty()).is_false()
			assert_float(NodeLayout.flat_distance(pose["p"], real)).is_less(1.5)
	assert_int(_server.sessions().size()).is_equal(LOAD_BOTS)
	assert_bool(_bots.all(func(b): return b.result.is_empty())).is_true()


func _avg(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s / maxf(a.size(), 1)
