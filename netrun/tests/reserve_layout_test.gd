extends GdUnitTestSuite
## Запасной Страж и его будка в раскладке (П8, ice.md §4 «тревога 2», levels.md §2 «b»): блок «b» — будка (клетка 1 м у стены),
## запись `kind: reserve` — маршрут запасного Стража в формате Стража; первая точка маршрута — клетка будки.

const CELLS := ["V.......", "........", "........", "........", "........", "........", "S......1", "b.....EE"]


func _layout(ice: Array) -> LayoutData:
	return LayoutData.parse({"name": "t", "cells": CELLS, "vaults": [{"cell": [0, 0], "pad": [0, 1], "ring": "outer"}], "ice": ice})


func test_блок_b_даёт_будку_в_клетке_у_стены() -> void:
	var ld := _layout([])
	assert_str(ld.error).is_empty()
	assert_int(ld.booths.size()).is_equal(1)
	assert_object(ld.booths[0]).is_equal(LayoutData.block_center_cell(Vector2i(0, 7)))   # (1, 15): южная стена
	assert_int(ld.reserves.size()).is_equal(0)


func test_запасной_страж_разбирается_как_страж_с_первой_точкой_в_будке() -> void:
	var ld := _layout([{"id": "r1", "kind": "reserve", "route": [{"cell": [0, 7], "wait": 1, "look": ["N"]}, {"cell": [0, 4], "wait": 2, "look": ["E"]}]}])
	assert_str(ld.error).is_empty()
	assert_int(ld.reserves.size()).is_equal(1)
	assert_str(str(ld.reserves[0]["id"])).is_equal("r1")
	assert_int((ld.reserves[0]["route"] as Array).size()).is_equal(2)
	assert_object((ld.reserves[0]["route"] as Array)[0]["cell"]).is_equal(ld.booths[0])
	assert_int(ld.sentries.size()).is_equal(0)   # обычным Стражем не считается: выходит только на тревоге 2


func test_маршрут_запасного_начинается_не_в_будке_ошибка() -> void:
	var ld := _layout([{"id": "r1", "kind": "reserve", "route": [{"cell": [3, 3]}, {"cell": [0, 4]}]}])
	assert_str(ld.error).contains("будк")


func test_запасной_без_будки_на_карте_ошибка() -> void:
	var rows := CELLS.duplicate()
	rows[7] = ".....EE."   # без «b»
	var ld := LayoutData.parse({"name": "t", "cells": rows, "vaults": [{"cell": [0, 0], "pad": [0, 1], "ring": "outer"}], "ice": [{"id": "r1", "kind": "reserve", "route": [{"cell": [0, 7]}, {"cell": [0, 4]}]}]})
	assert_str(ld.error).is_not_empty()
