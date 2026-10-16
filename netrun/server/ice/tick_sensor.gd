class_name TickSensor
extends RefCounted
## Датчик (Soft ICE, docs/gamedesign/ice.md §5, levels.md §4.2): луч вдоль ряда или столбца 2–6 клеток карты (2–12 клеток 1 м). Включён `on` тактов, выключен `off`,
## за такт до включения мигает. Срабатывает на нетраннера в клетке включённого луча и на прыжок, отрезок которого пересекает включённый
## луч («луч видит перенос»). Чистая логика без сцены и сети: такт — `tick()`, проверки — `hit_by` (кто стоит на луче) и `crossed_by` (прыжок).
## Последствия (trace +5, тревога +5, ближайший Страж в Проверку к клетке) накладывает узел: у датчика только факт и клетка срабатывания.

## Программа по тиру: x — тактов включён, y — тактов выключен (ice.md §5: BASE 3/3, HARD 2/2, NIGHTMARE 2/1).
const PROGRAMS := {"BASE": Vector2i(3, 3), "HARD": Vector2i(2, 2), "NIGHTMARE": Vector2i(2, 1)}

var _cells: Array[Vector2i] = []
var _set: Dictionary = {}
var _on := 3
var _off := 3
var _t := 0   # позиция в цикле: 0 … on+off−1; меньше `on` — включён


## Программа тира; неизвестный тир — как BASE.
static func program_of(tier: String) -> Vector2i:
	return PROGRAMS.get(tier, PROGRAMS["BASE"])


## Клетки луча (общий код NodeGrid: раскладку разбирает и клиент, которому каталога server/ не видно).
static func beam_cells(start: Vector2i, dir: Vector2i, length: int) -> Array[Vector2i]:
	return NodeGrid.beam_cells(start, dir, length)


## phase — сколько тактов цикла уже прошло в начале (разводит парные датчики по фазе); on и off не меньше 1.
func _init(cells: Array[Vector2i], on_ticks: int, off_ticks: int, phase: int = 0) -> void:
	_cells = cells.duplicate()
	for c in _cells:
		_set[c] = true
	_on = maxi(on_ticks, 1)
	_off = maxi(off_ticks, 1)
	_t = posmod(phase, _on + _off)


## Датчик записи раскладки `sd` ({cells, on, off, phase}): числа цикла из записи, ноль — из `program` (программа тира). Стартует в фазе «выключен»:
## П6 (16.10): у конструктора позиция 0 — «включён», и игрок входил в узел под включённым лучом («луч был включён с самого начала»). Узел и проверка раскладки
## (LayoutBots) строят датчики одним путём, чтобы то, что считает проверка, было тем, что в игре.
static func for_layout(sd: Dictionary, program: Vector2i) -> TickSensor:
	var on := int(sd["on"]) if int(sd["on"]) > 0 else program.x
	var off := int(sd["off"]) if int(sd["off"]) > 0 else program.y
	var ts := TickSensor.new(sd["cells"], on, off)
	ts.start_off(int(sd["phase"]))
	return ts


## Начало цикла в фазе «выключен»: `delay` — сколько выключенных тактов уже прошло (разводит парные датчики), не больше, чем есть выключенных — луч при входе не включён.
func start_off(delay: int = 0) -> void:
	_t = _on + posmod(delay, _off)


func cells() -> Array[Vector2i]:
	return _cells


func program() -> Vector2i:
	return Vector2i(_on, _off)


## Один такт: позиция цикла вперёд.
func tick() -> void:
	_t = (_t + 1) % (_on + _off)


func is_on() -> bool:
	return _t < _on


## Выключен сейчас и включится на следующем такте: клиенту — мигание, игроку — «последнее окно».
func blinking() -> bool:
	return not is_on() and (_t + 1) % (_on + _off) < _on


## Тактов до смены состояния (включён — до выключения, выключен — до включения), не меньше 1.
func ticks_left() -> int:
	return (_on - _t) if is_on() else (_on + _off - _t)


func covers(c: Vector2i) -> bool:
	return _set.has(c)


## Сессии, стоящие на клетках луча, пока он включён: сессия → клетка.
func hit_by(positions: Dictionary) -> Dictionary:
	var out := {}
	if not is_on():
		return out
	for s in positions:
		var c := NodeGrid.cell_of(positions[s])
		if _set.has(c):
			out[s] = c
	return out


## Прыжок из `from` в `to` (мировые точки): первая клетка луча, которую задевает отрезок (включая точку приземления), или Vector2i.MAX, если
## датчик выключен или отрезок луча не касается. Клетка старта не считается: нетраннер уже стоял под лучом, когда тот погас.
func crossed_by(from: Vector3, to: Vector3) -> Vector2i:
	if not is_on():
		return Vector2i.MAX
	return NodeGrid.segment_first_hit(_set, from, to)


## Намерение для клиента: клетки луча, включён ли, мигает ли, сколько тактов до смены.
func intent() -> Dictionary:
	return {"cells": _cells, "on": is_on(), "blink": blinking(), "left": ticks_left()}
