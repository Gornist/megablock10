extends GdUnitTestSuite
## Настоящий клиент (ProtoClient: сцена, риг, сеть, журнал) телепортируется через сервер: запрос уходит, сервер переносит
## аватар, журнал пишет события; отказ сервера возвращает риг на место. Сервер — только NetServer (без узла и Моста).

static var _next_port := 19291
const SESSION := "alice"
const DT := 1.0 / 72.0

var _server: NetServer
var _proto: ProtoClient
var _root: Node


func before_test() -> void:
	_root = Node.new()
	_root.name = "TpProtoRoot"
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
	_server = NetServer.new()
	sroot.add_child(_server)
	assert_int(_server.start(cfg, DictTokenVerifier.new({"tok-a": SESSION}))).is_equal(OK)
	_proto = ProtoClient.new()
	croot.add_child(_proto)
	_proto.start(PackedStringArray(["--token=tok-a", "--port=%d" % cfg.port]), "flat", false)
	assert_bool(await _wait_for(func(): return _proto.net.is_connected_to_world and _server.has_avatar(SESSION))).is_true()


func after_test() -> void:
	await _proto.net.drop()
	_server.stop_net()
	_root.queue_free()


func _wait_for(cond: Callable, sec: float = 5.0) -> bool:
	var t := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _log() -> String:
	return FileAccess.get_file_as_string(_proto.log_file.path)


## Прицелиться вперёд; отпускает стик сам риг: его _process каждый кадр подаёт пустой ввод.
func _aim_forward() -> Vector3:
	var rig: XRRig = _proto.scene.rig
	for i in 3:
		rig.drive(0.0, Vector2(0, 1), false, DT)
	return rig.aim_target()


func test_client_logs_the_comfort_settings_at_start() -> void:
	assert_str(_log()).contains("comfort turn=none speed=60")


func test_teleport_goes_through_the_server_and_is_logged() -> void:
	var target := _aim_forward()
	var avatar := _server.get_avatar(SESSION)
	assert_bool(await _wait_for(func(): return NodeLayout.flat_distance(avatar.position, target) < 0.05)).is_true()
	assert_bool(await _wait_for(func(): return NodeLayout.flat_distance(_proto.scene.rig.global_position, target) < 0.05)).is_true()
	assert_int(_server.teleport_count(SESSION)).is_equal(1)
	var text := _log()
	assert_str(text).contains("rig.teleport")
	assert_str(text).contains("ok=true")
	assert_str(text).not_contains("teleport.denied")


func test_server_denial_puts_the_rig_back_and_is_logged() -> void:
	_server.set_node(SESSION, NetServer.TUNNEL_NODE)   # клиент об этом не знает: сервер откажет
	var rig: XRRig = _proto.scene.rig
	var home := rig.global_position
	_aim_forward()
	assert_bool(await _wait_for(func(): return _log().contains("teleport.denied"))).is_true()
	assert_str(_log()).contains("reason=tunnel")
	assert_bool(await _wait_for(func(): return rig.blink_alpha() == 0.0 and NodeLayout.flat_distance(rig.global_position, home) < 0.05)).is_true()
	assert_bool(NodeLayout.flat_distance(_server.get_avatar(SESSION).position, NodeLayout.SPAWN) < 0.05).is_true()
