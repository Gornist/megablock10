extends GdUnitTestSuite
## Отправка добычи другому игроку (К5б), сервер мира: два настоящих клиента сети, GrayNode, GiveService и фейковый Мост (op_give_item повторяет
## контракт 6.7). Проверки сервера — предмет в ГРУЗе и его можно отдать, получатель в Сети, ключ похож на ключ; ценности двигает Мост.

static var _next_port := 18491
const ALICE := "s_give00000000001"
const BOB := "s_give00000000002"
const FIXTURE := "res://tests/fixtures/give_bridge_fixture.json"
const SHARD := "it_g_e001"
const DAEMON := "it_g_e002"
const CARRIED_SHARD := "it_g_e003"
const PROTECTED := "it_g_d001"
const WORKING := "it_g_d002"
const PHONE := "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAECarol00000000000000000000000000000000000000000000000000000000000000="

var _root: Node
var _server: NetServer
var _node: GrayNode
var _give: GiveService
var _bridge: FakeBridge
var _cfg: NetConfig
var _clients: Dictionary = {}   # сессия -> {net, evs}


func before_test() -> void:
	_root = Node.new()
	_root.name = "GiveTestRoot"
	add_child(_root)
	var sroot := Node.new()
	sroot.name = "S"
	_root.add_child(sroot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), sroot.get_path())
	_cfg = NetConfig.new()
	_cfg.port = _next_port
	_next_port += 1
	_bridge = FakeBridge.new(FIXTURE)
	_server = NetServer.new()
	sroot.add_child(_server)
	assert_int(_server.start(_cfg, _bridge)).is_equal(OK)
	_node = GrayNode.new()
	sroot.add_child(_node)
	_node.start(_server, _bridge)
	_give = GiveService.new()
	sroot.add_child(_give)
	_give.start(_server, _bridge, func(s: String) -> GrayNode: return _node if _node.has_session(s) else null, func() -> Array: return [_node])
	_give.retry_sec = 0.02
	_give.settle_sec = 0.05
	_clients.clear()


func after_test() -> void:
	for s in _clients:
		await _clients[s]["net"].drop()
	_server.stop_net()
	_root.queue_free()


func _wait_for(cond: Callable, sec: float = 10.0) -> bool:
	var t := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


## Игрок подключён и получил деку; evs — все его события.
func _join(session: String, terminal: String) -> Dictionary:
	var croot := Node.new()
	croot.name = "C_" + session
	_root.add_child(croot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), croot.get_path())
	var net := NetClient.new()
	croot.add_child(net)
	var cfg := NetConfig.new()
	cfg.port = _cfg.port
	cfg.token = "%s:token-t03" % terminal
	var evs: Array = []
	net.event_received.connect(func(ev: Dictionary): evs.append(ev))
	assert_int(net.start_client(cfg)).is_equal(OK)
	var c := {"net": net, "evs": evs}
	_clients[session] = c
	assert_bool(await _wait_for(func(): return _last(c, "deck") != null)).is_true()
	return c


func _both() -> void:
	await _join(ALICE, "t03")
	await _join(BOB, "t04")


func _last(c: Dictionary, kind: String, dir: String = "") -> Variant:
	var found: Variant = null
	for ev in c["evs"]:
		if ev.get("kind") == kind and (dir == "" or ev.get("dir") == dir):
			found = ev
	return found


func _count(c: Dictionary, kind: String, dir: String = "") -> int:
	var n := 0
	for ev in c["evs"]:
		if ev.get("kind") == kind and (dir == "" or ev.get("dir") == dir):
			n += 1
	return n


func _loot_ids(c: Dictionary) -> Array:
	var ev: Variant = _last(c, "deck")
	return [] if ev == null else (ev["loot"] as Array).map(func(l): return l["id"])


func _runner_id(c: Dictionary) -> int:
	var before := _count(c, "give_list")
	c["net"].request_give_list()
	assert_bool(await _wait_for(func(): return _count(c, "give_list") > before)).is_true()
	var runners: Array = _last(c, "give_list")["runners"]
	return int(runners[0]["id"]) if not runners.is_empty() else 0


## Отправить и дождаться ответа give (dir out).
func _give_and_wait(c: Dictionary, item: String, to: Dictionary) -> Dictionary:
	var before := _count(c, "give", "out")
	c["net"].request_give(item, to)
	assert_bool(await _wait_for(func(): return _count(c, "give", "out") > before)).is_true()
	return _last(c, "give", "out")


