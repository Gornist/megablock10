class_name IceStingers
extends RefCounted
## Стингеры состояний Стража «как в MGS» (карточка Game w3-p4-sound-vault, п. А): чистая логика без сцены и звука. По списку намерений ICE на каждом
## такте находит переходы стадии и отдаёт ОДИН звук такта по приоритету «!» > «?» > «…»:
##  • "q"     — «?» (подозрение): Патруль → Взгляд / Проверка;
##  • "alert" — «!» (обнаружен): любая стадия → Поиск;
##  • "lost"  — «…» (потерял): Поиск → ниже, либо флаг lost пришёл на этот такт.
## Звук только на переходе, не на каждом такте; один и тот же стингер от одного ICE — не чаще раза в COOLDOWN_TICKS тактов. Black ICE (охота) не озвучивается:
## у него нет стадий Патруль/Взгляд/Проверка/Поиск. Ключ — порядковый номер ICE в списке (сервер шлёт его стабильно в рамках узла).

const ST_PATROL := 0
const ST_GAZE := 1
const ST_CHECK := 2
const ST_SEARCH := 3

const KIND_ALERT := "alert"
const KIND_QUESTION := "q"
const KIND_LOST := "lost"
## Порядок важности: громче и приоритетнее всех «!».
const PRIORITY := [KIND_ALERT, KIND_QUESTION, KIND_LOST]
## Не чаще раза в столько тактов один и тот же стингер от одного ICE.
const COOLDOWN_TICKS := 2

var cooldown_ticks := COOLDOWN_TICKS

var _prev_st: Array = []
var _prev_lost: Array = []
var _last_tick := {}   # "индекс|звук" -> номер такта последнего стингера


## Забыть прошлые стадии (переход в другой узел, сброс сцены): следующий снимок снова «первый» — без переходов.
func reset() -> void:
	_prev_st.clear()
	_prev_lost.clear()
	_last_tick.clear()


## Какой звук даёт переход prev → st (lost / prev_lost — флаг «потерял» на этом и прошлом такте). "" — перехода нет.
static func transition(prev: int, st: int, lost: bool, prev_lost: bool) -> String:
	if st == ST_SEARCH and prev != ST_SEARCH:
		return KIND_ALERT
	if prev == ST_PATROL and (st == ST_GAZE or st == ST_CHECK):
		return KIND_QUESTION
	if (prev == ST_SEARCH and st != ST_SEARCH) or (lost and not prev_lost):
		return KIND_LOST
	return ""


## Самый приоритетный из звуков (""/"" — тишина).
static func best(kinds: Array) -> String:
	for k: String in PRIORITY:
		if kinds.has(k):
			return k
	return ""


## Любой обычный ICE (не Black) в Поиске: на пульс такта ложится тревожный слой.
static func any_search(intents: Array) -> bool:
	for it: Dictionary in intents:
		if not bool(it.get("black", false)) and int(it.get("st", 0)) == ST_SEARCH:
			return true
	return false


## Снимок такта n: звук этого такта по переходам с прошлого снимка ("" — ничего не звучит). Звать один раз на такт (по TickBeat.observe).
func observe(intents: Array, n: int) -> String:
	var kinds: Array = []
	var st_now: Array = []
	var lost_now: Array = []
	for i in intents.size():
		var it: Dictionary = intents[i]
		var st := int(it.get("st", 0))
		var lost := bool(it.get("lost", false))
		st_now.append(st)
		lost_now.append(lost)
		if bool(it.get("black", false)) or i >= _prev_st.size():
			continue   # Black ICE не озвучивается; новый в списке — без перехода
		var kind := transition(int(_prev_st[i]), st, lost, bool(_prev_lost[i]))
		if kind == "":
			continue
		var key := "%d|%s" % [i, kind]
		if _last_tick.has(key) and n - int(_last_tick[key]) < cooldown_ticks:
			continue
		_last_tick[key] = n
		kinds.append(kind)
	_prev_st = st_now
	_prev_lost = lost_now
	return best(kinds)
