extends GdUnitTestSuite
## Журнал клиента для замера на очках: `node.perf` при входе в узел (сборка, первая отрисовка, вызовы отрисовки) и `perf` раз в
## несколько секунд (кадры, долгие кадры, отрисовка). Без экрана счётчики отрисовки нулевые — проверяем, что строки и поля есть.


func _client() -> ProtoClient:
	var proto: ProtoClient = auto_free(ProtoClient.new())
	proto.config_paths = PackedStringArray()
	proto.perf_sample_delay_s = 0.1
	add_child(proto)
	proto.start(PackedStringArray(), "flat", false)
	return proto


func _log(proto: ProtoClient) -> String:
	return FileAccess.get_file_as_string(proto.log_file.path)


func test_entering_a_node_logs_build_first_frame_and_draw_calls() -> void:
	var proto := _client()
	proto._on_event({"kind": WorldMsg.EV_NODE, "node": "node_07", "tier": "BASE", "shards": [], "portals": []})
	assert_bool(await _wait_for_line(proto, "node.perf node=node_07")).is_true()
	var line := _line(proto, "node.perf ")
	for field in ["tier=BASE", "build_ms=", "first_frame_ms=", "draws=", "prims=", "objects="]:
		assert_str(line).contains(field)


func test_perf_line_summarises_the_frames() -> void:
	var proto := _client()
	await get_tree().process_frame
	await get_tree().process_frame
	proto._log_perf()
	var line := _line(proto, "perf ")
	for field in ["frames=", "avg_ms=", "max_ms=", "slow=", "draws="]:
		assert_str(line).contains(field)


func _line(proto: ProtoClient, prefix: String) -> String:
	for l in _log(proto).split("\n"):
		if l.contains(" " + prefix):
			return l
	return ""


func _wait_for_line(proto: ProtoClient, text: String) -> bool:
	var tries := 0
	while tries < 60:
		if _log(proto).contains(text):
			return true
		await get_tree().create_timer(0.1).timeout
		tries += 1
	return false