# ---------------------------------------------------------------- чистая логика

func test_parse_target_takes_exactly_one_recipient() -> void:
	assert_dict(GiveService.parse_target({"runner": 3})).is_equal({"runner": 3})
	assert_dict(GiveService.parse_target({"runner": 3.0})).is_equal({"runner": 3})
	assert_dict(GiveService.parse_target({"phone": "abc"})).is_equal({"phone": "abc"})
	assert_dict(GiveService.parse_target({})).is_empty()
	assert_dict(GiveService.parse_target({"runner": 3, "phone": "abc"})).is_empty()
	assert_dict(GiveService.parse_target({"runner": "3"})).is_empty()


func test_phone_key_must_look_like_a_key() -> void:
	assert_bool(GiveService.valid_phone_key(PHONE)).is_true()
	assert_bool(GiveService.valid_phone_key("")).is_false()
	assert_bool(GiveService.valid_phone_key("не ключ, а текст который длинный")).is_false()
	assert_bool(GiveService.valid_phone_key("короткий")).is_false()
	assert_bool(GiveService.valid_phone_key("A".repeat(300))).is_false()
	assert_bool(GiveService.valid_phone_key("MFkwEwYHKoZIzj0CAQYI KoZIzj0DAQcDQgAE")).is_false()
	assert_bool(GiveService.valid_phone_key(FakePhoneLink.fake_key("ВОБЛА"))).is_true()


func test_bridge_codes_map_to_reasons_for_the_player() -> void:
	assert_str(GiveService.error_for("wrong_owner")).is_equal(WorldMsg.GIVE_GONE)
	assert_str(GiveService.error_for("protected_item")).is_equal(WorldMsg.GIVE_NOT_LOOT)
	assert_str(GiveService.error_for("loaded_item")).is_equal(WorldMsg.GIVE_NOT_LOOT)
	assert_str(GiveService.error_for("session_state")).is_equal(WorldMsg.GIVE_BUSY)
	assert_str(GiveService.error_for("rid_mismatch")).is_equal(WorldMsg.GIVE_REFUSED)
	for r in WorldMsg.GIVE_ERRORS:
		assert_str(HudLogic.give_error_text(r)).is_not_empty()


func test_loot_marks_what_can_be_given() -> void:
	var sdata: Dictionary = {"loaded": [PROTECTED, WORKING, CARRIED_SHARD], "runner": "x"}
	var docs: Array = []
	for id in [SHARD, DAEMON, CARRIED_SHARD, PROTECTED, WORKING]:
		docs.append({"id": id, "data": _bridge.doc("item", id)["data"]})
	var loot := GrayNode.loot_from_items(docs, ALICE, sdata)
	var give := {}
	for l in loot:
		give[l["id"]] = l["give"]
	assert_dict(give).is_equal({SHARD: true, DAEMON: true, CARRIED_SHARD: false})   # сданное при входе, пусть и шард, отдавать нельзя


# ---------------------------------------------------------------- нетраннер в Сети

func test_recipients_list_shows_other_runners_in_the_net() -> void:
	await _both()
	var alice: Dictionary = _clients[ALICE]
	var bob_id := await _runner_id(alice)
	assert_int(bob_id).is_equal(_server.avatar_id(BOB))
	var row: Dictionary = (_last(alice, "give_list")["runners"] as Array)[0]
	assert_str(row["name"]).is_equal("Лис")
	assert_bool(row["same"]).is_true()
	assert_int((_last(alice, "give_list")["runners"] as Array).size()).is_equal(1)   # себя в списке нет


func test_give_to_a_runner_moves_the_item_and_tells_both() -> void:
	await _both()
	var alice: Dictionary = _clients[ALICE]
	var bob: Dictionary = _clients[BOB]
	assert_array(_loot_ids(alice)).contains([SHARD, DAEMON])
	var bob_id := await _runner_id(alice)
	var res := await _give_and_wait(alice, SHARD, {"runner": bob_id})
	assert_bool(res["ok"]).is_true()
	assert_str(res["via"]).is_equal("runner")
	assert_str(res["who"]).is_equal("Лис")
	assert_str(res["title"]).is_equal("Чертежи склада")
	assert_str(_bridge.doc("item", SHARD)["data"]["owner"]).is_equal("deck:" + BOB)
	assert_int(_bridge.give_calls).is_equal(1)
	# получатель: событие и новый груз
	assert_bool(await _wait_for(func(): return _count(bob, "give", "in") == 1 and _loot_ids(bob).has(SHARD))).is_true()
	var inc: Dictionary = _last(bob, "give", "in")
	assert_str(inc["from"]).is_equal("Призрак")
	assert_str(inc["title"]).is_equal("Чертежи склада")
	assert_int(int(inc["tier"])).is_equal(2)
	# отправитель: груз без предмета
	assert_bool(await _wait_for(func(): return not _loot_ids(alice).has(SHARD))).is_true()
	assert_array(_loot_ids(alice)).contains([DAEMON])
	# у получателя это груз, рабочим демоном он не стал
	assert_array((_last(bob, "deck")["daemons"] as Array).map(func(d): return d["id"])).is_equal(["it_g_d003"])


