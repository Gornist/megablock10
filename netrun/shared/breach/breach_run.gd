class_name BreachRun
extends RefCounted
## Ход одной попытки взлома без сцены и сети (порт BreachRun из app/.../breach/BreachRun.kt): попытка, таймер, итог и события реплик ICE.
## Один движок на три режима (docs/netrun-deck-design.md, §3.1) — режим задаёт фабрика, дальше ход одинаков:
##   for_storage — «взлом хранилища»: сетка и ловушки по тиру узла, цель — цепочки выбранных демонов, буфер = RAM,
##                 демон JITTER среди выбранных даёт таймеру +jitter_bonus_sec;
##   for_charge  — «заряд демона»: сетка и таймер по тиру демона, цель — его цепочка, буфер = длина + buffer_extra, ловушек нет;
##   for_decrypt — «расшифровка шарда»: сетка и таймер по тиру шарда, цель — шифр-замок длиной по тиру шарда, буфер = длина + buffer_extra, ловушек нет.
## Фабрики возвращают null на заведомо негодных входах (нет демонов, цепочки не влезают в RAM или в сетку).
##
## Время — целые секунды (tick) или дробные (advance, копит остаток). Когда буфер полон или время вышло, итог фиксируется сам; уход игрока,
## выброс, телепорт, обрыв — resolve(): досрочный итог по тому, что собрано (подсмотреть сетку и уйти без последствий нельзя).
## Для заряда и расшифровки досрочный итог — повод просто бросить попытку без последствий; решает вызывающий.
##
## Ловушка и совпадение в тапе не меняют мир: trace, звук, реплику ICE и эффекты применяет вызывающий по результату tap.

const MODE_STORAGE := "storage"
const MODE_CHARGE := "charge"
const MODE_DECRYPT := "decrypt"

const EVENT_TRAP := "TRAP"
const EVENT_MATCH := "MATCH"
const EVENT_INTRO := "INTRO"
const EVENT_HALF_TIME := "HALF_TIME"
const EVENT_LOW_TIME := "LOW_TIME"

var mode := MODE_STORAGE
var tier := "BASE"           # тир сетки: BASE / HARD / NIGHTMARE (от него и пул реплик ICE)
var attempt: BreachAttempt
var timer_sec := 0
var seconds_left := 0
var result := ""             # "" пока идёт; потом BreachRules.SUCCESS / PARTIAL / FAIL
var seed_value := 0
var _data: BreachData
var _frac := 0.0


## Взлом хранилища. tier — имя тира узла; daemons — выбранные BreachDaemon; ram — буфер игрока.
## null: демонов нет или их суммарная цепочка не влезает в ram.
static func for_storage(tier_: String, daemons: Array, ram: int, seed_: int, data: BreachData = null) -> BreachRun:
	var d := data if data != null else BreachData.shared()
	var total := 0
	var jitter := false
	for dm in daemons:
		total += dm.length()
		jitter = jitter or dm.effect == "JITTER"
	if daemons.is_empty() or total > ram:
		return null
	var p := d.tier_params(tier_)
	var timer: int = int(p["timer_sec"]) + (d.jitter_bonus_sec if jitter else 0)
	var traps := {"dead_cells": p["dead_cells"], "corrupted_codes": p["corrupted_codes"]}
	return _build(MODE_STORAGE, tier_, daemons, ram, timer, int(p["grid_size"]), traps, seed_, d)


## Заряд демона: цель — его собственная цепочка, тир сетки — тир демона, ловушек нет.
static func for_charge(daemon: BreachDaemon, seed_: int, data: BreachData = null) -> BreachRun:
	var d := data if data != null else BreachData.shared()
	if daemon == null or daemon.length() == 0:
		return null
	var tier_ := BreachData.tier_name(daemon.tier)
	var p := d.tier_params(tier_)
	return _build(MODE_CHARGE, tier_, [daemon], daemon.length() + d.decrypt_buffer_extra, int(p["cipher_timer_sec"]), int(p["grid_size"]), {}, seed_, d)


## Расшифровка шарда тира shard_tier (1/2/3). target — цепочка шифр-замка; пусто — выводится из зерна попытки (длина по тиру шарда).
static func for_decrypt(shard_tier: int, seed_: int, target: Array = [], data: BreachData = null) -> BreachRun:
	var d := data if data != null else BreachData.shared()
	var tier_ := BreachData.tier_name(shard_tier)
	var p := d.tier_params(tier_)
	var seq: Array = target.duplicate()
	if seq.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_
		for _i in range(d.decrypt_length(shard_tier)):
			seq.append(d.alphabet[rng.randi_range(0, d.alphabet.size() - 1)])
	var lock := BreachDaemon.make("decrypt", seq, "DECRYPT", shard_tier, "Шифр-замок")
	return _build(MODE_DECRYPT, tier_, [lock], seq.size() + d.decrypt_buffer_extra, int(p["cipher_timer_sec"]), int(p["grid_size"]), {}, seed_, d)


