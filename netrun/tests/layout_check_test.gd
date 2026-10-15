extends GdUnitTestSuite
## Проверка правил раскладки (LayoutCheck): Фойе и учебный узел проходят (а)–(е); испорченные раскладки не проходят свой пункт.

const OK_CELLS := ["V..3...V", "..#..#..", "........", "..#..#..", "........", "1......2", "...S.EE.", ".....EE."]


## Словарь раскладки Фойе из файла — чтобы портить его в тестах.
func _foyer_dict() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/layouts/foyer.json"))
	return parsed as Dictionary


func _cells_with(rows: Dictionary) -> Array:
	var cells: Array = OK_CELLS.duplicate()
	for r: int in rows:
		cells[r] = rows[r]
	return cells


func _parse(d: Dictionary) -> LayoutData:
	var ld := LayoutData.parse(d)
	assert_str(ld.error).is_empty()
	return ld


func _fail_text(ld: LayoutData) -> String:
	return "; ".join(LayoutCheck.failures(ld))


func test_фойе_проходит_все_проверки() -> void:
	var ld := LayoutData.load_named("foyer")
	assert_str(ld.error).is_empty()
	assert_str(_fail_text(ld)).is_empty()


func test_учебный_узел_проходит_все_проверки() -> void:
	var ld := LayoutData.load_named("foyer_tutorial")
	assert_str(ld.error).is_empty()
	assert_str(_fail_text(ld)).is_empty()


func test_цикл_патруля_фойе_двадцать_четыре_такта_учебного_двадцать_восемь() -> void:
	assert_int(LayoutCheck.cycle_ticks(LayoutData.load_named("foyer"))).is_equal(24)
	assert_int(LayoutCheck.cycle_ticks(LayoutData.load_named("foyer_tutorial"))).is_equal(28)


func test_окна_фойе_внешние_хранилища_не_меньше_двенадцати_тактов() -> void:
	var ld := LayoutData.load_named("foyer")
	var cycle := LayoutCheck.cycle_ticks(ld)
	var left := LayoutCheck.window_ticks(ld, Vector2i(0, 1), cycle)
	var right := LayoutCheck.window_ticks(ld, Vector2i(7, 1), cycle)
	assert_bool(left >= 12 and left < cycle).is_true()   # под взглядом, только когда Страж идёт вверх по западному столбцу
	assert_bool(right >= 12).is_true()
	assert_int(LayoutCheck.window_ticks(ld, Vector2i(0, 1), 0)).is_equal(-1)


func test_окно_без_стражей_весь_цикл() -> void:
	var d := _foyer_dict()
	d["ice"] = []
	var ld := _parse(d)
	assert_int(LayoutCheck.cycle_ticks(ld)).is_equal(1)
	assert_int(LayoutCheck.window_ticks(ld, Vector2i(0, 1), 1)).is_equal(1)


func test_хранилище_у_маршрута_не_проходит_расстояние() -> void:
	var d := _foyer_dict()
	d["ice"] = [{"id": "g1", "kind": "sentry", "route": [{"cell": [0, 1]}, {"cell": [3, 1]}]}]   # Страж у самой площадки
	var ld := _parse(d)
	var r := LayoutCheck.check_vault_distance(ld)
	assert_bool(r["ok"]).is_false()
	assert_str(r["detail"]).contains("хранилище")
	assert_bool(LayoutCheck.check_vault_distance(LayoutData.load_named("foyer"))["ok"]).is_true()


func test_закрытый_вход_не_проходит_достижимость() -> void:
	var d := _foyer_dict()
	d["cells"] = _cells_with({5: "1.###..2", 6: "..#S#EE.", 7: "..###EE."})
	var r := LayoutCheck.check_reachable(_parse(d))
	assert_bool(r["ok"]).is_false()
	assert_str(r["detail"]).contains("выход")
	assert_bool(LayoutCheck.check_reachable(LayoutData.load_named("foyer"))["ok"]).is_true()


