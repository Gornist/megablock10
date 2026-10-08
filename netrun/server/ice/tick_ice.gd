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
## Потолок осведомлённости у неуязвимого (грейс прибытия): «?» (Взгляд, 1–2) — ICE может повернуться к нему, но не Проверка и не Поиск.
const AWARENESS_IMMUNE_MAX := 2
## Сколько шагов вперёд показывает след маршрута (intent()["ahead"], state.rt): ближайший — стрелка, остальные — «отпечатки».
const AHEAD_STEPS := 3
const _EPS := 0.0001
const _GUARD := 64

var _grid: NodeGrid
var _s: Dictionary = {}
var _route: Array[Vector2i] = []
## Ожидание на точках маршрута (тактов; параллельно _route) и взгляд на время ожидания (dir8; ZERO — не менять направление).
var _waits: Array[int] = []
var _looks: Array[Vector2i] = []
## Сколько тактов ещё стоять на точке маршрута, куда только что пришёл.
var _wait_left := 0
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
## Неуязвимые нетраннеры этого такта (грейс прибытия, сессия → клетка; скрытые тоже): ICE не заходит в их клетку, не берёт их, счётчик ≤ AWARENESS_IMMUNE_MAX.
var _icells: Dictionary = {}
## Скрытые нетраннеры этого такта (Призрак, вход в узел; сессия → клетка), не неуязвимые: скрыты от взгляда, но не от касания — ICE не заходит в их клетку,
## упёршись, «?» и Проверка этой клетки (захвата нет); а вот прыжок самого нетраннера на клетку ICE берёт его всегда.
var _hcells: Dictionary = {}
## То же на следующий такт (сессия → клетка): по нему строится intent(), чтобы стрелка и шаг следующего такта не расходились.
var _icells_next: Dictionary = {}
## Как ICE видел нетраннеров в конце последнего такта: сессия → TickVision.NONE/PERIPHERY/FOCUS.
var _vis: Dictionary = {}
var _dry := false
## Отпечаток: клетка, где ICE заметил нетраннера (Проверка идёт к ней); lost — потерял его в этом такте (один такт).
var _fp := Vector2i.ZERO
var _fp_valid := false
var _lost := false
## «Наткнулся» этого такта (шаг патруля упёрся в клетку нетраннера): события {kind:"bump", session, cell}; tick() отдаёт их вызывающему.
var _bumped: Array = []


## route — точки маршрута: Vector2i или {cell: Vector2i, wait: int (тактов стоять на точке, по умолчанию 0), look: взгляд на время ожидания
## (Vector2i dir8 или имя "N"/"NE"/…/"NW"; по умолчанию не менять)}. Старый вызов с одними клетками работает как раньше.
func _init(settings: Dictionary, route: Array, grid: NodeGrid) -> void:
	_grid = grid
	_s = DEFAULTS.duplicate()
	for k in settings:
		_s[k] = settings[k]
	for p: Variant in route:
		if p is Dictionary:
			var pd: Dictionary = p
			_route.append(pd["cell"])
			_waits.append(maxi(int(pd.get("wait", 0)), 0))
			_looks.append(look_dir(pd.get("look", Vector2i.ZERO)))
		else:
			_route.append(p)
			_waits.append(0)
			_looks.append(Vector2i.ZERO)
	if _route.is_empty():
		_route.append(Vector2i.ZERO)
		_waits.append(0)
		_looks.append(Vector2i.ZERO)
	_cell = _route[0]
	if _route.size() > 1:
		_wp = 1
		_dir = NodeGrid.dir8(_route[0], _route[1])
	_build_route_set()


