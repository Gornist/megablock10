class_name TickBlack
extends RefCounted
## Black ICE по тактам (docs/gamedesign/ice.md §6.1): сон в логове → пробуждение 6 тактов → охота (пинг раз в 3 такта, шаг 2 клетки 1 м = 1 клетка
## карты) → захват (+1 ожог за такт) → флэтлайн на 3-м ожоге; разрыв прыжком; потеря следа после 2 пингов мимо → в логово, «чуткий сон».
## Чистая логика без сцены и сети: такт — tick(), ход игрока между тактами — on_hop(). Клетки — 1 м (NodeGrid); числа §6.1 даны в клетках карты
## по 2 м, здесь пересчитаны (Чебышёв ≤ 2 клетки 1 м = «в клетке цели или соседней»). Журнал по тактам — journal() (карточка флэтлайна).

enum Phase { SLEEP, WAKING, HUNT, RETURNING }

const DEFAULTS := {
	"wake_trace": 50.0,          # trace нетраннера узла, при котором ICE просыпается (глубокий сон)
	"wake_light_trace_step": 10.0,  # чуткий сон: будит каждые новые +10 trace к уровню на момент возврата в логово
	"wake_ticks": 6,
	"wake_light_ticks": 3,       # пробуждение из чуткого сна
	"wake_alarm_level": 3,       # тревога узла, будящая ICE
	"adjacent_cells": 2,         # «рядом с логовом»: Чебышёв до ближайшей клетки логова не больше (1 клетка карты)
	"adjacent_ticks": 2,         # столько тактов подряд рядом — будит
	"ping_ticks": 3,
	"lost_pings": 2,             # столько пингов подряд мимо — потеря следа
	"step_cells": 2,             # клеток 1 м за такт (1 клетка карты)
	"capture_cells": 2,          # захват: конец такта не дальше (Чебышёв), клеток 1 м
	"burns_to_flatline": 3,
	"break_cells": 2,            # разрыв: после прыжка дальше этого от ICE — он стоит 1 такт
	"journal_max": 120,
}

var phase: int = Phase.SLEEP
var burns: Dictionary = {}       # сессия → ожоги за забег; ссылка делится с владельцем забега (граф миров)

var _s: Dictionary
var _grid: NodeGrid
var _lair: Array[Vector2i] = []
var _home: Vector2i
var _cell: Vector2i
var _t := 0
var _wake_left := 0
var _light := false              # «чуткий сон» после потери следа
var _ref_trace := 0.0            # trace на момент возврата в логово (чуткий сон будит при +wake_light_trace_step)
var _since_ping := 0
var _misses := 0
var _known := Vector2i.ZERO      # последняя засечённая клетка цели
var _has_known := false
var _target := ""
var _stun := 0
var _captured: Dictionary = {}   # сессия → true: взята на прошлом такте (разрыв прыжком снимает)
var _near: Dictionary = {}       # сессия → тактов подряд рядом с логовом
var _master := false
var _journal: Array = []
var _last_wake_reason := ""


## lair — клетки логова (занятые на сетке узла), home — клетка, в которой ICE спит и откуда выходит.
func _init(lair: Array[Vector2i], home: Vector2i, grid: NodeGrid, settings: Dictionary = {}, shared_burns: Dictionary = {}) -> void:
	_s = DEFAULTS.duplicate()
	_s.merge(settings, true)
	_lair = lair.duplicate()
	_home = home
	_cell = home
	burns = shared_burns
	# Логово занято на карте, но ICE спит и выходит из него: в копии сетки его клетки свободны.
	_grid = NodeGrid.new()
	_grid.occ = grid.occ.duplicate()
	_grid.landing = grid.landing
	for c in _lair:
		_grid.occ.erase(c)


func cell() -> Vector2i:
	return _cell


func is_hunting() -> bool:
	return phase == Phase.HUNT


func wake_left() -> int:
	return _wake_left


## Тактов до следующего пинга (0 — пинг на ближайшем такте охоты); −1 вне охоты.
func ping_in() -> int:
	if phase != Phase.HUNT:
		return -1
	return maxi(int(_s["ping_ticks"]) - _since_ping, 0)


func target() -> String:
	return _target


func known_cell() -> Variant:
	return _known if _has_known else null


func journal() -> Array:
	return _journal


func burns_of(session: String) -> int:
	return int(burns.get(session, 0))


func lair_cells() -> Array[Vector2i]:
	return _lair


## Мастер будит ICE (решение мастера, ice.md §6.1): сработает на ближайшем такте сна.
func wake_by_master() -> void:
	_master = true


func _log(ev: String, extra: Dictionary = {}) -> void:
	var e := {"t": _t, "ev": ev}
	e.merge(extra)
	_journal.append(e)
	if _journal.size() > int(_s["journal_max"]):
		_journal.pop_front()


## Ход игрока (между тактами, сразу после телепорта): разрыв захвата прыжком дальше break_cells.
func on_hop(session: String, to: Vector2i) -> void:
	_log("hop", {"s": session, "c": [to.x, to.y]})
	if phase == Phase.HUNT and _captured.has(session) and _cheb(to, _cell) > int(_s["break_cells"]):
		_captured.erase(session)
		_stun = 1
		_log("break", {"s": session})


static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _lair_dist(c: Vector2i) -> int:
	var best := 999
	for l in _lair:
		best = mini(best, _cheb(c, l))
	return best