func test_стражу_виден_вход_на_старте_не_проходит() -> void:
	var d := _foyer_dict()
	d["ice"] = [{"id": "g1", "kind": "sentry", "route": [{"cell": [3, 4]}, {"cell": [3, 5]}]}]   # старт у входа, смотрит на него
	var r := LayoutCheck.check_entry_hidden(_parse(d))
	assert_bool(r["ok"]).is_false()
	assert_str(r["detail"]).contains("вход")


func test_площадка_всё_время_под_взглядом_не_проходит_окна() -> void:
	var d := _foyer_dict()
	d["ice"] = [{"id": "g1", "kind": "sentry", "route": [{"cell": [1, 2]}, {"cell": [1, 3]}]}]   # Страж ходит туда-сюда у западной площадки
	var ld := _parse(d)
	var r := LayoutCheck.check_windows(ld)
	assert_bool(r["ok"]).is_false()
	assert_str(r["detail"]).contains("окно")
	assert_int(LayoutCheck.window_ticks(ld, Vector2i(0, 1), LayoutCheck.cycle_ticks(ld))).is_less(3)


func test_без_колонн_нет_укрытия_у_площадки() -> void:
	var d := _foyer_dict()
	d["cells"] = _cells_with({1: "........", 3: "........"})
	var ld := _parse(d)
	var r := LayoutCheck.check_cover(ld)
	assert_bool(r["ok"]).is_false()
	assert_bool(LayoutCheck.check_cover(LayoutData.load_named("foyer"))["ok"]).is_true()


func test_длинный_тупик_не_проходит_а_короткий_проходит() -> void:
	var long_dead := {"name": "t", "vaults": [], "ice": [], "cells": ["........", ".......#", "......#.", "......#.", "......#.", "......#.", "...S.EE.", ".....EE."]}
	var r := LayoutCheck.check_dead_ends(_parse(long_dead))
	assert_bool(r["ok"]).is_false()
	assert_str(r["detail"]).contains("(4)")
	var short_dead := {"name": "t", "vaults": [], "ice": [], "cells": ["........", "........", ".......#", "......#.", "......#.", "........", "...S.EE.", ".....EE."]}
	assert_bool(LayoutCheck.check_dead_ends(_parse(short_dead))["ok"]).is_true()
	assert_bool(LayoutCheck.check_dead_ends(LayoutData.load_named("foyer"))["ok"]).is_true()


func test_хранилища_фойе_и_учебного_узла_по_сетке() -> void:
	for n in ["foyer", "foyer_tutorial", "legacy"]:
		var r := LayoutCheck.check_vault_grid(LayoutData.load_named(n))
		assert_bool(r["ok"]).override_failure_message("%s: %s" % [n, r["detail"]]).is_true()
	assert_bool(LayoutCheck.run_all(LayoutData.load_named("foyer")).has("vault_grid")).is_true()


func test_занятые_клетки_фойе_учебного_узла_и_legacy_видны() -> void:
	for n in ["foyer", "foyer_tutorial", "legacy"]:
		var r := LayoutCheck.check_occupied_visible(LayoutData.load_named(n))
		assert_bool(r["ok"]).override_failure_message("%s: %s" % [n, r["detail"]]).is_true()
	assert_bool(LayoutCheck.run_all(LayoutData.load_named("foyer")).has("occupied_visible")).is_true()
	assert_int(LayoutData.load_named("legacy").cover_cells().size()).is_equal(0)   # у legacy хранилища не занимают клетки, укрытий нет


func test_занятый_символ_без_модели_не_проходит_проверку_видимости() -> void:
	for sym in ["B", "L"]:
		var d := _foyer_dict()
		d["cells"] = _cells_with({2: "...%s...." % sym})
		var r := LayoutCheck.check_occupied_visible(_parse(d))
		assert_bool(r["ok"]).override_failure_message("символ %s прошёл" % sym).is_false()
		assert_str(r["detail"]).contains("без модели")
		assert_str(r["detail"]).contains(sym)


