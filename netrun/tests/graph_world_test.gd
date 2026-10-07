extends GdUnitTestSuite
## Граф узлов целиком (W1): сервер (NetServer + GraphWorld + фейковый Мост) и бот в одном процессе, как в gray_node_test.gd.
## Граф — tests/fixtures/graph_test.json (4 узла, короткие времена), Мост — graph_bridge_fixture.json.
## Критерий этапа 6: полный забег через три узла (g_a -> g_b -> g_c) с возвращением добычи на телефон.

static var _next_port := 18491
const SESSION := "s_fake000000000001"
const GRAPH := "res://tests/fixtures/graph_test.json"
const BRIDGE := "res://tests/fixtures/graph_bridge_fixture.json"

var _root: Node
var _sroot: Node
var _croot: Node
var _server: NetServer
var _world: GraphWorld
var _bridge: FakeBridge
var _bot: BotClient
var _cfg: NetConfig
var _events: Array = []


func before_test() -> void:
	_root = Node.new()
	_root.name = "GraphTestRoot"
	add_child(_root)
	_sroot = Node.new()
	_sroot.name = "S"
	_croot = Node.new()
	_croot.name = "C"
	_root.add_child(_sroot)
	_root.add_child(_croot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), _sroot.get_path())
	get_tree().set_multiplayer(SceneMultiplayer.new(), _croot.get_path())
	_cfg = NetConfig.new()
	_cfg.port = _next_port
	_next_port += 1
	_cfg.token = "t03:token-t03"
	_bridge = FakeBridge.new(BRIDGE)
	_server = NetServer.new()
	_sroot.add_child(_server)
	assert_int(_server.start(_cfg, _bridge)).is_equal(OK)
	_world = GraphWorld.new()
	_world.trace_settings = {"decay_per_sec": 0.0}  # trace не спадает: сравниваем значение до и после перехода
	_world.ice_settings = {"sight_range": 0.0}      # ICE слепы: проход чистый, тревогу трогаем сами
	_sroot.add_child(_world)
	_world.start(_server, _bridge, NodeGraph.load_file(GRAPH))
	for gn in _world.nodes.values():
		(gn as GrayNode).event.connect(func(ev: Dictionary): _events.append(ev))
	_bot = BotClient.new()
	_croot.add_child(_bot)


func after_test() -> void:
	if _bot.net != null:
		await _bot.net.drop()
	_server.stop_net()
	_root.queue_free()


func _wait_for(cond: Callable, sec: float = 30.0) -> bool:
	var t := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _kinds() -> Array:
	return _events.map(func(e): return e["kind"])


func _item_owner(id: String) -> String:
	return str(_bridge.doc(BridgeApi.T_ITEM, id)["data"]["owner"])


func _session_data() -> Dictionary:
	return _bridge.doc(BridgeApi.T_SESSION, SESSION)["data"]


func _run_through_three_nodes() -> void:
	_bot.route.assign(["g_b", "g_c"])
	_bot.start(_cfg, BotClient.Scenario.GRAPH_RUN)
	assert_bool(await _wait_for(func(): return not _bot.result.is_empty())).is_true()


func test_full_run_through_three_nodes_returns_loot() -> void:
	var seen := {"before": null, "after": [], "steps": 0}
	_world.transit_started.connect(func(s: String, from: String, _to: String):
		var ds: DaemonSession = _world.node_of(from).session_state(s)
		if seen["before"] == null:
			seen["before"] = ds
			ds.trace.add_action("noise", _world.clock.now, 5.0))  # trace 15 до первого перехода
	_world.transit_finished.connect(func(s: String, _from: String, to: String):
		seen["after"].append(_world.node_of(to).session_state(s)))
	await _run_through_three_nodes()
	assert_str(_bot.result).is_equal("clean")
	assert_array(_bot.visited).is_equal(["g_a", "g_b", "g_c"])
	assert_int(_bot.tunnels_seen).is_equal(2)
	assert_bool(_bot.shard_taken).is_true()
	assert_bool(await _wait_for(func(): return "finished" in _kinds())).is_true()
	# Добыча: шард g_c на телефоне, сессия закрыта чисто, забег закрыт одним run.finish (в узле g_c)
	assert_str(_item_owner("it_g_c_1")).is_equal("outbox:KEY_ALICE")
	assert_str(str(_session_data()["state"])).is_equal("closed")
	assert_str(str(_session_data()["outcome"])).is_equal("clean")
	assert_int(_bridge.finish_calls).is_equal(1)
	assert_bool(_server.has_avatar(SESSION)).is_false()
	# Trace и дека — те же объекты после обоих переходов, значение не потеряно
	assert_int(seen["after"].size()).is_equal(2)
	for ds in seen["after"]:
		assert_object(ds).is_same(seen["before"])
	assert_float((seen["before"] as DaemonSession).trace.value()).is_equal(15.0)
	assert_array((seen["before"] as DaemonSession).deck).is_equal(NodeLayout.DEFAULT_DECK)


