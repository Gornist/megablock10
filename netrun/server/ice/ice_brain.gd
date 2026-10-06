class_name IceBrain
extends RefCounted
## Soft ICE: патруль → подозрение → поиск → выброс (docs/netrun.md, «Обнаружение и сигнал СБ»).
## Black ICE (настройка black): то же зрение, но поймал — не выброс, а флэтлайн (причина black_caught), и есть охота:
## пока trace нетраннера не ниже уровня TRACE, ICE идёт на него по позиции (зрение не нужно), медленнее бега игрока.
## Чистая логика: без физики и сцены. Время подаётся снаружи (секунды), шаг — IceNode, 10 раз в секунду.
## Видимость — функция позиций: расстояние и конус перед ICE (препятствия не учитываем).
## Добычу не трогаем: «выброшен» — только событие, предметы остаются в узле (решает вызывающий).

enum State { PATROL, SUSPICIOUS, SEARCH, HUNT }

## ICE поймал нетраннера: сессия и причина ("caught" — Soft поймал вблизи, "flatline" — Soft при trace 100,
## "black_caught" — Black ICE догнал: флэтлайн, а не выброс).
signal ejected(session: String, reason: String)
signal state_changed(old_state: int, new_state: int)

const DEFAULT_SETTINGS := {
	"sight_range": 12.0,  # м, дальше не видит
	"sight_half_angle_deg": 50.0,  # половина конуса
	"notice_per_sec": 0.5,  # рост осведомлённости на виду (1.0 = поиск)
	"forget_per_sec": 0.25,  # спад осведомлённости, если цель пропала
	"catch_range": 1.5,  # м: в поиске ближе этого — выброс
	"catch_grace_sec": 0.0,  # с «тревоги» после «!»: первые секунды поиска ICE стоит и смотрит, не ловит (0 — как раньше)
	"search_duration": 8.0,  # с поиска у последней точки, потом возврат на патруль
	"patrol_speed": 1.0,
	"chase_speed": 2.5,
	"waypoint_reach": 0.5,
	"trace_action": "seen_by_ice",  # действие trace, пока цель на виду (вес — в настройках TraceMeter)
	"black": false,  # Black ICE: поимка = флэтлайн, есть охота
	"hunt_level": TraceMeter.Level.TRACE,  # с какого уровня trace Black ICE охотится
	"hunt_speed": 2.0,  # м/с: медленнее бега игрока (≈2.5 в плоской сборке) — от охоты можно уйти к выходу
}

## Тревога узла (W1): множитель дальности зрения и скорости внимания, ≥ 1. Ставит узел, 1 — без тревоги.
var alert_scale := 1.0
var position := Vector3.ZERO
var facing := Vector3.FORWARD  ## единичный, в плоскости XZ

var _s: Dictionary
var _state: int = State.PATROL
var _awareness := 0.0
var _target := ""  # сессия, которую подозреваем/ищем
var _last_seen := Vector3.ZERO
var _search_until := 0.0
var _grace_until := -1.0  # до этого времени поиск после «!» — тревога: ICE стоит и смотрит, не ловит
var _waypoints: Array[Vector3] = []
var _wp_index := 0
var _last_time := 0.0
var _has_time := false


func _init(settings: Dictionary = {}, start: Vector3 = Vector3.ZERO, waypoints: Array[Vector3] = []) -> void:
	_s = DEFAULT_SETTINGS.duplicate(true)
	_s.merge(settings, true)
	position = start
	_waypoints = waypoints
	if waypoints.size() > 1:
		# Старт — первая точка маршрута: ICE смотрит на вторую (раньше -Z, пока не сделает первый шаг).
		var d := Vector3(waypoints[1].x - waypoints[0].x, 0.0, waypoints[1].z - waypoints[0].z)
		if d.length() > 0.0001:
			facing = d.normalized()


func state() -> int:
	return _state