func test_a_daemon_from_the_loot_can_be_given_too() -> void:
	await _both()
	var alice: Dictionary = _clients[ALICE]
	var res := await _give_and_wait(alice, DAEMON, {"runner": await _runner_id(alice)})
	assert_bool(res["ok"]).is_true()
	assert_str(_bridge.doc("item", DAEMON)["data"]["owner"]).is_equal("deck:" + BOB)


func test_the_item_can_come_back_and_leave_again() -> void:
	await _both()
	var alice: Dictionary = _clients[ALICE]
	var bob: Dictionary = _clients[BOB]
	var bob_id := await _runner_id(alice)
	var alice_id := await _runner_id(bob)
	assert_bool((await _give_and_wait(alice, SHARD, {"runner": bob_id}))["ok"]).is_true()
	assert_bool(await _wait_for(func(): return _loot_ids(bob).has(SHARD))).is_true()
	assert_bool((await _give_and_wait(bob, SHARD, {"runner": alice_id}))["ok"]).is_true()
	assert_bool(await _wait_for(func(): return _loot_ids(alice).has(SHARD))).is_true()
	assert_bool((await _give_and_wait(alice, SHARD, {"runner": bob_id}))["ok"]).is_true()   # A -> B -> A -> B: новая версия — новый rid
	assert_int(_bridge.give_calls).is_equal(3)
	assert_str(_bridge.doc("item", SHARD)["data"]["owner"]).is_equal("deck:" + BOB)


# ---------------------------------------------------------------- контакт телефона

func test_give_to_a_phone_contact_leaves_the_run_through_the_outbox() -> void:
	await _both()
	var alice: Dictionary = _clients[ALICE]
	var res := await _give_and_wait(alice, SHARD, {"phone": PHONE})
	assert_bool(res["ok"]).is_true()
	assert_str(res["via"]).is_equal("phone")
	var item: Dictionary = _bridge.doc("item", SHARD)["data"]
	assert_str(item["owner"]).is_equal("outbox:" + PHONE)
	assert_str(item["handover"]).is_equal("PENDING")
	assert_bool(await _wait_for(func(): return not _loot_ids(alice).has(SHARD))).is_true()
	assert_int(_count(_clients[BOB], "give", "in")).is_equal(0)   # нетраннеру в Сети сообщать нечего
	# повторно тот же предмет — его уже нет в ГРУЗе
	var again := await _give_and_wait(alice, SHARD, {"phone": PHONE})
	assert_bool(again["ok"]).is_false()
	assert_str(again["error"]).is_equal(WorldMsg.GIVE_NOT_LOOT)
	assert_int(_bridge.give_calls).is_equal(1)


# ---------------------------------------------------------------- отказы

func test_protected_working_and_carried_in_items_are_refused_before_the_bridge() -> void:
	await _both()
	var alice: Dictionary = _clients[ALICE]
	var bob_id := await _runner_id(alice)
	for item in [PROTECTED, WORKING, CARRIED_SHARD, "it_g_nope", "it_g_d003"]:
		var res := await _give_and_wait(alice, item, {"runner": bob_id})
		assert_bool(res["ok"]).is_false()
		assert_str(res["error"]).is_equal(WorldMsg.GIVE_NOT_LOOT)
	assert_int(_bridge.give_attempts).is_equal(0)
	assert_str(_bridge.doc("item", PROTECTED)["data"]["owner"]).is_equal("deck:" + ALICE)


