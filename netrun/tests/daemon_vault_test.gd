extends GdUnitTestSuite
## EXTRACT_DAEMON и мёртвая дека (К8): хранилище с демоном, добытый демон в ГРУЗе (не рабочий), мёртвая дека в узле, рестарт сервера мира
## (деление добычи по `session.loaded`, а не по `origin`). Граф и сервер — как в graph_world_test.gd; Мост — фейковый.

static var _next_port := 18651
const GRAPH := "res://tests/fixtures/graph_test.json"
const BRIDGE := "res://tests/fixtures/graph_bridge_fixture.json"
const BREACH_BRIDGE := "res://tests/fixtures/breach_bridge_fixture.json"
const S1 := "s_fake000000000001"
const ALICE := "KEY_ALICE"

var _root: Node
var _server: NetServer
var _world: GraphWorld
var _bridge: FakeBridge


func before_test() -> void:
	_root = Node.new()
	_root.name = "DaemonVaultRoot"
	add_child(_root)
	var sroot := Node.new()
	sroot.name = "S"
	_root.add_child(sroot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), sroot.get_path())
	var cfg := NetConfig.new()
	cfg.port = _next_port
	_next_port += 1
	_bridge = FakeBridge.new(BRIDGE)
	_server = NetServer.new()
	sroot.add_child(_server)
	assert_int(_server.start(cfg, _bridge)).is_equal(OK)
	_world = GraphWorld.new()
	sroot.add_child(_world)
	_world.start(_server, _bridge, NodeGraph.load_file(GRAPH))


func after_test() -> void:
	_server.stop_net()
	_root.queue_free()


static func _daemon_doc(id: String, own: String, origin: String, effect: String = "GHOST", tier: int = 2, cells: Array = ["1C", "BD"]) -> Dictionary:
	return {"type": "item", "id": id, "ver": 1, "data": {"owner": own, "kind": "DAEMON", "origin": origin, "protected": false,
		"daemon": {"effect": effect, "tier": tier, "name": "Демон " + id, "cells": cells}}}


static func _session_doc(loaded: Array, node: String = "g_c") -> Dictionary:
	return {"type": "session", "id": S1, "ver": 1, "data": {"state": "active", "node": node, "runner": ALICE, "world": {"node": node}, "loaded": loaded}}


# ---------------------------------------------------------------- хранилище с демоном

func test_a_vault_holding_a_dead_deck_daemon_is_shown_as_a_daemon_with_a_dead_deck_beside_it() -> void:
	var gc := _world.node_of("g_c")
	var pk0 := GrayNode.shard_id("g_c", 0)
	var pk1 := GrayNode.shard_id("g_c", 1)
	_recover(gc, [
		_daemon_doc("it_a_dead", "node:g_c", "phone:KEY_DEAD", "EXTRACT_SHARD", 3),
		{"type": "item", "id": "it_b_shard", "ver": 1, "data": {"owner": "node:g_c", "kind": "SHARD", "origin": "node:g_c", "shard": {"tier": 1, "decrypted": true}}},
	])
	var view := {}
	for e in gc.shard_view(S1):
		view[e["id"]] = e
	assert_str(view[pk0]["kind"]).is_equal("daemon")
	assert_int(view[pk0]["tier"]).is_equal(3)
	assert_bool(view[pk0]["enc"]).is_false()           # демон не шифруется
	assert_bool(view[pk0]["dead"]).is_true()           # origin phone:* — дека погибшего
	assert_str(view[pk1]["kind"]).is_equal("shard")
	assert_bool(view[pk1]["dead"]).is_false()
	# мёртвая дека видна в описании узла: одна, рядом со слотом демона
	var ev := _world.node_event("g_c", null, S1)
	assert_int((ev["dead"] as Array).size()).is_equal(1)
	var p: Vector3 = NodeLayout.SHARD_SLOTS[0]
	var spot: Array = ev["dead"][0]
	assert_float(Vector2(float(spot[0]) - p.x, float(spot[1]) - p.z).length()).is_between(0.79, 0.81)
	# узел без демонов мёртвых дек не рисует
	assert_bool(_world.node_event("g_a", null, S1).has("dead")).is_false()


