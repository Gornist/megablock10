extends GdUnitTestSuite
## Фейковый Мост (F1): токен терминала, сессия, взять/оставить/завершить с повтором по rid, подписка.

const S1 := "s_fake000000000001"
const S2 := "s_fake000000000002"
const SHARD := "it_fake00000000a001"
const DAEMON_P := "it_fake000000d001"
const DAEMON := "it_fake000000d002"

var _b: FakeBridge


func before_test() -> void:
	_b = FakeBridge.new()


func test_fixture_loaded() -> void:
	assert_bool(_b.is_ready()).is_true()
	assert_str(_b.load_error()).is_empty()


func test_missing_fixture_is_not_ready() -> void:
	var bad := FakeBridge.new("res://tests/fixtures/нет.json")
	assert_bool(bad.is_ready()).is_false()


func test_terminal_auth_good_and_bad_token() -> void:
	var r: Dictionary = await _b.terminal_auth("t03", "token-t03")
	assert_bool(r["ok"]).is_true()
	assert_str(r["session"]["id"]).is_equal(S1)
	assert_str(BridgeApi.err_code(await _b.terminal_auth("t03", "чужой"))).is_equal("bad_token")
	assert_str(BridgeApi.err_code(await _b.terminal_auth("t99", "token-t03"))).is_equal("bad_token")


func test_verify_async_returns_session_id() -> void:
	assert_str(await _b.verify_async("t03:token-t03")).is_equal(S1)
	assert_str(await _b.verify_async('{"terminal":"t04","token":"token-t03"}')).is_equal(S2)
	assert_str(await _b.verify_async("t03:плохой")).is_empty()
	assert_str(await _b.verify_async("мусор")).is_empty()


func test_parse_terminal_token() -> void:
	assert_dict(BridgeApi.parse_terminal_token("t03:a:b")).is_equal({"terminal": "t03", "token": "a:b"})
	assert_dict(BridgeApi.parse_terminal_token('{"terminal":"t1","token":"x"}')).is_equal({"terminal": "t1", "token": "x"})
	assert_dict(BridgeApi.parse_terminal_token("")).is_empty()
	assert_dict(BridgeApi.parse_terminal_token(":x")).is_empty()
	assert_dict(BridgeApi.parse_terminal_token("{}")).is_empty()


func test_confirm_pending_becomes_active_and_is_idempotent() -> void:
	var r: Dictionary = await _b.session_confirm(S2, "t04")
	assert_str(r["session"]["data"]["state"]).is_equal("active")
	var again: Dictionary = await _b.session_confirm(S2, "t04")
	assert_bool(again["ok"]).is_true()
	assert_str(BridgeApi.err_code(await _b.session_confirm(S2, "t03"))).is_equal("bad_request")


func test_take_moves_item_to_deck_and_replays() -> void:
	var r: Dictionary = await _b.op_take_from_node(S1, "node_07", SHARD)
	assert_bool(r["ok"]).is_true()
	assert_bool(r["replayed"]).is_false()
	assert_str(r["item"]["data"]["owner"]).is_equal("deck:" + S1)
	var again: Dictionary = await _b.op_take_from_node(S1, "node_07", SHARD)
	assert_bool(again["replayed"]).is_true()
	assert_int(_b.doc("item", SHARD)["ver"]).is_equal(2)  # второй раз не взяли


func test_take_race_second_gets_wrong_owner() -> void:
	await _b.session_confirm(S2, "t04")
	await _b.op_take_from_node(S1, "node_07", SHARD)
	var r: Dictionary = await _b.op_take_from_node(S2, "node_07", SHARD)
	assert_str(BridgeApi.err_code(r)).is_equal("wrong_owner")
	assert_str(r["err"]["doc"]["data"]["owner"]).is_equal("deck:" + S1)


func test_take_requires_active_session() -> void:
	assert_str(BridgeApi.err_code(await _b.op_take_from_node(S2, "node_07", SHARD))).is_equal("session_state")


func test_leave_protected_is_refused() -> void:
	assert_str(BridgeApi.err_code(await _b.op_leave_in_node(S1, "node_07", DAEMON_P))).is_equal("protected_item")
	var r: Dictionary = await _b.op_leave_in_node(S1, "node_07", DAEMON)
	assert_str(r["item"]["data"]["owner"]).is_equal("node:node_07")