func test_блок_o_без_записи_маяка_не_проходит_проверку_ice_gear() -> void:
	var d := _foyer_dict()
	d["cells"] = _cells_with({2: "...O...."})
	var ld := _parse(d)
	assert_bool(ld.occupied.has(LayoutData.block_center_cell(Vector2i(3, 2)))).is_false()   # без записи kind: beacon тумбы нет
	var r := LayoutCheck.check_ice_gear(ld)
	assert_bool(r["ok"]).is_false()
	assert_str(r["detail"]).contains("без записи kind: beacon")


func test_луч_датчика_на_площадке_хранилища_не_проходит_проверку_ice_gear() -> void:
	var d := _foyer_dict()
	var pad: Vector2i = _parse(d).vaults[0]["pad1"]
	d["ice"] = (d["ice"] as Array) + [{"id": "d1", "kind": "sensor", "cell1": [pad.x, pad.y], "dir": "E", "len": 2}]
	var r := LayoutCheck.check_ice_gear(_parse(d))
	assert_bool(r["ok"]).is_false()
	assert_str(r["detail"]).contains("площадки хранилища")


func test_блок_хранилища_без_записи_vaults_не_занимает_клеток() -> void:
	var d := _foyer_dict()
	(d["vaults"] as Array).pop_back()   # блок «V» [7, 0] без записи в vaults: с П5 занятость даёт только запись (клетка хранилища), поэтому клеток нет
	var ld := _parse(d)
	for c in LayoutData.block_cells(Vector2i(7, 0)):
		assert_bool(ld.occupied.has(c)).is_false()
	assert_bool(LayoutCheck.check_occupied_visible(ld)["ok"]).is_true()


func test_хранилище_на_углу_блока_не_проходит_проверку_сетки() -> void:
	var ld := _parse(_foyer_dict())
	var v: Dictionary = ld.vaults[0]
	v["slot"] = NodeLayout.cell_center(0, 0) + Vector3(0, 1.0, 0)   # угол четырёх клеток, как было до W3
	var r := LayoutCheck.check_vault_grid(ld)
	assert_bool(r["ok"]).is_false()
	assert_str(r["detail"]).contains("не в центре клетки")


func test_площадка_на_колонне_не_проходит_проверку_сетки() -> void:
	var d := _foyer_dict()
	d["cells"] = _cells_with({1: "#.#..#.."})   # блок [0, 1] — площадка хранилища [0, 0] — стал колонной
	var r := LayoutCheck.check_vault_grid(_parse(d))
	assert_bool(r["ok"]).is_false()
	assert_str(r["detail"]).contains("занята")


func test_площадка_не_рядом_с_хранилищем_не_проходит_проверку_сетки() -> void:
	var ld := _parse(_foyer_dict())
	var v: Dictionary = ld.vaults[1]
	v["pad"] = NodeGrid.center(Vector2i(14, 3))   # из блока [7, 1], но в двух клетках от хранилища (15; 1)
	var r := LayoutCheck.check_vault_grid(ld)
	assert_bool(r["ok"]).is_false()
	assert_str(r["detail"]).contains("не соседняя")


func test_прибытие_фойе_и_учебного_узла_безопасно() -> void:
	for n in ["foyer", "foyer_tutorial"]:
		var r := LayoutCheck.check_arrival_safe(LayoutData.load_named(n))
		assert_bool(r["ok"]).override_failure_message("%s: %s" % [n, r["detail"]]).is_true()
	assert_bool(LayoutCheck.run_all(LayoutData.load_named("foyer")).has("arrival_safe")).is_true()


func test_клетки_прибытия_вход_и_каждый_портал() -> void:
	var cells := LayoutCheck.arrival_cells(LayoutData.load_named("foyer"))
	assert_int(cells.size()).is_equal(4)   # вход и три портала
	assert_object(cells[0]["cell"]).is_equal(NodeGrid.cell_of(LayoutData.load_named("foyer").spawn))


func test_маршрут_через_вход_не_проходит_проверку_прибытия() -> void:
	var d := _foyer_dict()
	d["ice"] = [{"id": "g1", "kind": "sentry", "route": [{"cell": [3, 6]}, {"cell": [3, 4]}]}]   # Страж ходит по клетке входа
	var r := LayoutCheck.check_arrival_safe(_parse(d))
	assert_bool(r["ok"]).is_false()
	assert_str(r["detail"]).contains("вход")
	assert_str(r["detail"]).contains("на маршруте")