func test_bad_recipients_are_refused() -> void:
	await _both()
	var alice: Dictionary = _clients[ALICE]
	assert_str((await _give_and_wait(alice, SHARD, {"runner": _server.avatar_id(ALICE)}))["error"]).is_equal(WorldMsg.GIVE_SELF)
	assert_str((await _give_and_wait(alice, SHARD, {"runner": 999}))["error"]).is_equal(WorldMsg.GIVE_NO_RECIPIENT)
	assert_str((await _give_and_wait(alice, SHARD, {}))["error"]).is_equal(WorldMsg.GIVE_NO_RECIPIENT)
	assert_str((await _give_and_wait(alice, SHARD, {"phone": "не ключ"}))["error"]).is_equal(WorldMsg.GIVE_BAD_CONTACT)
	var own: String = _bridge.doc("session", ALICE)["data"]["runner"]
	assert_str((await _give_and_wait(alice, SHARD, {"phone": own}))["error"]).is_equal(WorldMsg.GIVE_SELF)   # на свой телефон нельзя
	assert_int(_bridge.give_calls).is_equal(0)
	assert_str(_bridge.doc("item", SHARD)["data"]["owner"]).is_equal("deck:" + ALICE)


func test_a_runner_who_is_leaving_is_not_a_recipient() -> void:
	await _both()
	var alice: Dictionary = _clients[ALICE]
	var bob_id := await _runner_id(alice)
	_node._finishing[BOB] = true   # у Боба идёт исход: ему ничего не отдают и в списке его нет
	assert_str((await _give_and_wait(alice, SHARD, {"runner": bob_id}))["error"]).is_equal(WorldMsg.GIVE_NO_RECIPIENT)
	assert_int(await _runner_id(alice)).is_equal(0)
	_node._finishing.erase(BOB)
	_node._finishing[ALICE] = true   # и сам отправитель в исходе — отдавать нечего
	assert_str((await _give_and_wait(alice, SHARD, {"runner": bob_id}))["error"]).is_equal(WorldMsg.GIVE_BUSY)
	assert_int(_bridge.give_attempts).is_equal(0)


func test_bridge_refusal_is_reported_and_nothing_moves() -> void:
	await _both()
	var alice: Dictionary = _clients[ALICE]
	var bob_id := await _runner_id(alice)
	var s: Dictionary = _bridge.doc("session", BOB)
	var d: Dictionary = (s["data"] as Dictionary).duplicate()
	d["state"] = "pending"   # Мост знает, что получатель ещё не в забеге
	_bridge._put("session", BOB, d)
	var res := await _give_and_wait(alice, SHARD, {"runner": bob_id})
	assert_str(res["error"]).is_equal(WorldMsg.GIVE_BUSY)
	assert_str(_bridge.doc("item", SHARD)["data"]["owner"]).is_equal("deck:" + ALICE)
	assert_bool(_loot_ids(alice).has(SHARD)).is_true()


# ---------------------------------------------------------------- обрывы связи

func test_lost_reply_after_the_bridge_committed_still_counts_as_given() -> void:
	await _both()
	var alice: Dictionary = _clients[ALICE]
	var bob_id := await _runner_id(alice)
	_bridge.give_drop_reply = true   # Мост записал, ответ потерялся; повтор с тем же rid вернёт сохранённый
	var res := await _give_and_wait(alice, SHARD, {"runner": bob_id})
	assert_bool(res["ok"]).is_true()
	assert_int(_bridge.give_calls).is_equal(1)
	assert_str(_bridge.doc("item", SHARD)["data"]["owner"]).is_equal("deck:" + BOB)


func test_no_bridge_connection_reports_unavailable_and_keeps_the_item() -> void:
	await _both()
	var alice: Dictionary = _clients[ALICE]
	var bob_id := await _runner_id(alice)
	_bridge.give_offline = true
	var res := await _give_and_wait(alice, SHARD, {"runner": bob_id})
	assert_bool(res["ok"]).is_false()
	assert_str(res["error"]).is_equal(WorldMsg.GIVE_UNAVAILABLE)
	assert_int(_bridge.give_attempts).is_equal(GiveService.NET_ATTEMPTS)
	assert_str(_bridge.doc("item", SHARD)["data"]["owner"]).is_equal("deck:" + ALICE)
	_bridge.give_offline = false   # связь вернулась — тот же предмет уходит
	assert_bool((await _give_and_wait(alice, SHARD, {"runner": bob_id}))["ok"]).is_true()


func test_inflight_gives_hold_back_the_end_of_the_run() -> void:
	await _both()
	_node.begin_inflight(ALICE)
	assert_int(int(_node._takes_inflight[ALICE])).is_equal(1)   # _finish_in_bridge ждёт, пока счётчик не обнулится
	_node.end_inflight(ALICE)
	_node.end_inflight(ALICE)
	assert_int(int(_node._takes_inflight[ALICE])).is_equal(0)


