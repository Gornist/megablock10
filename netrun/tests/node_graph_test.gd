extends GdUnitTestSuite
## Граф узлов как данные (W1): настоящий data/graph.json и правила проверки NodeGraph.errors().


func test_real_graph_is_valid() -> void:
	var g := NodeGraph.load_file()
	assert_array(g.errors()).is_empty()
	assert_int(g.nodes.size()).is_between(11, 13)  # 10–12 узлов графа и учебный узел node_00
	var tiers := {}
	for id in g.nodes:
		tiers[g.tier_of(id)] = int(tiers.get(g.tier_of(id), 0)) + 1
		assert_int(int(g.nodes[id]["shards"])).is_greater_equal(1)
	# все три уровня в графе, самый тяжёлый — не вход
	for t in NodeGraph.TIERS:
		assert_int(int(tiers.get(t, 0))).is_greater_equal(1)
	assert_str(g.tier_of(g.default_entry)).is_not_equal("NIGHTMARE")


## W1-Ч1: ICE графа не срабатывает «мгновенно» — зрение по тиру, внимание и бег помедленнее, trace за «на виду» — 2, не 8.
func test_real_graph_ice_and_trace_numbers() -> void:
	var g := NodeGraph.load_file()
	assert_float(float(g.settings["trace"]["weights"]["seen_by_ice"])).is_equal(2.0)
	assert_float(float(g.settings["trace"]["decay_per_sec"])).is_equal(0.2)
	for id in g.nodes:
		if id == "node_00":
			continue  # учебный узел со своими числами
		var s: Dictionary = g.nodes[id]["ice_settings"]
		var sight := 6.0 if g.tier_of(id) == "BASE" else 8.0
		assert_float(float(s["sight_range"])).is_equal(sight)
		assert_float(float(s["notice_per_sec"])).is_equal(0.15)
		assert_float(float(s["chase_speed"])).is_equal(1.5)


func test_entry_depends_on_terminal() -> void:
	var g := NodeGraph.load_file()
	assert_str(g.entry_for("t01")).is_equal("node_01")
	assert_str(g.entry_for("t03")).is_equal("node_07")
	assert_str(g.entry_for("t99")).is_equal(g.default_entry)  # неизвестный терминал — узел по умолчанию


func test_tunnels_are_symmetric_and_slots_match() -> void:
	var g := NodeGraph.load_file()
	for id in g.nodes:
		for to in g.nodes[id]["links"]:
			assert_bool(g.is_linked(to, id)).is_true()
			assert_int(g.slot_to(id, to)).is_between(0, NodeLayout.PORTAL_SLOTS.size() - 1)


func test_bad_graph_reports_errors() -> void:
	var bad := NodeGraph.from_dict({
		"default_entry": "x_boss",
		"entries": {"t1": "ghost_node"},
		"nodes": {
			"x_boss": {"tier": "NIGHTMARE", "ice": 5, "shards": 0, "links": ["x_b", "x_b", "x_c", "x_d"]},
			"x_b": {"tier": "WEIRD", "links": []},
			"x_c": {"links": ["x_boss"]},
			"x_d": {"links": ["x_boss"]},
			"x_island": {"links": []},
		},
	})
	var joined := "\n".join(bad.errors())
	assert_str(joined).contains("ICE 5")
	assert_str(joined).contains("шардов 0")
	assert_str(joined).contains("слотов порталов")
	assert_str(joined).contains("WEIRD")
	assert_str(joined).contains("не симметричен")
	assert_str(joined).contains("не связный")
	assert_str(joined).contains("ghost_node")
	assert_str(joined).contains("с Black ICE не начинают")


func test_settings_merge_over_defaults() -> void:
	var g := NodeGraph.from_dict({"settings": {"tunnel_sec": 9.0, "shard_refill_sec": {"HARD": 5}}, "nodes": {}})
	assert_float(float(g.settings["tunnel_sec"])).is_equal(9.0)
	assert_float(g.refill_sec("HARD")).is_equal(5.0)
	assert_float(g.refill_sec("BASE")).is_equal(600.0)  # недостающий тир — из умолчаний
	assert_float(float(g.settings["lockdown_sec"])).is_equal(600.0)