func test_session_world_follows_the_player() -> void:
	_bot.route.assign(["g_b"])
	_bot.start(_cfg, BotClient.Scenario.GRAPH_RUN)
	assert_bool(await _wait_for(func(): return _bot.visited.size() == 2)).is_true()
	# Мост знает, где игрок: session.world.node — по нему узел найдёт игрока после рестарта сервера мира
	assert_bool(await _wait_for(func(): return str(_session_data().get("world", {}).get("node", "")) == "g_b")).is_true()
	assert_str(_world.where(SESSION)).is_equal("g_b")


func test_depleted_slot_refills_when_bridge_has_free_shard() -> void:
	await _run_through_three_nodes()
	assert_str(_bot.result).is_equal("clean")
	var gc := _world.node_of("g_c")
	var pk0 := GrayNode.shard_id("g_c", 0)
	var pk1 := GrayNode.shard_id("g_c", 1)
	# Вынесенный шард: слот пуст и закрыт, соседний слот не тронут
	assert_bool(_server.is_object_locked(pk0)).is_true()
	assert_bool(_server.is_object_locked(pk1)).is_false()
	assert_int(gc.empty_slots()).is_equal(1)
	# Свободного шарда в Мосте нет — слот ждёт и не оживает (не выдумываем шардов, которых Мост не выпускал)
	await get_tree().create_timer(1.8).timeout
	assert_bool(_server.is_object_locked(pk0)).is_true()
	# Мост выпустил шард в узел — по таймеру слот пополняется им
	var made := _bridge.put_doc(BridgeApi.T_ITEM, "it_g_c_3", 0, {"owner": "node:g_c", "kind": "SHARD", "payload": "shard-c3", "protected": false, "origin": "node:g_c"})
	assert_bool(made["ok"]).is_true()
	assert_bool(await _wait_for(func(): return not _server.is_object_locked(pk0), 6.0)).is_true()
	assert_str(str(gc._shard_items[pk0])).is_equal("it_g_c_3")
	assert_int(gc.empty_slots()).is_equal(0)
	assert_array(_kinds()).contains(["shard_depleted", "shard_refilled"])


## Автопополнение не идёт, пока узел в локдауне (docs/netrun.md, «Открытые вопросы», п. 2): срок слота прошёл, шард в Мосте есть —
## слот ждёт конца локдауна и только тогда оживает.
func test_refill_waits_while_node_is_locked_down() -> void:
	await _run_through_three_nodes()
	assert_bool(await _wait_for(func(): return "shard_depleted" in _kinds())).is_true()
	var gc := _world.node_of("g_c")
	var pk0 := GrayNode.shard_id("g_c", 0)
	_bridge.put_doc(BridgeApi.T_ITEM, "it_g_c_3", 0, {"owner": "node:g_c", "kind": "SHARD", "payload": "shard-c3", "protected": false, "origin": "node:g_c"})
	gc.lock_for(4.0)
	await get_tree().create_timer(2.2).timeout  # срок (1 с) и повтор (0,4 с) давно прошли
	assert_bool(gc.is_locked_down()).is_true()
	assert_bool(_server.is_object_locked(pk0)).is_true()
	assert_int(gc.empty_slots()).is_equal(1)
	assert_bool(await _wait_for(func(): return not _server.is_object_locked(pk0), 6.0)).is_true()
	assert_bool(gc.is_locked_down()).is_false()
	assert_str(str(gc._shard_items[pk0])).is_equal("it_g_c_3")


