extends GdUnitTestSuite
## Расшифровка шарда на месте (К7), сервер узла: фейковый Мост, настоящий клиент сети и автосолвер. Мини-игра for_decrypt (цепочка шифр-замка, буфер = цепочка + 2,
## ловушек нет); выиграна — сервер зовёт Мост (op.decrypt_item, меняется один флаг в payload), шард в ГРУЗе становится ОТКРЫТ. Мост: повтор по rid ничего не дублирует,
## обрыв связи и потерянный ответ не ломают, отказ Моста не теряет шард. Кошелёк коллектора не трогается (отдельной записи расшифровка не пишет).

static var _next_port := 18431
const SESSION := "s_dec000000000001"
const FIXTURE := "res://tests/fixtures/decrypt_bridge_fixture.json"
const SHARD2 := "it_k_s2"
const SHARD3 := "it_k_s3"
const OPEN := "it_k_open"

var _root: Node
var _server: NetServer
var _node: GrayNode
var _bridge: FakeBridge
var _cfg: NetConfig
var _events: Array = []


class Peer:
	extends RefCounted
	var net: NetClient
	var evs: Array = []
	var mirror: BreachMirror
	var ends: Array = []
	var nos: Array = []

	func last_deck() -> Dictionary:
		var decks := evs.filter(func(e): return e.get("kind") == WorldMsg.EV_DECK)
		return {} if decks.is_empty() else decks[-1]

	func loot_row(id: String) -> Dictionary:
		for l in last_deck().get("loot", []):
			if l["id"] == id:
				return l
		return {}


func before_test() -> void:
	_events.clear()
	_root = Node.new()
	_root.name = "DecryptWorldRoot"
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
	_node.event.connect(func(ev: Dictionary): _events.append(ev))
	_node.start(_server, _bridge)
	_node.decrypt.retry_sec = 0.02


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


func _peer() -> Peer:
	var p := Peer.new()
	p.net = NetClient.new()
	_root.get_node("C").add_child(p.net)
	p.net.event_received.connect(func(ev: Dictionary):
		p.evs.append(ev)
		var kind := str(ev.get("kind", ""))
		if kind == WorldMsg.EV_BK:
			p.mirror = BreachMirror.from_event(ev)
		elif kind == WorldMsg.EV_BK_TICK and p.mirror != null:
			p.mirror.apply_tick(ev)
		elif kind == WorldMsg.EV_BK_END:
			if p.mirror != null:
				p.mirror.apply_end(ev)
			p.ends.append(ev)
		elif kind == WorldMsg.EV_BK_NO:
			p.nos.append(ev))
	var cfg := NetConfig.new()
	cfg.port = _cfg.port
	cfg.token = _cfg.token
	assert_int(p.net.start_client(cfg)).is_equal(OK)
	return p


func _ready_peer() -> Peer:
	var p := _peer()
	assert_bool(await _wait_for(func(): return p.net.is_connected_to_world)).is_true()
	assert_bool(await _wait_for(func(): return _node.session_state(SESSION) != null and not _node.session_state(SESSION).loot_view.is_empty())).is_true()
	return p


func _start(p: Peer, item: String) -> bool:
	p.mirror = null
	p.nos.clear()
	p.net.request_decrypt(item)
	await _wait_for(func(): return p.mirror != null or not p.nos.is_empty())
	return p.mirror != null


func _solve(p: Peer) -> void:
	var path := BreachAutoSolver.solve(p.mirror.attempt)
	for i in range(path.size()):
		if p.mirror.finished:
			return
		assert_bool(p.mirror.tap(path[i])).is_true()
		p.net.request_breach_tap(path[i])
		assert_bool(await _wait_for(func(): return p.mirror.pending == null or p.mirror.finished)).is_true()
	await _wait_for(func(): return p.mirror.finished)


func _decrypt_and_solve(p: Peer, item: String) -> void:
	assert_bool(await _start(p, item)).is_true()
	await _solve(p)
	assert_bool(await _wait_for(func(): return not p.ends.is_empty())).is_true()


func _item_data(id: String) -> Dictionary:
	return _bridge.doc("item", id)["data"]


# ---------------------------------------------------------------- успех

