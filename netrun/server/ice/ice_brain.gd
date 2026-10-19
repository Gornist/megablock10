class_name IceBrain
extends RefCounted
## Шим ICE в узле. Думает не он: Soft ICE решает TickIce, Black ICE логова — TickBlack (через наследника TickBlackBrain). Здесь остаётся то, что
## читают узел, журнал и снимок состояния: позиция и взгляд, код состояния (для поля `s` и журнала), осведомлённость и цель, сигналы, множитель
## тревоги. Soft-шим сам состояние не меняет: позицию и взгляд ставит GrayNode._sync_brain_view по клетке TickIce.
## Добычу не трогаем: «выброшен» — только событие, предметы остаются в узле (решает вызывающий).

enum State { PATROL, SUSPICIOUS, SEARCH, HUNT }

## ICE поймал нетраннера: сессия и причина ("caught" — Soft поймал вблизи, "flatline" — Soft при trace 100;
## "black_caught" шлёт Black ICE логова через узел: флэтлайн, а не выброс).
signal ejected(session: String, reason: String)
signal state_changed(old_state: int, new_state: int)

## Тревога узла (W1): множитель, ≥ 1. Ставит узел (NodeAlarm), 1 — без тревоги.
var alert_scale := 1.0
var position := Vector3.ZERO
var facing := Vector3.FORWARD  ## единичный, в плоскости XZ

var _black := false
var _state: int = State.PATROL
var _awareness := 0.0
var _target := ""  # сессия, которую подозреваем/ищем


func _init(black: bool = false, start: Vector3 = Vector3.ZERO) -> void:
	_black = black
	position = start


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
	return _black


## Идёт охота за этим нетраннером (только Black ICE).
func is_hunting(session: String) -> bool:
	return _state == State.HUNT and _target == session


## Нетраннер ушёл (вышел, выброшен кем-то ещё): шим забывает его.
func forget(session: String) -> void:
	if _target == session:
		_target = ""
		_awareness = 0.0
		_set_state(State.PATROL)


func _set_state(s: int) -> void:
	if s == _state:
		return
	var old := _state
	_state = s
	state_changed.emit(old, s)