## Имя состояния для журнала сервера.
static func state_name(s: int) -> String:
	match s:
		State.PATROL:
			return "PATROL"
		State.SUSPICIOUS:
			return "SUSPICIOUS"
		State.SEARCH:
			return "SEARCH"
		State.HUNT:
			return "HUNT"
	return "?"


func awareness() -> float:
	return _awareness


func target() -> String:
	return _target


func is_black() -> bool:
	return bool(_s["black"])


## Идёт охота за этим нетраннером (только Black ICE).
func is_hunting(session: String) -> bool:
	return _state == State.HUNT and _target == session


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


## Узел опустел и ICE перестал думать: первый шаг после пробуждения не должен засчитать всё время сна одним шагом (иначе внимание
## взлетает до 1,0, а ICE «перепрыгивает» по патрулю на десятки секунд). Состояние и позиция остаются как были.
func rest() -> void:
	_has_time = false


## Один шаг мысли. targets: сессия → позиция (только нетраннеры узла), meters: сессия → TraceMeter (необязательно).
func step(now: float, targets: Dictionary, meters: Dictionary = {}) -> void:
	var dt := 0.0
	if _has_time:
		dt = maxf(now - _last_time, 0.0)
	_has_time = true
	_last_time = now

	if is_black():
		var hunted := _hunted_session(targets, meters)
		if hunted != "":
			_hunt(hunted, targets[hunted], now, dt)
			return
		if _state == State.HUNT:
			# Trace упал ниже порога: идём к последнему месту поиска, как после потери из виду.
			_search_until = now + float(_s["search_duration"])
			_set_state(State.SEARCH)
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
		if not can_see(position, facing, p, float(_s["sight_range"]) * alert_scale, _s["sight_half_angle_deg"]):
			continue
		var d := position.distance_to(p)
		if d < best_d:
			best_d = d
			best = session
	return best


## Ближайший нетраннер, чей trace дошёл до порога охоты. Скрытого GHOST'ом в targets нет — охота его не видит.
func _hunted_session(targets: Dictionary, meters: Dictionary) -> String:
	var best := ""
	var best_d := INF
	for session in targets:
		var meter: TraceMeter = meters.get(session)
		if meter == null or meter.level() < int(_s["hunt_level"]):
			continue
		var d := position.distance_to(targets[session])
		if d < best_d:
			best_d = d
			best = session
	return best


func _hunt(session: String, pos: Vector3, _now: float, dt: float) -> void:
	_target = session
	_last_seen = pos
	_awareness = 1.0
	_set_state(State.HUNT)
	if position.distance_to(pos) <= float(_s["catch_range"]):
		_eject(session, "black_caught")
		return
	_move(dt)


func _on_seen(session: String, pos: Vector3, now: float, dt: float, meters: Dictionary) -> void:
	_target = session
	_last_seen = pos
	_awareness = minf(_awareness + float(_s["notice_per_sec"]) * alert_scale * dt, 1.0)
	if _state == State.PATROL:
		_set_state(State.SUSPICIOUS)
	if _state == State.SUSPICIOUS and _awareness >= 1.0:
		_search_until = now + float(_s["search_duration"])
		_grace_until = now + float(_s["catch_grace_sec"])
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
	if _state == State.SEARCH and close and not _in_grace():
		_eject(session, "black_caught" if is_black() else "caught")
		return true
	if flat:
		_eject(session, "flatline")
		return true
	return false


## Идёт ли тревога после «!»: первые catch_grace_sec секунд поиска (по времени последнего шага).
func _in_grace() -> bool:
	return _last_time < _grace_until


func _eject(session: String, reason: String) -> void:
	_reset_to_patrol()
	ejected.emit(session, reason)


func _reset_to_patrol() -> void:
	_target = ""
	_awareness = 0.0
	_grace_until = -1.0
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
			speed = 0.0 if _in_grace() else float(_s["chase_speed"])  # тревога: стоит и смотрит на игрока
		State.HUNT:
			goal = _last_seen
			speed = _s["hunt_speed"]
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
