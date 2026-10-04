class_name FrameStats
extends RefCounted
## Время кадров клиента для журнала: что считать долгим кадром и сводка за окно (строка `perf`).
## Раньше долгим считался любой кадр дольше 1/72 с, а таймер кадра дрожит на доли миллисекунды: на очках `frame.slow` срабатывал
## почти на каждом кадре при ровных 72 Гц (все ms=13.89 при limit_ms=13.89, сессия 4 октября 2026). Теперь — допуск: долгий кадр
## пропустил обновление экрана (≥ ~17,4 мс), а не просто чуть выше периода.

const REFRESH_HZ := 72.0
const FRAME_SEC := 1.0 / REFRESH_HZ
## Во сколько раз кадр может превысить период, чтобы ещё считаться ровным (14,3–16,6 мс на 72 Гц — дрожание, 19,4 — пропуск).
const SLOW_TOLERANCE := 1.25
const SLOW_SEC := FRAME_SEC * SLOW_TOLERANCE

var frames := 0
var slow := 0
var _sum_sec := 0.0
var _max_sec := 0.0


static func is_slow(delta_sec: float) -> bool:
	return delta_sec > SLOW_SEC


func add(delta_sec: float) -> void:
	frames += 1
	_sum_sec += delta_sec
	_max_sec = maxf(_max_sec, delta_sec)
	if is_slow(delta_sec):
		slow += 1


## Сводка за окно с прошлого вызова (кадров, среднее и наибольшее время кадра в мс, долгих кадров) и сброс окна.
## Пустое окно — frames=0 и нули.
func take() -> Dictionary:
	var out := {
		"frames": frames,
		"avg_ms": snappedf(_sum_sec / frames * 1000.0, 0.01) if frames > 0 else 0.0,
		"max_ms": snappedf(_max_sec * 1000.0, 0.01),
		"slow": slow,
	}
	frames = 0
	slow = 0
	_sum_sec = 0.0
	_max_sec = 0.0
	return out
