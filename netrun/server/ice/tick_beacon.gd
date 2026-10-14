class_name TickBeacon
extends RefCounted
## Маяк (Soft ICE, docs/gamedesign/ice.md §5, levels.md §4.2): стоит на клетке-тумбе и поворачивается на `step_deg` градусов каждый такт
## (45° — оборот за 8 тактов) или качается в секторе. Видит только фокус (±25°) на 5 клеток (+1 на тревоге узла 2+) по общей функции зрения
## (TickVision: укрытия и колонны закрывают). Не ходит и не захватывает: счётчик осведомлённости — как у Стража (фокус +2, иначе −1), на уровне
## «Поиск» шлёт событие search_started (trace и тревога узла — на узле). Чистая логика без сцены и сети: тик на такт, намерение — следующий угол.

const DEFAULTS := {
	"sight_cells": 5.0,
	"focus_deg": 25.0,
	"step_deg": 45.0,
	"awareness_max": 6,
	"sweep_steps": 0,   # 0 — полный оборот; n > 0 — качание на n шагов в каждую сторону от начального угла
}
## 8 направлений по часовой от севера (−z), шаг 45°.
const DIRS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]
## Как у Стража: неуязвимый (грейс прибытия) набирает самое большее «?».
const IMMUNE_MAX := 2

var _grid: NodeGrid
var _s: Dictionary
var _cell: Vector2i
var _start := 0       # индекс направления в DIRS в начале
var _idx := 0
var _swing := 1       # +1 / −1: сторона качания
var _offset := 0      # смещение от начала при качании (шагов)
var _aw: Dictionary = {}
var _search_armed := true
var _sight_bonus := 0.0
var _vis: Dictionary = {}


func _init(cell: Vector2i, start_dir: Vector2i, grid: NodeGrid, settings: Dictionary = {}) -> void:
	_cell = cell
	# Тумба (блок 2×2 карты) не загораживает сама себе взгляд: свой блок в копии сетки свободен (иначе из его угла видно лишь в сторону наружу).
	_grid = NodeGrid.new()
	_grid.occ = grid.occ.duplicate()
	_grid.landing = grid.landing
	var bx := cell.x - posmod(cell.x, 2)
	var by := cell.y - posmod(cell.y, 2)
	for dx in 2:
		for dy in 2:
			_grid.occ.erase(Vector2i(bx + dx, by + dy))
	_s = DEFAULTS.duplicate()
	_s.merge(settings, true)
	_start = maxi(DIRS.find(start_dir), 0)
	_idx = _start


func cell() -> Vector2i:
	return _cell


func dir() -> Vector2i:
	return DIRS[_idx]


## Шагов поворота за такт (45° → 1, 90° → 2; не меньше 1).
func _steps() -> int:
	return maxi(roundi(float(_s["step_deg"]) / 45.0), 1)


## Угол после следующего тика (намерение для клиента: поворот головы маяка за такт).
func next_dir() -> Vector2i:
	return DIRS[_advanced(_idx, _offset, _swing)["idx"]]


func _advanced(idx: int, offset: int, swing: int) -> Dictionary:
	var n := int(_s["sweep_steps"])
	var step := _steps()
	if n <= 0:
		return {"idx": posmod(idx + step, DIRS.size()), "offset": 0, "swing": swing}
	# качание: идём в сторону swing до ±n шагов от начала, у края разворачиваемся
	var target := offset + swing * step
	if absi(target) > n:
		swing = -swing
		target = offset + swing * step
	return {"idx": posmod(_start + target, DIRS.size()), "offset": target, "swing": swing}


## Прибавка к дальности зрения, клеток (тревога узла 2+ — 1).
func set_sight_bonus(cells: float) -> void:
	_sight_bonus = maxf(cells, 0.0)


## Дальность зрения сейчас, клеток.
func sight_cells() -> float:
	return float(_s["sight_cells"]) + _sight_bonus


## Один такт: поворот, затем осведомлённость по тем, кто виден. targets — сессия → позиция Vector3; hidden — сессия → true (GHOST, скрытый
## вход); immune — сессия → true (грейс прибытия); suspicious — сессия → true (trace ≥ SUSPICIOUS: «+1 к счётчику», ice.md §3).
## События: {"kind": "search_started", "session": <у кого наибольший счётчик>}.
func tick(targets: Dictionary, hidden: Dictionary = {}, immune: Dictionary = {}, suspicious: Dictionary = {}) -> Array:
	var step := _advanced(_idx, _offset, _swing)
	_idx = int(step["idx"])
	_offset = int(step["offset"])
	_swing = int(step["swing"])
	var amax := int(_s["awareness_max"])
	var best_session := ""
	var best := -1
	_vis.clear()
	for s in targets:
		var v := 0
		if not hidden.get(s, false):
			var tc := NodeGrid.cell_of(targets[s])
			# только фокус: половина угла зрения равна фокусу, периферии нет
			v = TickVision.classify(_grid, _cell, DIRS[_idx], tc, sight_cells(), float(_s["focus_deg"]), float(_s["focus_deg"]))
		_vis[s] = v
		var delta := -1
		if v == TickVision.FOCUS:
			delta = 2 + (1 if suspicious.get(s, false) else 0)
		var a := clampi(int(_aw.get(s, 0)) + delta, 0, amax)
		if immune.get(s, false):
			a = mini(a, IMMUNE_MAX)
		_aw[s] = a
		if v != TickVision.NONE and a > best:
			best = a
			best_session = str(s)
	for s in _aw.keys():
		if not targets.has(s):
			var a := maxi(int(_aw[s]) - 1, 0)
			if a == 0:
				_aw.erase(s)
			else:
				_aw[s] = a
	var events: Array = []
	var level := TickIce._level(_max_aw())
	if level == TickIce.Mode.SEARCH and _search_armed:
		_search_armed = false
		events.append({"kind": "search_started", "session": best_session})
	elif level == TickIce.Mode.PATROL:
		_search_armed = true
	return events


func _max_aw() -> int:
	var m := 0
	for s in _aw:
		m = maxi(m, int(_aw[s]))
	return m


## Видит ли маяк нетраннера в конце последнего такта.
func sees(session: Variant) -> bool:
	return int(_vis.get(session, TickVision.NONE)) != TickVision.NONE


func awareness_of(session: Variant) -> int:
	return int(_aw.get(session, 0))


## Намерение для клиента: клетка, текущий и следующий угол, наибольший счётчик, дальность.
func intent() -> Dictionary:
	return {"cell": _cell, "dir": DIRS[_idx], "next_dir": next_dir(), "aware": _max_aw(), "range": sight_cells()}