## То же при охоте Black ICE в узле: пока за кем-то в узле идёт охота, слот не пополняется; охота кончилась — пополняется.
func test_refill_waits_while_black_ice_hunts_in_the_node() -> void:
	await _run_through_three_nodes()
	assert_bool(await _wait_for(func(): return "shard_depleted" in _kinds())).is_true()
	var gc := _world.node_of("g_c")
	var pk0 := GrayNode.shard_id("g_c", 0)
	_bridge.put_doc(BridgeApi.T_ITEM, "it_g_c_3", 0, {"owner": "node:g_c", "kind": "SHARD", "payload": "shard-c3", "protected": false, "origin": "node:g_c"})
	assert_bool(gc.is_hunt_active()).is_false()
	gc._hunted["s_hunted"] = true
	assert_bool(gc.is_hunt_active()).is_true()
	await get_tree().create_timer(2.2).timeout
	assert_bool(_server.is_object_locked(pk0)).is_true()
	assert_int(gc.empty_slots()).is_equal(1)
	gc._hunted.erase("s_hunted")
	assert_bool(await _wait_for(func(): return not _server.is_object_locked(pk0), 6.0)).is_true()
	assert_int(gc.empty_slots()).is_equal(0)


## Пополнение — только до числа шардов узла из графа: лишние свободные шарды Моста слотов не получают.
func test_refill_never_exceeds_graph_shard_count() -> void:
	await _run_through_three_nodes()
	assert_bool(await _wait_for(func(): return "shard_depleted" in _kinds())).is_true()
	var gc := _world.node_of("g_c")  # в графе у g_c 2 шарда
	for n in ["it_g_c_3", "it_g_c_4", "it_g_c_5"]:
		_bridge.put_doc(BridgeApi.T_ITEM, n, 0, {"owner": "node:g_c", "kind": "SHARD", "payload": "shard-" + n, "protected": false, "origin": "node:g_c"})
	assert_bool(await _wait_for(func(): return gc.empty_slots() == 0, 6.0)).is_true()
	await get_tree().create_timer(1.5).timeout  # ещё несколько проходов пополнения
	assert_int(gc.slot_ids().size()).is_equal(2)
	assert_int(gc._shard_items.size()).is_equal(2)
	assert_int(gc.empty_slots()).is_equal(0)
	assert_str(_item_owner("it_g_c_5")).is_equal("node:g_c")  # лишний шард так и лежит свободным


func test_emergency_exit_keeps_shard_in_the_node() -> void:
	_bot.route.assign(["g_b", "g_c"])
	_bot.chaos = "emergency"
	_bot.chaos_after = 0.3
	_bot.start(_cfg, BotClient.Scenario.GRAPH_RUN)
	assert_bool(await _wait_for(func(): return not _bot.result.is_empty())).is_true()
	assert_bool(await _wait_for(func(): return "finished" in _kinds())).is_true()
	# Шард остался в узле g_c: Мост вернул его в узел, слот снова с шардом (это тот же узел, где закончился забег)
	assert_str(_item_owner("it_g_c_1")).is_equal("node:g_c")
	assert_bool(_server.is_object_locked(GrayNode.shard_id("g_c", 0))).is_false()
	assert_str(_server.holder_of(GrayNode.shard_id("g_c", 0))).is_empty()


func test_shard_carried_to_another_node_depletes_origin_slot() -> void:
	# Забег закончился в другом узле: шард из g_c ушёл в узел окончания, слот g_c пустеет
	var gc := _world.node_of("g_c")
	var pk0 := GrayNode.shard_id("g_c", 0)
	gc._taken_by["s_x"] = [pk0]
	gc.settle_shards("s_x", "g_b", "node")
	assert_bool(_server.is_object_locked(pk0)).is_true()
	assert_int(gc.empty_slots()).is_equal(1)
	# а закончился в самом g_c с добычей в узле — слот остаётся живым
	var pk1 := GrayNode.shard_id("g_c", 1)
	gc._taken_by["s_y"] = [pk1]
	gc.settle_shards("s_y", "g_c", "node")
	assert_bool(_server.is_object_locked(pk1)).is_false()


func test_locked_down_node_denies_portal_until_it_opens() -> void:
	_world.node_of("g_b").lock_for(4.0)
	_bot.route.assign(["g_b"])
	_bot.start(_cfg, BotClient.Scenario.GRAPH_RUN)
	assert_bool(await _wait_for(func(): return "lockdown" in _bot.denied_reasons)).is_true()
	assert_array(_bot.visited).is_equal(["g_a"])  # пока узел закрыт — бот у портала
	# Локдаун кончился — тот же портал открывается, и забег заканчивается как обычно
	assert_bool(await _wait_for(func(): return not _bot.result.is_empty())).is_true()
	assert_str(_bot.result).is_equal("clean")
	assert_array(_bot.visited).is_equal(["g_a", "g_b"])