## Точки маршрута (Vector3, вершины клеток, как в NodeLayout.ICE) → клетки: юго-восточная от точки, как у игрока.
## Точка может быть и словарём {point: Vector3, wait, look} — тогда в маршруте будет {cell, wait, look} (формат конструктора).
static func route_from_points(points: Array) -> Array:
	var out: Array = []
	for p: Variant in points:
		if p is Dictionary:
			var pd: Dictionary = p.duplicate()
			var pt: Vector3 = pd["point"]
			pd.erase("point")
			pd["cell"] = NodeGrid.cell_of(pt)
			out.append(pd)
		else:
			out.append(NodeGrid.cell_of(p as Vector3))
	return out


## Направление взгляда: Vector2i (dir8) как есть; строка "N"/"NE"/"E"/"SE"/"S"/"SW"/"W"/"NW" (север — к −Z, как у карты); массив — по первому
## элементу; всё прочее (нет значения, неизвестное имя) — ZERO, «направление не менять».
static func look_dir(v: Variant) -> Vector2i:
	return NodeGrid.look_dir(v)


func cell() -> Vector2i:
	return _cell


func dir() -> Vector2i:
	return _dir


## 0 Патруль, 1 Взгляд, 2 Проверка, 3 Поиск (Mode).
func state() -> int:
	return _mode


func awareness_of(session: Variant) -> int:
	return int(_aw.get(session, 0))


## Был ли нетраннер виден ICE в конце последнего такта (фокус или периферия; скрытый — нет). Для trace «на виду».
func sees(session: Variant) -> bool:
	return int(_vis.get(session, TickVision.NONE)) != TickVision.NONE


## Наибольший счётчик осведомлённости 0..awareness_max.
func max_awareness() -> int:
	return _max_aw()


## Нетраннер ушёл из узла: счётчик и память о нём не нужны.
func forget(session: Variant) -> void:
	_aw.erase(session)
	_tcells.erase(session)
	_vis.erase(session)


## Один такт. targets: сессия → позиция (Vector3); hidden: сессия → true для невидимых (Призрак, вход в узел);
## immune: сессия → true для неуязвимых (грейс прибытия): ICE не заходит в клетку такого нетраннера («наткнулся» не бывает), не берёт его,
## а осведомлённость о нём не выше AWARENESS_IMMUNE_MAX.
## Возвращает события: {kind:"state", state, from}, {kind:"search_started", cell}, {kind:"capture", session, reason:"caught"}, {kind:"bump", session, cell}.
func tick(targets: Dictionary, hidden: Dictionary = {}, immune: Dictionary = {}) -> Array:
	var events: Array = []
	var tcell: Dictionary = {}
	_tcells.clear()
	_icells.clear()
	_hcells.clear()
	for s in targets:
		var c := NodeGrid.cell_of(targets[s])
		tcell[s] = c
		if not hidden.get(s, false):
			_tcells[s] = c
		elif not immune.get(s, false):
			_hcells[s] = c
		if immune.get(s, false):
			_icells[s] = c
	var prev_mode := _mode
	_lost = false
	_bumped.clear()
	var start_cell := _cell
	_program_step()
	events.append_array(_bumped)
	# Нетраннер сам прыгнул / встал в клетку ICE (П5; клетка ICE в начале такта — ICE за такт мог уйти — или в конце) — мгновенный выброс, всегда: и под
	# Призраком, и в грейсе (прыжок — ход игрока, грейс защищает только от ходов ICE). Без осведомлённости и красной стрелки: прикосновение, а не «ICE подошёл».
	# ICE сам в клетку нетраннера не заходит (видимого — bump: Поиск + красная стрелка + захват тактом позже; скрытого и в грейсе — см. _bump).
	var caught := {}
	for s in tcell:
		if not caught.has(s) and (tcell[s] == _cell or tcell[s] == start_cell):
			caught[s] = true
			events.append({"kind": "capture", "session": s, "reason": "caught"})
	_update_awareness(targets, tcell, hidden)
	var m := _level(_max_aw())
	_notice(prev_mode, m)
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
			if _icells.has(s) or caught.has(s):
				continue   # грейс прибытия: не берём; уже взят прикосновением
			if _flat_dist(NodeGrid.center(_tcells[s]), here) <= float(_s["capture_m"]) + _EPS:
				events.append({"kind": "capture", "session": s, "reason": "caught"})
	return events


