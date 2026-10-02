extends GdUnitTestSuite
## Клиент Моста без сети: разбор кадров, сборка запросов, сопоставление ответов по cid, локальная копия документов.

func test_parse_reply() -> void:
	var m := BridgeClient.parse_message('{"v":1,"re":"w-7","ok":true,"ver":5}')
	assert_str(m["kind"]).is_equal("reply")
	assert_str(m["re"]).is_equal("w-7")


func test_parse_push() -> void:
	var m := BridgeClient.parse_message('{"v":1,"push":"chg","seq":9,"last":false,"doc":{"type":"item","id":"i","ver":2,"data":{}}}')
	assert_str(m["kind"]).is_equal("push")
	assert_int(m["seq"]).is_equal(9)
	assert_bool(m["last"]).is_false()
	assert_bool(m["deleted"]).is_false()


func test_parse_garbage() -> void:
	assert_str(BridgeClient.parse_message("не json")["kind"]).is_equal("invalid")
	assert_str(BridgeClient.parse_message("[1]")["kind"]).is_equal("invalid")
	assert_str(BridgeClient.parse_message('{"v":1}')["kind"]).is_equal("invalid")


func test_to_response_ok_and_error() -> void:
	var ok := BridgeClient.to_response({"v": 1, "re": "w-1", "ok": true, "ver": 5})
	assert_dict(ok).is_equal({"ok": true, "ver": 5})
	var bad := BridgeClient.to_response({"v": 1, "re": "w-1", "ok": false, "err": {"code": "wrong_owner", "msg": "x"}})
	assert_str(BridgeApi.err_code(bad)).is_equal("wrong_owner")
	assert_str(BridgeApi.err_code(BridgeClient.to_response({"ok": false}))).is_equal("internal")


func test_build_request_has_envelope() -> void:
	var m: Dictionary = JSON.parse_string(BridgeClient.build_request("w-3", "op.take_from_node", {"rid": "take:s:i", "item": "i"}))
	assert_int(int(m["v"])).is_equal(1)
	assert_str(m["cid"]).is_equal("w-3")
	assert_str(m["op"]).is_equal("op.take_from_node")
	assert_str(m["rid"]).is_equal("take:s:i")


func test_reply_resolves_pending_by_cid() -> void:
	var c := BridgeClient.new()
	var p := BridgeClient.Pending.new()
	var got := []
	p.done.connect(func(r): got.append(r))
	c._pending["w-1"] = p
	c.handle_text('{"v":1,"re":"w-2","ok":true}')  # чужой cid — ничего
	assert_array(got).is_empty()
	c.handle_text('{"v":1,"re":"w-1","ok":true,"ver":3}')
	assert_int(got.size()).is_equal(1)
	assert_bool(got[0]["ok"]).is_true()
	assert_int(int(got[0]["ver"])).is_equal(3)  # числа из JSON — float
	assert_bool(c._pending.has("w-1")).is_false()


func test_fail_all_resolves_with_error() -> void:
	var c := BridgeClient.new()
	var p := BridgeClient.Pending.new()
	var got := []
	p.done.connect(func(r): got.append(r))
	c._pending["w-1"] = p
	c._fail_all("disconnected")
	assert_str(BridgeApi.err_code(got[0])).is_equal("disconnected")


func test_push_updates_local_docs_and_deletes() -> void:
	var c := BridgeClient.new()
	var seen := []
	c.doc_changed.connect(func(d, deleted): seen.append([d["id"], deleted]))
	c.handle_text('{"v":1,"push":"chg","seq":4,"last":true,"doc":{"type":"item","id":"it_1","ver":2,"data":{"owner":"deck:s"}}}')
	assert_str(c.docs["item"]["it_1"]["data"]["owner"]).is_equal("deck:s")
	assert_int(c.last_seq).is_equal(4)
	c.handle_text('{"v":1,"push":"chg","seq":5,"last":true,"deleted":true,"doc":{"type":"item","id":"it_1","ver":2,"data":{}}}')
	assert_bool(c.docs["item"].has("it_1")).is_false()
	assert_array(seen).is_equal([["it_1", false], ["it_1", true]])


func test_garbage_frame_is_ignored() -> void:
	var c := BridgeClient.new()
	c.handle_text("мусор")
	assert_dict(c.docs).is_empty()


func test_make_bridge_choice() -> void:
	var cfg := NetConfig.new()
	assert_object(WorldServer.make_bridge(PackedStringArray([]), cfg)).is_instanceof(FakeBridge)
	assert_object(WorldServer.make_bridge(PackedStringArray(["--bridge=fake"]), cfg)).is_instanceof(FakeBridge)
	var ws := WorldServer.make_bridge(PackedStringArray(["--bridge=ws://10.0.0.5:7410", "--bridge-key=kw"]), cfg)
	assert_object(ws).is_instanceof(BridgeClient)
	assert_str((ws as BridgeClient).url).is_equal("ws://10.0.0.5:7410/netrun/v1")
	assert_str((ws as BridgeClient).key).is_equal("kw")
	cfg.tokens = {"t1": "alice"}
	assert_object(WorldServer.make_bridge(PackedStringArray([]), cfg)).is_null()


func test_socket_buffer_fits_big_snapshot() -> void:
	# Снимок `sub` с тысячами документов приходит одним кадром; 64 КиБ Godot по умолчанию хватало на ~200 документов.
	var ws := BridgeClient.new_socket()
	assert_int(ws.inbound_buffer_size).is_greater_equal(8 << 20)
	assert_int(ws.outbound_buffer_size).is_greater_equal(1 << 20)
