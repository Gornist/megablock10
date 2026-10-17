extends GdUnitTestSuite
## Карта раскладки любого размера W×H блоков, 1..12 по стороне (G1): размеры, границы комнаты, мировые координаты, сетка, прыжки у краёв,
## предел площади по тиру (LayoutCheck "area"), боты на новых клетках. 8×8 бит-в-бит как раньше проверяют остальные тесты раскладок.

const ROOM_MIN := Vector2(-8.0, -14.0)


## Синтетическая раскладка c×r блоков: открытое поле; вход S в (0,0), порталы 1 и 2 в юго-западном и северо-восточном углах, площадка выхода E на севере посередине,
## хранилище V в юго-восточном углу (площадка — блок слева от него). extra — поля поверх (например ice).
func _dict(c: int, r: int, extra: Dictionary = {}) -> Dictionary:
	var rows: Array = []
	for z in r:
		var line := ""
		for x in c:
			var ch := "."
			if x == 0 and z == 0:
				ch = "S"
			elif x == 0 and z == r - 1:
				ch = "1"
			elif x == c - 1 and z == 0:
				ch = "2"
			elif x == c / 2 and z == 0:
				ch = "E"
			elif x == c - 1 and z == r - 1:
				ch = "V"
			line += ch
		rows.append(line)
	var d := {"name": "synt_%dx%d" % [c, r], "cells": rows, "vaults": [{"cell": [c - 1, r - 1], "pad": [c - 2, r - 1], "ring": "outer"}],
		"ice": [], "black": null, "meta": {"sight_cells": 6}}
	d.merge(extra, true)
	return d


func _parse(c: int, r: int, extra: Dictionary = {}) -> LayoutData:
	var ld := LayoutData.parse(_dict(c, r, extra))
	assert_str(ld.error).override_failure_message("%dx%d: %s" % [c, r, ld.error]).is_empty()
	return ld


func _center(ix: int, iz: int) -> Vector3:
	return Vector3(ROOM_MIN.x + 2.0 * (ix + 0.5), 0.0, ROOM_MIN.y + 2.0 * (iz + 0.5))


# ---------------------------------------------------------------- разбор и размеры

func test_размеры_10x10_и_6x9() -> void:
	var a := _parse(10, 10)
	assert_int(a.cols).is_equal(10)
	assert_int(a.rows).is_equal(10)
	assert_int(a.blocks.size()).is_equal(10)
	assert_vector(a.room_max()).is_equal(Vector2(12.0, 6.0))      # ROOM_MIN + 2 · 10
	assert_vector(a.room_center()).is_equal(Vector3(2.0, 0.0, -4.0))
	var b := _parse(6, 9)
	assert_int(b.cols).is_equal(6)
	assert_int(b.rows).is_equal(9)
	assert_vector(b.room_max()).is_equal(Vector2(4.0, 4.0))
	assert_vector(b.room_center()).is_equal(Vector3(-2.0, 0.0, -5.0))


func test_8x8_это_прежние_константы() -> void:
	var ld := _parse(8, 8)
	assert_vector(ld.room_max()).is_equal(NodeLayout.ROOM_MAX)
	assert_vector(ld.room_center()).is_equal(NodeLayout.ROOM_CENTER)
	assert_vector(Vector2(ld.grid().size)).is_equal(Vector2(NodeGrid.cols(), NodeGrid.rows()))
	assert_vector(ld.grid().room_max()).is_equal(NodeLayout.ROOM_MAX)
	for name: String in ["legacy", "foyer", "foyer_tutorial", "core", "server_room"]:
		var f := LayoutData.load_named(name)
		assert_str(f.error).is_empty()
		assert_int(f.cols).is_equal(8)
		assert_int(f.rows).is_equal(8)


