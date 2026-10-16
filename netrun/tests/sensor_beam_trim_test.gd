extends GdUnitTestSuite
## Луч Датчика обрывается на первой занятой клетке (Game 16.10: «что видно, то и работает»): раскладка обрезает клетки луча, и сервер, клиент и боты видят один и тот же луч.

func _layout(row5: String, sensor: Dictionary) -> LayoutData:
	return LayoutData.parse({
		"name": "beam_trim",
		"cells": ["V......V", "........", "........", "........", "........", row5, "1..S.EE2", "b....EE3"],
		"vaults": [{"cell": [0, 0], "pad": [0, 1], "ring": "outer"}, {"cell": [7, 0], "pad": [7, 1], "ring": "outer"}],
		"ice": [sensor],
	})


func test_колонна_на_пути_обрезает_луч() -> void:
	var ld := _layout("...#....", {"id": "d1", "kind": "sensor", "cell1": [2, 10], "dir": "E", "len": 8})
	assert_str(ld.error).is_empty()
	var cells: Array = ld.sensors[0]["cells"]
	assert_int(cells.size()).is_equal(4)   # клетки x 2…5: блок «#» занимает x 6…7
	assert_object(cells[cells.size() - 1]).is_equal(Vector2i(5, 10))


func test_без_препятствий_луч_целиком() -> void:
	var ld := _layout("........", {"id": "d1", "kind": "sensor", "cell1": [2, 10], "dir": "E", "len": 8})
	assert_str(ld.error).is_empty()
	assert_int((ld.sensors[0]["cells"] as Array).size()).is_equal(8)


func test_луч_упирающийся_сразу_в_препятствие_ошибка_раскладки() -> void:
	var ld := _layout(".#......", {"id": "d1", "kind": "sensor", "cell1": [2, 10], "dir": "E", "len": 6})
	assert_str(ld.error).contains("упирается")


func test_датчик_сервера_и_клиента_получают_обрезанные_клетки() -> void:
	var ld := _layout("...#....", {"id": "d1", "kind": "sensor", "cell1": [2, 10], "dir": "E", "len": 8})
	var s := TickSensor.new(ld.sensors[0]["cells"], 2, 1)
	assert_bool(s.covers(Vector2i(5, 10))).is_true()
	assert_bool(s.covers(Vector2i(6, 10))).is_false()   # за колонной луча нет
	assert_bool(s.covers(Vector2i(8, 10))).is_false()
