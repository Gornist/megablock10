extends GdUnitTestSuite
## Взлом хранилища сквозным путём без очков (К3): сервер мира (граф + фейковый Мост) и настоящий плоский клиент ProtoClient в одном процессе.
## Игрок стоит у хранилища -> панель появляется сама -> «НАЧАТЬ» -> сетка -> тапы по подсвеченным клеткам -> итог -> хранилище открыто -> шард в руку.

static var _next_port := 18891
const GRAPH := "res://tests/fixtures/breach_graph.json"
const BRIDGE := "res://tests/fixtures/breach_bridge_fixture.json"
const S1 := "s_fake000000000001"

var _root: Node
var _server: NetServer
var _world: GraphWorld
var _bridge: FakeBridge
var _cfg: NetConfig


func before_test() -> void:
	_root = Node.new()
	_root.name = "BreachClientRoot"
	add_child(_root)
	var sroot := Node.new()
	sroot.name = "S"
	var croot := Node.new()
	croot.name = "C"
	_root.add_child(sroot)
	_root.add_child(croot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), sroot.get_path())
	get_tree().set_multiplayer(SceneMultiplayer.new(), croot.get_path())
	_cfg = NetConfig.new()
	_cfg.port = _next_port
	_next_port += 1
	_cfg.token = "t03:token-t03"
	_bridge = FakeBridge.new(BRIDGE)
	_server = NetServer.new()
	sroot.add_child(_server)
	assert_int(_server.start(_cfg, _bridge)).is_equal(OK)
	_world = GraphWorld.new()
	_world.trace_settings = {"decay_per_sec": 0.0}
	sroot.add_child(_world)
	_world.start(_server, _bridge, NodeGraph.load_file(GRAPH))


func after_test() -> void:
	_server.stop_net()
	_root.queue_free()


func _wait_for(cond: Callable, sec: float = 20.0) -> bool:
	var t := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _client() -> ProtoClient:
	var proto := ProtoClient.new()
	_root.get_node("C").add_child(proto)
	proto.start(PackedStringArray(["--token=" + _cfg.token, "--port=%d" % _cfg.port]), "flat", false)
	return proto


## Игрок у площадки перед хранилищем k: и аватар на сервере, и риг клиента.
func _go_to_pad(proto: ProtoClient, k: int) -> void:
	var pad := NodeLayout.vault_pad(NodeLayout.SHARD_SLOTS[k])
	_server.teleport(S1, pad)
	proto.scene.rig.global_position = Vector3(pad.x, proto.scene.rig.global_position.y, pad.z)


func test_full_flat_flow_panel_appears_breach_opens_the_vault_and_the_shard_is_taken() -> void:
	var proto := _client()
	var scene: Node3D = proto.scene
	var panel: BreachPanel = scene.world_ui.breach_panel
	var slot := GrayNode.shard_id("b_a", 0)
	assert_bool(await _wait_for(func(): return not scene.deck_info.is_empty() and (scene.deck_info.get("daemons", []) as Array).any(func(d): return not (d.get("cells", []) as Array).is_empty()) and scene.node_info.has("shards"))).is_true()
	assert_str(panel.mode()).is_equal(BreachPanel.MODE_HIDDEN)          # далеко от хранилищ — панели нет
	_go_to_pad(proto, 0)
	assert_bool(await _wait_for(func(): return panel.mode() == BreachPanel.MODE_IDLE)).is_true()
	assert_str(panel.vault_id()).is_equal(slot)
	# панель в мире — на экране корпуса hack_panel рядом с площадкой: впереди игрока на площадке (в сторону хранилища), в 0,6–1,1 м, экраном к голове
	var head: Vector3 = scene.rig.camera.global_position
	var to_panel := panel.global_position - head
	assert_float(Vector2(to_panel.x, to_panel.z).length()).is_between(0.6, 1.1)
	assert_float(to_panel.z).is_less(0.0)
	assert_float(panel.global_transform.basis.z.dot(-to_panel.normalized())).is_greater(0.8)
	var at := panel.global_transform
	assert_str("\n".join(panel.texts())).contains("Извлечение").contains("Призрак")
	# отметили только Извлечение (цепочка короче) и начали
	panel.toggle_daemon("it_b_d2")
	assert_array(panel.picked_ids()).is_equal(["it_b_d1"])
	assert_bool(panel.request_start()).is_true()
	assert_bool(await _wait_for(func(): return panel.mode() == BreachPanel.MODE_RUN)).is_true()
	assert_bool(panel.global_transform.is_equal_approx(at)).is_true()   # панель осталась там, где появилась
	assert_int(panel.cell_nodes().size()).is_equal(25)                 # BASE: 5 × 5
	var avail := panel.cell_nodes().values().filter(func(c: BreachCell): return c.is_available())
	assert_int(avail.size()).is_equal(5)                               # первая строка
	# человек нажимает подсвеченные клетки, сервер подтверждает каждую
	var path := BreachAutoSolver.solve(panel.mirror.attempt)
	for c in path:
		if panel.mode() != BreachPanel.MODE_RUN:
			break
		assert_bool(panel.tap_cell(c)).is_true()
		assert_bool(await _wait_for(func(): return panel.mirror == null or panel.mirror.pending == null)).is_true()
	assert_bool(await _wait_for(func(): return panel.mode() == BreachPanel.MODE_RESULT)).is_true()
	assert_str("\n".join(panel.texts())).contains("ВЗЛОМ УДАЛСЯ").contains("Хранилище открыто")
	# хранилище открыто для нас; шард берётся рукой (плоская сборка — F/ЛКМ, здесь try_grab)
	assert_bool(await _wait_for(func(): return scene._vault_state.get(slot) == NodeView.VAULT_OPEN)).is_true()
	assert_bool(scene.try_grab(scene.rig.camera.global_position, 3.0, scene.rig.camera)).is_true()
	assert_bool(await _wait_for(func(): return str(_bridge.doc("item", "it_b_s1")["data"]["owner"]) == "deck:" + S1)).is_true()
	assert_bool(FileAccess.get_file_as_string(proto.log_file.path).contains("breach.end")).is_true()
	await proto.net.drop()