func test_вход_порталы_выход_хранилище_в_мировых_координатах() -> void:
	var ld := _parse(10, 10)
	assert_vector(ld.spawn).is_equal(_center(0, 0))
	assert_int(ld.portals.size()).is_equal(2)
	assert_vector(ld.portals[0]).is_equal(_center(0, 9))
	assert_vector(ld.portals[1]).is_equal(_center(9, 0))
	assert_vector(ld.exit_pos).is_equal(_center(5, 0))
	# хранилище в юго-восточном блоке: клетка 1 м — одна из четырёх клеток блока (18..19, 18..19), площадка — в блоке слева
	var v: Dictionary = ld.vaults[0]
	assert_bool(LayoutData.block_of(v["cell1"]) == Vector2i(9, 9)).is_true()
	assert_bool(LayoutData.block_of(v["pad1"]) == Vector2i(8, 9)).is_true()
	assert_vector(v["slot"]).is_equal(NodeGrid.center(v["cell1"]) + Vector3(0, 1, 0))
	assert_bool(NodeLayout.in_room(v["pad"], ld.room_max())).is_true()
	assert_bool(NodeLayout.in_room(v["slot"], ld.room_max())).is_true()
	assert_bool(NodeLayout.in_room(ld.portals[0], NodeLayout.ROOM_MAX)).is_false()   # по старым границам 8×8 — вне комнаты


func test_6x9_центр_последнего_блока_у_юго_восточного_угла() -> void:
	var ld := _parse(6, 9)
	assert_vector(ld.portals[0]).is_equal(_center(0, 8))
	assert_vector(ld.portals[1]).is_equal(_center(5, 0))
	assert_float(NodeLayout.wall_gap(_center(5, 8), ld.room_max())).is_equal(1.0)   # центр блока — в метре от обеих стен


func test_сетка_20x20_границы() -> void:
	var g := _parse(10, 10).grid()
	assert_int(g.size.x).is_equal(20)
	assert_int(g.size.y).is_equal(20)
	assert_bool(g.has_cell(Vector2i(19, 19))).is_true()
	assert_bool(g.has_cell(Vector2i(20, 0))).is_false()
	assert_bool(g.has_cell(Vector2i(0, 20))).is_false()
	assert_bool(g.is_occupied(Vector2i(20, 5))).is_true()          # вне границ — занято
	assert_bool(g.is_occupied(Vector2i(17, 5))).is_false()         # по старой сетке 16×16 это была бы стена
	assert_vector(g.room_max()).is_equal(Vector2(12.0, 6.0))
	var g69 := _parse(6, 9).grid()
	assert_int(g69.size.x).is_equal(12)
	assert_int(g69.size.y).is_equal(18)


func test_умолчание_сетки_по_прежнему_16x16() -> void:
	var g := NodeGrid.new()
	assert_int(g.size.x).is_equal(16)
	assert_int(g.size.y).is_equal(16)
	assert_vector(g.room_max()).is_equal(NodeLayout.ROOM_MAX)
	assert_bool(g.is_occupied(Vector2i(16, 0))).is_true()
	assert_bool(NodeGrid.for_layout().is_occupied(Vector2i(16, 0))).is_true()


# ---------------------------------------------------------------- ошибки разбора

func test_ошибки_разбора_размера() -> void:
	var rows12: Array = []
	for z in 12:
		rows12.append(".".repeat(13))
	assert_str(LayoutData.parse({"cells": rows12}).error).is_not_empty()           # 13 столбцов
	var rows13: Array = []
	for z in 13:
		rows13.append(".".repeat(12))
	assert_str(LayoutData.parse({"cells": rows13}).error).is_not_empty()           # 13 строк
	assert_str(LayoutData.parse({"cells": []}).error).is_not_empty()
	assert_str(LayoutData.parse({"cells": [""]}).error).is_not_empty()
	var d := _dict(6, 6)
	(d["cells"] as Array)[3] = ".....S."                                          # строка длиннее первой
	assert_str(LayoutData.parse(d).error).contains("cells[3]")
	var d2 := _dict(6, 6)
	(d2["cells"] as Array)[2] = "..."                                             # короче
	assert_str(LayoutData.parse(d2).error).contains("cells[2]")


