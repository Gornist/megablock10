extends GdUnitTestSuite
## Графы стенда П9 (Серверная HARD двумя размерами, вход прямо в неё): tools/stand/p9_graph_hard8.json и p9_graph_hard10.json, общая фикстура Моста
## p9_bridge_fixture.json, отчёт tools/p9_report.sh. Граф П8 (p7_graph.json) не трогаем: цепочка, тиры и настройки у обоих графов П9 — его копии.

const G8 := "res://tools/stand/p9_graph_hard8.json"
const G10 := "res://tools/stand/p9_graph_hard10.json"
const P7 := "res://tools/stand/p7_graph.json"
const FIXTURE := "res://tools/stand/p9_bridge_fixture.json"
const REPORT := "res://tools/p9_report.sh"


func _graph(path: String) -> NodeGraph:
	var g := NodeGraph.load_file(path)
	assert_str(g.load_error).is_empty()
	assert_array(g.errors()).override_failure_message("%s: %s" % [path, "; ".join(g.errors())]).is_empty()   # связи симметричны, порталы, шарды и ICE укладываются в раскладку
	return g


func test_оба_графа_разбираются_цепочка_и_тиры_как_на_предыдущем_стенде() -> void:
	for path in [G8, G10]:
		var g := _graph(path)
		assert_str(g.tier_of("node_03")).is_equal("BASE")
		assert_str(g.tier_of("node_05")).is_equal("HARD")
		assert_str(g.tier_of("node_11")).is_equal("NIGHTMARE")
		assert_array(g.nodes["node_05"]["links"]).contains_exactly(["node_03", "node_11"])
		assert_str(str(g.nodes["node_03"]["layout"])).is_equal("server_room_light")
		assert_str(str(g.nodes["node_11"]["layout"])).is_equal("core")
		for id in ["node_03", "node_05", "node_11"]:
			var ld := LayoutData.load_named(str(g.nodes[id]["layout"]))
			assert_str(ld.error).is_empty()
			assert_array(LayoutCheck.failures(ld, g.tier_of(id))).override_failure_message("%s %s: %s" % [path, id, "; ".join(LayoutCheck.failures(ld, g.tier_of(id)))]).is_empty()


func test_вход_прямо_в_серверную() -> void:
	for path in [G8, G10]:
		var g := _graph(path)
		assert_str(g.default_entry).is_equal("node_05")
		for t in ["t03", "t04", "t05"]:
			assert_str(g.entry_for(t)).is_equal("node_05")


func test_серверная_8_и_10_различаются_только_раскладкой_и_числом_ice_и_хранилищ() -> void:
	var g8 := _graph(G8)
	var g10 := _graph(G10)
	assert_str(str(g8.nodes["node_05"]["layout"])).is_equal("server_room")
	assert_str(str(g10.nodes["node_05"]["layout"])).is_equal("server_room_hard10")
	var l8 := LayoutData.load_named("server_room")
	var l10 := LayoutData.load_named("server_room_hard10")
	assert_int(l8.cols * l8.rows).is_equal(64)
	assert_int(l10.cols * l10.rows).is_equal(100)
	# Страж на узле — не больше, чем просит ice (GrayNode: mini(ice, sentries)); хранилище-слот — не больше, чем shards (_build_slots).
	assert_int(int(g8.nodes["node_05"]["ice"])).is_equal(l8.sentries.size())
	assert_int(int(g10.nodes["node_05"]["ice"])).is_equal(l10.sentries.size())
	assert_int(int(g8.nodes["node_05"]["shards"])).is_equal(l8.vaults.size())
	assert_int(int(g10.nodes["node_05"]["shards"])).is_equal(l10.vaults.size())   # иначе третье (внутреннее) хранилище остаётся без слота
	# Остальное в графах (настройки, остальные узлы, ice_settings Серверной) — как на П8.
	var p7: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(P7))
	for path in [G8, G10]:
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert_dict(d["settings"]).is_equal(p7["settings"])
		assert_dict(d["nodes"]["node_03"]).is_equal(p7["nodes"]["node_03"])
		assert_dict(d["nodes"]["node_11"]).is_equal(p7["nodes"]["node_11"])
		assert_dict(d["nodes"]["node_05"]["ice_settings"]).is_equal(p7["nodes"]["node_05"]["ice_settings"])


