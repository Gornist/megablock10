class_name TickBeat
extends RefCounted
## «Такт слышно и видно» (time-and-movement.md, п. 4 разбора П3): чистая логика без сцены и звука. По полю `tk` сообщения state и намерениям ICE
## считает: долю окна такта (кольцо на руке), смену такта (пульс и вспышка — один раз на такт, повторы того же `tk.n` не считаются), «тиканье»
## перед шагом ближайшего ICE (щелчки учащаются к концу окна). Экземпляр помнит последний такт и фазу щелчков; статические функции — без состояния.

## Дальше этого (в клетках) шаг ICE не тикает: слышен только тот, что рядом.
const HEAR_CELLS := 12.0
## Щелчков в секунду: в начале окна и в конце (или во «вдохе»).
const CLICK_HZ_MIN := 2.0
const CLICK_HZ_MAX := 8.0
## Тиканье включается не с самого начала окна: с этой доли окна (до неё слышен только пульс такта).
const TICKING_FROM := 0.35

var _last_n := -1
var _click_phase := 0.0


## Сменился ли такт с прошлого раза. Первый снимок (прошлого такта нет) и повтор того же `n` — нет; `n` < 0 (нет такта) — нет.
func observe(tk: Dictionary) -> bool:
	var n := int(tk.get("n", -1))
	if n < 0:
		return false
	var changed := _last_n >= 0 and n != _last_n
	_last_n = n
	return changed


## Забыть последний такт (переход в другой узел, сброс сцены): следующий снимок снова «первый».
func reset() -> void:
	_last_n = -1
	_click_phase = 0.0


## Сколько щелчков надо издать за delta секунд при частоте rate_hz (фаза переносится между вызовами). rate_hz ≤ 0 — тишина, фаза сбрасывается.
func clicks(delta: float, rate_hz: float) -> int:
	if rate_hz <= 0.0 or delta <= 0.0:
		if rate_hz <= 0.0:
			_click_phase = 0.0
		return 0
	_click_phase += delta * rate_hz
	var n := int(floor(_click_phase))
	_click_phase -= float(n)
	return n


## Доля окна такта 0..1: от tk.at до tk.at + tk.win по часам сервера server_now. Нет tk (realtime) или окно 0 — 0.
static func window_fraction(tk: Dictionary, server_now: float) -> float:
	var win := float(tk.get("win", 0.0))
	if tk.is_empty() or win <= 0.0:
		return 0.0
	return clampf((server_now - float(tk.get("at", 0.0))) / win, 0.0, 1.0)


## Ближайший к клетке игрока тактовый Soft ICE в пределах hear_cells (Black ICE шага не готовит): его намерение, иначе пустой словарь.
static func nearest_ice(intents: Array, player_cell: Vector2i, hear_cells: float = HEAR_CELLS) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for it: Dictionary in intents:
		if bool(it.get("black", false)):
			continue
		var d := Vector2(it["c"] - player_cell).length()
		if d <= hear_cells and d < best_d:
			best_d = d
			best = it
	return best


## Будет ли ближайший ICE шагать в следующий такт (клетка меняется): тогда за такт до шага звучит тиканье.
static func ice_steps_soon(intents: Array, player_cell: Vector2i, hear_cells: float = HEAR_CELLS) -> bool:
	var it := nearest_ice(intents, player_cell, hear_cells)
	if it.is_empty():
		return false
	return it.get("nc", it["c"]) != it["c"]


## Частота щелчков 0 — тишина: тикает, только если ближайший ICE шагнёт и окно перевалило TICKING_FROM (или идёт «вдох»); дальше учащается линейно к концу окна.
static func click_rate(steps_soon: bool, frac: float, inhale: bool) -> float:
	if not steps_soon:
		return 0.0
	if inhale:
		return CLICK_HZ_MAX
	if frac < TICKING_FROM:
		return 0.0
	var k := clampf(inverse_lerp(TICKING_FROM, 1.0, frac), 0.0, 1.0)
	return lerpf(CLICK_HZ_MIN, CLICK_HZ_MAX, k)