func test_transit_check_reasons() -> void:
	assert_str(_server.entry_node_for.call("t03", "s_check")).is_equal("g_a")
	assert_str(_world.transit_check("s_check", "g_b")).is_empty()
	assert_str(_world.transit_check("s_check", "g_c")).is_equal("not_linked")  # тоннеля g_a -> g_c нет
	assert_str(_world.transit_check("s_check", "nowhere")).is_equal("unknown")
	_world.node_of("g_b").lock_for(5.0)
	assert_str(_world.transit_check("s_check", "g_b")).is_equal("lockdown")
	_world.node_of("g_a")._hunted["s_check"] = true
	assert_str(_world.transit_check("s_check", "g_b")).is_equal("hunt")  # под охотой портал закрыт
	assert_str(_world.transit_check("s_unknown", "g_b")).is_equal("unknown")


func test_entry_node_follows_terminal() -> void:
	# t04 по graph.entries входит в g_b, хотя в Мосте сессия записана на g_a (вход определяет граф, а не запись Моста)
	_cfg.token = "t04:token-t03"
	_bot.route.assign([])
	_bot.start(_cfg, BotClient.Scenario.GRAPH_RUN)
	assert_bool(await _wait_for(func(): return not _bot.visited.is_empty())).is_true()
	assert_str(_bot.visited[0]).is_equal("g_b")
	assert_str(_server.node_of("s_fake000000000002")).is_equal("g_b")


func test_alert_rises_cools_down_and_sharpens_ice() -> void:
	var gb := _world.node_of("g_b")  # в g_b один ICE
	var ice: IceNode = gb.ices()[0]
	assert_float(gb.alert).is_equal(0.0)
	assert_float(ice.brain.alert_scale).is_equal(1.0)
	gb.raise_alert(1.0)
	assert_float(ice.brain.alert_scale).is_equal_approx(1.5, 0.001)  # alert_boost 0.5 при полной тревоге
	await get_tree().create_timer(1.0).timeout
	assert_float(gb.alert).is_between(0.1, 0.8)  # остывает (alert_cool_sec 2): за секунду — примерно наполовину
	assert_bool(await _wait_for(func(): return gb.alert == 0.0, 5.0)).is_true()
	assert_float(ice.brain.alert_scale).is_equal(1.0)


func test_trace_in_new_node_raises_that_nodes_alert() -> void:
	var seen := {"ds": null}
	_world.transit_finished.connect(func(s: String, _f: String, to: String): seen["ds"] = _world.node_of(to).session_state(s))
	_bot.route.assign(["g_b"])
	_bot.use_ghost = false
	_bot.start(_cfg, BotClient.Scenario.GRAPH_RUN)
	assert_bool(await _wait_for(func(): return seen["ds"] != null)).is_true()
	var ds: DaemonSession = seen["ds"]
	# trace после перехода слушает НОВЫЙ узел: g_b поднимает тревогу, g_a — нет
	ds.trace.add_action("noise", _world.clock.now, 20.0)  # 60: уровень TRACE
	assert_float(_world.node_of("g_b").alert).is_greater(0.2)
	assert_float(_world.node_of("g_a").alert).is_equal(0.0)


func test_twelve_node_graph_builds_by_tier() -> void:
	var g := NodeGraph.load_file()
	var srv := NetServer.new()
	var sroot2 := Node.new()
	sroot2.name = "S2"
	_root.add_child(sroot2)
	get_tree().set_multiplayer(SceneMultiplayer.new(), sroot2.get_path())
	sroot2.add_child(srv)
	var cfg := NetConfig.new()
	cfg.port = _next_port
	_next_port += 1
	assert_int(srv.start(cfg, DictTokenVerifier.new({}))).is_equal(OK)
	var w := GraphWorld.new()
	sroot2.add_child(w)
	w.start(srv, null, g)
	assert_int(w.nodes.size()).is_equal(g.nodes.size())
	for id in g.nodes:
		var gn: GrayNode = w.node_of(id)
		assert_bool(gn.has_black_ice()).is_equal(g.tier_of(id) == "NIGHTMARE")  # Black ICE только в NIGHTMARE
		assert_int(gn.slot_ids().size()).is_equal(int(g.nodes[id]["shards"]))
		assert_int(gn.portals().size()).is_equal((g.nodes[id]["links"] as Array).size())
		var soft := 0
		for i in gn.ices():
			if not i.brain.is_black():
				soft += 1
		var expected := int(g.nodes[id]["ice"])
		if not str(g.nodes[id]["layout"]).is_empty():   # такты: Стражей узла с раскладкой — не больше, чем в её файле
			expected = mini(expected, LayoutData.cached(str(g.nodes[id]["layout"])).sentries.size())
		assert_int(soft).is_equal(expected)
	srv.stop_net()


