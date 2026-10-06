class_name BreachData
extends RefCounted
## Числа и реплики движка взлома (docs/netrun-deck-design.md, §10.3): параметры тиров, алфавит кодов, маркер мёртвой клетки,
## JITTER +15 с, длины шифр-замка, окна таймера, реплики ICE. Источник — data/rules/breach.json (его выгружает Kotlin-тест :rules,
## задача К0, и сверяет со своими константами). Ни одного числа правил в коде движка нет: всё берётся отсюда. Чистые данные, без сцены
## и сети. Маркер ловушки в буфере (TRAP_SENTINEL) — внутреннее соглашение движка, не число правил, в файле его нет.

const PATH := "res://data/rules/breach.json"
const TIER_NAMES: Array = ["BASE", "HARD", "NIGHTMARE"]
## События реплик ICE (как IceEvent приложения).
const EVENT_NAMES: Array = ["INTRO", "TRAP", "MATCH", "HALF_TIME", "LOW_TIME"]

static var _shared: BreachData

var source := ""
var load_error := ""
var alphabet: Array = []                 # коды сетки (строки)
var dead_marker := ""                    # код мёртвой клетки на сетке
var trap_sentinel := TRAP_SENTINEL       # в буфере вместо ловушки
var jitter_bonus_sec := 0
var cooldown_minutes := 0                # остывание узла; для движка не нужно, лежит в файле как общее число правил
var decrypt_target_length: Array = []    # длина шифр-замка по тиру шарда, индекс = тир - 1
var decrypt_buffer_extra := 0            # буфер заряда и расшифровки = длина цепочки + это
var events_min_timer_sec := 0            # реплики HALF_TIME/LOW_TIME — только при таймере длиннее этого
var low_time_sec := 0                    # последние секунды: мигает таймер и реплика LOW_TIME
var warning_sec := 0                     # последние секунды со звуковым предупреждением
## имя тира -> {grid_size, timer_sec (взлом хранилища), cipher_timer_sec (заряд и расшифровка: прежние 45/60/75), dead_cells: Vector2i,
## corrupted_codes: Vector2i (приманки без замка), lock_traps: Vector2i (приманки при замке), lock_length, buffer_slack,
## fail_penalty: {lock_step, trap_step, max_steps, minutes}}. Взлом 2.0: docs/gamedesign/breach.md, §2–3.
var tiers: Dictionary = {}
var ice_lines: Dictionary = {}           # имя тира -> событие -> Array[String]


## Не равен ни одному коду алфавита и маркеру мёртвой клетки: ловушка в буфере рвёт любую цепочку (BreachSymbols.TRAP_SENTINEL телефона).
const TRAP_SENTINEL := "  "

## Общий экземпляр из файла (читается один раз). Тесты сбрасывают его reset_shared().
static func shared() -> BreachData:
	if _shared == null:
		_shared = load_default()
	return _shared


static func reset_shared() -> void:
	_shared = null


static func load_default() -> BreachData:
	return load_file(PATH)


static func load_file(path: String) -> BreachData:
	if not FileAccess.file_exists(path):
		var d := BreachData.new()
		d.load_error = "файла нет: " + path
		return d
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		var d := BreachData.new()
		d.load_error = "не разобрать JSON: " + path
		return d
	var data := from_dict(parsed)
	data.source = path
	return data


static func from_dict(d: Dictionary) -> BreachData:
	var data := BreachData.new()
	data.alphabet = _strings(d.get("alphabet"))
	data.dead_marker = str(d.get("dead_marker", ""))
	data.trap_sentinel = str(d.get("trap_sentinel", TRAP_SENTINEL))
	data.jitter_bonus_sec = int(d.get("jitter_bonus_sec", 0))
	data.cooldown_minutes = int(d.get("container_cooldown_minutes", 0))
	var dec: Variant = d.get("decrypt")
	if dec is Dictionary:
		for n in (dec as Dictionary).get("target_length_by_shard_tier", []):
			data.decrypt_target_length.append(int(n))
		data.decrypt_buffer_extra = int((dec as Dictionary).get("buffer_extra", 0))
	data.events_min_timer_sec = int(d.get("time_events_min_timer_sec", 0))
	data.low_time_sec = int(d.get("low_time_sec", 0))
	data.warning_sec = int(d.get("warning_sec", 0))
	var raw_tiers: Variant = d.get("tiers")
	if raw_tiers is Dictionary:
		for name in raw_tiers:
			var p: Variant = raw_tiers[name]
			if p is Dictionary:
				var corrupted := _range(p.get("corrupted_codes"))
				var timer := int(p.get("timer_sec", 0))
				var penalty: Variant = p.get("fail_penalty")
				var pen: Dictionary = penalty if penalty is Dictionary else {}
				data.tiers[str(name)] = {
					"grid_size": int(p.get("grid_size", 0)),
					"timer_sec": timer,
					"cipher_timer_sec": int(p.get("cipher_timer_sec", timer)),   # нет поля — как раньше: таймер тира
					"dead_cells": _range(p.get("dead_cells")),
					"corrupted_codes": corrupted,
					"lock_traps": _range(p["lock_traps"]) if p.has("lock_traps") else corrupted,
					"lock_length": int(p.get("lock_length", 0)),
					"buffer_slack": int(p.get("buffer_slack", 0)),
					"fail_penalty": {
						"lock_step": int(pen.get("lock_step", 0)),
						"trap_step": int(pen.get("trap_step", 0)),
						"max_steps": int(pen.get("max_steps", 0)),
						"minutes": int(pen.get("minutes", 0)),
					},
				}
	var raw_lines: Variant = d.get("ice_lines")
	if raw_lines is Dictionary:
		for name in raw_lines:
			var by_event: Variant = raw_lines[name]
			if by_event is Dictionary:
				var out := {}
				for ev in by_event:
					out[str(ev)] = _strings(by_event[ev])
				data.ice_lines[str(name)] = out
	return data