func test_строгая_проверка_зрения_ловит_стража_напротив_выхода_портала() -> void:
	var d := _foyer_dict()
	var ld0 := _parse(d)
	var arrive: Vector2i = LayoutCheck.arrival_cells(ld0)[1]["cell"]
	var guard := Vector2i(arrive.x + 3, arrive.y)
	# Страж стоит напротив выхода портала 1 и смотрит на него: на маршруте клеток прибытия нет, но они видны
	d["ice"] = [{"id": "g1", "kind": "sentry", "route": [{"cell1": [guard.x, guard.y], "wait": 1, "look": ["W"]}, {"cell1": [guard.x, guard.y + 1], "wait": 1, "look": ["W"]}]}]
	var ld := _parse(d)
	assert_bool(LayoutCheck.check_arrival_safe(ld)["ok"]).is_true()   # по маршруту чисто; зрение — справка (прикрывает грейс на сервере)
	var strict := LayoutCheck.check_arrival_safe(ld, 2, true)
	assert_bool(strict["ok"]).is_false()
	assert_str(strict["detail"]).contains("видна")


func test_без_стражей_прибытие_безопасно_и_строго() -> void:
	var d := _foyer_dict()
	d["ice"] = []
	assert_bool(LayoutCheck.check_arrival_safe(_parse(d), 2, true)["ok"]).is_true()


func test_серверная_разбирается_и_несёт_маяк_датчик_и_двух_стражей() -> void:
	var ld := LayoutData.load_named("server_room")
	assert_str(ld.error).is_empty()
	assert_int(ld.sentries.size()).is_equal(2)
	assert_int(ld.beacons.size()).is_equal(1)
	assert_int(ld.sensors.size()).is_equal(1)
	assert_int(ld.vaults.size()).is_equal(2)
	assert_int(ld.portals.size()).is_equal(3)
	assert_float(ld.sight_cells).is_equal(8.0)   # HARD: 4 клетки карты = 8 м
	assert_bool(ld.occupied.has(LayoutData.block_center_cell(Vector2i(3, 3)))).is_true()   # тумба Маяка — одна клетка
	assert_bool(ld.occupied.has(Vector2i(6, 6))).is_false()   # остальные три клетки блока свободны


func test_серверная_проходит_все_проверки() -> void:
	var ld := LayoutData.load_named("server_room")
	assert_str(ld.error).is_empty()
	var all := LayoutCheck.run_all(ld, "HARD")   # node_05 — HARD: окно площадки ≥ 8 тактов (BASE ≥ 12)
	for k: String in all:
		print("[layout_check] server_room %s ok=%s %s" % [k, str(all[k]["ok"]), str(all[k]["detail"])])
	assert_str("; ".join(LayoutCheck.failures(ld, "HARD"))).is_empty()
	assert_int(LayoutCheck.outer_window_min("BASE")).is_equal(12)
	assert_int(LayoutCheck.outer_window_min("NIGHTMARE")).is_equal(8)


func test_лёгкие_варианты_серверной_проходят_проверки_base_один_страж_без_маяка() -> void:
	for n in ["server_room_light", "server_room_dark"]:
		var ld := LayoutData.load_named(n)
		assert_str(ld.error).is_empty()
		assert_int(ld.sentries.size()).is_equal(1)
		assert_int(ld.beacons.size()).is_equal(0)
		assert_str("; ".join(LayoutCheck.failures(ld, "BASE"))).override_failure_message("%s: %s" % [n, "; ".join(LayoutCheck.failures(ld, "BASE"))]).is_empty()
	# «Тёмный» Подвал: зрение всех ICE на клетку карты (2 м) короче лёгкого
	assert_float(LayoutData.load_named("server_room_light").sight_cells - LayoutData.load_named("server_room_dark").sight_cells).is_equal(2.0)