func test_portal_and_arrival_geometry() -> void:
	var slots: Array = NodeLayout.PORTAL_SLOTS
	for i in slots.size():
		var p: Vector3 = slots[i]
		assert_bool(NodeLayout.in_room(p)).is_true()
		assert_bool(NodeLayout.on_exit_pad(p)).is_false()
		var arrive := NodeLayout.arrival_for_slot(i)
		assert_bool(NodeLayout.in_room(arrive)).is_true()
		# вход — вне радиуса любого портала: иначе переход сработал бы заново
		for q in slots:
			assert_float(NodeLayout.flat_distance(arrive, q)).is_greater(NodeLayout.PORTAL_RADIUS)
		for j in range(i + 1, slots.size()):
			assert_float(NodeLayout.flat_distance(p, slots[j])).is_greater(2.0 * NodeLayout.PORTAL_RADIUS)
	for sp in NodeLayout.SHARD_SLOTS:
		assert_bool(NodeLayout.in_room(sp)).is_true()


func test_server_loads_graph_by_default_and_single_node_flag_disables_it() -> void:
	assert_object(WorldServer.load_graph(PackedStringArray())).is_not_null()
	assert_object(WorldServer.load_graph(PackedStringArray(["--exit-after=5"]))).is_not_null()
	assert_object(WorldServer.load_graph(PackedStringArray(["--single-node"]))).is_null()


func test_узел_читает_имя_раскладки_пусто_значит_legacy() -> void:
	var g := NodeGraph.from_dict({"nodes": {"a": {"layout": "foyer", "links": []}, "b": {"links": []}}})
	assert_str(g.nodes["a"]["layout"]).is_equal("foyer")
	assert_str(g.nodes["b"]["layout"]).is_empty()


## Узлы реального графа с раскладкой: связей не больше порталов раскладки, шардов не больше её хранилищ.
func test_раскладки_реального_графа_вмещают_связи_и_шарды() -> void:
	var g := NodeGraph.load_file()
	var with_layout := 0   # (в шаге с graph.json — не меньше 1)
	for id in g.nodes:
		var name := str(g.nodes[id]["layout"])
		if name.is_empty():
			continue
		with_layout += 1
		var ld := LayoutData.cached(name)
		assert_str(ld.error).is_empty()
		assert_int((g.nodes[id]["links"] as Array).size()).is_less_equal(ld.portals.size())
		assert_int(int(g.nodes[id]["shards"])).is_less_equal(ld.vaults.size())
		for i in (g.nodes[id]["links"] as Array).size():
			assert_bool(ld.portals[i] != Vector3.INF).is_true()
	assert_int(with_layout).is_equal(4)   # node_00 (учебная) и node_01, node_02, node_07 (Фойе)
	assert_str(g.nodes["node_00"]["layout"]).is_equal("foyer_tutorial")
	for id: String in ["node_01", "node_02", "node_07"]:
		assert_str(g.nodes[id]["layout"]).is_equal("foyer")
		assert_int((g.nodes[id]["links"] as Array).size()).is_less_equal(3)
	assert_array(g.errors()).is_empty()


func test_граф_сообщает_о_раскладке_не_вмещающей_узел() -> void:
	var bad := NodeGraph.from_dict({
		"default_entry": "a",
		"nodes": {
			"a": {"layout": "foyer", "shards": 3, "links": ["b", "c", "d", "e"]},
			"b": {"links": ["a"]}, "c": {"links": ["a"]}, "d": {"links": ["a"]}, "e": {"links": ["a"]},
			"z": {"layout": "нет_такой", "links": []},
		},
	})
	var joined := "\n".join(bad.errors())
	assert_str(joined).contains("a: шардов 3, допустимо 1…2")
	assert_str(joined).contains("a: связей 4, слотов порталов 3")
	assert_str(joined).contains("нет_такой")


## Фойе и учебный узел — для новичков (П3): тир BASE (в игре он же «лёгкий»; понятия NORMAL нет), замок хранилища не длиннее 1 и ловушек в замке нет.
func test_узлы_с_раскладкой_фойе_имеют_тир_BASE_и_замок_не_длиннее_одного() -> void:
	var g := NodeGraph.load_file("res://data/graph.json")
	var foyers := 0
	for id: String in g.nodes:
		if str(g.nodes[id].get("layout", "")) in ["foyer", "foyer_tutorial"]:
			foyers += 1
			assert_str(g.nodes[id]["tier"]).is_equal("BASE")
			var p: Dictionary = BreachData.shared().tier_params(g.nodes[id]["tier"])
			assert_int(int(p["lock_length"])).is_less_equal(1)
			assert_int((p["lock_traps"] as Vector2i).y).is_equal(0)
	assert_int(foyers).is_equal(4)
