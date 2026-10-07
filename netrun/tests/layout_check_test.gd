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
	for sym in ["O", "B", "L"]:
		var d := _foyer_dict()
		d["cells"] = _cells_with({2: "...%s...." % sym})
		var r := LayoutCheck.check_occupied_visible(_parse(d))
		assert_bool(r["ok"]).override_failure_message("символ %s прошёл" % sym).is_false()
		assert_str(r["detail"]).contains("без модели")
		assert_str(r["detail"]).contains(sym)


func test_блок_хранилища_без_записи_vaults_не_проходит_проверку_видимости() -> void:
	var d := _foyer_dict()
	(d["vaults"] as Array).pop_back()   # блок «V» [7, 0] остался занятым, а хранилища и укрытий в нём нет
	var r := LayoutCheck.check_occupied_visible(_parse(d))
	assert_bool(r["ok"]).is_false()
	assert_str(r["detail"]).contains("«V»")


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