func test_фикстура_моста_держит_призрака_в_серверной_и_шарды_на_все_хранилища() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	for t in ["t03", "t04", "t05"]:
		assert_str(str(d["terminals"][t]["node"])).is_equal("node_05")
	var s: Dictionary = d["sessions"]["s_fake000000000001"]
	assert_str(str(s["node"])).is_equal("node_05")
	assert_int(int(s["ram"])).is_equal(14)
	assert_str(str(s["callsign"])).is_equal("Призрак")
	var daemons := 0
	var shards := 0
	for k: String in d["items"]:
		var it: Dictionary = d["items"][k]
		if str(it["owner"]) == "deck:s_fake000000000001":
			daemons += 1
		if str(it["owner"]) == "node:node_05":
			shards += 1
	assert_int(daemons).is_equal(4)   # Извлечение 1-3 и Призрак, как на П8
	# 3 шарда на Серверной: на hard10 каждому из трёх хранилищ свой, на hard8 третий предмет просто лежит без слота.
	assert_int(shards).is_equal(LayoutData.load_named("server_room_hard10").vaults.size())


const SYNTH := """srv_p9: Серверная HARD 10x10, граф p9_graph_hard10.json
@1000.000 [gray-node] s1 вошёл в node_05
@1000.500 [tick] n=7
@1003.000 [netrun-server] teleport ok s1 from=0.0,0.0 to=1.0,1.0 dist=2.0 cell=3,3
@1006.000 [netrun-server] teleport ok s1 from=1.0,1.0 to=2.0,2.0 dist=2.0 cell=4,4
@1010.000 [gray-node] breach.request session=s1 vault=node_05_pk2 daemons="" codes=0 ram=14 lock=2
@1010.000 [gray-node] breach.no session=s1 reason=no_daemons
@1015.000 [gray-node] breach.request session=s1 vault=node_05_pk0 daemons=it_a,it_b codes=12 ram=14 lock=2
@1030.000 [netrun-server] s1 взял node_05_pk0
@1032.000 [tick] n=12
@1035.000 [ice] t=35.0 g1 PATROL→GAZE aw=2.00 alert=0.30 d=3.0 s1 tick=12
@1036.000 [gray-node] alarm.level node=node_05 level=1 alarm=30
@1040.000 [ice] t=40.0 g1 ВЫБРОС caught alert=0.31 d=1.0 s1 tick=13
@1041.000 [netrun-server] выход s1: ejected,
"""


func _run_report(text: String) -> String:
	var p := OS.get_user_data_dir().path_join("p9_report_synth.log")
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	var out: Array = []
	var rc := OS.execute("bash", [ProjectSettings.globalize_path(REPORT), p], out, true)
	assert_int(rc).is_equal(0)
	return "".join(out)


func test_отчёт_по_синтетическому_журналу() -> void:
	var r := _run_report(SYNTH)
	assert_str(r).contains("Серверная HARD 10x10 (server_room_hard10)")
	assert_str(r).contains("на узле всего 41 с")
	assert_str(r).contains("до первого взлома: 10 с")
	assert_str(r).contains("до первого хранилища: 30 с")
	assert_str(r).contains("прыжки: 2")
	assert_str(r).contains("поимки (ВЫБРОС): 1 [g1 caught]")
	assert_str(r).contains("макс. уровень 1")
	assert_str(r).contains("внешние: запросов 1 / взято 1; внутреннее: запросов 1 / взято 0")
	assert_str(r).contains("с демонами 1, без демонов 1")
	assert_str(r).contains("нет в журнале:")


func test_отчёт_без_меток_времени_и_размера_говорит_что_нет() -> void:
	var lines := PackedStringArray()
	for l in SYNTH.split("\n"):
		if l.begins_with("srv_p9"):
			continue
		lines.append(l.substr(l.find(" ") + 1) if l.begins_with("@") else l)
	var r := _run_report("\n".join(lines))
	assert_str(r).contains("размер раскладки")
	assert_str(r).contains("время в секундах")
	assert_str(r).contains("такт +")


func test_отчёт_без_входа_в_серверную_отказывает() -> void:
	var p := OS.get_user_data_dir().path_join("p9_report_empty.log")
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("[gray-node] s1 вошёл в node_03\n")
	f.close()
	var out: Array = []
	assert_int(OS.execute("bash", [ProjectSettings.globalize_path(REPORT), p], out, true)).is_equal(1)
	assert_str("".join(out)).contains("нет в журнале: вход в node_05")
