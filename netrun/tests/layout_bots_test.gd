extends GdUnitTestSuite
## Боты раскладки (server/layout_bots.gd, levels.md §8): итоги по Фойе, учебному узлу и Серверной одной строкой на раскладку (в журнале теста),
## проверки периодов и путей, согласованность окон бота с LayoutCheck.


func test_отчёт_по_раскладкам() -> void:
	for pair in [["foyer", "BASE"], ["foyer_tutorial", "BASE"], ["server_room", "HARD"], ["server_room_light", "BASE"], ["server_room_dark", "BASE"]]:
		var ld := LayoutData.load_named(pair[0])
		assert_str(ld.error).is_empty()
		print("[bots] " + LayoutBots.report_line(ld, pair[1]))


func test_периоды_серверной_некратны_а_два_одинаковых_кратны() -> void:
	var r := LayoutBots.check_periods(LayoutData.load_named("server_room"))
	assert_bool(r["ok"]).override_failure_message(str(r["detail"])).is_true()
	var d := (JSON.parse_string(FileAccess.get_file_as_string("res://data/layouts/server_room.json")) as Dictionary)
	var ice: Array = d["ice"]
	ice[1] = ice[0].duplicate(true)
	ice[1]["id"] = "g2"
	var bad := LayoutBots.check_periods(LayoutData.parse(d))
	assert_bool(bad["ok"]).is_false()


func test_к_хранилищам_не_меньше_двух_путей() -> void:
	for n in ["foyer", "foyer_tutorial", "server_room"]:
		var r := LayoutBots.check_paths(LayoutData.load_named(n))
		assert_bool(r["ok"]).override_failure_message("%s: %s" % [n, r["detail"]]).is_true()


func test_окно_бота_не_меньше_окна_проверки_маяк_и_датчик_только_сужают() -> void:
	var ld := LayoutData.load_named("foyer")
	var b := LayoutBots.new(ld, "BASE")
	assert_str(b.error).is_empty()
	var cyc := LayoutCheck.cycle_ticks(ld)
	assert_int(b.cycle).is_equal(cyc)
	for v: Dictionary in ld.vaults:
		assert_int(b.window_of(v["pad1"])).is_greater_equal(LayoutCheck.window_ticks(ld, v["pad_cell"], cyc))   # клетка площадки видна не чаще, чем весь блок


func test_проверка_ботов_проходит_на_реальных_раскладках() -> void:
	for pair in [["foyer", "BASE"], ["foyer_tutorial", "BASE"], ["server_room", "HARD"], ["server_room_light", "BASE"], ["server_room_dark", "BASE"]]:
		var r := LayoutBots.check_bots(LayoutData.load_named(pair[0]), pair[1])
		assert_bool(r["ok"]).override_failure_message("%s: %s" % [pair[0], r["detail"]]).is_true()


func test_страж_у_площадки_ломает_вора_и_проверку() -> void:
	var d := JSON.parse_string(FileAccess.get_file_as_string("res://data/layouts/foyer.json")) as Dictionary
	# второй Страж ходит между двумя клетками рядом с площадкой хранилища (0,0) и всё время смотрит на неё: окна нет, вор на площадке виден
	(d["ice"] as Array).append({"id": "g2", "kind": "sentry", "route": [{"cell": [1, 1], "wait": 20, "look": ["W"]}, {"cell": [1, 0], "wait": 20, "look": ["W"]}]})
	var ld := LayoutData.parse(d)
	assert_str(ld.error).is_empty()
	var r := LayoutBots.check_bots(ld, "BASE")
	assert_bool(r["ok"]).is_false()
	assert_str(r["detail"]).contains("вор")


func test_ступеньки_и_уход_по_реальным_раскладкам() -> void:
	for pair in [["foyer", "BASE"], ["foyer_tutorial", "BASE"], ["server_room", "HARD"], ["server_room_light", "BASE"], ["server_room_dark", "BASE"]]:
		var ld := LayoutData.load_named(pair[0])
		var s := LayoutBots.check_safe_steps(ld, pair[1])
		var e := LayoutBots.check_escape(ld, pair[1])
		print("[safe] %s %s ступеньки ok=%s %s" % [pair[0], pair[1], str(s["ok"]), str(s["detail"])])
		print("[safe] %s %s уход ok=%s %s" % [pair[0], pair[1], str(e["ok"]), str(e["detail"])])


func test_ступеньки_серверной_и_уход_проходят_правила_видимости() -> void:
	for pair in [["server_room", "HARD"], ["server_room_light", "BASE"], ["server_room_dark", "BASE"]]:
		var r := LayoutCheck.stealth_rules(LayoutData.load_named(pair[0]), pair[1])
		for k: String in r:
			assert_bool(r[k]["ok"]).override_failure_message("%s %s: %s" % [pair[0], k, r[k]["detail"]]).is_true()


func test_уход_фойе_укладывается_в_прыжки_но_кратчайший_путь_весь_безопасен() -> void:
	# Известное расхождение с levels.md п. 7 (сообщено Game): в Фойе от площадки до выхода 2 прыжка, и все клетки кратчайших путей безопасны.
	for n in ["foyer", "foyer_tutorial"]:
		var ld := LayoutData.load_named(n)
		var b := LayoutBots.new(ld, "BASE")
		for v: Dictionary in ld.vaults:
			var e := b.escape_of(LayoutBots._idx_static(v["pad1"]))
			assert_int(int(e["hops"])).is_between(LayoutBots.ESCAPE_MIN_HOPS, LayoutBots.ESCAPE_MAX_HOPS)


func test_зоркое_зрение_уменьшает_число_безопасных_клеток() -> void:
	var d := JSON.parse_string(FileAccess.get_file_as_string("res://data/layouts/foyer.json")) as Dictionary
	var base := LayoutBots.new(LayoutData.parse(d), "BASE").safe_cells().size()
	d["meta"] = {"sight_cells": 40}
	var wide := LayoutBots.new(LayoutData.parse(d), "BASE").safe_cells().size()
	assert_int(wide).is_less(base)


func test_уход_в_base_предупреждение_а_в_hard_ошибка() -> void:
	# Фойе: уход 2 прыжка, все клетки кратчайших путей безопасны (п. 7 не выполнен). BASE — предупреждение (решение Game, Фойе — учебный), HARD — ошибка.
	var ld := LayoutData.load_named("foyer")
	var base := LayoutBots.check_escape(ld, "BASE")
	assert_bool(base["ok"]).is_true()
	assert_bool(base["warning"]).is_true()
	assert_str(base["detail"]).starts_with("ПРЕДУПРЕЖДЕНИЕ")
	var hard := LayoutBots.check_escape(ld, "HARD")
	assert_bool(hard["ok"]).is_false()
	assert_bool(LayoutBots.check_escape(LayoutData.load_named("server_room"), "HARD")["warning"]).is_false()
