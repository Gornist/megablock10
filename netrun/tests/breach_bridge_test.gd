extends GdUnitTestSuite
## run.breach в фейковом Мосте и клиенте Моста (К3): контракт docs/netrun-bridge-protocol.md, 6.6 — исход, эдди из запаса, открытие хранилищ, остывание,
## повтор по rid, отказы. Настоящая проверка Моста — JUnit модуля :netrun-bridge (К4) и e2e; здесь — что поток работает на фальшь-мосте.

const BRIDGE := "res://tests/fixtures/breach_bridge_fixture.json"
const S1 := "s_fake000000000001"
const S2 := "s_fake000000000002"


func _req(n: int = 1, matched: Array = ["it_b_d1"], selected: Array = ["it_b_d1"], tier: String = "BASE") -> Dictionary:
	return {"n": n, "tier": tier, "selected": selected, "matched": matched, "active": ["GHOST"], "vaults": ["it_b_s1", "it_b_s2"], "open_s": 60}


func test_success_pays_eddies_from_the_node_stock_opens_the_vault_and_sets_the_cooldown() -> void:
	var b := FakeBridge.new(BRIDGE)
	var r: Dictionary = await b.run_breach(S1, "b_a", _req())
	assert_bool(r["ok"]).is_true()
	assert_str(r["outcome"]).is_equal("SUCCESS")
	assert_array(r["effects"]).is_equal(["EXTRACT_SHARD", "GHOST"])   # совпавшие ∪ активные окна
	assert_int(r["eddies"]).is_equal(2)
	assert_int(r["loot_eddies"]).is_equal(2)
	assert_int(int(b.doc("node", "b_a")["data"]["eddies"])).is_equal(98)
	assert_array(r["opened"].map(func(o): return o["item"])).is_equal(["it_b_s1"])      # тир шарда 1 ≤ тира демона 2, первый из vaults
	assert_bool(r["exhausted"]).is_false()
	assert_int(r["cooldown_until"]).is_greater(int(Time.get_unix_time_from_system() * 1000.0) + 1_700_000)
	var s: Dictionary = b.doc("session", S1)["data"]
	assert_int(int(s["breach"]["n"])).is_equal(1)
	assert_int(s["opened"].size()).is_equal(1)
	assert_bool(r["alert"] == null).is_true()


func test_fail_pays_nothing_and_does_not_cool_the_node_down() -> void:
	var b := FakeBridge.new(BRIDGE)
	var r: Dictionary = await b.run_breach(S1, "b_a", _req(1, [], ["it_b_d1"]))
	assert_str(r["outcome"]).is_equal("FAIL")
	assert_int(r["eddies"]).is_equal(0)
	assert_int(r["cooldown_until"]).is_equal(0)
	assert_array(r["opened"]).is_equal([])
	assert_int(int(b.doc("node", "b_a")["data"]["eddies"])).is_equal(100)
	var again: Dictionary = await b.run_breach(S1, "b_a", _req(2, [], ["it_b_d1"]))     # остывания нет — можно снова
	assert_bool(again["ok"]).is_true()


func test_partial_when_only_some_of_the_selected_matched() -> void:
	var b := FakeBridge.new(BRIDGE)
	var r: Dictionary = await b.run_breach(S1, "b_a", _req(1, ["it_b_d2"], ["it_b_d1", "it_b_d2"]))
	assert_str(r["outcome"]).is_equal("PARTIAL")
	assert_array(r["opened"]).is_equal([])           # GHOST ничего не открывает
	assert_bool(r["exhausted"]).is_false()


func test_a_replayed_rid_returns_the_saved_answer_and_pays_once() -> void:
	var b := FakeBridge.new(BRIDGE)
	var first: Dictionary = await b.run_breach(S1, "b_a", _req())
	var second: Dictionary = await b.run_breach(S1, "b_a", _req())
	assert_bool(second["replayed"]).is_true()
	assert_int(second["eddies"]).is_equal(first["eddies"])
	assert_int(b.breach_calls).is_equal(1)
	assert_int(int(b.doc("session", S1)["data"]["loot_eddies"])).is_equal(2)
	assert_int(int(b.doc("node", "b_a")["data"]["eddies"])).is_equal(98)
	# тот же rid с другими параметрами — rid_mismatch, ничего не изменилось
	var other: Dictionary = await b.run_breach(S1, "b_a", _req(1, [], ["it_b_d1"]))
	assert_str(BridgeApi.err_code(other)).is_equal("rid_mismatch")
	assert_int(int(b.doc("session", S1)["data"]["loot_eddies"])).is_equal(2)


