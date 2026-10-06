class_name TickIce
extends RefCounted
## Тактовый мозг ICE на клетках (docs/gamedesign/ice.md, 1–2, 9): зрение, осведомлённость 0–6, состояния Патруль / Взгляд / Проверка / Поиск,
## шаги за такт и «намерение» на следующий такт. Чистая логика: без сцены, сети и часов — такты подаёт вызывающий (tick), случайности нет.
##
## Порядок такта: (1) шаг программы по состоянию, определённому в конце прошлого такта; (2) видимость и осведомлённость по новой
## позиции; (3) состояние по наибольшему счётчику; (4) события. Позиция ICE — центр клетки, направление — одно из 8.

enum Mode { PATROL, GAZE, CHECK, SEARCH }
enum Phase { NONE, LOOK, SWEEP }

const DEFAULTS := {
	"sight_cells": 6.0,
	"half_angle_deg": 50.0,
	"focus_deg": 25.0,
	"patrol_cells": 2,
	"check_cells": 2,
	"search_cells": 4,
	"check_look_ticks": 2,
	"search_ticks": 4,
	"capture_m": 2.0,
	"awareness_max": 6,
}
const _EPS := 0.0001
const _GUARD := 64

var _grid: NodeGrid
var _s: Dictionary = {}
var _route: Array[Vector2i] = []
## Клетки маршрута (цепочки между точками, по кругу) → индекс точки, к которой по ним идут. Для возврата на маршрут.
var _route_set: Dictionary = {}

var _cell := Vector2i.ZERO
var _dir := Vector2i(1, 0)
## Индекс точки маршрута, к которой идёт патруль.
var _wp := 0
var _mode: int = Mode.PATROL
## Осведомлённость: сессия → 0..awareness_max.
var _aw: Dictionary = {}
var _last_seen := Vector2i.ZERO
var _has_seen := false
## Видел ли кого-то в конце прошлого такта (Взгляд поворачивается к последней клетке, только если цель потеряна).
var _seen_now := false
## Дошёл до последней клетки; осмотр / прочёсывание идут по _phase.
var _arrived := false
var _phase: int = Phase.NONE
var _phase_left := 0
var _sweep_i := 0
## Сошёл с маршрута (шёл за целью): прежде чем патрулировать, надо вернуться на ближайшую клетку маршрута.
var _off_route := false
## search_started один раз за Поиск: взводится заново, когда все счётчики упали в 0.
var _search_armed := true
## Нескрытые нетраннеры прошлого такта (сессия → клетка): по ним patrol «наталкивается», и по ним же строит намерение intent().
var _tcells: Dictionary = {}
var _dry := false


func _init(settings: Dictionary, route: Array[Vector2i], grid: NodeGrid) -> void:
	_grid = grid
	_s = DEFAULTS.duplicate()
	for k in settings:
		_s[k] = settings[k]
	_route.assign(route)
	if _route.is_empty():
		_route.append(Vector2i.ZERO)
	_cell = _route[0]
	if _route.size() > 1:
		_wp = 1
		_dir = NodeGrid.dir8(_route[0], _route[1])
	_build_route_set()