## «?» с последствием (PR B3): что ICE делает с замеченным нетраннером в конце такта. prev — состояние до такта, m — после.
## (1) Заметил впервые (отпечатка нет): запоминает клетку, где увидел, — Проверка идёт к ней, а не к текущей клетке нетраннера.
## (2) Осведомлённость поднялась до Взгляда / Проверки из-за клетки нетраннера: взгляд в тот же такт поворачивается на неё (8 направлений).
## (3) В Поиске отпечаток — последняя клетка цели (Поиск за ней и ходит; когда спадёт до Проверки, идти надо туда, где её видели последний раз).
## (4) Осведомлённость спала до нуля, отпечаток отыгран — «потерял»: один такт стоит флаг lost, дальше обычный возврат на маршрут.
func _notice(prev: int, m: int) -> void:
	if m == Mode.PATROL:
		if prev != Mode.PATROL and _fp_valid:
			_lost = true
		_fp_valid = false
		return
	if _seen_now and not _fp_valid:
		_fp = _last_seen
		_fp_valid = true
	if _seen_now and m > prev and (m == Mode.GAZE or m == Mode.CHECK) and _last_seen != _cell:
		_dir = NodeGrid.dir8(_cell, _last_seen)
	if m == Mode.SEARCH and _fp_valid and _fp != _last_seen:
		_fp = _last_seen
		_arrived = false   # шёл к старому отпечатку, а не к последней клетке цели: осмотр там не засчитывается
		_phase = Phase.NONE
		_phase_left = 0


## Отпечаток (клетка, где ICE заметил нетраннера), пока он нужен Взгляду или Проверке; иначе null.
func footprint() -> Variant:
	if _fp_valid and (_mode == Mode.GAZE or _mode == Mode.CHECK):
		return _fp
	return null


## ICE только что потерял нетраннера (спал до нуля после замечания): истинно один такт.
func lost() -> bool:
	return _lost


## Кто будет неуязвим в следующем такте (сессия → позиция Vector3, где он стоит сейчас): по ним intent() считает шаг с обходом клетки.
func expect_immune(positions: Dictionary) -> void:
	_icells_next.clear()
	for s in positions:
		_icells_next[s] = NodeGrid.cell_of(positions[s])


## Чистая функция состояния: где ICE стоит и куда пойдёт следующим шагом программы при текущих счётчиках (без случайности).
## {cell, dir, state, next_cell, next_dir, aware, ahead, fp, lost}; fp — отпечаток (Vector2i) или null, lost — потерял в этом такте; state 0–3 — Патруль, Взгляд, Проверка, Поиск.
func intent() -> Dictionary:
	var snap := _snapshot()
	var icells_now := _icells
	_icells = _icells_next
	_dry = true
	_program_step()
	var res := {
		"cell": snap["cell"],
		"dir": snap["dir"],
		"state": _mode,
		"next_cell": _cell,
		"next_dir": _dir,
		"aware": _max_aw(),
		"fp": footprint(),
		"lost": _lost,
	}
	# След маршрута: те же шаги программы ещё раз и ещё (счётчики не меняются: состояние то же, что на первом шаге); клетка повторяется, пока ICE стоит.
	var ahead: Array[Vector2i] = [_cell]
	for _i in AHEAD_STEPS - 1:
		_program_step()
		ahead.append(_cell)
	res["ahead"] = ahead
	_dry = false
	_icells = icells_now
	_restore(snap)
	return res


# --- Осведомлённость ---

