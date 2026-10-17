extends GdUnitTestSuite
## Серверная HARD 10×10 (data/layouts/server_room_hard10.json, G1, карточка Game 17.10 v3): разбор, состав, все проверки LayoutCheck HARD и боты.
## Раскладка пока не подключена ни к графу, ни к стенду — это только данные и проверки.

const NAME := "server_room_hard10"


func _load() -> LayoutData:
	var ld := LayoutData.load_named(NAME)
	assert_str(ld.error).is_empty()
	return ld


func test_разбор_состав_и_размер() -> void:
	var ld := _load()
	assert_int(ld.cols).is_equal(10)
	assert_int(ld.rows).is_equal(10)
	assert_int(ld.sentries.size()).is_equal(3)
	assert_int(ld.beacons.size()).is_equal(1)
	assert_int(ld.sensors.size()).is_equal(1)
	assert_int(ld.vaults.size()).is_equal(3)
	assert_int(ld.portals.size()).is_equal(3)
	assert_int(ld.cols * ld.rows).is_less_equal(LayoutCheck.area_max("HARD"))


func test_внутреннее_хранилище_в_кармане_верхнего_ряда() -> void:
	var ld := _load()
	var inner: Array = ld.vaults.filter(func(v: Dictionary) -> bool: return str(v.get("ring", "")) == "inner")
	assert_int(inner.size()).is_equal(1)
	assert_bool(ld.vaults.any(func(v: Dictionary) -> bool: return v["cell"] == Vector2i(3, 0))).is_true()
	assert_bool(ld.vaults.any(func(v: Dictionary) -> bool: return v["cell"] == Vector2i(3, 0) and str(v.get("ring", "")) == "inner")).is_true()


func test_все_проверки_hard_зелёные() -> void:
	var ld := _load()
	var all := LayoutCheck.run_all(ld, "HARD")
	for k: String in all:
		print("[layout_check] %s %s ok=%s %s" % [NAME, k, str(all[k]["ok"]), str(all[k]["detail"])])
	assert_str("; ".join(LayoutCheck.failures(ld, "HARD"))).is_empty()


func test_окно_внутреннего_меньше_шести_только_с_инструментом() -> void:
	# Маяк (3,3) смотрит по столбцу 3 на площадку (3,1); оборот 90° за такт (4 такта) даёт окно 3 (при 45° — 7, то есть «слишком спокойно»).
	var ld := _load()
	var b := LayoutBots.new(ld, "HARD")
	assert_str(b.error).is_empty()
	var found := false
	for v: Dictionary in ld.vaults:
		if str(v["ring"]) == "inner":
			found = true
			var w := b.window_of(v["pad1"])
			assert_int(w).override_failure_message("окно внутреннего %d, нужно < 6" % w).is_less(6)
			assert_int(w).is_greater_equal(LayoutCheck.ANY_WINDOW_MIN)
	assert_bool(found).is_true()


func test_правила_видимости_и_боты_зелёные() -> void:
	var ld := _load()
	var r := LayoutCheck.stealth_rules(ld, "HARD")
	for k: String in r:
		assert_bool(r[k]["ok"]).override_failure_message("%s: %s" % [k, r[k]["detail"]]).is_true()
	var b := LayoutBots.check_bots(ld, "HARD")
	print("[bots] " + LayoutBots.report_line(ld, "HARD"))
	assert_bool(b["ok"]).override_failure_message(str(b["detail"])).is_true()
	var p := LayoutBots.check_periods(ld)
	assert_bool(p["ok"]).override_failure_message(str(p["detail"])).is_true()
	var w := LayoutBots.check_paths(ld)
	assert_bool(w["ok"]).override_failure_message(str(w["detail"])).is_true()