## Точки маршрута (Vector3, вершины клеток, как в NodeLayout.ICE) → клетки: юго-восточная от точки, как у игрока.
static func route_from_points(points: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p: Vector3 in points:
		out.append(NodeGrid.cell_of(p))
	return out


func cell() -> Vector2i:
	return _cell


func dir() -> Vector2i:
	return _dir


## 0 Патруль, 1 Взгляд, 2 Проверка, 3 Поиск (Mode).
func state() -> int:
	return _mode


func awareness_of(session: Variant) -> int:
	return int(_aw.get(session, 0))


## Нетраннер ушёл из узла: счётчик и память о нём не нужны.
func forget(session: Variant) -> void:
	_aw.erase(session)
	_tcells.erase(session)


## Один такт. targets: сессия → позиция (Vector3); hidden: сессия → true для невидимых (Призрак, вход в узел).
## Возвращает события: {kind:"state", state, from}, {kind:"search_started", cell}, {kind:"capture", session, reason:"caught"}.
func tick(targets: Dictionary, hidden: Dictionary = {}) -> Array:
	var events: Array = []
	var tcell: Dictionary = {}
	_tcells.clear()
	for s in targets:
		var c := NodeGrid.cell_of(targets[s])
		tcell[s] = c
		if not hidden.get(s, false):
			_tcells[s] = c
	var prev_mode := _mode
	_program_step()
	_update_awareness(targets, tcell, hidden)
	var m := _level(_max_aw())
	if m == Mode.PATROL:
		_search_armed = true
	if m != _mode:
		events.append({"kind": "state", "state": m, "from": _mode})
	_mode = m
	if m == Mode.SEARCH and _search_armed:
		_search_armed = false
		events.append({"kind": "search_started", "cell": _last_seen})
	# Захват: целый такт в Поиске (в начале и в конце) и нетраннер не дальше capture_m.
	if prev_mode == Mode.SEARCH and m == Mode.SEARCH:
		var here := NodeGrid.center(_cell)
		for s in _tcells:
			if _flat_dist(NodeGrid.center(_tcells[s]), here) <= float(_s["capture_m"]) + _EPS:
				events.append({"kind": "capture", "session": s, "reason": "caught"})
	return events


## Чистая функция состояния: где ICE стоит и куда пойдёт следующим шагом программы при текущих счётчиках (без случайности).
## {cell, dir, state, next_cell, next_dir, aware}; state 0–3 — Патруль, Взгляд, Проверка, Поиск.
func intent() -> Dictionary:
	var snap := _snapshot()
	_dry = true
	_program_step()
	_dry = false
	var res := {
		"cell": snap["cell"],
		"dir": snap["dir"],
		"state": _mode,
		"next_cell": _cell,
		"next_dir": _dir,
		"aware": _max_aw(),
	}
	_restore(snap)
	return res


# --- Осведомлённость ---

func _update_awareness(targets: Dictionary, tcell: Dictionary, hidden: Dictionary) -> void:
	var amax := int(_s["awareness_max"])
	var best := -1
	var best_cell := Vector2i.ZERO
	for s in targets:
		var v := 0
		if not hidden.get(s, false):
			if tcell[s] == _cell:
				v = TickVision.FOCUS   # нетраннер вошёл в клетку ICE сам: «потерянным» он не становится
			else:
				v = TickVision.classify(_grid, _cell, _dir, tcell[s], float(_s["sight_cells"]), float(_s["half_angle_deg"]), float(_s["focus_deg"]))
		var delta := -1
		if v == TickVision.FOCUS:
			delta = 2
		elif v == TickVision.PERIPHERY:
			delta = 1
		var a := clampi(int(_aw.get(s, 0)) + delta, 0, amax)
		_aw[s] = a
		if v != TickVision.NONE and a > best:
			best = a
			best_cell = tcell[s]
	for s in _aw.keys():
		if not targets.has(s):
			var a := maxi(int(_aw[s]) - 1, 0)
			if a == 0:
				_aw.erase(s)
			else:
				_aw[s] = a
	_seen_now = best >= 0
	if _seen_now:
		_note_seen(best_cell)


func _note_seen(c: Vector2i) -> void:
	if not _has_seen or c != _last_seen:
		_last_seen = c
		_arrived = false
		_phase = Phase.NONE
		_phase_left = 0
	_has_seen = true


func _max_aw() -> int:
	var m := 0
	for s in _aw:
		m = maxi(m, int(_aw[s]))
	return m


## Состояние по наибольшему счётчику: 0 Патруль; 1–2 Взгляд; 3–4 Проверка; 5–6 Поиск.
static func _level(aw: int) -> int:
	if aw <= 0:
		return Mode.PATROL
	if aw <= 2:
		return Mode.GAZE
	if aw <= 4:
		return Mode.CHECK
	return Mode.SEARCH


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- Шаг программы ---

func _program_step() -> void:
	match _mode:
		Mode.PATROL:
			_step_patrol()
		Mode.GAZE:
			_step_gaze()
		Mode.CHECK:
			_step_check()
		Mode.SEARCH:
			_step_search()


func _step_patrol() -> void:
	if _arrived and _phase_left > 0:
		_phase_tick()   # досматривает начатый осмотр / прочёсывание, даже если счётчик уже 0
		return
	_arrived = false
	_phase = Phase.NONE
	_phase_left = 0
	_has_seen = false
	_patrol_walk(int(_s["patrol_cells"]))


## Взгляд: стоит; если цель потеряна — поворачивается к последней клетке, где её видел.
func _step_gaze() -> void:
	_phase = Phase.NONE
	_phase_left = 0
	if _has_seen and not _seen_now and _last_seen != _cell:
		_dir = NodeGrid.dir8(_cell, _last_seen)


func _step_check() -> void:
	if not _has_seen:
		return
	if not _arrived:
		if _walk_to(_last_seen, int(_s["check_cells"])):
			_arrived = true
			_start_phase(Phase.LOOK)   # осмотр — со следующего такта
		return
	if _phase_left > 0:
		_phase_tick()


func _step_search() -> void:
	if not _has_seen:
		return
	if not _arrived:
		if _walk_to(_last_seen, int(_s["search_cells"])):
			_arrived = true
			_start_phase(Phase.SWEEP)
		return
	if _phase != Phase.SWEEP:
		_start_phase(Phase.SWEEP)
	if _phase_left > 0:
		_phase_tick()


func _start_phase(kind: int) -> void:
	_phase = kind
	_phase_left = int(_s["check_look_ticks"]) if kind == Phase.LOOK else int(_s["search_ticks"])
	_sweep_i = 0


## Такт осмотра (поворот на 90°) или прочёсывания (одна соседняя клетка по кругу).
func _phase_tick() -> void:
	if _phase == Phase.LOOK:
		_dir = _rotated(_dir, 2)
	elif _phase == Phase.SWEEP:
		var ring: Array[Vector2i] = []
		for d: Vector2i in NodeGrid.DIRS8:
			if not _grid.is_occupied(_last_seen + d):
				ring.append(_last_seen + d)
		if not ring.is_empty():
			var tgt := ring[_sweep_i % ring.size()]
			if _cell == tgt:
				_sweep_i += 1
				tgt = ring[_sweep_i % ring.size()]
			var p := _grid.path(_cell, tgt)
			if not p.is_empty() and not _runner_blocks(p[0]):
				_move(p[0], true)
			if _cell == tgt:
				_sweep_i += 1
	_phase_left -= 1


## До `steps` клеток по кратчайшему пути к `goal`. true — дошёл (или ближе не подойти: цель занята / недостижима).
func _walk_to(goal: Vector2i, steps: int) -> bool:
	for _i in steps:
		if _cell == goal:
			return true
		var p := _grid.path(_cell, goal)
		if p.is_empty():
			return true
		if _runner_blocks(p[0]):
			return true   # встал перед нетраннером: цель рядом и в фокусе
		_move(p[0], true)
	return _cell == goal


## В Проверке и Поиске ICE не заходит в клетку нетраннера (как и в Патруле): шаг в неё не делается, ICE поворачивается к ней лицом.
func _runner_blocks(nxt: Vector2i) -> bool:
	for s in _tcells:
		if _tcells[s] == nxt:
			_dir = NodeGrid.dir8(_cell, nxt)
			return true
	return false


func _move(next: Vector2i, off_route: bool) -> void:
	var d := next - _cell
	_dir = Vector2i(signi(d.x), signi(d.y))
	_cell = next
	if off_route:
		_off_route = true


## Патруль по маршруту: по прямой между точками, остаток шагов на углах переносится; сошёл с маршрута — сначала возврат.
func _patrol_walk(steps: int) -> void:
	if _route.size() < 2:
		return
	var left := steps
	var guard := 0
	while left > 0 and guard < _GUARD:
		guard += 1
		if _off_route:
			if _route_set.has(_cell):
				_wp = int(_route_set[_cell])
				_off_route = false
			else:
				var tgt := _nearest_route_cell()
				var p := _grid.path(_cell, tgt)
				if p.is_empty():
					return
				_move(p[0], false)
				left -= 1
				continue
		if _cell == _route[_wp]:
			_wp = (_wp + 1) % _route.size()
			continue
		var step := _greedy_step(_cell, _route[_wp])
		if step == Vector2i.ZERO:
			return
		var nxt := _cell + step
		if _bump(nxt):
			return
		_move(nxt, false)
		left -= 1
	if not _off_route and _cell == _route[_wp]:
		_wp = (_wp + 1) % _route.size()


## Шаг патруля привёл бы в клетку нетраннера: ICE останавливается, счётчик этого нетраннера сразу максимум.
func _bump(nxt: Vector2i) -> bool:
	for s in _tcells:
		if _tcells[s] == nxt:
			if not _dry:
				_aw[s] = int(_s["awareness_max"])
				_has_seen = true
				_note_seen(nxt)
			return true
	return false


## Шаг к точке по прямой: по большей оси, плюс по меньшей, когда она не меньше половины большей (диагональ при равных). Закрыто — по пути.
func _greedy_step(c: Vector2i, goal: Vector2i) -> Vector2i:
	var d := goal - c
	if d == Vector2i.ZERO:
		return Vector2i.ZERO
	var ax := absi(d.x)
	var ay := absi(d.y)
	var step: Vector2i
	if ax >= ay:
		step = Vector2i(signi(d.x), signi(d.y) if ay * 2 >= ax else 0)
	else:
		step = Vector2i(signi(d.x) if ax * 2 >= ay else 0, signi(d.y))
	if _grid.can_step(c, step):
		return step
	var p := _grid.path(c, goal)
	if p.is_empty():
		return Vector2i.ZERO
	return p[0] - c


## Ближайшая достижимая клетка маршрута (по прямой; равные — в порядке построения маршрута).
func _nearest_route_cell() -> Vector2i:
	var best := _cell
	var best_d := INF
	for c: Vector2i in _route_set:
		var d := Vector2(c - _cell).length()
		if d < best_d - _EPS and not _grid.path(_cell, c).is_empty():
			best_d = d
			best = c
	return best


func _build_route_set() -> void:
	_route_set.clear()
	var n := _route.size()
	if n < 2:
		_route_set[_route[0]] = 0
		return
	for i in n:
		var goal_i := (i + 1) % n
		var c := _route[i]
		var guard := 0
		while guard < 400:
			guard += 1
			if not _route_set.has(c):
				_route_set[c] = goal_i
			if c == _route[goal_i]:
				break
			var step := _greedy_step(c, _route[goal_i])
			if step == Vector2i.ZERO:
				break
			c += step


static func _rotated(d: Vector2i, k: int) -> Vector2i:
	var i := NodeGrid.DIRS8.find(d)
	if i < 0:
		return d
	return NodeGrid.DIRS8[(i + k) % 8]


# --- Снимок для intent() ---

func _snapshot() -> Dictionary:
	return {
		"cell": _cell, "dir": _dir, "wp": _wp, "mode": _mode, "aw": _aw.duplicate(), "last_seen": _last_seen, "has_seen": _has_seen,
		"seen_now": _seen_now, "arrived": _arrived, "phase": _phase, "phase_left": _phase_left, "sweep_i": _sweep_i,
		"off_route": _off_route, "search_armed": _search_armed,
	}


func _restore(snap: Dictionary) -> void:
	_cell = snap["cell"]
	_dir = snap["dir"]
	_wp = snap["wp"]
	_mode = snap["mode"]
	_aw = snap["aw"]
	_last_seen = snap["last_seen"]
	_has_seen = snap["has_seen"]
	_seen_now = snap["seen_now"]
	_arrived = snap["arrived"]
	_phase = snap["phase"]
	_phase_left = snap["phase_left"]
	_sweep_i = snap["sweep_i"]
	_off_route = snap["off_route"]
	_search_armed = snap["search_armed"]