func _update_awareness(targets: Dictionary, tcell: Dictionary, hidden: Dictionary) -> void:
	var amax := int(_s["awareness_max"])
	var best := -1
	var best_cell := Vector2i.ZERO
	_vis.clear()
	for s in targets:
		var v := 0
		if not hidden.get(s, false):
			if tcell[s] == _cell:
				v = TickVision.FOCUS   # нетраннер вошёл в клетку ICE сам: «потерянным» он не становится
			else:
				v = TickVision.classify(_grid, _cell, _dir, tcell[s], float(_s["sight_cells"]), float(_s["half_angle_deg"]), float(_s["focus_deg"]))
		_vis[s] = v
		var delta := -1
		if v == TickVision.FOCUS:
			delta = 2
		elif v == TickVision.PERIPHERY:
			delta = 1
		var a := clampi(int(_aw.get(s, 0)) + delta, 0, amax)
		if _icells.has(s):
			a = mini(a, AWARENESS_IMMUNE_MAX)   # грейс прибытия: самое большее «?»
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
	if _wait_left > 0:
		_wait_left -= 1   # стоит на точке маршрута, глядя в look
		return
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
		var goal := _fp if _fp_valid else _last_seen   # Проверка идёт к отпечатку, а не за нетраннером
		if _walk_to(goal, int(_s["check_cells"])):
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
	for s in _icells:
		if _icells[s] == nxt:
			_dir = NodeGrid.dir8(_cell, nxt)
			return true
	for s in _tcells:
		if _tcells[s] == nxt:
			_dir = NodeGrid.dir8(_cell, nxt)
			return true
	for s in _hcells:
		if _hcells[s] == nxt:
			_dir = NodeGrid.dir8(_cell, nxt)
			return true
	return false


func _move(next: Vector2i, off_route: bool) -> void:
	var d := next - _cell
	_dir = Vector2i(signi(d.x), signi(d.y))
	_cell = next
	if off_route:
		_off_route = true
		_wait_left = 0   # ушёл за целью: недосиженное ожидание на точке не догоняет


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
				if p.is_empty() or _bump(p[0]):   # возврат на маршрут тоже не входит в клетку нетраннера
					return
				_move(p[0], false)
				left -= 1
				continue
		if _cell == _route[_wp]:
			if _arrive():
				return   # остаток шагов через ожидание не переносится
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
		_arrive()


## Пришёл на точку маршрута: следующей целью становится следующая точка; если на этой точке надо ждать — встать, развернуться в look.
## true — ждать (шаги этого такта кончились).
func _arrive() -> bool:
	var i := _wp
	_wp = (_wp + 1) % _route.size()
	if _waits[i] <= 0:
		return false
	_wait_left = _waits[i]
	if _looks[i] != Vector2i.ZERO:
		_dir = _looks[i]
	return true


## Шаг патруля привёл бы в клетку нетраннера: ICE останавливается, счётчик этого нетраннера сразу максимум.
func _bump(nxt: Vector2i) -> bool:
	for s in _icells:
		if _icells[s] == nxt:
			return true   # грейс прибытия: ICE просто не заходит в клетку, счётчик не взлетает
	for s in _tcells:
		if _tcells[s] == nxt:
			_dir = NodeGrid.dir8(_cell, nxt)   # встаёт перед нетраннером лицом к нему: он в фокусе, рамка прицела на его клетке красная
			if not _dry:
				_aw[s] = int(_s["awareness_max"])
				_has_seen = true
				_note_seen(nxt)
				_bumped.append({"kind": "bump", "session": s, "cell": nxt})
			return true
	for s in _hcells:
		if _hcells[s] == nxt:
			# Скрытый (Призрак, вход в узел): взгляд его не видит, но коснуться ICE может — в клетку не заходит, «?» и Проверка этой клетки, захвата нет.
			# Счётчик 4 до убывания в _update_awareness (скрытый v = 0, −1) даёт 3 — Проверка; Призрак с игрока не снимается.
			_dir = NodeGrid.dir8(_cell, nxt)
			if not _dry:
				_aw[s] = maxi(int(_aw.get(s, 0)), 4)
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
		"off_route": _off_route, "search_armed": _search_armed, "wait_left": _wait_left,
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
	_wait_left = snap["wait_left"]