func test_the_bot_solves_the_decrypt_and_the_shard_becomes_open_in_the_bridge_and_the_cargo() -> void:
	var p := await _ready_peer()
	var ver_before := int(_bridge.doc("item", SHARD2)["ver"])
	assert_bool(await _start(p, SHARD2)).is_true()
	# Режим for_decrypt: цепочка шифр-замка 4 кода (тир 2), сетка и таймер по тиру шарда, буфер = цепочка + 2, ловушек нет.
	assert_str(p.mirror.mode).is_equal("decrypt")
	assert_str(p.mirror.tier).is_equal("HARD")
	assert_int(p.mirror.targets[0]["cells"].size()).is_equal(BreachData.shared().decrypt_length(2))
	assert_int(p.mirror.buffer_size).is_equal(p.mirror.targets[0]["cells"].size() + BreachData.shared().decrypt_buffer_extra)
	assert_int((p.evs.filter(func(e): return e["kind"] == WorldMsg.EV_BK)[0]["grid"]["traps"] as Array).size()).is_equal(0)
	await _solve(p)
	assert_bool(await _wait_for(func(): return not p.ends.is_empty())).is_true()
	var end: Dictionary = p.ends[0]
	assert_str(end["mode"]).is_equal("decrypt")
	assert_str(end["outcome"]).is_equal("SUCCESS")
	assert_bool(end["decrypted"]).is_true()
	assert_str(end["item"]).is_equal(SHARD2)
	# Мост: ровно одна операция, payload — один флаг поменялся, версия выросла, владелец тот же.
	assert_int(_bridge.decrypt_calls).is_equal(1)
	var d := _item_data(SHARD2)
	assert_str(d["payload"]).is_equal("SHARD|sh2|1|2|||||0|1")
	assert_bool(d["shard"]["decrypted"]).is_true()
	assert_str(d["owner"]).is_equal("deck:" + SESSION)
	assert_int(int(_bridge.doc("item", SHARD2)["ver"])).is_equal(ver_before + 1)
	# ГРУЗ игрока: шард ОТКРЫТ (свежий ev deck после записи).
	assert_bool(await _wait_for(func(): return not p.loot_row(SHARD2).is_empty() and not bool(p.loot_row(SHARD2)["enc"]))).is_true()
	assert_bool(_node.decrypt.has_attempt(SESSION)).is_false()
	assert_int((_events.filter(func(e): return e["kind"] == "decrypt_end" and e["decrypted"])).size()).is_equal(1)


func test_decrypting_is_not_a_breach_and_writes_no_signal_or_money() -> void:
	var p := await _ready_peer()
	await _decrypt_and_solve(p, SHARD2)
	assert_int(_bridge.breach_calls).is_equal(0)
	assert_int(_bridge.finish_calls).is_equal(0)


# ---------------------------------------------------------------- отказы

func test_a_decrypter_of_a_lower_tier_than_the_shard_is_refused() -> void:
	var p := await _ready_peer()
	assert_bool(await _start(p, SHARD3)).is_false()   # DECRYPT тира 2, шард тира 3
	assert_str(p.nos[0]["reason"]).is_equal("no_decrypter")
	assert_str(p.nos[0]["mode"]).is_equal("decrypt")
	assert_bool(_node.decrypt.has_attempt(SESSION)).is_false()
	assert_int(_bridge.decrypt_attempts).is_equal(0)


func test_open_shards_unknown_items_and_daemons_are_refused() -> void:
	var p := await _ready_peer()
	assert_bool(await _start(p, OPEN)).is_false()
	assert_str(p.nos[0]["reason"]).is_equal("open")
	assert_bool(await _start(p, "it_nope")).is_false()
	assert_str(p.nos[0]["reason"]).is_equal("gone")
	assert_bool(await _start(p, "it_k_dec")).is_false()   # рабочий демон не в ГРУЗе
	assert_str(p.nos[0]["reason"]).is_equal("gone")


func test_without_a_working_decrypter_the_shard_stays_locked() -> void:
	var p := await _ready_peer()
	# Дешифратор «вылетел» из рабочих: в деке сессии его нет.
	var ds := _node.session_state(SESSION)
	ds.deck.erase("it_k_dec")
	assert_bool(await _start(p, SHARD2)).is_false()
	assert_str(p.nos[0]["reason"]).is_equal("no_decrypter")


func test_another_mini_game_blocks_the_decrypt_and_the_decrypt_blocks_a_charge() -> void:
	var p := await _ready_peer()
	assert_bool(await _start(p, SHARD2)).is_true()
	p.nos.clear()
	p.net.request_decrypt(SHARD2)
	assert_bool(await _wait_for(func(): return not p.nos.is_empty())).is_true()
	assert_str(p.nos[0]["reason"]).is_equal("active")
	p.nos.clear()
	p.net.request_charge("it_k_ghost")
	assert_bool(await _wait_for(func(): return not p.nos.is_empty())).is_true()
	assert_str(p.nos[0]["reason"]).is_equal("active")
	assert_bool(_node.charge.has_attempt(SESSION)).is_false()


# ---------------------------------------------------------------- бросили