## Нетраннер вышел или выброшен: ICE забывает цель, а взятый им не держит.
func forget(session: String) -> void:
	_captured.erase(session)
	_near.erase(session)
	if _target == session:
		_target = ""


## Один такт. ctx: targets {сессия → Vector2i}, hidden {сессия → true} (Призрак, скрытые такты: пинг мимо), traces {сессия → float},
## alarm_level int. События: {kind: wake|wake_step|hunt|ping|capture|break|lost|sleep|flatline, ...}; flatline несёт session и journal.
func tick(ctx: Dictionary) -> Array:
	_t += 1
	var events: Array = []
	var targets: Dictionary = ctx.get("targets", {})
	var hidden: Dictionary = ctx.get("hidden", {})
	var traces: Dictionary = ctx.get("traces", {})
	var alarm := int(ctx.get("alarm_level", 0))
	for s in _near.keys():
		if not targets.has(s):
			_near.erase(s)
	match phase:
		Phase.SLEEP:
			_tick_sleep(targets, traces, alarm, events)
		Phase.WAKING:
			_wake_left -= 1
			if _wake_left > 0:
				_log("wake_step", {"left": _wake_left})
				events.append({"kind": "wake_step", "left": _wake_left})
			else:
				phase = Phase.HUNT
				_since_ping = int(_s["ping_ticks"])   # первый пинг — сразу на первом такте охоты
				_misses = 0
				_log("hunt")
				events.append({"kind": "hunt"})
				_tick_hunt(targets, hidden, traces, events)
		Phase.HUNT:
			_tick_hunt(targets, hidden, traces, events)
		Phase.RETURNING:
			_step_toward(_home)
			if _cell == _home:
				phase = Phase.SLEEP
				_light = true
				_ref_trace = _max_trace(traces)
				_log("sleep", {"light": true})
				events.append({"kind": "sleep"})
	return events


func _max_trace(traces: Dictionary) -> float:
	var m := 0.0
	for s in traces:
		m = maxf(m, float(traces[s]))
	return m


func _tick_sleep(targets: Dictionary, traces: Dictionary, alarm: int, events: Array) -> void:
	var reason := ""
	if _master:
		reason = "master"
	elif alarm >= int(_s["wake_alarm_level"]):
		reason = "alarm"
	else:
		var threshold := float(_s["wake_trace"])
		if _light:
			threshold = _ref_trace + float(_s["wake_light_trace_step"])
		if _max_trace(traces) >= threshold:
			reason = "trace"
	if reason == "":
		for s in targets:
			if _lair_dist(targets[s]) <= int(_s["adjacent_cells"]):
				_near[s] = int(_near.get(s, 0)) + 1
				if int(_near[s]) >= int(_s["adjacent_ticks"]):
					reason = "near"
			else:
				_near[s] = 0
	if reason == "":
		return
	_master = false
	_near.clear()
	phase = Phase.WAKING
	_wake_left = int(_s["wake_light_ticks"]) if _light else int(_s["wake_ticks"])
	_last_wake_reason = reason
	_log("wake", {"why": reason, "ticks": _wake_left, "light": _light})
	events.append({"kind": "wake", "why": reason, "ticks": _wake_left})


func _tick_hunt(targets: Dictionary, hidden: Dictionary, traces: Dictionary, events: Array) -> void:
	if targets.is_empty():
		_to_return(events, "empty")
		return
	if _stun > 0:
		_stun -= 1
		return
	# цель — нетраннер с наибольшим trace (при равенстве — по имени сессии: детерминированно)
	var best := ""
	var bv := -1.0
	for s in targets:
		var v := float(traces.get(s, 0.0))
		if v > bv or (v == bv and str(s) < best):
			bv = v
			best = str(s)
	_target = best
	_since_ping += 1
	if _since_ping >= int(_s["ping_ticks"]):
		_since_ping = 0
		if hidden.get(best, false):
			_misses += 1
			_log("ping", {"s": best, "hit": false})
			events.append({"kind": "ping", "session": best, "hit": false})
			if _misses >= int(_s["lost_pings"]):
				_to_return(events, "lost")
				return
		else:
			_misses = 0
			_known = targets[best]
			_has_known = true
			_log("ping", {"s": best, "hit": true, "c": [_known.x, _known.y]})
			events.append({"kind": "ping", "session": best, "hit": true, "cell": _known})
	if _has_known:
		_step_toward(_known)
	for s in targets:
		var c: Vector2i = targets[s]
		if _cheb(c, _cell) <= int(_s["capture_cells"]):
			burns[s] = int(burns.get(s, 0)) + 1
			_captured[s] = true
			_log("capture", {"s": s, "burns": burns[s]})
			events.append({"kind": "capture", "session": s, "burns": burns[s]})
			if int(burns[s]) >= int(_s["burns_to_flatline"]):
				_log("flatline", {"s": s})
				events.append({"kind": "flatline", "session": s, "journal": _journal.duplicate(true)})
				return
		else:
			_captured.erase(s)


func _to_return(events: Array, why: String) -> void:
	phase = Phase.RETURNING
	_has_known = false
	_target = ""
	_captured.clear()
	_log("lost", {"why": why})
	events.append({"kind": "lost", "why": why})


func _step_toward(goal: Vector2i) -> void:
	var path := _grid.path(_cell, goal)
	var n := mini(int(_s["step_cells"]), path.size())
	if n > 0:
		_cell = path[n - 1]