func test_an_empty_slot_is_refilled_with_a_free_daemon_of_the_node() -> void:
	var gc := _world.node_of("g_c")
	var pk0 := GrayNode.shard_id("g_c", 0)
	_recover(gc, [_daemon_doc("it_a_dead", "node:g_c", "phone:KEY_DEAD")])
	assert_str(str(gc._shard_items[pk0])).is_equal("it_a_dead")
	# слот опустел (демон унесли), в узле остался только следующий демон: пополнение берёт его, а не требует шарда
	gc._deplete(pk0, 0.0)
	assert_bool(gc._shard_items.has(pk0)).is_false()
	var d: Dictionary = (_bridge.doc("item", "it_g_c_1")["data"] as Dictionary).duplicate()
	d["owner"] = "deck:" + S1   # шарды узла разобраны: свободного шарда в Мосте нет
	_bridge._put("item", "it_g_c_1", d)
	d = (_bridge.doc("item", "it_g_c_2")["data"] as Dictionary).duplicate()
	d["owner"] = "deck:" + S1
	_bridge._put("item", "it_g_c_2", d)
	var dd := _daemon_doc("it_z_master", "node:g_c", "master:M", "EXTRACT_DAEMON", 1)
	_add_item(_bridge, "it_z_master", dd["data"])
	assert_str(await gc._free_shard_item()).is_equal("it_z_master")
	gc._refill_at[pk0] = 0.0
	await gc._refill(pk0)
	assert_str(str(gc._shard_items[pk0])).is_equal("it_z_master")
	assert_str(gc.shard_view(S1)[0]["kind"]).is_equal("daemon")


# ---------------------------------------------------------------- добытый демон: ГРУЗ, не рабочий

func test_a_daemon_taken_by_extract_daemon_lands_in_the_cargo_and_goes_to_the_phone_on_exit() -> void:
	var b := FakeBridge.new(BREACH_BRIDGE)
	var dead := _daemon_doc("it_b_dead", "node:b_a", "phone:KEY_DEAD", "MINER", 2, ["BD", "E9"])
	_add_item(b, "it_b_dead", dead["data"])
	var extractor := _daemon_doc("it_b_xd", "deck:" + "s_fake000000000001", "phone:KEY_ALICE", "EXTRACT_DAEMON", 2)
	_add_item(b, "it_b_xd", extractor["data"])
	var req := {"n": 1, "tier": "BASE", "selected": ["it_b_xd"], "matched": ["it_b_xd"], "active": [], "vaults": ["it_b_s1", "it_b_dead"], "open_s": 60}
	var r: Dictionary = await b.run_breach("s_fake000000000001", "b_a", req)
	assert_bool(r["ok"]).is_true()
	assert_array(r["opened"].map(func(o): return o["item"])).is_equal(["it_b_dead"])   # EXTRACT_DAEMON открывает только демона, шард не трогает
	var taken: Dictionary = await b.op_take_from_node("s_fake000000000001", "b_a", "it_b_dead")
	assert_bool(taken["ok"]).is_true()
	var docs: Array = (await b.list_docs(BridgeApi.T_ITEM))["docs"]
	var sdata: Dictionary = b.doc("session", "s_fake000000000001")["data"]
	# рабочие — только принесённые с телефона; добытый демон — груз, и в рабочие не попадает даже если у него phone:*
	var working := GrayNode.deck_from_items(docs, "s_fake000000000001", sdata).map(func(x): return x["id"])
	assert_array(working).contains_exactly_in_any_order(["it_b_d1", "it_b_d2", "it_b_xd"])
	assert_bool(working.has("it_b_dead")).is_false()
	var loot := GrayNode.loot_from_items(docs, "s_fake000000000001", sdata)
	assert_int(loot.size()).is_equal(1)
	assert_str(loot[0]["kind"]).is_equal("daemon")
	assert_str(loot[0]["effect"]).is_equal("MINER")
	assert_array(loot[0]["cells"]).is_equal(["BD", "E9"])
	assert_bool(loot[0]["give"]).is_true()
	# ДОБЫЧА: «ДЕМОН · тир · эффект» с цепочкой
	var rows := HudLogic.loot_rows(loot)
	assert_str(rows[0]["text"]).is_equal("ДЕМОН  Демон it_b_dead  тир 2  добыча эдди")
	assert_str(rows[0]["chain"]).is_equal("BD E9")
	assert_str(rows[0]["label"]).is_equal("В ГРУЗЕ")
	# чистый выход: демон уходит на телефон, origin остаётся прежним (phone:<погибший>)
	var moves := GrayNode.finish_moves(docs, "s_fake000000000001", sdata, {"loot": "phone", "daemon": "phone"})
	var fin: Dictionary = await b.run_finish("s_fake000000000001", "clean", "b_a", false, moves)
	assert_bool(fin["ok"]).is_true()
	var item: Dictionary = b.doc("item", "it_b_dead")["data"]
	assert_str(str(item["owner"])).is_equal("outbox:KEY_ALICE")
	assert_str(str(item["origin"])).is_equal("phone:KEY_DEAD")


