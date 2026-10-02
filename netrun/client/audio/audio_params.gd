class_name AudioParams
extends RefCounted
## Чистые функции «состояние → параметры звука». Без узлов и времени: удобно тестировать.


## Уровень trace → {volume_db, base_hz, pulse_hz, pulse_depth}. Неизвестный уровень зажимается в допустимый.
static func trace_params(level: int, settings: Dictionary = AudioSettings.DEFAULTS) -> Dictionary:
	var t: Dictionary = settings["trace"]
	var i := clampi(level, 0, (t["volume_db"] as Array).size() - 1)
	return {
		"volume_db": float(t["volume_db"][i]),
		"base_hz": float(t["base_hz"][i]),
		"pulse_hz": float(t["pulse_hz"][i]),
		"pulse_depth": float(t["pulse_depth"][i]),
	}


## Состояние ICE и расстояние (м) → {audible, volume_db, base_hz, warble_hz}.
## Громкость линейна в дБ между near_m и far_m; дальше far_m — не слышно.
static func ice_params(state: int, distance: float, settings: Dictionary = AudioSettings.DEFAULTS) -> Dictionary:
	var s: Dictionary = settings["ice"]
	var i := clampi(state, 0, (s["base_hz"] as Array).size() - 1)
	var near: float = s["near_m"]
	var far: float = s["far_m"]
	var k := clampf(inverse_lerp(near, far, distance), 0.0, 1.0)
	var db: float = lerpf(float(s["max_db"]), float(s["min_db"]), k) + float(s["state_gain_db"][i])
	return {
		"audible": distance < far,
		"volume_db": db,
		"base_hz": float(s["base_hz"][i]),
		"warble_hz": float(s["warble_hz"][i]),
	}


## Звук флэтлайна через t секунд после начала → {active, hz, volume_db}: падающий тон, затем тишина.
static func flatline_params(t: float, settings: Dictionary = AudioSettings.DEFAULTS) -> Dictionary:
	var f: Dictionary = settings["flatline"]
	var dur: float = f["duration_s"]
	if t < 0.0 or t >= dur:
		return {"active": false, "hz": float(f["end_hz"]), "volume_db": -80.0}
	var k := t / dur
	return {
		"active": true,
		"hz": lerpf(float(f["start_hz"]), float(f["end_hz"]), k),
		"volume_db": float(f["volume_db"]) - 40.0 * k * k,
	}
