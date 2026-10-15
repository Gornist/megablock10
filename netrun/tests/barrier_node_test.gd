extends GdUnitTestSuite
## Барьер в узле (раскладка core, ice.md §5): закрыт — клетки заняты и виден в state (`br`), вскрытие освобождает клетки; силой — тревога +10,
## Отмычкой — тихо; повторное вскрытие и неизвестный барьер — отказ; Черный ICE и датчики раскладки поднимаются вместе с барьером.

static var _next_port := 19300

var _root: Node
var _server: NetServer
var _world: GraphWorld


func before_test() -> void:
	_root = Node.new()
	add_child(_root)
	var d := {"default_entry": "x_core", "entries": {}, "settings": {"time_mode": "tick", "vault_requires_open": false}, "nodes": {
		"x_core": {"title": "Ядро", "tier": "NIGHTMARE", "ice": 2, "shards": 1, "layout": "core", "links": []},
	}}
	var sroot := Node.new()
	sroot.name = "S"
	_root.add_child(sroot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), sroot.get_path())
	_server = NetServer.new()
	sroot.add_child(_server)
	var cfg := NetConfig.new()
	cfg.port = _next_port
	_next_port += 1
	assert_int(_server.start(cfg, DictTokenVerifier.new({}))).is_equal(OK)
	_world = GraphWorld.new()
	sroot.add_child(_world)
	_world.start(_server, null, NodeGraph.from_dict(d))


func after_test() -> void:
	_server.stop_net()
	_root.queue_free()


func test_барьер_закрыт_клетки_заняты_и_виден_в_state() -> void:
	var node := _world.node_of("x_core")
	var view := node.barrier_view()
	assert_int(view.size()).is_equal(1)
	assert_str(str(view[0]["id"])).is_equal("bar1")
	assert_int(int(view[0]["open"])).is_equal(0)
	assert_int((view[0]["c"] as Array).size()).is_equal(4)
	assert_bool(node.barrier_closed("bar1")).is_true()
	for c in LayoutData.block_cells(Vector2i(3, 2)):
		assert_bool(node.ice_grid.is_occupied(c)).is_true()
	assert_object(node.black_ice()).is_not_null()   # логово в той же раскладке
	assert_int(node.sensors().size()).is_equal(2)


func test_вскрытие_силой_освобождает_клетки_и_даёт_тревогу() -> void:
	var node := _world.node_of("x_core")
	var before := node.alarm
	assert_bool(node.open_barrier("bar1", "force", "s1")).is_true()
	assert_bool(node.barrier_closed("bar1")).is_false()
	for c in LayoutData.block_cells(Vector2i(3, 2)):
		assert_bool(node.ice_grid.is_occupied(c)).is_false()
	assert_float(node.alarm - before).is_equal_approx(10.0, 0.001)
	assert_bool(node.open_barrier("bar1", "force", "s1")).is_false()   # повторно — отказ
	assert_bool(node.open_barrier("нет такого", "force")).is_false()


func test_отмычка_вскрывает_тихо() -> void:
	var node := _world.node_of("x_core")
	var before := node.alarm
	assert_bool(node.open_barrier("bar1", "pick", "s1")).is_true()
	assert_float(node.alarm - before).is_equal_approx(0.0, 0.001)
	assert_int(int(node.barrier_view()[0]["open"])).is_equal(1)