## W1-Ч1: пустые trace_settings / ice_settings мира берутся из graph.settings["trace"] / ["ice"]; заданные снаружи главнее.
func test_empty_world_settings_come_from_graph_settings() -> void:
	var d := {"default_entry": "x_a", "entries": {}, "settings": {
		"trace": {"weights": {"seen_by_ice": 2.0}, "decay_per_sec": 0.2},
		"ice": {"sight_range": 7.0},
		"black_ice": {"sight_range": 12.0}},
		"nodes": {"x_a": {"title": "A", "tier": "BASE", "ice": 0, "shards": 1, "links": []}}}
	var srv := NetServer.new()
	var sroot2 := Node.new()
	sroot2.name = "S3"
	_root.add_child(sroot2)
	get_tree().set_multiplayer(SceneMultiplayer.new(), sroot2.get_path())
	sroot2.add_child(srv)
	var cfg := NetConfig.new()
	cfg.port = _next_port
	_next_port += 1
	assert_int(srv.start(cfg, DictTokenVerifier.new({}))).is_equal(OK)
	var w := GraphWorld.new()
	sroot2.add_child(w)
	w.start(srv, null, NodeGraph.from_dict(d))
	var gn: GrayNode = w.node_of("x_a")
	var meter := TraceMeter.new(gn.trace_settings)
	meter.add_action("seen_by_ice", 0.0, 1.0)
	assert_float(meter.value()).is_equal(2.0)                        # вес из graph.json, не умолчание 8
	assert_float(float(gn.ice_settings.get("sight_range", -1.0))).is_equal(7.0)
	assert_float(float(gn.black_ice_settings.get("sight_range", -1.0))).is_equal(12.0)   # Black ICE не смягчается числами узла
	srv.stop_net()


## L1: тревога и сроки пополнения слотов переживают рестарт сервера мира (их пишет узел в node.data.world, снимок отдаёт обратно).
func test_alert_and_refill_deadlines_survive_restart() -> void:
	var gc := _world.node_of("g_c")
	var pk0 := GrayNode.shard_id("g_c", 0)
	var pk1 := GrayNode.shard_id("g_c", 1)
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var saved := {"alert": 0.9, "alert_at": now_ms - 1000, "refill": {pk0: now_ms + 600000}}
	gc.recover([
		{"type": "node", "id": "g_c", "ver": 1, "data": {"tier": "HARD", "lockdown_until": 0, "world": saved}},
		{"type": "item", "id": "it_g_c_1", "ver": 1, "data": {"owner": "node:g_c", "kind": "SHARD", "origin": "node:g_c"}},
		{"type": "item", "id": "it_g_c_2", "ver": 1, "data": {"owner": "node:g_c", "kind": "SHARD", "origin": "node:g_c"}},
	])
	# alert_cool_sec 2: за секунду тревога остыла на половину
	assert_float(gc.alert).is_between(0.3, 0.5)
	# слот pk0 ждёт срока (10 минут), хотя свободный шард в Мосте есть; pk1 получил шард сразу
	assert_bool(_server.is_object_locked(pk0)).is_true()
	assert_bool(_server.is_object_locked(pk1)).is_false()
	assert_bool(gc._refill_at.has(pk0)).is_true()
	assert_float(float(gc._refill_at[pk0]) - gc.now()).is_greater(500.0)
	assert_str(str(gc._shard_items[pk1])).is_equal("it_g_c_1")
	gc._write_node_state()
	# и пишется обратно: срок и время записи тревоги лежат в документе узла
	assert_bool(await _wait_for(func(): return _bridge.doc(BridgeApi.T_NODE, "g_c")["data"].get("world", {}).has("refill"), 5.0)).is_true()


## Сессия из снимка Моста без вернувшегося игрока (рестарт сервера мира): по окну возврата её закрывает узел графа (run.finish emergency).
## Фейковый Мост отдаёт снимок при старте узлов, окно возврата уже идёт; сокращаем его напрямую.
func test_recovered_session_without_player_is_closed_after_grace() -> void:
	assert_array(_world.node_of("g_a").recovered_sessions).contains([SESSION])
	_server._deadline_ms[SESSION] = Time.get_ticks_msec() + 1000
	assert_bool(await _wait_for(func(): return str(_session_data()["state"]) == "closed", 10.0)).is_true()
	assert_str(str(_session_data()["outcome"])).is_equal("emergency")