static func _build(mode_: String, tier_: String, daemons: Array, buffer: int, timer: int, grid_size: int, traps: Dictionary, seed_: int, data: BreachData) -> BreachRun:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var grid := BreachGrid.generate(grid_size, daemons, rng, data, traps)
	if grid == null:
		return null
	return from_attempt(BreachAttempt.make(grid, daemons, buffer, data), timer, tier_, mode_, seed_, data)


## Попытка по готовой сетке (проигрыватель golden, тесты, повтор с сервера): без генерации.
static func from_attempt(attempt_: BreachAttempt, timer: int, tier_: String, mode_: String = MODE_STORAGE, seed_: int = 0, data: BreachData = null) -> BreachRun:
	var run := BreachRun.new()
	run.mode = mode_
	run.tier = tier_
	run.attempt = attempt_
	run.timer_sec = timer
	run.seconds_left = timer
	run.seed_value = seed_
	run._data = data if data != null else BreachData.shared()
	return run


func is_finished() -> bool:
	return result != ""


## Таймер ещё идёт: время не вышло, буфер не полон, итога нет.
func is_ticking() -> bool:
	return seconds_left > 0 and not attempt.is_full() and result == ""


## Последние секунды до итога — таймер мигает.
func is_low_time() -> bool:
	return seconds_left >= 1 and seconds_left <= _data.low_time_sec and result == ""


## Последние секунды — на каждом тике предупреждение.
func is_warning() -> bool:
	return seconds_left >= 1 and seconds_left <= _data.warning_sec


## Реплика ICE на текущей секунде или "". Если половина окна и «10 секунд» совпали, остаётся LOW_TIME.
## Короткие таймеры (не длиннее events_min_timer_sec) реплик по времени не дают.
func time_event() -> String:
	if timer_sec <= _data.events_min_timer_sec:
		return ""
	if seconds_left == _data.low_time_sec:
		return EVENT_LOW_TIME
	@warning_ignore("integer_division")
	var half := timer_sec / 2  # целочисленное деление, как timerSec / 2 в Kotlin
	if seconds_left == half:
		return EVENT_HALF_TIME
	return ""


## Клетки, которые можно тапнуть сейчас; после итога — никакие.
func selectable() -> Array[Vector2i]:
	if result != "":
		var none: Array[Vector2i] = []
		return none
	return attempt.selectable_cells()


## Тап по клетке. Возвращает {ok, hit_trap, matched, ice_event, finished}: ok=false — тап не принят (итог уже есть или клетка недоступна),
## ничего не изменилось. matched — после тапа совпало больше демонов, чем до него; ice_event — TRAP, MATCH или "" (ловушка важнее).
## Полный буфер сам фиксирует итог (finished=true), как экран телефона.
func tap(cell: Vector2i) -> Dictionary:
	if result != "" or not attempt.can_select(cell):
		return {"ok": false, "hit_trap": false, "matched": false, "ice_event": "", "finished": result != ""}
	var before := attempt.matched_daemon_ids().size()
	attempt.select(cell)
	var hit_trap := attempt.grid.is_trap(cell)
	var matched := attempt.matched_daemon_ids().size() > before
	if attempt.is_full():
		resolve()
	return {
		"ok": true,
		"hit_trap": hit_trap,
		"matched": matched,
		"ice_event": EVENT_TRAP if hit_trap else (EVENT_MATCH if matched else ""),
		"finished": result != "",
	}


## Прошла одна секунда. Возвращает реплику времени (time_event) или "". Когда время вышло, фиксирует итог. После итога и при полном буфере — ничего.
func tick() -> String:
	if not is_ticking():
		return ""
	seconds_left -= 1
	var ev := time_event()
	if seconds_left <= 0:
		resolve()
	return ev


## Прошло delta секунд (дробных): целые секунды превращаются в tick, остаток копится. Возвращает реплики времени по порядку.
func advance(delta: float) -> Array[String]:
	var events: Array[String] = []
	if result != "" or delta <= 0.0:
		return events
	_frac += delta
	while _frac >= 1.0 and is_ticking():
		_frac -= 1.0
		var ev := tick()
		if ev != "":
			events.append(ev)
	if not is_ticking():
		_frac = 0.0
	return events


## Зафиксировать итог по тому, что собрано (по таймеру, по полному буферу, досрочно). true — итог поставлен этим вызовом;
## повторный вызов ничего не меняет и даёт false.
func resolve() -> bool:
	if result != "":
		return false
	result = BreachRules.outcome(attempt.daemons, attempt.matched_daemon_ids())
	return true


## Итог для вызывающего: {outcome, matched (id совпавших), total (сколько демонов), seconds_left}. Пусто, пока итога нет.
func result_info() -> Dictionary:
	if result == "":
		return {}
	return {"outcome": result, "matched": attempt.matched_daemon_ids(), "total": attempt.daemons.size(), "seconds_left": seconds_left}


## Реплика ICE на событие (INTRO, TRAP, MATCH, HALF_TIME, LOW_TIME) для тира сетки.
func ice_line(event: String) -> String:
	return _data.ice_line(tier, event, seed_value)
