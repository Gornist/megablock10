class_name ServerClock
extends RefCounted
## Соответствие часов сервера и местных часов клиента, чистая логика. Каждый пакет даёт оценку смещения
## «местное − серверное» = задержка пути + постоянная разница; берём минимум по скользящему окну — это пакет, дошедший
## быстрее всех, остальные (с дрожью) окажутся «позже» и сгладятся задержкой показа. Скачок смещения больше JUMP
## (перезапуск сервера, местные часы переведены) — окно сбрасывается сразу, не ждать, пока оно выветрится.

const WINDOW := 40
const JUMP := 1.0

var _cands: Array[float] = []
var _offset := 0.0


func has_data() -> bool:
	return not _cands.is_empty()


func offset() -> float:
	return _offset


func observe(server_t: float, local_t: float) -> void:
	var c := local_t - server_t
	if not _cands.is_empty() and absf(c - _offset) > JUMP:
		_cands.clear()
	_cands.append(c)
	if _cands.size() > WINDOW:
		_cands.remove_at(0)
	_offset = _cands.min()


## Серверное время, которое «сейчас» у клиента (без задержки показа).
func server_time(local_t: float) -> float:
	return local_t - _offset


## Момент серверного времени, который надо показать: сейчас минус задержка показа.
func render_time(local_t: float, delay: float) -> float:
	return server_time(local_t) - delay
