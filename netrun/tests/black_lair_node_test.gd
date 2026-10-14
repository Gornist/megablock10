extends GdUnitTestSuite
## Black ICE по тактам в узле (GrayNode + раскладка с логовом): создаётся в логове и спит, будится trace, охота закрывает порталы, ожоги общие
## на забег (black_burns), третий ожог — выброс black_caught; раскладка разбирает логово и ловит ошибки.

static var _next_port := 19100
const LAIR := "test_lair"

var _root: Node
var _server: NetServer
var _world: GraphWorld


func before_test() -> void:
	LayoutData._cache[LAIR] = LayoutData.parse({
		"name": LAIR,
		"cells": ["V......V", "........", "........", "...LL...", "...LL...", "........", "1..S.EE2", "b....EE3"],
		"vaults": [{"cell": [0, 0], "pad": [0, 1], "ring": "outer"}, {"cell": [7, 0], "pad": [7, 1], "ring": "outer"}],
		"ice": [],
		"black": {"id": "b1", "kind": "", "cell": [3, 3]},
	})
	assert_str((LayoutData._cache[LAIR] as LayoutData).error).is_empty()
	_root = Node.new()
	add_child(_root)
	var d := {"default_entry": "x_core", "entries": {}, "settings": {"time_mode": "tick", "vault_requires_open": false}, "nodes": {
		"x_core": {"title": "Ядро", "tier": "NIGHTMARE", "ice": 0, "shards": 1, "layout": LAIR, "links": []},
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
	assert_int(_server.start(cfg, DictTokenVerifier.new({})) ).is_equal(OK)
	_world = GraphWorld.new()
	sroot.add_child(_world)
	_world.start(_server, null, NodeGraph.from_dict(d))


func after_test() -> void:
	_server.stop_net()
	_root.queue_free()
	LayoutData._cache.erase(LAIR)


func _meter(v: float) -> TraceMeter:
	var m := TraceMeter.new()
	m.add_amount(v, 0.0)
	return m


func _tick(node: GrayNode, cell: Vector2i, trace: float, hidden: bool = false) -> void:
	var pos := {"s1": NodeGrid.center(cell)}
	node._step_tick_black(pos, {"s1": hidden}, {"s1": _meter(trace)})


func test_логово_разобрано_и_black_ice_спит_в_нём() -> void:
	var ld := LayoutData.cached(LAIR)
	assert_int((ld.lair["cells"] as Array).size()).is_equal(16)
	assert_object(ld.lair["home"]).is_equal(Vector2i(8, 8))
	var node := _world.node_of("x_core")
	var tb := node.black_ice()
	assert_object(tb).is_not_null()
	assert_int(tb.phase).is_equal(TickBlack.Phase.SLEEP)
	assert_object(tb.cell()).is_equal(Vector2i(8, 8))


func test_логово_без_четырёх_блоков_L_отвергается() -> void:
	var d := {"name": "t", "cells": ["V......V", "........", "........", "...LL...", "...L....", "........", "1..S.EE2", "b....EE3"],
		"vaults": [], "ice": [], "black": {"id": "b1", "cell": [3, 3]}}
	assert_str(LayoutData.parse(d).error).is_not_empty()


func test_охота_закрывает_порталы_ожоги_общие_и_третий_флэтлайн() -> void:
	var node := _world.node_of("x_core")
	var ejected: Array = []
	for ice in node.ices():
		ice.ejected.connect(func(s: String, r: String): ejected.append([s, r]))
	var far := Vector2i(1, 8)
	for i in 7:
		_tick(node, far, 60.0)   # trace ≥ 50: проснулся, 6 тактов пробуждения
	var tb := node.black_ice()
	assert_int(tb.phase).is_equal(TickBlack.Phase.HUNT)
	assert_bool(node.ices()[0].brain.is_hunting("s1")).is_true()
	assert_bool(node.ices()[0].brain.is_hunting("other")).is_true()   # под охотой порталы закрыты для всех
	for i in 40:
		_tick(node, Vector2i(tb.cell().x + 1, tb.cell().y), 60.0)   # рядом с ICE: ожог за каждый такт захвата
		if not ejected.is_empty():
			break
	assert_int(int(node.black_burns.get("s1", 0))).is_equal(3)
	assert_array(ejected).is_equal([["s1", "black_caught"]])
	assert_bool(node.black_burns == _world.black_burns).is_true()   # один словарь на весь мир


func test_бегун_black_ice_далеко_уходит_а_стоявший_у_логова_пойман() -> void:
	var ld := LayoutData.cached(LAIR)
	var b := LayoutBots.new(ld, "NIGHTMARE")
	assert_str(b.error).is_empty()
	assert_bool(b.black_runner_run(Vector2i(11, 12), 0)["ok"]).is_true()   # у выхода: пара прыжков
	var caught := b.black_runner_run(Vector2i(10, 8), 30)   # простоял всё пробуждение и охоту у логова
	assert_bool(caught["ok"]).is_false()
	assert_int(int(caught["captured_at"])).is_greater(0)
	var r := LayoutBots.check_black_runner(ld, "NIGHTMARE")
	print("[black-runner] ", r)
	assert_bool(r.has("ok")).is_true()
