class_name TickClock
extends RefCounted
## Часы тактов узла (docs/gamedesign/time-and-movement.md, 3.1–3.3, Т2–Т8). Чистая логика: часы (`now`, секунды) подаёт вызывающий.
##
## Такт наступает, когда каждый свободный нетраннер сходил с прошлого такта и с него прошло не меньше `min_interval_sec`,
## или когда с прошлого такта прошло `window_sec`. Тактов нет, пока в узле нет нетраннеров (Т8); отсчёт окна начинается
## с появления первого. Свободен (Т3) — тот, кого вызывающий назвал в `set_free`: не в панели, не в тоннеле, не в паузе.

var window_sec := 5.0
var min_interval_sec := 0.6

## Номер последнего такта (0 — тактов ещё не было).
var tick_no := 0
## Время последнего такта (или начала отсчёта окна, когда нетраннер появился в пустом узле).
var last_tick_at := 0.0

var _free: Array = []
var _present := false
var _moved: Dictionary = {}
## Сколько ходов было в последнем такте и чем он вызван: "moves" | "window" (для журнала).
var last_moves := 0
var last_by := ""


func _init(window: float = 5.0, min_interval: float = 0.6) -> void:
	window_sec = window
	min_interval_sec = min_interval


## Запомнить ход нетраннера: до следующего такта ходить ему больше нельзя (Т4).
func register_move(session: Variant) -> void:
	_moved[session] = true


func moved(session: Variant) -> bool:
	return _moved.has(session)


## Кто сейчас держит такт (Т3). Нетраннеры не в списке такт не задерживают, но ходы их учитываются.
func set_free(sessions: Array) -> void:
	_free = sessions.duplicate()


## Есть ли в узле хоть один нетраннер (в панели, в паузе — тоже, главное, что он в узле). Пустой узел — тактов нет.
func set_present(present: bool, now: float) -> void:
	if present and not _present:
		last_tick_at = now   # окно отсчитывается с появления первого нетраннера
	_present = present
	if not present:
		_moved.clear()


## Пора ли делать такт. true — такт сделан: счётчики сброшены, `tick_no` вырос, `last_by` сказал почему.
func poll(now: float) -> bool:
	if not _present:
		return false
	var since := now - last_tick_at
	var by := ""
	if since >= window_sec:
		by = "window"
	elif since >= min_interval_sec and _all_free_moved():
		by = "moves"
	if by == "":
		return false
	tick_no += 1
	last_tick_at = now
	last_by = by
	last_moves = _moved.size()
	_moved.clear()
	return true


## «Вдох» (Т6): до такта по окну осталось не больше `inhale_sec`, а такт не вот-вот сделают ходы.
func inhale(now: float, inhale_sec: float) -> bool:
	if not _present:
		return false
	var left := window_sec - (now - last_tick_at)
	return left > 0.0 and left <= inhale_sec and not _all_free_moved()


## Все свободные сходили. Ни одного свободного (все в панелях) — ходов ждать не от кого: такт идёт только по окну.
func _all_free_moved() -> bool:
	if _free.is_empty():
		return false
	for s in _free:
		if not _moved.has(s):
			return false
	return true
