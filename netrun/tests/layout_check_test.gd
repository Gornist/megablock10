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


func test_цикл_патруля_фойе_восемнадцать_тактов_учебного_двадцать_два() -> void:
	assert_int(LayoutCheck.cycle_ticks(LayoutData.load_named("foyer"))).is_equal(18)
	assert_int(LayoutCheck.cycle_ticks(LayoutData.load_named("foyer_tutorial"))).is_equal(22)


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