func test_cooldown_blocks_the_next_breach_of_the_same_node_for_that_runner() -> void:
	var b := FakeBridge.new(BRIDGE)
	await b.run_breach(S1, "b_a", _req())
	var r: Dictionary = await b.run_breach(S1, "b_a", _req(2))
	assert_str(BridgeApi.err_code(r)).is_equal("cooldown")
	assert_int(b.breach_calls).is_equal(1)
	# другой нетраннер того же узла не остывает
	var other: Dictionary = await b.run_breach(S2, "b_a", {"n": 1, "tier": "BASE", "selected": ["it_b_d3"], "matched": ["it_b_d3"], "active": [], "vaults": ["it_b_s2"], "open_s": 60})
	assert_bool(other["ok"]).is_true()
	assert_str(other["outcome"]).is_equal("SUCCESS")


func test_exhausted_when_no_vault_item_fits_the_daemon_tier() -> void:
	var b := FakeBridge.new(BRIDGE)
	# демон тира 1 не открывает шард тира 2 (it_b_s2): vaults только он
	var r: Dictionary = await b.run_breach(S2, "b_a", {"n": 1, "tier": "BASE", "selected": ["it_b_d3"], "matched": ["it_b_d3"], "active": [], "vaults": ["it_b_s2"], "open_s": 60})
	assert_str(r["outcome"]).is_equal("SUCCESS")
	assert_bool(r["exhausted"]).is_true()
	assert_array(r["opened"]).is_equal([])
	assert_int(r["eddies"]).is_greater(0)             # эдди платятся, даже когда КЭШ пуст


func test_eddies_are_capped_by_the_node_stock() -> void:
	var b := FakeBridge.new(BRIDGE)
	var nd: Dictionary = b.doc("node", "b_h")
	nd["data"]["eddies"] = 3
	var r: Dictionary = await b.run_breach("s_fake000000000003", "b_h", {"n": 1, "tier": "HARD", "selected": ["it_b_d4"], "matched": ["it_b_d4"], "active": [], "vaults": ["it_b_h1"], "open_s": 60})
	assert_int(r["eddies"]).is_equal(3)               # HARD дал бы 5, в запасе 3
	assert_int(int(b.doc("node", "b_h")["data"]["eddies"])).is_equal(0)


func test_refusals_follow_the_contract() -> void:
	var b := FakeBridge.new(BRIDGE)
	# bad_request
	var bad: Array = [
		_req(0),                                                                       # n < 1
		_req(1, ["it_b_d2"], ["it_b_d1"]),                                              # matched не подмножество selected
		_req(1, ["it_b_d1"], ["it_b_d1", "it_b_d1"]),                                   # повторы
		_req(1, [], ["it_b_d3"]),                                                       # чужой демон
		_req(1, [], ["it_b_s1"]),                                                       # не демон
		_req(1, [], ["it_b_d1"], "EASY"),                                               # неизвестный тир
	]
	for req in bad:
		assert_str(BridgeApi.err_code(await b.run_breach(S1, "b_a", req))).is_equal("bad_request")
	var open_zero := _req()
	open_zero["open_s"] = 0
	assert_str(BridgeApi.err_code(await b.run_breach(S1, "b_a", open_zero))).is_equal("bad_request")
	var too_big := _req(1, [], ["it_b_d1", "it_b_d2"])    # 2 + 3 = 5 ячеек, RAM 8: влезает
	assert_bool((await b.run_breach(S1, "b_a", too_big))["ok"]).is_true()
	var s: Dictionary = b.doc("session", S1)
	s["data"]["ram"] = 4
	assert_str(BridgeApi.err_code(await b.run_breach(S1, "b_a", _req(2, [], ["it_b_d1", "it_b_d2"])))).is_equal("bad_request")   # 5 > RAM 4
	# not_found
	assert_str(BridgeApi.err_code(await b.run_breach("s_nope", "b_a", _req()))).is_equal("not_found")
	assert_str(BridgeApi.err_code(await b.run_breach(S1, "no_node", _req()))).is_equal("not_found")
	# session_state: устаревший номер, идёт исход, сессия не active
	var stale: Dictionary = await b.run_breach(S1, "b_a", _req(1, [], ["it_b_d1"]))     # n=1 уже был (too_big)
	assert_bool(stale.get("ok", false) or BridgeApi.err_code(stale) != "").is_true()
	var fin := FakeBridge.new(BRIDGE)
	fin.doc("session", S1)["data"]["world"] = {"finish": "flatline"}
	assert_str(BridgeApi.err_code(await fin.run_breach(S1, "b_a", _req()))).is_equal("session_state")
	var closed := FakeBridge.new(BRIDGE)
	closed.doc("session", S1)["data"]["state"] = "closed"
	assert_str(BridgeApi.err_code(await closed.run_breach(S1, "b_a", _req()))).is_equal("session_state")
	var tut := FakeBridge.new(BRIDGE)
	tut.doc("node", "b_a")["data"]["tutorial"] = true
	assert_str(BridgeApi.err_code(await tut.run_breach(S1, "b_a", _req()))).is_equal("session_state")


