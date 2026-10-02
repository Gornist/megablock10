extends GdUnitTestSuite
## Одноразовость сервера мира (M5): убить сервер посреди забега, поднять новый на том же Мосте — тот же забег.
## Мост здесь — FakeBridge, переживающий «сервер»; настоящий Мост — netrun/tools/live_run.sh.

static var _next_port := 18491
const SESSION := "s_fake000000000001"
const SHARD_ITEM := "it_fake00000000a001"

var _root: Node
var _croot: Node
var _bridge: FakeBridge
var _cfg: NetConfig
var _server: NetServer
var _node: GrayNode
var _sroot: Node
var _boots := 0
var _bot: BotClient


func before_test() -> void:
	_root = Node.new()
	_root.name = "RestartTestRoot"
	add_child(_root)
	_croot = Node.new()
	_croot.name = "C"
	_root.add_child(_croot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), _croot.get_path())
	_cfg = NetConfig.new()
	_cfg.port = _next_port
	_next_port += 1
	_cfg.token = "t03:token-t03"
	_bridge = FakeBridge.new()
	_bot = null


func after_test() -> void:
	if _bot != null and _bot.net != null:
		await _bot.net.drop()
	_kill_server()
	_root.queue_free()


## Поднять сервер мира на общем Мосте (каждый раз своё поддерево и свой MultiplayerAPI).
func _boot() -> void:
	_boots += 1
	_sroot = Node.new()
	_sroot.name = "S%d" % _boots
	_root.add_child(_sroot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), _sroot.get_path())
	_server = NetServer.new()
	_sroot.add_child(_server)
	assert_int(_server.start(_cfg, _bridge)).is_equal(OK)
	_node = GrayNode.new()
	_sroot.add_child(_node)
	_node.start(_server, _bridge)


## «Убийство»: сокет закрыт без прощания, все сопрограммы и сигналы сервера исчезают вместе с узлами.
func _kill_server() -> void:
	if _sroot != null and is_instance_valid(_sroot):
		_server.stop_net()
		_root.remove_child(_sroot)
		_sroot.free()
	_sroot = null


func _wait_for(cond: Callable, sec: float = 30.0) -> bool:
	var t := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _item_owner(id: String) -> String:
	return str(_bridge.doc(BridgeApi.T_ITEM, id)["data"]["owner"])


func _session_data() -> Dictionary:
	return _bridge.doc(BridgeApi.T_SESSION, SESSION)["data"]


func test_kill_mid_run_then_same_run_continues() -> void:
	_cfg.grace_sec = 20.0
	_boot()
	_bot = BotClient.new()
	_bot.reconnect = true
	_croot.add_child(_bot)
	_bot.start(_cfg, BotClient.Scenario.GHOST_RUN)
	assert_bool(await _wait_for(func(): return _bot.shard_taken and _item_owner(SHARD_ITEM) == "deck:" + SESSION)).is_true()
	_kill_server()
	# Мост хранит всё: сессия active, шард в деке игрока.
	assert_str(str(_session_data()["state"])).is_equal("active")
	_boot()
	assert_array(_node.recovered_sessions).is_equal([SESSION])
	assert_str(_server.holder_of(NetConfig.PICKUP_ID)).is_equal(SESSION)
	# Клиент замечает обрыв по таймауту ENet (~5 с), возвращается тем же токеном и доходит до выхода.
	assert_bool(await _wait_for(func(): return not _bot.result.is_empty(), 60.0)).is_true()
	assert_str(_bot.result).is_equal("clean")
	assert_int(_bot.reconnects).is_greater_equal(1)
	assert_bool(await _wait_for(func(): return str(_session_data()["state"]) == "closed")).is_true()
	assert_str(str(_session_data()["outcome"])).is_equal("clean")
	assert_str(_item_owner(SHARD_ITEM)).is_equal("outbox:KEY_ALICE")


func test_player_does_not_return_emergency_exit_after_grace() -> void:
	_cfg.grace_sec = 1.0
	var taken: Dictionary = await _bridge.op_take_from_node(SESSION, "node_07", SHARD_ITEM)
	assert_bool(taken["ok"]).is_true()
	_boot()
	assert_array(_node.recovered_sessions).is_equal([SESSION])
	assert_str(_server.holder_of(NetConfig.PICKUP_ID)).is_equal(SESSION)
	assert_bool(await _wait_for(func(): return str(_session_data()["state"]) == "closed", 10.0)).is_true()
	assert_str(str(_session_data()["outcome"])).is_equal("emergency")
	assert_bool(_session_data()["disconnect"]).is_true()
	# Добыча при обрыве остаётся в узле, шард снова на постаменте.
	assert_str(_item_owner(SHARD_ITEM)).is_equal("node:node_07")
	assert_str(_server.holder_of(NetConfig.PICKUP_ID)).is_empty()


func test_snapshot_gives_lockdown_and_node_state_is_written() -> void:
	var n: Dictionary = (await _bridge.get_doc("node", "node_07"))["doc"]
	var data: Dictionary = (n["data"] as Dictionary).duplicate()
	data["lockdown_until"] = 1234567
	assert_bool((await _bridge.put_doc("node", "node_07", int(n["ver"]), data))["ok"]).is_true()
	_boot()
	assert_int(_node.lockdown_until).is_equal(1234567)
	# Состояние узла записано в Мост, чужие поля и эдди на месте.
	assert_bool(await _wait_for(func(): return _node.node_writes >= 1, 5.0)).is_true()
	var d: Dictionary = _bridge.doc("node", "node_07")["data"]
	assert_bool(d["world"]["up"]).is_true()
	assert_int(int(d["lockdown_until"])).is_equal(1234567)
	assert_int(int(d["eddies"])).is_equal(100)
	# Локдаун, поставленный Мостом на ходу, узел видит по подписке.
	var cur: Dictionary = (await _bridge.get_doc("node", "node_07"))["doc"]
	var d2: Dictionary = (cur["data"] as Dictionary).duplicate()
	d2["lockdown_until"] = 0
	await _bridge.put_doc("node", "node_07", int(cur["ver"]), d2)
	assert_int(_node.lockdown_until).is_equal(0)


func test_deck_from_items_takes_daemon_field() -> void:
	var g := {"effect": "GHOST", "tier": 2, "name": "Призрак", "cells": ["1C"]}
	var items := [
		{"id": "it_a", "data": {"owner": "deck:s1", "kind": "DAEMON", "daemon": g}},
		{"id": "it_b", "data": {"owner": "deck:s2", "kind": "DAEMON", "daemon": g}},
		{"id": "it_c", "data": {"owner": "deck:s1", "kind": "SHARD", "shard": {"tier": 1}}},
		{"id": "it_d", "data": {"owner": "deck:s1", "kind": "DAEMON", "payload": "без поля daemon"}},
	]
	var deck := GrayNode.deck_from_items(items, "s1")
	assert_int(deck.size()).is_equal(1)
	assert_str(deck[0]["id"]).is_equal("it_a")
	assert_str(deck[0]["daemon"]["effect"]).is_equal("GHOST")
	assert_array(GrayNode.deck_from_items(items, "s9")).is_empty()


func test_transient_errors_are_retried_final_are_not() -> void:
	assert_bool(GrayNode.is_transient(BridgeApi.err("unavailable"))).is_true()
	assert_bool(GrayNode.is_transient(BridgeApi.err("timeout"))).is_true()
	assert_bool(GrayNode.is_transient(BridgeApi.err("wrong_owner"))).is_false()
	assert_bool(GrayNode.is_transient(BridgeApi.ok())).is_false()
