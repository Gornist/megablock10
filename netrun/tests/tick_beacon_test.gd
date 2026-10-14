extends GdUnitTestSuite
## Маяк (server/ice/tick_beacon.gd, ice.md §5): поворот на такт, зрение только фокусом на 5 клеток, укрытия закрывают, счётчик как у Стража,
## «Поиск» один раз, +1 на SUSPICIOUS, дальность +1 на тревоге 2+, качание в секторе; разбор `kind: beacon` в раскладке.

const N := Vector2i(0, -1)
const E := Vector2i(1, 0)
const S := Vector2i(0, 1)


func _grid() -> NodeGrid:
	return NodeGrid.new()   # пустая сетка: ни колонн, ни укрытий


func _beacon(start: Vector2i = N, settings: Dictionary = {}) -> TickBeacon:
	return TickBeacon.new(Vector2i(8, 8), start, _grid(), settings)


func _at(c: Vector2i) -> Dictionary:
	return {"s1": NodeGrid.center(c)}


func test_оборот_за_8_тактов_по_45_градусов() -> void:
	var b := _beacon(N)
	var seen: Array[Vector2i] = []
	for i in 8:
		b.tick({})
		seen.append(b.dir())
	assert_array(seen).is_equal([Vector2i(1, -1), E, Vector2i(1, 1), S, Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), N])


func test_намерение_показывает_следующий_угол() -> void:
	var b := _beacon(N)
	assert_object(b.intent()["next_dir"]).is_equal(Vector2i(1, -1))
	b.tick({})
	assert_object(b.intent()["dir"]).is_equal(Vector2i(1, -1))
	assert_object(b.intent()["next_dir"]).is_equal(E)


func test_видит_только_фокус_и_дальше_5_клеток_нет() -> void:
	# старт NW: после такта маяк смотрит на север
	var b := _beacon(Vector2i(-1, -1))
	b.tick(_at(Vector2i(8, 4)))   # прямо на север на 4 клетки — виден
	assert_bool(b.sees("s1")).is_true()
	b = _beacon(Vector2i(-1, -1))
	b.tick(_at(Vector2i(12, 8)))   # сбоку (восток) — вне фокуса
	assert_bool(b.sees("s1")).is_false()
	b = _beacon(Vector2i(-1, -1))
	b.tick(_at(Vector2i(8, 1)))   # на 7 клеток — дальше 5
	assert_bool(b.sees("s1")).is_false()


func test_счётчик_и_поиск_один_раз() -> void:
	var b := _beacon(Vector2i(-1, -1))   # после первого такта смотрит на N: держим цель на пути; дальше он уходит, возвращается через 8 тактов
	var events: Array = []
	b.tick(_at(Vector2i(8, 5)))   # такт 1: фокус, +2
	assert_int(b.awareness_of("s1")).is_equal(2)
	for i in 7:
		events.append_array(b.tick(_at(Vector2i(8, 5))))   # пока смотрит мимо, счётчик падает
	assert_int(b.awareness_of("s1")).is_less(2)
	assert_array(events.filter(func(e): return e["kind"] == "search_started")).is_empty()


func test_подозрительный_trace_даёт_плюс_один() -> void:
	var b := _beacon(Vector2i(-1, -1))
	b.tick(_at(Vector2i(8, 5)), {}, {}, {"s1": true})
	assert_int(b.awareness_of("s1")).is_equal(3)   # фокус +2 и +1 за SUSPICIOUS


func test_дальность_плюс_клетка_на_тревоге() -> void:
	var b := _beacon(Vector2i(-1, -1))
	assert_float(b.sight_cells()).is_equal(5.0)
	b.set_sight_bonus(1.0)
	assert_float(b.sight_cells()).is_equal(6.0)
	b.tick(_at(Vector2i(8, 2)))   # 6 клеток на север — теперь видна
	assert_bool(b.sees("s1")).is_true()


func test_укрытие_закрывает_взгляд() -> void:
	var g := _grid()
	g.occ[Vector2i(8, 6)] = true   # колонна между маяком (8,8) и целью (8,4) на пути на север
	var b := TickBeacon.new(Vector2i(8, 8), Vector2i(-1, -1), g)
	b.tick(_at(Vector2i(8, 4)))
	assert_bool(b.sees("s1")).is_false()


func test_скрытого_не_видит_неуязвимому_потолок_два() -> void:
	var b := _beacon(Vector2i(-1, -1))
	b.tick(_at(Vector2i(8, 5)), {"s1": true})
	assert_int(b.awareness_of("s1")).is_equal(0)
	b = _beacon(Vector2i(-1, -1))
	b.tick(_at(Vector2i(8, 5)), {}, {"s1": true})
	assert_int(b.awareness_of("s1")).is_less_equal(TickBeacon.IMMUNE_MAX)


func test_качание_в_секторе_не_делает_оборот() -> void:
	var b := _beacon(N, {"sweep_steps": 2})
	var seen: Array[Vector2i] = []
	for i in 8:
		b.tick({})
		seen.append(b.dir())
	# от севера: NE, E, NE, N, NW, W, NW, N — не дальше двух шагов в каждую сторону
	assert_array(seen).is_equal([Vector2i(1, -1), E, Vector2i(1, -1), N, Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, -1), N])


func test_раскладка_разбирает_маяк() -> void:
	var d := {"name": "t", "cells": ["V......V", ".##.###.", "........", ".##O.##.", "........", ".##.###.", "1..S.EE2", "b....EE3"],
		"vaults": [], "ice": [{"id": "o1", "kind": "beacon", "cell": [3, 3], "start": "N", "step_deg": 45}], "black": null}
	var ld := LayoutData.parse(d)
	assert_str(ld.error).is_empty()
	assert_int(ld.beacons.size()).is_equal(1)
	assert_object(ld.beacons[0]["start"]).is_equal(N)
	assert_object(ld.beacons[0]["cell"]).is_equal(LayoutData.block_center_cell(Vector2i(3, 3)))
	d["ice"] = [{"id": "o1", "kind": "beacon", "cell": [9, 3], "start": "N"}]
	assert_str(LayoutData.parse(d).error).is_not_empty()   # вне карты
