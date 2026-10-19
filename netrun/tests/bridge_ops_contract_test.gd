extends GdUnitTestSuite
## Общие векторы Моста (rules/src/test/resources/contracts/bridge-ops.json) против фальши FakeBridge: тот же файл читает и Kotlin-Мост.
## Ожидания в файле выписаны из docs/netrun-bridge-protocol.md (6.2, 6.6, 6.7); расхождение фальши с протоколом — красный случай с пунктом в имени.
## Файл лежит вне netrun/, поэтому на devbox (dev.sh кладёт только netrun/) его может не быть — тогда тест пропускается с причиной.

const VECTORS_REL := "../rules/src/test/resources/contracts/bridge-ops.json"
const EMPTY_FIXTURE := "res://tests/fixtures/bridge_empty.json"
## Типы документов, которых в фальши нет: в vectors они нужны Мосту с деками, фальшь меняет только владельца предмета.
const UNMODELLED := ["deck"]


static func _vectors_path() -> String:
	return ProjectSettings.globalize_path("res://").path_join(VECTORS_REL).simplify_path()


static func _vectors_missing() -> bool:
	return not FileAccess.file_exists(_vectors_path())


func _load() -> Dictionary:
	var f := FileAccess.open(_vectors_path(), FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert_bool(parsed is Dictionary).is_true()
	return parsed


func test_vectors_file_is_well_formed(do_skip := _vectors_missing(), skip_reason := "нет rules/src/test/resources/contracts/bridge-ops.json рядом с netrun/ (на devbox dev.sh кладёт только netrun/)") -> void:
	var v := _load()
	assert_int(int(v.get("version", 0))).is_equal(1)
	var cases: Array = v.get("cases", [])
	assert_int(cases.size()).is_greater_equal(25)
	var names := {}
	for c in cases:
		assert_bool(names.has(c["name"])).override_failure_message("повтор имени случая: %s" % c["name"]).is_false()
		names[c["name"]] = true
		assert_bool(c.has("docs") and c.has("request") and c.has("expect")).override_failure_message("в случае нет docs/request/expect: %s" % c["name"]).is_true()
		var e: Dictionary = c["expect"]
		if not e.get("ok", false):
			assert_bool(e.has("err") and e.has("docs_after")).override_failure_message("у отказа нет err/docs_after: %s" % c["name"]).is_true()


func test_fake_bridge_gives_the_known_answers(do_skip := _vectors_missing(), skip_reason := "нет rules/src/test/resources/contracts/bridge-ops.json рядом с netrun/ (на devbox dev.sh кладёт только netrun/)") -> void:
	var cases: Array = _load()["cases"]
	var fails: Array = []
	for c in cases:
		var why := await _run_case(c)
		if not why.is_empty():
			fails.append("[%s] %s" % [c["name"], why])
	assert_str("\n".join(fails)).override_failure_message("%d из %d случаев расходятся с протоколом:\n%s" % [fails.size(), cases.size(), "\n".join(fails)]).is_empty()


## "" — случай прошёл; иначе — что не сошлось.
func _run_case(c: Dictionary) -> String:
	var b := FakeBridge.new(EMPTY_FIXTURE)
	var idx := 0
	for d in c["docs"]:
		idx += 1
		var type: String = d["type"]
		if not b._docs.has(type):
			b._docs[type] = {}
		b._docs[type][d["id"]] = {"type": type, "id": d["id"], "ver": idx, "data": (d["data"] as Dictionary).duplicate(true)}
	b.now_override_ms = int(c["now_ms"])
	var req: Dictionary = c["request"]
	var resp: Dictionary
	match str(req["op"]):
		"op.take_from_node":
			resp = await b.op_take_from_node(str(req.get("session", "")), str(req.get("node", "")), str(req.get("item", "")))
		"op.give_item":
			resp = await b.op_give_item(str(req.get("session", "")), str(req.get("item", "")), int(req.get("ver", 0)), str(req.get("to_session", "")), str(req.get("to_phone", "")))
		"run.breach":
			resp = await b.run_breach(str(req.get("session", "")), str(req.get("node", "")), req)
		_:
			return "неизвестная операция %s" % req["op"]
	var exp: Dictionary = c["expect"]
	if bool(exp["ok"]) != bool(resp.get("ok", false)):
		return "ok: ждали %s, получили %s (%s)" % [exp["ok"], resp.get("ok", false), JSON.stringify(resp.get("err", {}))]
	if bool(exp["ok"]):
		var m := _subset(exp.get("reply", {}), resp, "reply")
		if not m.is_empty():
			return m
	else:
		if BridgeApi.err_code(resp) != str(exp["err"]):
			return "err: ждали %s, получили %s (%s)" % [exp["err"], BridgeApi.err_code(resp), JSON.stringify(resp.get("err", {}))]
		if exp.has("err_doc"):
			var m := _subset(exp["err_doc"], (resp.get("err", {}) as Dictionary).get("doc", {}), "err.doc")
			if not m.is_empty():
				return m
	for d in exp.get("docs_after", []):
		if str(d["type"]) in UNMODELLED:
			continue
		var actual := b.doc(str(d["type"]), str(d["id"]))
		if actual.is_empty():
			return "docs_after: нет документа %s/%s" % [d["type"], d["id"]]
		var m := _subset(d, actual, "docs_after[%s/%s]" % [d["type"], d["id"]])
		if not m.is_empty():
			return m
	return ""


## Ожидание — подмножество факта: словарь — по ключам (ключ обязан быть, null значит «есть и null»), массив — той же длины, поэлементно, число — по значению.
static func _subset(want: Variant, got: Variant, path: String) -> String:
	if want is Dictionary:
		if not (got is Dictionary):
			return "%s: ждали объект, получили %s" % [path, JSON.stringify(got)]
		for k in want:
			if not (got as Dictionary).has(k):
				return "%s.%s: поля нет" % [path, k]
			var m := _subset(want[k], got[k], path + "." + str(k))
			if not m.is_empty():
				return m
		return ""
	if want is Array:
		if not (got is Array) or (got as Array).size() != (want as Array).size():
			return "%s: ждали %s, получили %s" % [path, JSON.stringify(want), JSON.stringify(got)]
		for i in (want as Array).size():
			var m := _subset(want[i], got[i], "%s[%d]" % [path, i])
			if not m.is_empty():
				return m
		return ""
	if (want is float or want is int) and (got is float or got is int):
		return "" if float(want) == float(got) else "%s: ждали %s, получили %s" % [path, want, got]
	return "" if typeof(want) == typeof(got) and want == got else "%s: ждали %s, получили %s" % [path, JSON.stringify(want), JSON.stringify(got)]