## Имя тира по уровню 1/2/3 (как Tier.level в приложении); вне диапазона — BASE.
static func tier_name(level: int) -> String:
	return str(TIER_NAMES[level - 1]) if level >= 1 and level <= TIER_NAMES.size() else str(TIER_NAMES[0])


## Параметры тира по имени («HARD»). Неизвестное имя — параметры BASE (как Tier.fromLevel в приложении).
func tier_params(tier: String) -> Dictionary:
	var p: Variant = tiers.get(tier)
	if p == null:
		p = tiers.get(TIER_NAMES[0], {})
	return p


## Буфер попытки хранилища: наименьшее из RAM и «замок + сумма длин демонов + запас тира» (breach.md 2.3, BreachTierParams.bufferSize).
## lock_length — длина замка этой попытки (число тира; надбавку настороженности добавляет вызывающий).
func buffer_size(tier: String, ram: int, lock_length: int, daemons_length: int) -> int:
	return mini(ram, lock_length + daemons_length + int(tier_params(tier)["buffer_slack"]))


## Дека влезает в RAM: «замок + выбранные» не больше RAM, иначе начать взлом нельзя (breach.md 2.3).
static func fits_ram(ram: int, lock_length: int, daemons_length: int) -> bool:
	return lock_length + daemons_length <= ram


## Длина цели шифр-замка по тиру шарда 1/2/3; вне таблицы — 3 (как getOrElse в приложении).
func decrypt_length(shard_tier: int) -> int:
	if shard_tier >= 1 and shard_tier <= decrypt_target_length.size():
		return int(decrypt_target_length[shard_tier - 1])
	return 3


## Реплика ICE: пул зависит от тира и события; выбор — от seed попытки (в одном взломе стабильна, между взломами разная).
func ice_line(tier: String, event: String, seed_value: int) -> String:
	var by_event: Variant = ice_lines.get(tier)
	if not (by_event is Dictionary):
		by_event = ice_lines.get(TIER_NAMES[0], {})
	var pool: Array = (by_event as Dictionary).get(event, [])
	if pool.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ EVENT_NAMES.find(event)
	return pool[rng.randi_range(0, pool.size() - 1)]


## Что не так с данными (пусто — всё хорошо).
func errors() -> Array[String]:
	var out: Array[String] = []
	if load_error != "":
		out.append(load_error)
		return out
	if alphabet.size() < 2:
		out.append("алфавит: нужно не меньше двух кодов")
	if dead_marker == "" or dead_marker in alphabet:
		out.append("dead_marker пуст или совпадает с кодом алфавита")
	if trap_sentinel in alphabet or trap_sentinel == dead_marker:
		out.append("trap_sentinel совпадает с кодом алфавита или маркером мёртвой клетки")
	if decrypt_target_length.size() != TIER_NAMES.size():
		out.append("decrypt.target_length_by_shard_tier: нужно %d значения" % TIER_NAMES.size())
	if low_time_sec <= 0 or warning_sec <= 0 or events_min_timer_sec <= 0:
		out.append("time_events_min_timer_sec, low_time_sec, warning_sec должны быть положительны")
	for name in TIER_NAMES:
		if not tiers.has(name):
			out.append("нет тира " + name)
			continue
		var p: Dictionary = tiers[name]
		if int(p["grid_size"]) < 2 or int(p["timer_sec"]) < 1 or int(p["cipher_timer_sec"]) < 1:
			out.append("%s: grid_size/timer_sec/cipher_timer_sec вне диапазона" % name)
		if int(p["lock_length"]) < 0 or int(p["buffer_slack"]) < 0:
			out.append("%s: lock_length/buffer_slack отрицательны" % name)
		for key in ["dead_cells", "corrupted_codes", "lock_traps"]:
			var r: Vector2i = p[key]
			if r.x < 0 or r.y < r.x:
				out.append("%s.%s: диапазон %s" % [name, key, r])
		var by_event: Variant = ice_lines.get(name)
		for ev in EVENT_NAMES:
			if not (by_event is Dictionary) or (by_event as Dictionary).get(ev, []).is_empty():
				out.append("%s.%s: нет реплик" % [name, ev])
	return out


static func _strings(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for x in v:
			out.append(str(x))
	return out


## [мин, макс] -> Vector2i; не пара — (0, 0).
static func _range(v: Variant) -> Vector2i:
	if v is Array and (v as Array).size() == 2:
		return Vector2i(int(v[0]), int(v[1]))
	return Vector2i.ZERO