# ---------------------------------------------------------------- слот шарда

func test_a_given_shard_does_not_come_back_to_its_pedestal_after_a_soft_ice_exit() -> void:
	await _both()
	var sid := NetConfig.PICKUP_ID
	_node._shard_items[sid] = SHARD
	_node._taken_by[ALICE] = [sid]
	_node.note_given(SHARD)
	_node.settle_shards(ALICE, "node_07", "node")   # добыча осталась в узле — но этот шард ушёл к другому игроку
	assert_bool(_node._refill_at.has(sid)).is_true()
	assert_bool(_node._shard_items.has(sid)).is_false()
	# без отдачи слот остаётся с шардом (прежнее поведение)
	var sid2 := "node_07_other"
	_node._shard_items[sid2] = "it_x"
	_node._taken_by[BOB] = [sid2]
	_node.settle_shards(BOB, "node_07", "node")
	assert_str(str(_node._shard_items[sid2])).is_equal("it_x")


func test_a_refusal_for_one_recipient_does_not_block_giving_to_another() -> void:
	await _both()
	var alice: Dictionary = _clients[ALICE]
	var bob_id := await _runner_id(alice)
	var d: Dictionary = (_bridge.doc("session", BOB)["data"] as Dictionary).duplicate()
	d["state"] = "pending"   # Мост откажет session_state и запомнит отказ по rid
	_bridge._put("session", BOB, d)
	assert_str((await _give_and_wait(alice, SHARD, {"runner": bob_id}))["error"]).is_equal(WorldMsg.GIVE_BUSY)
	# тот же предмет, та же версия, другой получатель: в rid другой получатель, rid_mismatch нет
	var res := await _give_and_wait(alice, SHARD, {"phone": PHONE})
	assert_bool(res["ok"]).is_true()
	assert_str(_bridge.doc("item", SHARD)["data"]["owner"]).is_equal("outbox:" + PHONE)


func test_give_rid_carries_the_recipient_digest() -> void:
	# эталон — ValueOpsGiveTest.giveRidCarriesTheRecipientDigest (Мост, Kotlin)
	assert_str(BridgeApi.give_rid("s_a", "it_x", 4, "s_77ab03c1d2e4f5a6")).is_equal("give:s_a:it_x:4:1d7ad1cb")
	assert_str(BridgeApi.give_rid("s_a", "it_x", 4, PHONE)).is_equal("give:s_a:it_x:4:1c166256")
	assert_str(BridgeApi.give_rid("s_a", "it_x", 4, "s_b")).is_not_equal(BridgeApi.give_rid("s_a", "it_x", 4, "s_c"))


# ---------------------------------------------------------------- задержанный коммит

func test_a_commit_that_lands_after_the_link_dropped_still_counts_and_holds_the_run() -> void:
	await _both()
	var alice: Dictionary = _clients[ALICE]
	var bob_id := await _runner_id(alice)
	# Мост «завис»: запросы дают обрыв (5 попыток по 0.02 с), а запись ложится через 0.25 с — позже, чем кончились повторы
	_bridge.give_late_commit_sec = 0.25
	var before := _count(alice, "give", "out")
	alice["net"].request_give(SHARD, {"runner": bob_id})
	assert_bool(await _wait_for(func(): return _node._takes_inflight.get(ALICE, 0) > 0)).is_true()
	await get_tree().create_timer(0.12).timeout   # повторы кончились, коммита ещё нет — но исход отправителя по-прежнему ждёт
	assert_str(_bridge.doc("item", SHARD)["data"]["owner"]).is_equal("deck:" + ALICE)
	assert_int(int(_node._takes_inflight.get(ALICE, 0))).is_equal(1)
	assert_bool(await _wait_for(func(): return _count(alice, "give", "out") > before)).is_true()
	assert_bool(_last(alice, "give", "out")["ok"]).is_true()   # перечитывание после паузы увидело предмет у получателя
	assert_str(_bridge.doc("item", SHARD)["data"]["owner"]).is_equal("deck:" + BOB)
	assert_int(_bridge.give_calls).is_equal(1)
	assert_int(int(_node._takes_inflight.get(ALICE, 0))).is_equal(0)