func test_black_ice_leaves_the_deck_in_the_node_and_another_runner_takes_it_by_hacking() -> void:
	var b := FakeBridge.new(BREACH_BRIDGE)
	var sid_a := "s_fake000000000001"
	var sid_b := "s_fake000000000002"
	# флэтлайн Алисы: дека остаётся в узле (moves: всё в node), origin прежний
	var docs: Array = (await b.list_docs(BridgeApi.T_ITEM))["docs"]
	var sdata: Dictionary = b.doc("session", sid_a)["data"]
	var moves := GrayNode.finish_moves(docs, sid_a, sdata, {"loot": "node", "daemon": "node"})
	assert_bool((await b.run_finish(sid_a, "black_ice", "b_a", false, moves))["ok"]).is_true()
	var left: Dictionary = b.doc("item", "it_b_d1")["data"]
	assert_str(str(left["owner"])).is_equal("node:b_a")
	assert_str(str(left["origin"])).is_equal("phone:KEY_ALICE")
	# Боб взламывает с EXTRACT_DAEMON: демон мёртвой деки (тир 2) открывается, берётся рукой и это груз, а не рабочий
	var xd := _daemon_doc("it_b_xd", "deck:" + sid_b, "phone:KEY_BOB", "EXTRACT_DAEMON", 3)
	_add_item(b, "it_b_xd", xd["data"])
	var req := {"n": 1, "tier": "BASE", "selected": ["it_b_xd"], "matched": ["it_b_xd"], "active": [], "vaults": ["it_b_d1"], "open_s": 60}
	var r: Dictionary = await b.run_breach(sid_b, "b_a", req)
	assert_array(r["opened"].map(func(o): return o["item"])).is_equal(["it_b_d1"])
	assert_bool((await b.op_take_from_node(sid_b, "b_a", "it_b_d1"))["ok"]).is_true()
	docs = (await b.list_docs(BridgeApi.T_ITEM))["docs"]
	var bdata: Dictionary = b.doc("session", sid_b)["data"]
	assert_array(GrayNode.loot_from_items(docs, sid_b, bdata).map(func(l): return l["id"])).is_equal(["it_b_d1"])
	assert_bool(GrayNode.deck_from_items(docs, sid_b, bdata).any(func(x): return x["id"] == "it_b_d1")).is_false()


# ---------------------------------------------------------------- рестарт сервера мира