func test_12x12_разбирается_13_нет() -> void:
	assert_str(LayoutData.parse(_dict(12, 12)).error).is_empty()
	assert_str(LayoutData.parse(_dict(1, 1)).error).is_not_empty()                 # 1×1: нет места ни входу, ни выходу — но это ошибка содержимого, не размера
	var d13 := _dict(12, 12)
	var rows: Array = d13["cells"]
	for i in rows.size():
		rows[i] = (rows[i] as String) + "."
	assert_str(LayoutData.parse(d13).error).is_not_empty()


func test_клетки_вне_карты_по_новому_размеру() -> void:
	# блок [9, 9] есть на 10×10 и нет на 6×9
	var ok := LayoutData.parse(_dict(10, 10, {"vaults": [{"cell": [9, 9], "pad": [8, 9]}]}))
	assert_str(ok.error).is_empty()
	var bad := LayoutData.parse(_dict(6, 9, {"vaults": [{"cell": [9, 9], "pad": [8, 9]}]}))
	assert_str(bad.error).contains("6×9")
	# клетка 1 м: cell1 [19, 19] есть на 10×10, на 6×9 (12×18) — нет
	var route := [{"cell1": [19, 3], "wait": 0}, {"cell1": [19, 9], "wait": 0}]
	assert_str(LayoutData.parse(_dict(10, 10, {"ice": [{"id": "g1", "kind": "sentry", "route": route}]})).error).is_empty()
	assert_str(LayoutData.parse(_dict(6, 9, {"ice": [{"id": "g1", "kind": "sentry", "route": route}]})).error).is_not_empty()


# ---------------------------------------------------------------- прыжки, границы комнаты

func test_прыжок_у_восточного_и_южного_края() -> void:
	var ld := _parse(10, 10)
	var g := ld.grid()
	var east := Vector3(11.5, 0.0, -3.5)            # клетка (19, 10)
	assert_vector(Vector3(NodeGrid.cell_of(east).x, 0, NodeGrid.cell_of(east).y)).is_equal(Vector3(19, 0, 10))
	assert_str(g.hop_verdict(east, east + Vector3(-2, 0, 0))).is_equal("")
	assert_str(g.hop_verdict(east - Vector3(1, 0, 0), east)).is_equal("")               # на восточную клетку — можно
	assert_str(g.hop_verdict(east, east + Vector3(1, 0, 0))).is_equal("occupied")       # за край — нет
	var south := Vector3(-3.5, 0.0, 5.5)            # клетка (9, 19)
	assert_str(g.hop_verdict(south, south + Vector3(0, 0, -2))).is_equal("")
	assert_str(g.hop_verdict(south, south + Vector3(0, 0, 1))).is_equal("occupied")
	# на сетке по умолчанию (16×16) те же клетки — вне комнаты
	assert_str(NodeGrid.new().hop_verdict(east - Vector3(2, 0, 0), east)).is_not_empty()


func test_pick_зажимает_в_границы_раскладки() -> void:
	var g := _parse(10, 10).grid()
	var from := Vector3(10.5, 0.0, 4.5)             # клетка (18, 18)
	var r := g.pick(from, Vector3(30.0, 0.0, 30.0)) # прицел далеко за юго-восточный угол
	assert_vector(Vector2(r["cell"])).is_equal(Vector2(19, 19))
	assert_str(r["kind"]).is_equal("hop")
	var north := g.pick(Vector3(-7.5, 0.0, -12.5), Vector3(-40.0, 0.0, -40.0))      # из клетки (0, 1) за северо-западный угол
	assert_vector(Vector2(north["cell"])).is_equal(Vector2(0, 0))


func test_путь_у_южного_и_восточного_края() -> void:
	var g := _parse(10, 10).grid()
	var p := g.path(Vector2i(0, 19), Vector2i(19, 19))
	assert_bool(p.is_empty()).is_false()
	assert_bool(p[p.size() - 1] == Vector2i(19, 19)).is_true()
	for c in p:
		assert_bool(g.has_cell(c)).is_true()