## К5: описание слотов для клиента — вид хранилища (vault), тир и признак «зашифрован» лежащего шарда из документа Моста.
func test_shard_view_reports_vault_state_tier_and_encryption() -> void:
	var gc := _world.node_of("g_c")
	var pk0 := GrayNode.shard_id("g_c", 0)
	var pk1 := GrayNode.shard_id("g_c", 1)
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	gc.recover([
		{"type": "node", "id": "g_c", "ver": 1, "data": {"tier": "HARD", "lockdown_until": 0, "world": {"refill": {pk0: now_ms + 600000}}}},
		{"type": "item", "id": "it_g_c_1", "ver": 1, "data": {"owner": "node:g_c", "kind": "SHARD", "origin": "node:g_c", "shard": {"tier": 3, "decrypted": true}}},
		{"type": "item", "id": "it_g_c_2", "ver": 1, "data": {"owner": "node:g_c", "kind": "SHARD", "origin": "node:g_c"}},
	])
	var view := {}
	for e in gc.shard_view(SESSION):
		view[e["id"]] = e
	assert_str(view[pk0]["vault"]).is_equal("empty")   # слот ждёт пополнения
	assert_bool(view[pk0]["ready"]).is_false()
	assert_bool(view[pk0].has("tier")).is_false()
	assert_str(view[pk1]["vault"]).is_equal("open")    # флаг vault_requires_open выключен: лежащий шард открыт всем
	assert_bool(view[pk1]["ready"]).is_true()
	assert_int(view[pk1]["tier"]).is_equal(3)
	assert_bool(view[pk1]["enc"]).is_false()           # decrypted: true -> открыт
	# предмет без разобранного shard считается зашифрованным, тир 1
	assert_dict(GrayNode.shard_meta({})).is_equal({"tier": 1, "enc": true})
	assert_dict(GrayNode.shard_meta({"shard": {"tier": 9, "decrypted": false}})).is_equal({"tier": 3, "enc": true})
	# Мост пишет encrypted = decryptAction && !decrypted: шард без действия расшифровки открытым не становится, но и «зашифрованным» не показывается
	assert_dict(GrayNode.shard_meta({"shard": {"tier": 2, "decrypted": false, "encrypted": false}})).is_equal({"tier": 2, "enc": false})
	assert_dict(GrayNode.shard_meta({"shard": {"tier": 2, "decrypted": false, "encrypted": true}})).is_equal({"tier": 2, "enc": true})
	var docs := [{"id": "it_x", "data": {"owner": "deck:s1", "kind": "SHARD", "shard": {"tier": 1, "title": "Х", "decrypted": false, "encrypted": false}}}]
	assert_bool(GrayNode.loot_from_items(docs, "s1")[0]["enc"]).is_false()


## К5: флаг «взятие требует открытия взломом» (К3 его включит): без открытия шард закрыт, открытие действует на одну сессию и гаснет с шардом.
func test_vault_requires_open_flag_hides_shards_until_opened_for_the_session() -> void:
	var gc := _world.node_of("g_c")
	var pk1 := GrayNode.shard_id("g_c", 1)
	assert_bool(bool(gc.settings.get("vault_requires_open", true))).is_false()   # по умолчанию выключен
	assert_str(gc.vault_state(pk1, SESSION)).is_equal("open")
	gc.settings = gc.settings.duplicate()
	gc.settings["vault_requires_open"] = true
	assert_str(gc.vault_state(pk1, SESSION)).is_equal("closed")
	assert_str(gc.vault_state(pk1, "")).is_equal("closed")   # безымянная сессия не открывает чужое
	gc.open_vault(pk1, SESSION)
	assert_str(gc.vault_state(pk1, SESSION)).is_equal("open")
	assert_str(gc.vault_state(pk1, "s_other")).is_equal("closed")
	gc.close_vault(pk1)
	assert_str(gc.vault_state(pk1, SESSION)).is_equal("closed")
	# can_grab учитывает вид хранилища: закрытое не отдаётся, даже если игрок рядом (аватара нет — всё равно false, но по причине замка)
	assert_bool(gc.can_grab(SESSION, pk1)).is_false()
