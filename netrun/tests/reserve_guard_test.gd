extends GdUnitTestSuite
## Запасной Страж (ice.md §4, «тревога 2»): из будки (блок «b») выходит один раз, остаётся, пока тревога не остыла до нуля; зрение +1 клетка карты действует и на него;
## будки и их состояние идут в state (поле `bo`). Раскладка test_reserve кладётся в кэш LayoutData.

static var _next_port := 18891
const NAME := "test_reserve"

var _root: Node
var _server: NetServer
var _world: GraphWorld


func before_test() -> void:
	LayoutData._cache[NAME] = LayoutData.parse({
		"name": NAME,
		"cells": ["V.......", ".2......", "........", "..#....V", "........", ".....1..", "S.......", "b.....EE"],
		"vaults": [{"cell": [7, 3], "pad": [6, 3], "ring": "outer"}, {"cell": [0, 0], "pad": [0, 1], "ring": "outer"}],
		"ice": [
			{"id": "g1", "kind": "sentry", "route": [{"cell": [1, 4], "wait": 2, "look": ["E"]}, {"cell": [6, 4], "wait": 1, "look": ["N"]}]},
			{"id": "r1", "kind": "reserve", "route": [{"cell": [0, 7], "wait": 1, "look": ["N"]}, {"cell": [0, 4], "wait": 2, "look": ["E"]}]},
		],
	})
	assert_str((LayoutData._cache[NAME] as LayoutData).error).is_empty()
	_root = Node.new()
	add_child(_root)
	var d := {"default_entry": "x_res", "entries": {}, "settings": {"time_mode": "tick", "vault_requires_open": false}, "nodes": {
		"x_res": {"title": "Будка", "tier": "BASE", "ice": 1, "shards": 1, "layout": NAME, "links": []},
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
	if _server != null:
		_server.stop_net()
	_root.queue_free()
	LayoutData._cache.erase(NAME)


func _node() -> GrayNode:
	return _world.node_of("x_res")


func _raise(value: float) -> void:
	_node().alarm = value
	_node()._apply_alert()


func _ids() -> Array:
	return _node().ices().map(func(i: IceNode) -> String: return str(i.name))


func test_до_тревоги_2_запасного_нет_будка_закрыта() -> void:
	assert_array(_ids()).contains_exactly(["g1"])
	_raise(30.0)   # уровень 1
	assert_array(_ids()).contains_exactly(["g1"])
	var view := _node().booth_view()
	assert_int(view.size()).is_equal(1)
	assert_int(int(view[0]["open"])).is_equal(0)
	assert_array(view[0]["c"]).contains_exactly([1, 15])   # клетка 1 м у южной стены


func test_на_тревоге_2_выходит_из_будки_и_видит_на_клетку_дальше() -> void:
	_raise(60.0)
	assert_array(_ids()).contains_exactly(["g1", "r1"])
	var r1: IceNode = _node().ices()[1]
	var ti: TickIce = _node()._tick_ices[r1]
	assert_object(ti.cell()).is_equal(Vector2i(1, 15))   # стоит в будке
	assert_int(int(_node().booth_view()[0]["open"])).is_equal(1)
	assert_float(ti.sight_bonus()).is_equal(GrayNode.ALARM_SIGHT_BONUS)


func test_выходит_один_раз_и_остаётся_пока_тревога_не_остыла_до_нуля() -> void:
	_raise(60.0)
	_raise(30.0)   # упала до 1 — Страж остаётся
	assert_array(_ids()).contains_exactly(["g1", "r1"])
	_raise(80.0)   # снова выше 2 — второго не выходит
	assert_array(_ids()).contains_exactly(["g1", "r1"])
	_raise(0.0)    # узел остыл до нуля
	assert_array(_ids()).contains_exactly(["g1"])
	assert_int(int(_node().booth_view()[0]["open"])).is_equal(0)
	_raise(60.0)   # новый забег: выходит снова
	assert_array(_ids()).contains_exactly(["g1", "r1"])