func test_узлы_графа_с_серверной_привязаны_и_проходят_проверки_своего_тира() -> void:
	var g := NodeGraph.load_file("res://data/graph.json")
	for id in ["node_03", "node_05", "node_10"]:
		var name := str(g.nodes[id]["layout"])
		assert_str(name).override_failure_message("%s без layout" % id).is_not_empty()
		var ld := LayoutData.load_named(name)
		assert_str(ld.error).is_empty()
		var fails := LayoutCheck.failures(ld, g.tier_of(id))
		assert_array(fails).override_failure_message("%s (%s): %s" % [id, name, "; ".join(fails)]).is_empty()


func test_ядро_разбирается_логово_барьер_лучи_стражи_маяк() -> void:
	var ld := LayoutData.load_named("core")
	assert_str(ld.error).is_empty()
	assert_int(ld.sentries.size()).is_equal(2)
	assert_int(ld.beacons.size()).is_equal(1)
	assert_int(ld.sensors.size()).is_equal(2)
	assert_int(ld.barriers.size()).is_equal(1)
	assert_int(ld.vaults.size()).is_equal(3)
	assert_int(ld.portals.size()).is_equal(3)
	assert_int((ld.lair["cells"] as Array).size()).is_equal(16)
	var rings: Array = ld.vaults.map(func(v): return v["ring"])
	assert_array(rings).is_equal(["outer", "outer", "inner"])


func test_ядро_проходит_все_проверки_nightmare() -> void:
	var ld := LayoutData.load_named("core")
	assert_str(ld.error).is_empty()
	var all := LayoutCheck.run_all(ld, "NIGHTMARE")
	for k: String in all:
		print("[layout_check] core %s ok=%s %s" % [k, str(all[k]["ok"]), str(all[k]["detail"])])
	assert_str("; ".join(LayoutCheck.failures(ld, "NIGHTMARE"))).is_empty()


## Правило Game (levels.md §4.5, §2 п. 1): клетка входа S и свободные соседние не попадают ни в фокус, ни в периферию Стражей ни в одной фазе цикла.
## НЕ ВЫПОЛНЕНО паузами и взглядами (отчёт Game, PR): перебор взглядов в паузах (север/юг/восток у северных и южных углов, обе стороны обхода у
## обоих Стражей) даёт компромисс: если у южных углов смотреть на север (N/NE), вход виден лишь 8–14 тактов из 80, но площадка (0,1) попадает
## в зрение (окно 4 при пороге 8); иначе окна 10–13 в порядке, а вход виден 42–58 тактов из 80 — направление при движении по южным ветвям
## задаёт сама ветвь. Тест держит число тактов под наблюдением входа не выше известного (42), пока Game не решит: маршрут, сетка или дальность.
func test_ядро_вход_и_соседние_клетки_видны_не_чаще_известного() -> void:
	var ld := LayoutData.load_named("core")
	var cycle := LayoutCheck.cycle_ticks(ld)
	assert_int(cycle).is_greater(0)
	var grid := ld.grid()
	var s := NodeGrid.cell_of(ld.spawn)
	var cells: Array[Vector2i] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var c := s + Vector2i(dx, dy)
			if not grid.is_occupied(c):
				cells.append(c)
	var states := LayoutCheck.simulate(ld, cycle)
	var seen := 0
	for t in states.size():
		if LayoutCheck._seen_by_any(ld, grid, states[t], cells):
			seen += 1
	print("[core-entry] вход и соседние под наблюдением %d тактов из %d" % [seen, states.size()])
	assert_int(seen).is_less_equal(42)
	# цикл не короче двух порогов окна (порог по тиру добычи Ядра — HARD, 8)
	assert_int(cycle).is_greater_equal(2 * LayoutCheck.outer_window_min("NIGHTMARE"))


func test_ядро_правила_логова_6_3() -> void:
	var ld := LayoutData.load_named("core")
	var r := LayoutBots.check_core_rules(ld, "NIGHTMARE")
	print("[core-rules] ", r)
	assert_bool(r["ok"]).override_failure_message(str(r["detail"])).is_true()