func test_границы_комнаты_по_раскладке_а_не_по_умолчанию() -> void:
	var ld := _parse(10, 10)
	var inside := Vector3(11.0, 0.0, 5.0)
	assert_bool(NodeLayout.in_room(inside, ld.room_max())).is_true()
	assert_bool(NodeLayout.in_room(inside)).is_false()
	assert_vector(NodeLayout.clamp_to_room(Vector3(99, 0, 99), ld.room_max())).is_equal(Vector3(12, 0, 6))
	assert_vector(NodeLayout.clamp_to_room(Vector3(99, 0, 99))).is_equal(Vector3(8, 0, 2))     # по умолчанию — 8×8
	# клиентские правила: прицел и вердикт телепорта
	var aim := RigMath.teleport_aim(Vector3(10.0, 1.0, 4.0), Vector3(1, -0.2, 1).normalized(), Vector3(10.0, 0.0, 4.0), 6.0, 0.0, ld.room_max())
	assert_bool(aim["valid"]).is_true()
	assert_bool(NodeLayout.in_room(aim["p"], ld.room_max())).is_true()
	assert_float(aim["p"].x).is_greater(8.0)         # старая граница 8 м не режет
	assert_str(RigMath.teleport_verdict(Vector3(10, 0, 4), Vector3(11.5, 0, 5.5), 5.0, false, 4.5, 0.0, ld.room_max())).is_equal("")
	assert_str(RigMath.teleport_verdict(Vector3(10, 0, 4), Vector3(11.5, 0, 5.5), 5.0, false, 4.5, 0.0)).is_equal(WorldMsg.REASON_ROOM)
	assert_str(RigMath.teleport_verdict(Vector3(10, 0, 4), Vector3(12.5, 0, 5.5), 5.0, false, 4.5, 0.0, ld.room_max())).is_equal(WorldMsg.REASON_ROOM)


func test_прибытие_от_портала_по_центру_и_границам_раскладки() -> void:
	var ld := _parse(10, 10)
	var arrive := NodeLayout.arrival_in(ld, 1)      # портал 2 в северо-восточном блоке (7, -13): входит к центру (2, -4)
	var to_center := (ld.room_center() - ld.portals[1]).normalized()
	assert_float(NodeLayout.flat_distance(arrive, ld.portals[1])).is_equal_approx(NodeLayout.ARRIVE_DIST, 0.001)
	assert_float(to_center.dot((arrive - ld.portals[1]).normalized())).is_greater(0.999)
	assert_bool(NodeLayout.in_room(arrive, ld.room_max())).is_true()


func test_дубликат_сетки_держит_размер() -> void:
	var g := _parse(10, 10).grid()
	var d := g.duplicate_grid()
	assert_int(d.size.x).is_equal(20)
	assert_int(d.size.y).is_equal(20)
	d.occ[Vector2i(1, 1)] = true
	assert_bool(g.occ.has(Vector2i(1, 1))).is_false()   # занятость — копия


# ---------------------------------------------------------------- предел площади

func _area_ok(c: int, r: int, tier: String) -> bool:
	return bool(LayoutCheck.check_area(_parse(c, r), tier)["ok"])


func test_предел_площади_по_тиру() -> void:
	assert_bool(_area_ok(8, 8, "BASE")).is_true()        # 64
	assert_bool(_area_ok(8, 9, "BASE")).is_false()       # 72 > 64
	assert_bool(_area_ok(9, 8, "BASE")).is_false()
	assert_bool(_area_ok(10, 10, "HARD")).is_true()      # 100
	assert_bool(_area_ok(10, 10, "BASE")).is_false()
	assert_bool(_area_ok(11, 11, "HARD")).is_false()     # 121 > 100
	assert_bool(_area_ok(12, 12, "NIGHTMARE")).is_true() # 144
	assert_bool(_area_ok(12, 12, "HARD")).is_false()
	assert_bool(_area_ok(6, 9, "BASE")).is_true()        # 54
	assert_str(LayoutCheck.check_area(_parse(8, 9), "BASE")["detail"]).contains("72")


