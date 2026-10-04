class_name StateBuffer
extends RefCounted
## Буфер состояний одного чужого объекта (аватар, ICE) для сглаживания по сети. Чистая логика, без сцены.
## Сервер шлёт позиции с меткой своего времени; клиент показывает объект «в прошлом» (render_time = сейчас − задержка) и
## интерполирует между двумя соседними снимками. Потерянный пакет — просто более длинный отрезок интерполяции.
##
## Правила:
## - снимки хранятся по возрастанию времени; опоздавший (переупорядоченный) вставляется на своё место, повтор того же времени заменяет;
## - время сервера резко ушло назад (перезапуск сервера, сброс часов) — буфер очищается, иначе объект застынет;
## - дырка между соседними снимками больше SNAP_GAP — не «скользим» через неё, держим старую позицию и прыгаем на новую;
## - показывать позже последнего снимка — экстраполяция по скорости, но не дольше MAX_EXTRAPOLATE, дальше стоим;
## - скачок (телепорт): у снимка есть счётчик скачков `jump`; между снимками с разным счётчиком не интерполируем и не
##   экстраполируем — стоим на старом месте и прыгаем на новое, когда время дошло (телепорт не должен «ползти»). Счётчик
##   лежит в каждом пакете, поэтому потеря пакета скачок не прячет.

const MAX_SAMPLES := 24
const MAX_EXTRAPOLATE := 0.1
const SNAP_GAP := 1.0
const REWIND_RESET := 2.0

var _t: Array[float] = []
var _p: Array[Vector3] = []
var _yaw: Array[float] = []
var _jump: Array[int] = []


func size() -> int:
	return _t.size()


func is_empty() -> bool:
	return _t.is_empty()


func newest_time() -> float:
	return _t[_t.size() - 1] if not _t.is_empty() else -INF


## Добавить снимок. false — отброшен (слишком старый для полного буфера). jump — счётчик скачков объекта (0 — не прыгал).
func push(t: float, p: Vector3, yaw: float = 0.0, jump: int = 0) -> bool:
	if not _t.is_empty() and t < newest_time() - REWIND_RESET:
		clear()
	var i := _t.size()
	while i > 0 and _t[i - 1] > t:
		i -= 1
	if i > 0 and is_equal_approx(_t[i - 1], t):
		_p[i - 1] = p
		_yaw[i - 1] = yaw
		_jump[i - 1] = jump
		return true
	if i == 0 and _t.size() >= MAX_SAMPLES:
		return false
	_t.insert(i, t)
	_p.insert(i, p)
	_yaw.insert(i, yaw)
	_jump.insert(i, jump)
	while _t.size() > MAX_SAMPLES:
		_t.remove_at(0)
		_p.remove_at(0)
		_yaw.remove_at(0)
		_jump.remove_at(0)
	return true


func clear() -> void:
	_t.clear()
	_p.clear()
	_yaw.clear()
	_jump.clear()


## Поза на момент t: {p: Vector3, yaw: float}. Пустой буфер — пустой словарь.
func sample(t: float) -> Dictionary:
	var n := _t.size()
	if n == 0:
		return {}
	if t <= _t[0] or n == 1:
		return _pose(0)
	if t >= _t[n - 1]:
		return _extrapolated(t)
	var i := n - 1
	while i > 0 and _t[i - 1] > t:
		i -= 1
	# теперь _t[i-1] <= t < _t[i]
	var a := i - 1
	var span := _t[i] - _t[a]
	if span > SNAP_GAP or _jump[a] != _jump[i]:
		return _pose(a)  # длинная дырка или телепорт между снимками: стоим на старом, на новый — прыжком, когда время дойдёт
	var k := (t - _t[a]) / span
	return {"p": _p[a].lerp(_p[i], k), "yaw": lerp_angle(_yaw[a], _yaw[i], k)}


func _pose(i: int) -> Dictionary:
	return {"p": _p[i], "yaw": _yaw[i]}


func _extrapolated(t: float) -> Dictionary:
	var n := _t.size()
	var last := n - 1
	var pose := _pose(last)
	if n < 2:
		return pose
	var span := _t[last] - _t[last - 1]
	if span <= 0.0 or span > SNAP_GAP or _jump[last] != _jump[last - 1]:
		return pose
	var ahead := minf(t - _t[last], MAX_EXTRAPOLATE)
	pose["p"] = _p[last] + (_p[last] - _p[last - 1]) / span * ahead
	return pose
