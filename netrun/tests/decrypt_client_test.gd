extends GdUnitTestSuite
## Расшифровка шарда сквозным путём без очков (К7): сервер узла + фейковый Мост + настоящий плоский клиент ProtoClient. ДОБЫЧА: у зашифрованного шарда с подходящим
## дешифратором кнопка «РАСШИФРОВАТЬ» -> сетка на деке -> тапы по подсвеченным клеткам (автосолвер) -> «ОТКРЫТ» -> дека возвращается к ДОБЫЧЕ, шард в ней открыт.

static var _next_port := 19191
const SESSION := "s_dec000000000001"
const FIXTURE := "res://tests/fixtures/decrypt_bridge_fixture.json"
const SHARD2 := "it_k_s2"

var _root: Node
var _server: NetServer
var _node: GrayNode
var _bridge: FakeBridge
var _cfg: NetConfig


func before_test() -> void:
	_root = Node.new()
	_root.name = "DecryptClientRoot"
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
	_node.trace_settings = {"decay_per_sec": 0.0}
	_node.start(_server, _bridge)


func after_test() -> void:
	_server.stop_net()
	_root.queue_free()


func _wait_for(cond: Callable, sec: float = 15.0) -> bool:
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


func _decrypt_buttons(deck: DeckPanel) -> Array:
	return DeckUi.buttons(deck).filter(func(b: MbButton) -> bool: return b.text == "РАСШИФРОВАТЬ")


func _open_loot(proto: ProtoClient) -> DeckPanel:
	var scene: Node3D = proto.scene
	assert_bool(await _wait_for(func(): return not scene.deck_info.is_empty() and (scene.deck_info.get("loot", []) as Array).size() == 3)).is_true()
	var deck: DeckPanel = scene.world_ui.deck
	deck.select_tab(DeckPanel.TAB_LOOT)
	await get_tree().process_frame
	await get_tree().process_frame
	return deck


func test_only_a_locked_shard_with_a_fitting_decrypter_gets_the_button() -> void:
	var proto := _client()
	var deck := await _open_loot(proto)
	var ids := _decrypt_buttons(deck).map(func(b: MbButton) -> String: return b.get_meta("item_id"))
	assert_array(ids).is_equal([SHARD2])   # тир 3 дешифратору тира 2 не по силам, открытому шарду незачем
	await proto.net.drop()


func test_decrypt_by_hand_shows_the_grid_then_open_and_returns_to_the_loot_tab() -> void:
	var proto := _client()
	var deck := await _open_loot(proto)
	(_decrypt_buttons(deck)[0] as MbButton).click()
	assert_bool(await _wait_for(func(): return deck.is_charging() and deck.charge_view().is_running())).is_true()
	var cv := deck.charge_view()
	assert_str(cv.mode).is_equal("decrypt")
	assert_str("\n".join(cv.texts())).contains("РАСШИФРОВКА")
	var path := BreachAutoSolver.solve(cv.mirror.attempt)
	for i in path.size():
		if not cv.is_running():
			break
		assert_bool((cv.cell_nodes()[path[i]] as BreachCell).is_available()).is_true()   # подсвечена клиентом без ожидания сервера
		assert_bool(cv.tap_cell(path[i])).is_true()
		assert_bool(await _wait_for(func(): return cv.mirror == null or cv.mirror.pending == null or cv.mirror.finished)).is_true()
	assert_bool(await _wait_for(func(): return "\n".join(cv.texts()).contains("ОТКРЫТ"), 6.0)).is_true()
	assert_bool(await _wait_for(func(): return not deck.is_charging(), 6.0)).is_true()
	assert_bool(await _wait_for(func(): return _decrypt_buttons(deck).is_empty())).is_true()
	assert_str("\n".join(deck.loot_texts())).contains("ШАРД  Схемы  тир 2  ОТКРЫТ")
	assert_int(_bridge.decrypt_calls).is_equal(1)
	assert_str(_bridge.doc("item", SHARD2)["data"]["payload"]).is_equal("SHARD|sh2|1|2|||||0|1")
	await proto.net.drop()


func test_cancel_keeps_the_button_and_the_shard_locked() -> void:
	var proto := _client()
	var deck := await _open_loot(proto)
	(_decrypt_buttons(deck)[0] as MbButton).click()
	assert_bool(await _wait_for(func(): return deck.is_charging() and deck.charge_view().is_running())).is_true()
	var cancel: Array = DeckUi.buttons(deck).filter(func(b: MbButton) -> bool: return b.text == "ОТМЕНА")
	(cancel[0] as MbButton).click()
	assert_bool(await _wait_for(func(): return not _node.decrypt.has_attempt(SESSION))).is_true()
	assert_bool(await _wait_for(func(): return not deck.is_charging(), 6.0)).is_true()
	assert_int(_decrypt_buttons(deck).size()).is_equal(1)
	assert_int(_bridge.decrypt_attempts).is_equal(0)
	await proto.net.drop()


# ---------------------------------------------------------------- чистая логика

func test_loot_rows_know_who_can_decrypt() -> void:
	var loot := [
		{"id": "a", "kind": "shard", "tier": 2, "title": "A", "enc": true},
		{"id": "b", "kind": "shard", "tier": 3, "title": "B", "enc": true},
		{"id": "c", "kind": "shard", "tier": 1, "title": "C", "enc": false},
		{"id": "d", "kind": "daemon", "tier": 1, "title": "D", "enc": false},
	]
	var rows := HudLogic.loot_rows(loot, [{"id": "x", "effect": "DECRYPT", "tier": 2}, {"id": "y", "effect": "GHOST", "tier": 3}])
	assert_array(rows.map(func(r): return r["can_decrypt"])).is_equal([true, false, false, false])
	assert_bool(rows[1]["no_decrypter"]).is_true()
	assert_array(HudLogic.loot_rows(loot).map(func(r): return r["can_decrypt"])).is_equal([false, false, false, false])   # без деки данных нет кнопки


func test_deck_decrypt_picks_the_nearest_tier() -> void:
	var ds := [{"effect": "DECRYPT", "tier": 3, "id": "hi"}, {"effect": "DECRYPT", "tier": 2, "id": "mid"}, {"effect": "GHOST", "tier": 1, "id": "g"}]
	assert_str(DeckDecrypt.best(ds, 1)["id"]).is_equal("mid")
	assert_str(DeckDecrypt.best(ds, 3)["id"]).is_equal("hi")
	assert_bool(DeckDecrypt.best([{"effect": "DECRYPT", "tier": 1}], 2).is_empty()).is_true()


func test_result_texts() -> void:
	assert_str(HudLogic.decrypt_result_sub({"decrypted": true, "title": "Схемы"})).is_equal("Схемы · теперь ОТКРЫТ")
	assert_str(HudLogic.decrypt_result_sub({"decrypted": false, "error": "unavailable"})).contains("Мост")
	assert_str(HudLogic.decrypt_result_sub({"decrypted": false, "early": "cancel"})).is_equal("Прервано")
	assert_str(HudLogic.decrypt_denied_text("no_decrypter")).contains("DECRYPT")
