extends GdUnitTestSuite
## Граф стенда П6 (tools/stand/p6_graph.json): вход — Архив (BASE, лёгкая Серверная), дальше Серверная (HARD) и Ядро (П6-5, Game 16.10: на П6 ноль взломов, «одна точка спокойная,
## на другой сразу согнал лёд» — начинать с простого узла). Фикстура Моста (p6_bridge_fixture.json) держит терминалы и шарды этого же входа.

const GRAPH := "res://tools/stand/p6_graph.json"
const FIXTURE := "res://tools/stand/p6_bridge_fixture.json"


func test_стенд_начинается_с_архива_потом_серверная_и_ядро() -> void:
	var g := NodeGraph.load_file(GRAPH)
	assert_str(g.load_error).is_empty()
	assert_array(g.errors()).override_failure_message("; ".join(g.errors())).is_empty()   # связи симметричны, порталы и шарды укладываются в раскладку
	assert_str(g.default_entry).is_equal("node_03")
	assert_str(g.tier_of("node_03")).is_equal("BASE")
	assert_str(str(g.nodes["node_03"]["layout"])).is_equal("server_room_light")
	assert_array(g.nodes["node_03"]["links"]).contains_exactly(["node_05"])
	assert_array(g.nodes["node_05"]["links"]).contains(["node_03", "node_11"])
	assert_str(g.tier_of("node_05")).is_equal("HARD")
	for id in ["node_03", "node_05", "node_11"]:
		var ld := LayoutData.load_named(str(g.nodes[id]["layout"]))
		assert_str(ld.error).is_empty()
		assert_array(LayoutCheck.failures(ld, g.tier_of(id))).override_failure_message("%s: %s" % [id, "; ".join(LayoutCheck.failures(ld, g.tier_of(id)))]).is_empty()


func test_фикстура_моста_ведёт_терминалы_и_шарды_в_архив() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	for t in ["t03", "t04", "t05"]:
		assert_str(str(d["terminals"][t]["node"])).is_equal("node_03")
	assert_str(str(d["sessions"]["s_fake000000000001"]["node"])).is_equal("node_03")
	var shards := 0
	for k: String in d["items"]:
		if str(d["items"][k]["owner"]) == "node:node_03":
			shards += 1
	assert_int(shards).is_equal(2)   # столько же, сколько shards у узла в графе стенда
