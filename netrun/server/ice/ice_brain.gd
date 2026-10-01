class_name IceBrain
extends RefCounted
## Soft ICE: патруль → подозрение → поиск → выброс (docs/netrun.md, «Обнаружение и сигнал СБ»).
## Чистая логика: без физики и сцены. Время подаётся снаружи (секунды), шаг — IceNode, 10 раз в секунду.
## Видимость — функция позиций: расстояние и конус перед ICE (препятствия не учитываем).
## Добычу не трогаем: «выброшен» — только событие, предметы остаются в узле (решает вызывающий).

enum State { PATROL, SUSPICIOUS, SEARCH }

## ICE выбросил нетраннера: сессия и причина ("caught" — поймал вблизи, "flatline" — trace 100).
signal ejected(session: String, reason: String)
signal state_changed(old_state: int, new_state: int)

const DEFAULT_SETTINGS := {
	"sight_range": 12.0,  # м, дальше не видит
	"sight_half_angle_deg": 50.0,  # половина конуса
	"notice_per_sec": 0.5,  # рост осведомлённости на виду (1.0 = поиск)
	"forget_per_sec": 0.25,  # спад осведомлённости, если цель пропала
	"catch_range": 1.5,  # м: в поиске ближе этого — выброс
	"search_duration": 8.0,  # с поиска у последней точки, потом возврат на патруль
	"patrol_speed": 1.0,
	"chase_speed": 2.5,
	"waypoint_reach": 0.5,
	"trace_action": "seen_by_ice",  # действие trace, пока цель на виду (вес — в настройках TraceMeter)
}

var position := Vector3.ZERO
var facing := Vector3.FORWARD  ## единичный, в плоскости XZ

var _s: Dictionary
var _state: int = State.PATROL
var _awareness := 0.0
var _target := ""  # сессия, которую подозреваем/ищем
var _last_seen := Vector3.ZERO
var _search_until := 0.0
var _waypoints: Array[Vector3] = []
var _wp_index := 0
var _last_time := 0.0
var _has_time := false


func _init(settings: Dictionary = {}, start: Vector3 = Vector3.ZERO, waypoints: Array[Vector3] = []) -> void:
	_s = DEFAULT_SETTINGS.duplicate(true)
	_s.merge(settings, true)
	position = start
	_waypoints = waypoints


func state() -> int:
	return _state


func awareness() -> float:
	return _awareness


func target() -> String:
	return _target


func last_seen() -> Vector3:
	return _last_seen


## Видит ли ICE точку: в радиусе и в конусе (по плоскости XZ; высота не важна).
static func can_see(from: Vector3, facing_dir: Vector3, point: Vector3, sight_range: float, half_angle_deg: float) -> bool:
	var d := Vector2(point.x - from.x, point.z - from.z)
	var dist := d.length()
	if dist > sight_range:
		return false
	if dist < 0.0001:
		return true
	var f := Vector2(facing_dir.x, facing_dir.z)
	if f.length() < 0.0001:
		return false
	return absf(f.angle_to(d)) <= deg_to_rad(half_angle_deg)


## Один шаг мысли. targets: сессия → позиция (только нетраннеры узла), meters: сессия → TraceMeter (необязательно).
func step(now: float, targets: Dictionary, meters: Dictionary = {}) -> void:
	var dt := 0.0
	if _has_time:
		dt = maxf(now - _last_time, 0.0)
	_has_time = true
	_last_time = now

	var seen := _closest_visible(targets)
	if seen != "":
		_on_seen(seen, targets[seen], now, dt, meters)
		if _state != State.PATROL and _check_eject(now, seen, meters):
			return
	else:
		_on_unseen(now, dt, targets)
	_move(dt)


## Нетраннер ушёл (вышел, выброшен кем-то ещё): ICE забывает его.
func forget(session: String) -> void:
	if _target == session:
		_target = ""
		_awareness = 0.0
		_set_state(State.PATROL)


func _closest_visible(targets: Dictionary) -> String:
	var best := ""
	var best_d := INF
	for session in targets:
		var p: Vector3 = targets[session]
		if not can_see(position, facing, p, _s["sight_range"], _s["sight_half_angle_deg"]):
			continue
		var d := position.distance_to(p)
		if d < best_d:
			best_d = d
			best = session
	return best


func _on_seen(session: String, pos: Vector3, now: float, dt: float, meters: Dictionary) -> void:
	_target = session
	_last_seen = pos
	_awareness = minf(_awareness + float(_s["notice_per_sec"]) * dt, 1.0)
	if _state == State.PATROL:
		_set_state(State.SUSPICIOUS)
	if _state == State.SUSPICIOUS and _awareness >= 1.0:
		_search_until = now + float(_s["search_duration"])
		_set_state(State.SEARCH)
	elif _state == State.SEARCH:
		_search_until = now + float(_s["search_duration"])
	# Подозрение повышает trace: «секунды на виду» — count действия.
	var meter: TraceMeter = meters.get(session)
	if meter != null and dt > 0.0:
		meter.add_action(_s["trace_action"], now, dt)


func _on_unseen(now: float, dt: float, targets: Dictionary) -> void:
	if _target != "" and not targets.has(_target):
		forget(_target)
		return
	match _state:
		State.SUSPICIOUS:
			_awareness = maxf(_awareness - float(_s["forget_per_sec"]) * dt, 0.0)
			if _awareness <= 0.0:
				_target = ""
				_set_state(State.PATROL)
		State.SEARCH:
			if now >= _search_until and position.distance_to(_last_seen) <= float(_s["waypoint_reach"]) + 0.01:
				_reset_to_patrol()
			elif now >= _search_until + float(_s["search_duration"]):
				_reset_to_patrol()  # не дошли за двойное время — не зависаем


func _check_eject(_now: float, session: String, meters: Dictionary) -> bool:
	var meter: TraceMeter = meters.get(session)
	var flat := meter != null and meter.level() == TraceMeter.Level.FLATLINE
	var close := position.distance_to(_last_seen) <= float(_s["catch_range"])
	if _state == State.SEARCH and close:
		_eject(session, "caught")
		return true
	if flat:
		_eject(session, "flatline")
		return true
	return false


func _eject(session: String, reason: String) -> void:
	_reset_to_patrol()
	ejected.emit(session, reason)


func _reset_to_patrol() -> void:
	_target = ""
	_awareness = 0.0
	_set_state(State.PATROL)


func _set_state(s: int) -> void:
	if s == _state:
		return
	var old := _state
	_state = s
	state_changed.emit(old, s)


func _move(dt: float) -> void:
	if dt <= 0.0:
		return
	var goal: Vector3
	var speed: float
	match _state:
		State.PATROL:
			if _waypoints.is_empty():
				return
			goal = _waypoints[_wp_index]
			speed = _s["patrol_speed"]
			if position.distance_to(goal) <= float(_s["waypoint_reach"]):
				_wp_index = (_wp_index + 1) % _waypoints.size()
				return
		State.SEARCH:
			goal = _last_seen
			speed = _s["chase_speed"]
		_:
			# Подозрение: стоит и смотрит на цель.
			goal = _last_seen
			speed = 0.0
	var to := Vector3(goal.x - position.x, 0.0, goal.z - position.z)
	if to.length() < 0.0001:
		return
	facing = to.normalized()
	var step_len := minf(speed * dt, to.length())
	position += facing * step_len