func test_cancel_time_out_and_teleport_leave_the_shard_locked_and_cost_nothing() -> void:
	var p := await _ready_peer()
	assert_bool(await _start(p, SHARD2)).is_true()
	var path := BreachAutoSolver.solve(p.mirror.attempt)
	p.mirror.tap(path[0])
	p.net.request_breach_tap(path[0])
	assert_bool(await _wait_for(func(): return p.mirror.pending == null)).is_true()
	p.net.request_breach_cancel()
	assert_bool(await _wait_for(func(): return not p.ends.is_empty())).is_true()
	assert_str(p.ends[0]["early"]).is_equal("cancel")
	assert_bool(p.ends[0]["decrypted"]).is_false()
	p.ends.clear()
	assert_bool(await _start(p, SHARD2)).is_true()   # повтор сразу
	for i in 90:
		_node.decrypt.tick(1.0)
	assert_bool(await _wait_for(func(): return not p.ends.is_empty())).is_true()
	assert_str(p.ends[0]["outcome"]).is_equal("FAIL")
	assert_bool(p.ends[0]["decrypted"]).is_false()
	p.ends.clear()
	assert_bool(await _start(p, SHARD2)).is_true()
	p.net.request_teleport(Vector3(1.0, 0.0, -2.0))
	assert_bool(await _wait_for(func(): return not p.ends.is_empty())).is_true()
	assert_str(p.ends[0]["early"]).is_equal("teleport")
	assert_int(_bridge.decrypt_attempts).is_equal(0)
	assert_bool(_item_data(SHARD2)["shard"]["decrypted"]).is_false()
	assert_str(_item_data(SHARD2)["payload"]).is_equal("SHARD|sh2|1|2|||||0|0")


# ---------------------------------------------------------------- Мост

func test_a_bridge_outage_after_the_win_loses_nothing_and_a_retry_succeeds() -> void:
	var p := await _ready_peer()
	_bridge.decrypt_offline = true
	await _decrypt_and_solve(p, SHARD2)
	assert_bool(p.ends[0]["decrypted"]).is_false()
	assert_str(p.ends[0]["error"]).is_equal("unavailable")
	assert_bool(_item_data(SHARD2)["shard"]["decrypted"]).is_false()
	assert_bool(_node.decrypt.has_attempt(SESSION)).is_false()
	_bridge.decrypt_offline = false
	p.ends.clear()
	await _decrypt_and_solve(p, SHARD2)
	assert_bool(p.ends[0]["decrypted"]).is_true()
	assert_int(_bridge.decrypt_calls).is_equal(1)


func test_a_lost_reply_after_the_commit_is_still_a_success_and_nothing_is_done_twice() -> void:
	var p := await _ready_peer()
	_bridge.decrypt_drop_reply = true
	await _decrypt_and_solve(p, SHARD2)
	assert_bool(p.ends[0]["decrypted"]).is_true()
	assert_int(_bridge.decrypt_calls).is_equal(1)


func test_the_same_rid_replays_and_a_late_call_changes_nothing() -> void:
	var ver := int(_bridge.doc("item", SHARD2)["ver"])
	var first: Dictionary = _bridge.op_decrypt_item(SESSION, SHARD2, ver)
	assert_bool(first["ok"]).is_true()
	assert_bool(first["changed"]).is_true()
	var again: Dictionary = _bridge.op_decrypt_item(SESSION, SHARD2, ver)   # тот же rid
	assert_bool(again["ok"]).is_true()
	assert_bool(again.get("replayed", false)).is_true()
	assert_int(_bridge.decrypt_calls).is_equal(1)
	var late: Dictionary = _bridge.op_decrypt_item(SESSION, SHARD2, int(_bridge.doc("item", SHARD2)["ver"]))   # новая версия, шард уже открыт
	assert_bool(late["ok"]).is_true()
	assert_bool(late["changed"]).is_false()
	assert_int(_bridge.decrypt_calls).is_equal(1)
	assert_str(_item_data(SHARD2)["payload"]).is_equal("SHARD|sh2|1|2|||||0|1")


func test_the_bridge_refuses_a_shard_that_left_the_deck_and_a_daemon() -> void:
	var s: Dictionary = _bridge.op_decrypt_item(SESSION, "it_k_dec", 1)
	assert_str(BridgeApi.err_code(s)).is_equal("bad_request")
	var d := _item_data(SHARD2).duplicate(true)
	d["owner"] = "outbox:KEY_X"
	_bridge._put("item", SHARD2, d)
	var o: Dictionary = _bridge.op_decrypt_item(SESSION, SHARD2, int(_bridge.doc("item", SHARD2)["ver"]))
	assert_str(BridgeApi.err_code(o)).is_equal("wrong_owner")
	assert_str(_item_data(SHARD2)["payload"]).is_equal("SHARD|sh2|1|2|||||0|0")
