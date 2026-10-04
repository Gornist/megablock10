extends GdUnitTestSuite
## Дека показывает правду (К2): сервер мира шлёт `ev deck` (RAM, рабочие демоны, груз, эдди) и состояния в `state.cd`, клиент рисует их
## на вкладках ДЕКА и ДОБЫЧА. Сервер, Мост-фейк и настоящий плоский клиент в одном процессе, как в gray_node_test.gd.

static var _next_port := 18291
const SESSION := "s_fake000000000001"
const FIXTURE := "res://tests/fixtures/deck_bridge_fixture.json"

var _root: Node
var _server: NetServer
var _node: GrayNode
var _bridge: FakeBridge
var _cfg: NetConfig


func before_test() -> void:
	_root = Node.new()
	_root.name = "DeckWorldRoot"
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
	_bridge = FakeBridge.new(FIXTURE)
	_server = NetServer.new()
	sroot.add_child(_server)
	assert_int(_server.start(_cfg, _bridge)).is_equal(OK)
	_node = GrayNode.new()
	sroot.add_child(_node)
	_node.start(_server, _bridge)


func after_test() -> void:
	_server.stop_net()
	_root.queue_free()


func _wait_for(cond: Callable, sec: float = 10.0) -> bool:
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


func test_client_gets_the_real_deck_and_loot_from_the_bridge() -> void:
	var proto := _client()
	var scene: Node3D = proto.scene
	assert_bool(await _wait_for(func(): return not scene.deck_info.is_empty() and not scene.deck_info.get("loot", []).is_empty())).is_true()
	var info: Dictionary = scene.deck_info
	assert_int(int(info["ram"])).is_equal(8)               # из session.data.ram
	assert_bool(info["ram_default"]).is_false()
	assert_int(int(info["used"])).is_equal(5)              # 3 + 2 ячейки рабочих демонов; добытый демон из узла в счёт не идёт
	assert_int(int(info["eddies"])).is_equal(75)
	# Рабочие — только принесённые с телефона; добытый в узле демон и оба шарда — груз.
	assert_array(info["daemons"].map(func(d): return d["id"])).is_equal(["it_fake000000d001", "it_fake000000d002"])
	assert_array(info["loot"].map(func(l): return l["id"])).is_equal(["it_fake000000d004", "it_fake000000e001", "it_fake000000e002"])
	assert_str(info["daemons"][0]["effect"]).is_equal("GHOST")
	assert_int(int(info["daemons"][0]["tier"])).is_equal(2)
	assert_array(info["daemons"][0]["cells"]).is_equal(["1C", "BD", "E9"])
	assert_bool((info["daemons"][1] as Dictionary).has("unsupported")).is_true()   # BLACKOUT в Сети пока не работает
	# Рабочие демоны в снимке перезарядок — те же, добытого там нет.
	assert_bool(await _wait_for(func(): return scene.deck_state.size() == 2)).is_true()
	assert_array(scene.deck_state.map(func(d): return d["id"])).is_equal(["it_fake000000d001", "it_fake000000d002"])
	var deck: DeckPanel = scene.world_ui.deck
	assert_bool(deck.has_loot_tab()).is_true()
	assert_array(deck.tab_ids()).contains([DeckPanel.TAB_LOOT])
	var loot_texts := deck.loot_texts()
	assert_str(loot_texts[1]).is_equal("Эдди  75")
	assert_str("\n".join(loot_texts)).contains("ДЕМОН  Дрожь из узла  тир 3  ОТКРЫТ")
	assert_str("\n".join(loot_texts)).contains("ШАРД  Чертежи склада  тир 2  ЗАШИФРОВАН")
	assert_str("\n".join(loot_texts)).contains("ШАРД  Накладная  тир 1  ОТКРЫТ")
	assert_bool(await _wait_for(func(): return "не работает в Сети" in "\n".join(deck.row_texts()))).is_true()
	assert_str(deck.row_texts()[1]).contains("1 Призрак").contains("готов")
	await proto.net.drop()


func test_using_a_program_shows_it_active_then_on_cooldown() -> void:
	var proto := _client()
	var scene: Node3D = proto.scene
	assert_bool(await _wait_for(func(): return scene.deck_state.size() == 2 and not scene.deck_info.is_empty())).is_true()
	scene.use_slot(0)   # GHOST, 30 с действия, 60 с перезарядки (тир 2)
	var deck: DeckPanel = scene.world_ui.deck
	assert_bool(await _wait_for(func(): return str(deck.row_texts()[1]).contains("активен"))).is_true()
	assert_str(deck.row_texts()[1]).contains("1 Призрак")
	await proto.net.drop()


func test_cd_entry_follows_ready_active_cooldown_and_unsupported() -> void:
	var node: GrayNode = auto_free(GrayNode.new())
	node.daemons.load_dir()
	var ds := DaemonSession.new(["ghost_1", "jitter_1"])
	assert_str(node.cd_entry(ds, "ghost_1", 10.0)["st"]).is_equal("ready")
	assert_bool(node.cd_entry(ds, "ghost_1", 10.0).has("until")).is_false()
	assert_bool(node.daemons.apply(ds, "ghost_1", {}, 10.0)["ok"]).is_true()   # GHOST тира 1: 20 с действия, 60 с перезарядки
	var act := node.cd_entry(ds, "ghost_1", 12.0)
	assert_str(act["st"]).is_equal("active")   # действие важнее перезарядки, которая идёт параллельно
	assert_float(act["until"]).is_equal_approx(30.0, 0.001)
	var cd := node.cd_entry(ds, "ghost_1", 31.0)
	assert_str(cd["st"]).is_equal("cooldown")
	assert_float(cd["until"]).is_equal_approx(70.0, 0.001)
	assert_float(cd["left"]).is_equal_approx(39.0, 0.001)
	assert_str(node.cd_entry(ds, "ghost_1", 71.0)["st"]).is_equal("ready")
	# JITTER: trace заморожен 15 с — это «активен».
	assert_bool(node.daemons.apply(ds, "jitter_1", {}, 100.0)["ok"]).is_true()
	assert_str(node.cd_entry(ds, "jitter_1", 105.0)["st"]).is_equal("active")
	assert_float(node.cd_entry(ds, "jitter_1", 105.0)["until"]).is_equal_approx(115.0, 0.001)
	assert_str(node.cd_entry(ds, "jitter_1", 116.0)["st"]).is_equal("cooldown")
	# Эффект, которого нет в Сети: виден, но не работает.
	node.daemons.add_item_daemon("x1", {"effect": "BLACKOUT", "tier": 1, "name": "Затмение"})
	ds.deck.append("x1")
	assert_str(node.cd_entry(ds, "x1", 0.0)["st"]).is_equal("unsupported")


func test_deck_view_without_ram_from_the_bridge_uses_the_default_and_marks_it() -> void:
	var node: GrayNode = auto_free(GrayNode.new())
	node.daemons.load_dir()
	var ds := DaemonSession.new(NodeLayout.DEFAULT_DECK)
	var view := node.deck_view(ds)
	assert_int(view["ram"]).is_equal(DaemonSession.DEFAULT_RAM)
	assert_int(DaemonSession.DEFAULT_RAM).is_equal(6)
	assert_bool(view["ram_default"]).is_true()
	assert_int(view["used"]).is_equal(0)
	assert_array(view["daemons"].map(func(d): return d["name"])).is_equal(["Призрак", "Дрожь"])
	assert_array(view["loot"]).is_empty()