func test_panel_goes_away_when_the_player_leaves_and_does_not_show_for_an_open_vault() -> void:
	var proto := _client()
	var scene: Node3D = proto.scene
	var panel: BreachPanel = scene.world_ui.breach_panel
	assert_bool(await _wait_for(func(): return scene.node_info.has("shards"))).is_true()
	_go_to_pad(proto, 0)
	assert_bool(await _wait_for(func(): return panel.mode() == BreachPanel.MODE_IDLE)).is_true()
	scene.rig.global_position = Vector3(4.0, 0.0, -3.0)
	assert_bool(await _wait_for(func(): return panel.mode() == BreachPanel.MODE_HIDDEN)).is_true()
	# открытое для игрока хранилище панели не требует: шард берут рукой
	(_world.node_of("b_a") as GrayNode).open_vault(GrayNode.shard_id("b_a", 0), S1)
	_go_to_pad(proto, 0)
	await get_tree().create_timer(0.5).timeout
	assert_str(panel.mode()).is_equal(BreachPanel.MODE_HIDDEN)
	await proto.net.drop()


func test_teleport_snap_in_the_rig_matches_the_server_and_turns_the_view_to_the_vault() -> void:
	var proto := _client()
	var scene: Node3D = proto.scene
	assert_bool(await _wait_for(func(): return scene.node_info.has("shards"))).is_true()
	var near := NodeLayout.SHARD_SLOTS[0] + Vector3(0.9, 0, 1.0)
	var s: Dictionary = scene.snap_teleport(near)
	var pad := NodeLayout.vault_pad(NodeLayout.SHARD_SLOTS[0])
	assert_float(NodeLayout.flat_distance(s["p"], pad)).is_less(0.001)
	assert_float(NodeLayout.flat_distance(s["p"], _server_snap(near)["p"])).is_less(0.001)   # тот же результат на сервере
	# поворот взгляда: face_toward смотрит камерой на хранилище
	scene.rig.rotation = Vector3.ZERO
	scene.rig.global_position = Vector3(pad.x, 0, pad.z)
	scene.rig.face_toward(NodeLayout.SHARD_SLOTS[0])
	var fwd: Vector3 = -scene.rig.camera.global_basis.z
	var want: Vector3 = (NodeLayout.SHARD_SLOTS[0] - scene.rig.camera.global_position)
	want.y = 0.0
	fwd.y = 0.0
	assert_float(fwd.normalized().dot(want.normalized())).is_greater(0.999)
	await proto.net.drop()


func _server_snap(p: Vector3) -> Dictionary:
	return (_world.node_of("b_a") as GrayNode).snap_teleport(p)