func test_area_входит_в_run_all_и_в_failures() -> void:
	var ld := _parse(8, 9)
	var all := LayoutCheck.run_all(ld, "BASE")
	assert_bool(all.has("area")).is_true()
	assert_bool(bool(all["area"]["ok"])).is_false()
	var found := false
	for f in LayoutCheck.failures(ld, "BASE"):
		found = found or f.begins_with("area:")
	assert_bool(found).is_true()
	assert_bool(bool(LayoutCheck.run_all(ld, "HARD")["area"]["ok"])).is_true()


# ---------------------------------------------------------------- LayoutCheck и боты на новых клетках

func test_run_all_на_10x10_не_падает_и_проверки_размера_проходят() -> void:
	var ld := _parse(10, 10)
	var all := LayoutCheck.run_all(ld, "HARD")
	for k: String in ["area", "reachable", "dead_ends", "vault_grid", "occupied_visible", "ice_gear"]:
		assert_bool(bool(all[k]["ok"])).override_failure_message("%s: %s" % [k, all[k]["detail"]]).is_true()


func test_run_all_на_6x9_не_падает() -> void:
	var ld := _parse(6, 9)
	var all := LayoutCheck.run_all(ld, "BASE")
	for k: String in ["area", "reachable", "dead_ends", "vault_grid", "occupied_visible"]:
		assert_bool(bool(all[k]["ok"])).override_failure_message("%s: %s" % [k, all[k]["detail"]]).is_true()


func test_тупики_считаются_до_восточного_и_южного_края() -> void:
	# глухой коридор вдоль восточного края: блоки (9,3)…(9,6), стена слева и снизу, вход только сверху — тупик в 4 блока
	var d := _dict(10, 10)
	var cells: Array = d["cells"]
	for z in range(3, 7):
		cells[z] = "........#."
	cells[7] = ".........#"
	var ld := LayoutData.parse(d)
	assert_str(ld.error).is_empty()
	var r := LayoutCheck.check_dead_ends(ld)
	assert_bool(bool(r["ok"])).override_failure_message(str(r["detail"])).is_false()
	assert_str(r["detail"]).contains("(9, 6)")


func test_боты_считают_окна_на_клетках_восточного_края() -> void:
	# Страж ходит вдоль восточного края сверху вниз: клетки столбца 19 под взглядом
	var route := [{"cell1": [18, 3], "wait": 2, "look": ["S"]}, {"cell1": [18, 12], "wait": 2, "look": ["N"]}]
	var ld := _parse(10, 10, {"ice": [{"id": "g1", "kind": "sentry", "route": route}]})
	var b := LayoutBots.new(ld, "HARD")
	assert_str(b.error).is_empty()
	assert_int(b._cols).is_equal(20)
	assert_int(b._rows).is_equal(20)
	assert_bool(b.cycle > 1).is_true()
	var seen_east := false
	var seen_south := false
	for t in b.cycle:
		seen_east = seen_east or b.exposed(t, b._idx(Vector2i(18, 8)))
		seen_south = seen_south or b.exposed(t, b._idx(Vector2i(18, 11)))
	assert_bool(seen_east).is_true()
	assert_bool(seen_south).is_true()
	# индексы не пересекаются между краями 20×20 (ключ i = y · 20 + x)
	assert_int(b._idx(Vector2i(19, 19))).is_equal(399)
	assert_bool(b._cell(399) == Vector2i(19, 19)).is_true()
	# окна и пути считаются на 20×20 без ошибок скрипта: ответ — словарь с ok и detail
	var w := LayoutCheck.check_windows(ld, LayoutCheck.outer_window_min("HARD"))
	assert_bool(w.has("ok") and w.has("detail")).is_true()
	var paths := LayoutBots.check_paths(ld)
	assert_bool(bool(paths["ok"])).override_failure_message(str(paths["detail"])).is_true()
	assert_bool(bool(LayoutBots.check_periods(ld)["ok"])).is_true()
	# вор и бегун проходят прогон по 20×20 до конца (результат — словарь с ok/detail, без ошибки скрипта)
	var bots := LayoutBots.check_bots(ld, "HARD")
	assert_bool(bots.has("ok") and bots.has("detail")).override_failure_message(str(bots)).is_true()