func test_held_items_follow_session_loaded_not_origin() -> void:
	var sessions := {S1: {"loaded": ["it_work"], "runner": ALICE}}
	var deck: Array = [
		_daemon_doc("it_work", "deck:" + S1, "phone:KEY_ALICE"),
		_daemon_doc("it_dead", "deck:" + S1, "phone:KEY_DEAD"),
		_daemon_doc("it_other_node", "deck:" + S1, "node:g_a"),
		{"type": "item", "id": "it_master", "data": {"owner": "deck:" + S1, "kind": "SHARD", "origin": "master:M"}},
		{"type": "item", "id": "it_here", "data": {"owner": "deck:" + S1, "kind": "SHARD", "origin": "node:g_c"}},
		_daemon_doc("it_foreign", "deck:s_other", "phone:KEY_DEAD"),
	]
	var held := GrayNode.held_items(deck, sessions, "g_c", false)
	assert_array(held.map(func(h): return h["item"])).is_equal(["it_dead", "it_here", "it_master"])
	assert_str(held[0]["by"]).is_equal(S1)
	# одиночный узел без графа: предмет с любого узла — тоже его
	assert_array(GrayNode.held_items(deck, sessions, "node_07", true).map(func(h): return h["item"])).is_equal(["it_dead", "it_here", "it_master", "it_other_node"])


func test_held_items_prefer_taken_at_over_origin() -> void:
	var sessions := {S1: {"loaded": [], "runner": ALICE}}
	var deck: Array = [
		# шард создан в g_a, оставлен в g_c и взят там: origin чужой, взяли здесь — это добыча g_c
		{"type": "item", "id": "it_moved", "data": {"owner": "deck:" + S1, "kind": "SHARD", "origin": "node:g_a", "taken_at": "g_c"}},
		# создан в g_c, но взят в g_a и принесён сюда: добыча g_a
		{"type": "item", "id": "it_away", "data": {"owner": "deck:" + S1, "kind": "SHARD", "origin": "node:g_c", "taken_at": "g_a"}},
		# после leave_in_node поле null (в JSON Моста) — решает origin, как у документов до taken_at
		{"type": "item", "id": "it_null", "data": {"owner": "deck:" + S1, "kind": "SHARD", "origin": "node:g_c", "taken_at": null}},
	]
	assert_array(GrayNode.held_items(deck, sessions, "g_c", false).map(func(h): return h["item"])).is_equal(["it_moved", "it_null"])
	# одиночный узел без графа: берём всё
	assert_int(GrayNode.held_items(deck, sessions, "node_07", true).size()).is_equal(3)


func test_restart_keeps_the_held_daemon_and_master_shard_with_the_player() -> void:
	var gc := _world.node_of("g_c")
	var pk0 := GrayNode.shard_id("g_c", 0)
	var pk1 := GrayNode.shard_id("g_c", 1)
	_recover(gc, [
		_session_doc(["it_work"]),
		_daemon_doc("it_work", "deck:" + S1, "phone:KEY_ALICE"),
		_daemon_doc("it_dead", "deck:" + S1, "phone:KEY_DEAD", "MINER"),
		{"type": "item", "id": "it_master", "ver": 1, "data": {"owner": "deck:" + S1, "kind": "SHARD", "origin": "master:M", "shard": {"tier": 2}}},
	])
	# оба несомых предмета занимают слоты за игроком (клиент второй раз их не возьмёт); рабочий демон слота не получает
	var held_slots := [str(_server.holder_of(pk0)), str(_server.holder_of(pk1))]
	assert_array(held_slots).is_equal([S1, S1])
	assert_array([gc._shard_items[pk0], gc._shard_items[pk1]]).contains_exactly_in_any_order(["it_dead", "it_master"])
	assert_array(gc._taken_by[S1]).has_size(2)
	assert_bool(gc._shard_items.values().has("it_work")).is_false()
	# выход с добычей в узле: слоты снова с предметами, не пустеют
	gc.settle_shards(S1, "g_c", "node")
	assert_bool(gc._refill_at.is_empty()).is_true()


## Снимок Моста поверх уже поднятого узла: слоты, занятые стартовым снимком фикстуры, освобождаются — как у свежего процесса.
func _recover(gc: GrayNode, docs: Array) -> void:
	gc._shard_items.clear()
	gc._refill_at.clear()
	gc.recover(docs)


## Новый предмет в фейковом Мосте (`_put` меняет только существующие документы).
static func _add_item(b: FakeBridge, id: String, data: Dictionary) -> void:
	b._docs["item"][id] = {"type": "item", "id": id, "ver": 1, "data": data}
