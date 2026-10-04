class_name TraceMeter
extends RefCounted
## Trace нетраннера (0–100): уровни, рост от действий, спад со временем.
## Чистая логика: время подаётся снаружи (секунды), своего таймера нет.
## Все числа — из словаря настроек (docs/netrun.md, «Обнаружение и сигнал СБ»).
## Гистерезиса в плане нет: уровень — чистая функция значения.

enum Level { NORMAL, SUSPICIOUS, TRACE, LOCKDOWN, FLATLINE }

## Смена уровня: прошлый и новый уровень, значение trace в этот момент.
signal level_changed(old_level: int, new_level: int, value: float)

## Стартовые числа; подбираются на этапе 2 — менять здесь или передавать свои настройки.
const DEFAULT_SETTINGS := {
	"max": 100.0,
	"suspicious_at": 25.0,
	"trace_at": 50.0,
	"lockdown_at": 75.0,
	"decay_per_sec": 1.0,  # спад, пока нетраннер скрыт
	"weights": {
		"seen_by_ice": 8.0,
		"sensor_hit": 5.0,
		"noise": 3.0,
		"door_forced": 10.0,
	},
}

var _settings: Dictionary
var _value: float = 0.0
var _level: int = Level.NORMAL
var _last_time: float = 0.0
var _has_time := false
var _frozen_until: float = -INF


func _init(settings: Dictionary = {}) -> void:
	_settings = DEFAULT_SETTINGS.duplicate(true)
	for key in settings:
		if key == "weights":
			_settings["weights"].merge(settings["weights"], true)
		else:
			_settings[key] = settings[key]


func value() -> float:
	return _value


func level() -> int:
	return _level


func is_frozen(now: float) -> bool:
	return now < _frozen_until


## Рост от действия (вес — из настроек). Неизвестное действие — ошибка, не тихий ноль.
## count — сколько раз подряд (например, секунд на виду). Заодно подтягивает спад до now.
func add_action(action: String, now: float, count: float = 1.0) -> void:
	var weights: Dictionary = _settings["weights"]
	assert(weights.has(action), "неизвестное действие trace: %s" % action)
	_advance(now, true)
	if _level == Level.FLATLINE or is_frozen(now):
		return
	_set_value(_value + float(weights.get(action, 0.0)) * count)


## Спад за время с прошлого вызова. hidden = false — нетраннера сейчас видят: спада нет.
func tick(now: float, hidden: bool = true) -> void:
	_advance(now, hidden)


## Сколько секунд trace ещё заморожен (0 — не заморожен).
func frozen_left(now: float) -> float:
	return maxf(0.0, _frozen_until - now)


## JITTER: trace замирает (ни роста, ни спада) на duration секунд.
func freeze(now: float, duration: float) -> void:
	_advance(now, true)
	_frozen_until = maxf(_frozen_until, now + duration)


## Новый забег / нетраннер выброшен: всё обнуляется без события.
func reset(now: float = 0.0) -> void:
	_value = 0.0
	_level = Level.NORMAL
	_last_time = now
	_has_time = true
	_frozen_until = -INF


func level_for(v: float) -> int:
	if v >= _settings["max"]:
		return Level.FLATLINE
	if v >= _settings["lockdown_at"]:
		return Level.LOCKDOWN
	if v >= _settings["trace_at"]:
		return Level.TRACE
	if v >= _settings["suspicious_at"]:
		return Level.SUSPICIOUS
	return Level.NORMAL


func _advance(now: float, hidden: bool) -> void:
	if not _has_time:
		_has_time = true
		_last_time = now
		return
	var from := _last_time
	_last_time = maxf(now, from)
	if not hidden or _level == Level.FLATLINE:
		return
	# Спад только вне окна заморозки.
	var start := maxf(from, _frozen_until)
	var dt := _last_time - start
	if dt > 0.0:
		_set_value(_value - float(_settings["decay_per_sec"]) * dt)


func _set_value(v: float) -> void:
	_value = clampf(v, 0.0, float(_settings["max"]))
	var new_level := level_for(_value)
	if new_level != _level:
		var old := _level
		_level = new_level
		level_changed.emit(old, new_level, _value)