func test_a_commit_that_never_lands_is_reported_unavailable_after_the_waits() -> void:
	await _both()
	var alice: Dictionary = _clients[ALICE]
	var bob_id := await _runner_id(alice)
	_bridge.give_late_commit_sec = 60.0
	var res := await _give_and_wait(alice, SHARD, {"runner": bob_id})
	assert_bool(res["ok"]).is_false()
	assert_str(res["error"]).is_equal(WorldMsg.GIVE_UNAVAILABLE)
	assert_str(_bridge.doc("item", SHARD)["data"]["owner"]).is_equal("deck:" + ALICE)


# ---------------------------------------------------------------- дека изменилась перед исходом

func test_finish_rebuilds_moves_when_an_item_arrives_before_run_finish() -> void:
	await _both()
	var new_item := "it_g_late"
	var late := {"type": "item", "id": new_item, "ver": 1, "data": {"owner": "deck:" + ALICE, "kind": "SHARD", "payload": "shL", "protected": false,
		"origin": "node:node_07", "shard": {"tier": 1, "title": "Пришёл по отдаче", "decrypted": true}}}
	# moves уже собраны без нового шарда, и тут Боб отдаёт его Алисе: Мост ответит bad_request «не упомянут в moves»
	_bridge.before_finish = func(): _bridge._docs["item"][new_item] = late
	await _node._finish_in_bridge({"session": ALICE, "reason": "clean"})
	assert_int(_bridge.finish_attempts.size()).is_equal(2)   # тот же rid, пересобранные moves
	assert_str(_bridge.doc("session", ALICE)["data"]["state"]).is_equal("closed")
	assert_str(_bridge.doc("item", new_item)["data"]["owner"]).is_not_equal("deck:" + ALICE)


func test_stale_moves_answer_is_recognized_only_for_that_bad_request() -> void:
	assert_bool(GrayNode.is_moves_stale(BridgeApi.err("bad_request", "it_x не упомянут в moves"))).is_true()
	assert_bool(GrayNode.is_moves_stale(BridgeApi.err("bad_request", "узел не тот"))).is_false()
	assert_bool(GrayNode.is_moves_stale(BridgeApi.err("unavailable", "не упомянут в moves"))).is_false()
	assert_bool(GrayNode.is_moves_stale(BridgeApi.ok())).is_false()


# ---------------------------------------------------------------- слот шарда: отданный и вернувшийся

func test_a_shard_that_came_back_to_its_taker_leaves_the_pedestal_alone() -> void:
	await _both()
	var sid := NetConfig.PICKUP_ID
	_node._shard_items[sid] = SHARD
	_node._taken_by[ALICE] = [sid]
	_node.note_given(SHARD, BOB)     # A -> B
	_node.note_given(SHARD, ALICE)   # B -> A: шард снова у Алисы
	_node.settle_shards(ALICE, "node_07", "node")   # выброс: груз вернулся в узел, слот не пустеет
	assert_bool(_node._refill_at.has(sid)).is_false()
	assert_str(str(_node._shard_items[sid])).is_equal(SHARD)
	# отдан дальше (A -> B -> A -> телефон): слот пустеет
	var sid2 := "node_07_two"
	_node._shard_items[sid2] = DAEMON
	_node._taken_by[ALICE] = [sid2]
	_node.note_given(DAEMON, ALICE)
	_node.note_given(DAEMON, "")
	_node.settle_shards(ALICE, "node_07", "node")
	assert_bool(_node._refill_at.has(sid2)).is_true()


func test_a_shard_laid_back_into_a_slot_forgets_the_old_giving() -> void:
	await _both()
	var sid := NetConfig.PICKUP_ID
	_node._shard_items.erase(sid)
	_node.note_given(SHARD, BOB)   # ушёл к Бобу, тот выбросился: шард снова в узле (Мост) и слот привязывает его заново
	var d: Dictionary = (_bridge.doc("item", SHARD)["data"] as Dictionary).duplicate()
	d["owner"] = "node:node_07"
	_bridge._put("item", SHARD, d)
	_node._refill_at[sid] = 0.0
	await _node._refill(sid)
	assert_str(str(_node._shard_items.get(sid, ""))).is_equal(SHARD)
	assert_bool(_node.is_given_away(SHARD, ALICE)).is_false()
	# игрок берёт его и выбрасывается: слот остаётся с шардом, а не пустеет по старой отдаче
	_node._taken_by[ALICE] = [sid]
	_node.settle_shards(ALICE, "node_07", "node")
	assert_bool(_node._refill_at.has(sid)).is_false()
