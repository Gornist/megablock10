extends GdUnitTestSuite
## Отправка добычи (К5б) сквозь настоящую сеть: плоский клиент (ProtoClient, дека на руке) нажимает «ОТПРАВИТЬ», сервер мира и фейковый Мост
## двигают предмет. Второй игрок — сетевой клиент без сцены, он только принимает события.

static var _next_port := 18591
const ALICE := "s_give00000000001"
const BOB := "s_give00000000002"
const FIXTURE := "res://tests/fixtures/give_bridge_fixture.json"
const SHARD := "it_g_e001"

var _root: Node
var _server: NetServer
var _node: GrayNode
var _give: GiveService
var _bridge: FakeBridge
var _cfg: NetConfig
var _bob_net: NetClient
var _bob_evs: Array = []


func before_test() -> void:
	_root = Node.new()
	_root.name = "GiveClientRoot"
	add_child(_root)
	for n in ["S", "C", "B"]:
		var r := Node.new()
		r.name = n
		_root.add_child(r)
		get_tree().set_multiplayer(SceneMultiplayer.new(), r.get_path())
	_cfg = NetConfig.new()
	_cfg.port = _next_port
	_next_port += 1
	_bridge = FakeBridge.new(FIXTURE)
	_server = NetServer.new()
	_root.get_node("S").add_child(_server)
	assert_int(_server.start(_cfg, _bridge)).is_equal(OK)
	_node = GrayNode.new()
	_root.get_node("S").add_child(_node)
	_node.start(_server, _bridge)
	_give = GiveService.new()
	_root.get_node("S").add_child(_give)
	_give.start(_server, _bridge, func(s: String) -> GrayNode: return _node if _node.has_session(s) else null, func() -> Array: return [_node])
	_bob_net = null
	_bob_evs = []


func after_test() -> void:
	if _bob_net != null:
		await _bob_net.drop()
	_server.stop_net()
	_root.queue_free()


func _wait_for(cond: Callable, sec: float = 10.0) -> bool:
	var t := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _alice() -> ProtoClient:
	var proto := ProtoClient.new()
	_root.get_node("C").add_child(proto)
	proto.start(PackedStringArray(["--token=t03:token-t03", "--port=%d" % _cfg.port]), "flat", false)
	return proto


func _bob() -> void:
	_bob_net = NetClient.new()
	_root.get_node("B").add_child(_bob_net)
	var cfg := NetConfig.new()
	cfg.port = _cfg.port
	cfg.token = "t04:token-t03"
	_bob_net.event_received.connect(func(ev: Dictionary): _bob_evs.append(ev))
	assert_int(_bob_net.start_client(cfg)).is_equal(OK)


func _loot_buttons(deck: DeckPanel) -> Array:
	return DeckUi.buttons(deck._loot_scroll).filter(func(b: MbButton) -> bool: return b.text == "ОТПРАВИТЬ")


func test_player_sends_a_shard_to_another_runner_from_the_deck() -> void:
	var proto := _alice()
	_bob()
	var deck: DeckPanel = proto.scene.world_ui.deck
	assert_bool(await _wait_for(func(): return deck.has_loot_tab() and _server.avatar_id(BOB) > 0 and _bob_evs.size() > 0)).is_true()
	deck.select_tab(DeckPanel.TAB_LOOT)
	assert_bool(await _wait_for(func(): return not _loot_buttons(deck).is_empty())).is_true()
	deck.open_give(SHARD)   # кнопка «ОТПРАВИТЬ» на строке шарда
	assert_bool(await _wait_for(func(): return not deck.give_view().targets().filter(func(t): return t["kind"] == "runner").is_empty())).is_true()
	assert_str(deck.give_view().targets()[0]["label"]).is_equal("Лис")   # нетраннеры в Сети — первыми
	deck.give_view().choose(0)
	deck.give_view().confirm()
	assert_bool(await _wait_for(func(): return deck.give_status().begins_with("ОТПРАВЛЕНО"))).is_true()
	assert_str(deck.give_status()).is_equal("ОТПРАВЛЕНО: Чертежи склада > Лис")
	assert_str(_bridge.doc("item", SHARD)["data"]["owner"]).is_equal("deck:" + BOB)
	assert_bool(await _wait_for(func(): return not deck._loot_rows.any(func(r: Dictionary) -> bool: return r["id"] == SHARD))).is_true()
	assert_bool(await _wait_for(func(): return _bob_evs.any(func(e): return e.get("kind") == "give" and e.get("dir") == "in"))).is_true()
	await proto.net.drop()


func test_player_sends_a_shard_to_a_phone_contact() -> void:
	var proto := _alice()
	var deck: DeckPanel = proto.scene.world_ui.deck
	assert_bool(await _wait_for(func(): return deck.has_loot_tab())).is_true()
	deck.select_tab(DeckPanel.TAB_LOOT)
	assert_bool(await _wait_for(func(): return not _loot_buttons(deck).is_empty())).is_true()
	deck.open_give(SHARD)
	assert_bool(await _wait_for(func(): return deck.give_view().targets().size() >= 3)).is_true()   # контакты телефона видны сразу
	var idx := deck.give_view().targets().find_custom(func(t: Dictionary) -> bool: return t["label"] == "ВОБЛА")
	assert_int(idx).is_greater_equal(0)
	deck.give_view().choose(idx)
	deck.give_view().confirm()
	assert_bool(await _wait_for(func(): return deck.give_status().begins_with("ОТПРАВЛЕНО"))).is_true()
	assert_str(deck.give_status()).is_equal("ОТПРАВЛЕНО: Чертежи склада > ВОБЛА")
	var item: Dictionary = _bridge.doc("item", SHARD)["data"]
	assert_str(item["owner"]).is_equal("outbox:" + FakePhoneLink.fake_key("ВОБЛА"))
	assert_str(item["handover"]).is_equal("PENDING")
	await proto.net.drop()