func test_finish_moves_deck_and_closes_session() -> void:
	await _b.op_take_from_node(S1, "node_07", SHARD)
	var moves := [{"item": DAEMON, "to": "phone"}, {"item": SHARD, "to": "phone"}]
	var r: Dictionary = await _b.run_finish(S1, "clean", "node_07", false, moves)
	assert_bool(r["ok"]).is_true()
	assert_str(r["session"]["data"]["state"]).is_equal("closed")
	assert_int(r["transfers"].size()).is_equal(3)  # защищённый демон ушёл сам
	assert_str(_b.doc("item", DAEMON_P)["data"]["owner"]).is_equal("outbox:KEY_ALICE")
	var replay: Dictionary = await _b.run_finish(S1, "clean", "node_07", false, moves)
	assert_bool(replay["replayed"]).is_true()


func test_finish_with_forgotten_item_is_bad_request_without_a_saved_rid() -> void:
	var r: Dictionary = await _b.run_finish(S1, "clean", "node_07", false, [])
	assert_str(BridgeApi.err_code(r)).is_equal("bad_request")
	# Как настоящий Мост (протокол 6.5): bad_request — ошибка запроса, записи rid нет; тот же rid с пересобранными moves разрешён.
	var other: Dictionary = await _b.run_finish(S1, "emergency", "node_07", false, [])
	assert_str(BridgeApi.err_code(other)).is_equal("bad_request")


func test_rids_are_deterministic() -> void:
	assert_str(BridgeApi.take_rid("s", "i")).is_equal("take:s:i")
	assert_str(BridgeApi.leave_rid("s", "i")).is_equal("leave:s:i")
	assert_str(BridgeApi.finish_rid("s")).is_equal("finish:s")


func test_subscribe_snapshot_and_changes() -> void:
	var snap: Dictionary = await _b.subscribe(["item"])
	assert_int(snap["docs"].size()).is_equal(5)
	var seen := []
	_b.doc_changed.connect(func(d, deleted): seen.append([d["id"], deleted]))
	await _b.op_take_from_node(S1, "node_07", SHARD)
	assert_array(seen).is_equal([[SHARD, false]])


func test_beat_and_get() -> void:
	var r: Dictionary = await _b.terminal_beat("t03", 80, 72)
	assert_bool(r["ok"]).is_true()
	var t: Dictionary = (await _b.get_doc("terminal", "t03"))["doc"]
	assert_int(t["data"]["battery"]).is_equal(80)
	assert_str(BridgeApi.err_code(await _b.terminal_beat("t99"))).is_equal("not_found")


func test_put_doc_checks_version_and_values() -> void:
	var n: Dictionary = (await _b.get_doc("node", "node_07"))["doc"]
	var data: Dictionary = (n["data"] as Dictionary).duplicate()
	data["world"] = {"up": true}
	var ok: Dictionary = await _b.put_doc("node", "node_07", int(n["ver"]), data)
	assert_bool(ok["ok"]).is_true()
	# версия устарела: version_conflict с текущим документом
	var stale: Dictionary = await _b.put_doc("node", "node_07", int(n["ver"]), data)
	assert_str(BridgeApi.err_code(stale)).is_equal("version_conflict")
	assert_bool(stale["err"]["doc"]["data"]["world"]["up"]).is_true()
	# эдди — ценность
	data["eddies"] = 999
	assert_str(BridgeApi.err_code(await _b.put_doc("node", "node_07", int(ok["doc"]["ver"]), data))).is_equal("value_field")
	# в сессии пишется только world
	var s: Dictionary = (await _b.get_doc("session", S1))["doc"]
	var sd: Dictionary = (s["data"] as Dictionary).duplicate()
	sd["state"] = "closed"
	assert_str(BridgeApi.err_code(await _b.put_doc("session", S1, int(s["ver"]), sd))).is_equal("value_field")


func test_ints_of_turns_whole_floats_into_ints() -> void:
	var v: Variant = BridgeApi.ints_of({"eddies": 300.0, "x": [1.0, 2.5], "n": {"a": 7.0}})
	assert_str(JSON.stringify(v)).is_equal('{"eddies":300,"n":{"a":7},"x":[1,2.5]}')
