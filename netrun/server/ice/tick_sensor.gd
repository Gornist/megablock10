class_name TickSensor
extends RefCounted
## Датчик (Soft ICE, docs/gamedesign/ice.md §5, levels.md §4.2): луч вдоль ряда или столбца 2–6 клеток карты (2–12 клеток 1 м). Включён `on` тактов, выключен `off`,
## за такт до включения мигает. Срабатывает на нетраннера в клетке включённого луча и на прыжок, отрезок которого пересекает включённый
## луч («луч видит перенос»). Чистая логика без сцены и сети: такт — `tick()`, проверки — `hit_by` (кто стоит на луче) и `crossed_by` (прыжок).
## Последствия (trace +5, тревога +5, ближайший Страж в Проверку к клетке) накладывает узел: у датчика только факт и клетка срабатывания.

## Программа по тиру: x — тактов включён, y — тактов выключен (ice.md §5: BASE 3/3, HARD 2/2, NIGHTMARE 2/1).
const PROGRAMS := {"BASE": Vector2i(3, 3), "HARD": Vector2i(2, 2), "NIGHTMARE": Vector2i(2, 1)}
## Шаг дискретизации отрезка прыжка, клетки: меньше клетки, чтобы не проскочить угол.
const _STEP := 0.25

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
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var start := NodeGrid.cell_of(from)
	var n := maxi(ceili(a.distance_to(b) / _STEP), 1)
	for i in range(1, n + 1):
		var p := a.lerp(b, float(i) / n)
		var c := NodeGrid.cell_of(Vector3(p.x, 0.0, p.y))
		if c != start and _set.has(c):
			return c
	return Vector2i.MAX


## Намерение для клиента: клетки луча, включён ли, мигает ли, сколько тактов до смены.
func intent() -> Dictionary:
	return {"cells": _cells, "on": is_on(), "blink": blinking(), "left": ticks_left()}
