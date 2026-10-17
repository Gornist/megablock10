extends GdUnitTestSuite
## Одиночная игра (client/solo_stub.gd): сервер мира и плоский клиент в одном процессе по петле 127.0.0.1; данные data/solo читаются сервером.

const SoloStubScript := preload("res://client/solo_stub.gd")
const SESSION :="s_fake000000000001"   # сессия «Призрак» в data/solo/bridge_fixture.json (терминал t03 → Архив)

var _solo: Node


func after_test() -> void:
	if _solo != null:
		var proto := _solo.flat.get_node_or_null("Proto") as ProtoClient
		if proto != null and proto.net != null:
			await proto.net.drop()
		_solo.server.net.stop_net()
		_solo.queue_free()
		_solo = null


func _wait_for(cond: Callable, sec: float = 10.0) -> bool:
	var t := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func test_режим_solo_по_аргументу_и_метке() -> void:
	assert_int(RunMode.detect({}, PackedStringArray(["--solo"]))).is_equal(RunMode.Mode.SOLO)
	assert_int(RunMode.detect({"solo": true}, PackedStringArray())).is_equal(RunMode.Mode.SOLO)
	assert_int(RunMode.detect({"solo": true}, PackedStringArray(["--server"]))).is_equal(RunMode.Mode.SERVER)
	assert_int(RunMode.detect({"solo": true}, PackedStringArray(["--flat"]))).is_equal(RunMode.Mode.FLAT)


func test_порт_петли_свободный_и_из_диапазона() -> void:
	var p: int = SoloStubScript.free_port()
	assert_int(p).is_between(SoloStubScript.PORT_FIRST, SoloStubScript.PORT_LAST)


func test_занятый_порт_пропускается() -> void:
	var busy := ENetMultiplayerPeer.new()
	busy.set_bind_ip(SoloStubScript.LOOPBACK)
	assert_int(busy.create_server(SoloStubScript.PORT_FIRST, 1)).is_equal(OK)
	assert_int(SoloStubScript.free_port()).is_not_equal(SoloStubScript.PORT_FIRST)
	busy.close()


func test_аргументы_сервера_только_петля() -> void:
	var a := SoloStubScript.server_args(49555)
	assert_array(a).contains(["--port=49555", "--bind=127.0.0.1", "--bridge=fake"])
	assert_str(NetConfig.from_args(a).bind).is_equal("127.0.0.1")


func test_аргументы_клиента_несут_адрес_и_токен() -> void:
	var a := SoloStubScript.client_args(PackedStringArray(["--x"]), 49555)
	assert_array(a).contains(["--x", "--host=127.0.0.1", "--port=49555"])
	var cfg := NetConfig.from_args(a)
	assert_str(cfg.terminal_id()).is_equal("t03")


func test_клиент_входит_в_архив_через_встроенный_сервер() -> void:
	_solo = preload("res://client/solo_stub.gd").new()
	add_child(_solo)
	assert_bool(_solo.start(PackedStringArray())).is_true()
	var proto := _solo.flat.get_node("Proto") as ProtoClient
	assert_bool(await _wait_for(func(): return proto.net != null and proto.net.is_connected_to_world)).is_true()
	assert_bool(await _wait_for(func(): return _solo.server.net.has_avatar(SESSION))).is_true()
