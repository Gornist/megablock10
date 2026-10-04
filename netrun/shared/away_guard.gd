class_name AwayGuard
extends RefCounted
## «Ушёл из игры» на очках: пауза приложения, потеря фокуса (системное меню, граница, диалог), датчик на лбу, остановка сессии OpenXR.
## Раньше любая пауза сразу превращалась в выход с причиной headset_off (под охотой это сжигает деку). Теперь выход — только если
## игрок не вернулся за GRACE_SEC (решение владельца, 4 октября 2026: на 15-секундное «открыл меню, мигнул датчик» не выкидывать).
## Чистая логика без узлов и времени движка: тесты подают время сами. Несколько причин «ушёл» могут идти одновременно (пауза и
## потеря фокуса приходят вместе): отсчёт — от начала всего «ухода» (первой причины), возвращение — когда кончились все.

const GRACE_SEC := 15.0

var _since: Dictionary = {}    # причина -> когда началась, мс (только идущие)
var _episode_ms := -1          # когда начался весь «уход» (первая причина); -1 — игрок на месте
var _fired := false


## Причина «ушёл» началась (повтор той же причины время не сдвигает).
func begin(source: String, now_ms: int) -> void:
	if _since.is_empty():
		_episode_ms = now_ms
	if not _since.has(source):
		_since[source] = now_ms


## Причина кончилась. true — игрок вернулся (кончились все причины), но окно уже вышло: выход пора запросить (один раз).
func end(source: String, now_ms: int) -> bool:
	if not _since.has(source):
		return false
	_since.erase(source)
	if not _since.is_empty():
		return false
	var away := float(now_ms - _episode_ms) / 1000.0
	_episode_ms = -1
	return _fire_if_late(away)


## Каждый кадр, пока приложение работает (потеря фокуса, но не пауза): true — окно вышло, пора выходить (один раз).
func due(now_ms: int) -> bool:
	if _since.is_empty():
		return false
	return _fire_if_late(float(now_ms - _episode_ms) / 1000.0)


## Идёт ли сейчас «ушёл» (хотя бы одна причина).
func is_away() -> bool:
	return not _since.is_empty()


## Сколько секунд уже «ушёл» (0 — не ушёл).
func away_sec(now_ms: int) -> float:
	return float(now_ms - _episode_ms) / 1000.0 if not _since.is_empty() else 0.0


## Новый забег: выход снова можно запросить.
func reset() -> void:
	_since.clear()
	_episode_ms = -1
	_fired = false


func _fire_if_late(away_sec: float) -> bool:
	if _fired or away_sec < GRACE_SEC:
		return false
	_fired = true
	return true