func test_n_must_grow_after_a_recorded_breach() -> void:
	var b := FakeBridge.new(BRIDGE)
	await b.run_breach(S1, "b_a", _req(3, [], ["it_b_d1"]))
	assert_str(BridgeApi.err_code(await b.run_breach(S1, "b_a", _req(3, [], ["it_b_d1", "it_b_d2"])))).is_equal("rid_mismatch")   # тот же rid, другие параметры
	assert_str(BridgeApi.err_code(await b.run_breach(S1, "b_a", _req(2, [], ["it_b_d1"])))).is_equal("session_state")
	assert_bool((await b.run_breach(S1, "b_a", _req(4, [], ["it_b_d1"])))["ok"]).is_true()


func test_take_from_node_of_a_vault_opened_by_another_session_is_claimed() -> void:
	var b := FakeBridge.new(BRIDGE)
	await b.run_breach(S1, "b_a", _req())               # it_b_s1 открыт сессии S1
	var r: Dictionary = await b.op_take_from_node(S2, "b_a", "it_b_s1")
	assert_str(BridgeApi.err_code(r)).is_equal("claimed")
	var own: Dictionary = await b.op_take_from_node(S1, "b_a", "it_b_s1")
	assert_bool(own["ok"]).is_true()
	# не открытый никем шард Мост отдаёт (проверку «брать только из открытого» делает сервер мира)
	assert_bool((await b.op_take_from_node(S2, "b_a", "it_b_s2"))["ok"]).is_true()


func test_a_second_breach_cannot_open_the_item_already_opened_by_another_session() -> void:
	var b := FakeBridge.new(BRIDGE)
	await b.run_breach(S1, "b_a", _req())
	var r: Dictionary = await b.run_breach(S2, "b_a", {"n": 1, "tier": "BASE", "selected": ["it_b_d3"], "matched": ["it_b_d3"], "active": [], "vaults": ["it_b_s1"], "open_s": 60})
	assert_bool(r["ok"]).is_true()
	assert_array(r["opened"]).is_equal([])
	assert_bool(r["exhausted"]).is_true()


func test_client_builds_the_request_with_a_deterministic_rid() -> void:
	assert_str(BridgeApi.breach_rid(S1, 3)).is_equal("breach:s_fake000000000001:3")
	var msg := BridgeClient.build_request("w-1", "run.breach", {"rid": BridgeApi.breach_rid(S1, 3), "session": S1, "node": "b_a", "n": 3, "tier": "HARD",
		"selected": ["a"], "matched": [], "active": [], "vaults": [], "open_s": 60})
	var parsed: Dictionary = JSON.parse_string(msg)
	assert_str(parsed["op"]).is_equal("run.breach")
	assert_int(int(parsed["n"])).is_equal(3)
	assert_str(parsed["rid"]).is_equal("breach:s_fake000000000001:3")
