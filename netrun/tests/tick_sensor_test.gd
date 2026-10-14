extends GdUnitTestSuite
## Датчик (server/ice/tick_sensor.gd, ice.md §5): луч 2–12 клеток 1 м (1–6 клеток карты), цикл вкл/выкл по тиру, мигание за такт до включения, срабатывание на клетке луча
## и на прыжке, отрезок которого пересекает луч; разбор `kind: sensor` в раскладке; Проверка Стража по внешнему сигналу (TickIce.investigate).

const E := Vector2i(1, 0)


func _beam(on: int = 2, off: int = 2, phase: int = 0) -> TickSensor:
	return TickSensor.new(TickSensor.beam_cells(Vector2i(8, 8), E, 3), on, off, phase)   # клетки (8,8), (9,8), (10,8)


func test_программа_по_тиру() -> void:
	assert_object(TickSensor.program_of("BASE")).is_equal(Vector2i(3, 3))
	assert_object(TickSensor.program_of("HARD")).is_equal(Vector2i(2, 2))
	assert_object(TickSensor.program_of("NIGHTMARE")).is_equal(Vector2i(2, 1))
	assert_object(TickSensor.program_of("???")).is_equal(Vector2i(3, 3))


func test_клетки_луча_только_по_ряду_или_столбцу_длиной_2_6() -> void:
	assert_int(TickSensor.beam_cells(Vector2i(0, 0), E, 4).size()).is_equal(4)
	assert_int(TickSensor.beam_cells(Vector2i(0, 0), Vector2i(0, 1), 2).size()).is_equal(2)
	assert_bool(TickSensor.beam_cells(Vector2i(0, 0), E, 1).is_empty()).is_true()
	assert_bool(TickSensor.beam_cells(Vector2i(0, 0), E, 13).is_empty()).is_true()
	assert_bool(TickSensor.beam_cells(Vector2i(0, 0), Vector2i(1, 1), 3).is_empty()).is_true()   # диагональ — нет


func test_цикл_включён_n_тактов_выключен_m_и_мигание_за_такт() -> void:
	var s := _beam(2, 2)   # старт: включён (t=0)
	var seen: Array = []
	var blink: Array = []
	for i in 8:
		seen.append(s.is_on())
		blink.append(s.blinking())
		s.tick()
	assert_array(seen).is_equal([true, true, false, false, true, true, false, false])
	assert_array(blink).is_equal([false, false, false, true, false, false, false, true])   # мигает последний выключенный такт


func test_фаза_сдвигает_цикл_и_осталось_тактов() -> void:
	var s := _beam(3, 3, 3)   # начинает выключенным
	assert_bool(s.is_on()).is_false()
	assert_int(s.ticks_left()).is_equal(3)
	s.tick()
	s.tick()
	assert_bool(s.blinking()).is_true()
	assert_int(s.ticks_left()).is_equal(1)


func test_стоящий_на_включённом_луче_виден_выключенный_нет() -> void:
	var s := _beam(1, 1)
	var on_beam := {"s1": NodeGrid.center(Vector2i(9, 8)), "s2": NodeGrid.center(Vector2i(9, 9))}
	assert_bool(s.hit_by(on_beam).has("s1")).is_true()
	assert_bool(s.hit_by(on_beam).has("s2")).is_false()   # рядом с лучом, не на нём
	s.tick()   # выключился
	assert_bool(s.hit_by(on_beam).is_empty()).is_true()


func test_прыжок_через_луч_срабатывает_и_перепрыгнуть_выключенный_можно() -> void:
	var s := _beam(1, 1)
	var a := NodeGrid.center(Vector2i(9, 6))
	var b := NodeGrid.center(Vector2i(9, 10))   # отрезок поперёк луча, концы вне него
	assert_object(s.crossed_by(a, b)).is_equal(Vector2i(9, 8))
	assert_object(s.crossed_by(a, NodeGrid.center(Vector2i(9, 7)))).is_equal(Vector2i.MAX)   # не дошёл до луча
	s.tick()
	assert_object(s.crossed_by(a, b)).is_equal(Vector2i.MAX)   # выключен: прыжок свободен


func test_клетка_старта_прыжка_не_считается() -> void:
	var s := _beam(2, 2)
	var from := NodeGrid.center(Vector2i(9, 8))   # стоял на луче, когда тот горел
	assert_object(s.crossed_by(from, NodeGrid.center(Vector2i(9, 5)))).is_equal(Vector2i.MAX)   # уходит вбок: не считается
	assert_object(s.crossed_by(from, NodeGrid.center(Vector2i(10, 8)))).is_equal(Vector2i(10, 8))   # в соседнюю клетку луча — считается


func test_раскладка_разбирает_датчик_и_отвергает_плохой() -> void:
	var d := {"name": "t", "cells": ["V......V", "........", "........", "........", "........", "........", "1..S.EE2", "b....EE3"],
		"vaults": [], "ice": [{"id": "d1", "kind": "sensor", "cell": [4, 3], "dir": "E", "len": 3, "on": 2, "off": 2}], "black": null}
	var ld := LayoutData.parse(d)
	assert_str(ld.error).is_empty()
	assert_int(ld.sensors.size()).is_equal(1)
	assert_int((ld.sensors[0]["cells"] as Array).size()).is_equal(3)
	assert_int(int(ld.sensors[0]["on"])).is_equal(2)
	d["ice"] = [{"id": "d1", "kind": "sensor", "cell": [4, 3], "dir": "NE", "len": 3}]
	assert_str(LayoutData.parse(d).error).is_not_empty()   # по диагонали нельзя
	d["ice"] = [{"id": "d1", "kind": "sensor", "cell": [7, 3], "dir": "E", "len": 6}]
	assert_str(LayoutData.parse(d).error).is_not_empty()   # выходит за карту


func test_проверка_по_сигналу_идёт_к_клетке_и_держит_два_такта() -> void:
	var ti := TickIce.new({}, [{"cell": Vector2i(2, 2), "wait": 0, "look": Vector2i.ZERO}, {"cell": Vector2i(10, 2), "wait": 0, "look": Vector2i.ZERO}], NodeGrid.new())
	ti.investigate("s1", Vector2i(2, 8))
	ti.tick({"s1": NodeGrid.center(Vector2i(12, 12))})   # цель далеко, не видна
	assert_int(ti.state()).is_equal(TickIce.Mode.CHECK)
	var fp: Variant = ti.footprint()
	assert_object(fp).is_equal(Vector2i(2, 8))
