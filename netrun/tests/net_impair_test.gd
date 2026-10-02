extends GdUnitTestSuite
## Эмуляция плохой сети в NetClient (P7): потери ненадёжных пакетов и задержка в обе стороны. Сервер и клиент в одном процессе.

static var _next_port := 17951

var _server: NetServer
var _client: NetClient
var _root: Node


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
	var cfg := NetConfig.new()
	cfg.port = _next_port
	_next_port += 1
	cfg.token = "tok-a"
	_server = NetServer.new()
	sroot.add_child(_server)
	_server.start(cfg, DictTokenVerifier.new({"tok-a": "alice"}))
	_client = NetClient.new()
	croot.add_child(_client)
	_client.start_client(cfg)
	await _wait_for(func(): return _server.peer_of("alice") != -1 and _client.is_connected_to_world)


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


func test_default_sends_immediately() -> void:
	var before := _client.tx_bytes
	assert_bool(_client.send_pos(Vector3(1, 0, 1))).is_true()
	assert_int(_client.tx_bytes).is_greater(before)


func test_full_loss_drops_unreliable_positions() -> void:
	_client.impair_loss = 1.0
	var before := _client.tx_bytes
	for i in 20:
		assert_bool(_client.send_pos(Vector3(i, 0, 0))).is_true()  # «ушло» — как в сети, отправитель потери не видит
	await get_tree().create_timer(0.4).timeout
	assert_int(_client.impair_dropped_up).is_equal(20)
	assert_int(_client.tx_bytes).is_equal(before)


func test_loss_on_reliable_means_delay_not_drop() -> void:
	_client.impair_loss = 1.0
	var before := _client.tx_bytes
	_client.request_leave()
	assert_int(_client.tx_bytes).is_equal(before)  # ещё в очереди повтора
	assert_bool(await _wait_for(func(): return _client.tx_bytes > before, 2.0)).is_true()
	assert_int(_client.impair_dropped_up).is_equal(0)


func test_delay_holds_packet_until_due_and_keeps_order() -> void:
	_client.impair_delay_ms = 300
	var before := _client.tx_bytes
	_client.send_pos(Vector3(1, 0, 0))
	_client.send_pos(Vector3(2, 0, 0))
	assert_int(_client.tx_bytes).is_equal(before)
	await get_tree().create_timer(0.1).timeout
	assert_int(_client.tx_bytes).is_equal(before)
	assert_bool(await _wait_for(func(): return _client.tx_bytes > before, 2.0)).is_true()
	assert_bool(await _wait_for(func(): return _client._out_queue.is_empty(), 1.0)).is_true()


func test_reconnect_clears_queues() -> void:
	_client.impair_delay_ms = 5000
	_client.send_pos(Vector3(1, 0, 0))
	assert_int(_client._out_queue.size()).is_equal(1)
	_client.reconnect()
	assert_int(_client._out_queue.size()).is_equal(0)
