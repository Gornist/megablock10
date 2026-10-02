class_name AudioSettings
extends RefCounted
## Настройки звука (громкости в дБ, пороги в метрах, тона в Гц). Словарь — как у TraceMeter/IceBrain:
## свои значения передаются поверх DEFAULTS через merged(). Числа стартовые, подбираются на плейтесте.

const DEFAULTS := {
	"sample_rate": 22050,
	"trace": {
		# индекс = TraceMeter.Level: NORMAL, SUSPICIOUS, TRACE, LOCKDOWN, FLATLINE
		"volume_db": [-30.0, -26.0, -20.0, -14.0, -80.0],  # FLATLINE: фон исчезает совсем
		"base_hz": [110.0, 130.0, 160.0, 196.0, 110.0],
		"pulse_hz": [0.0, 0.8, 1.6, 3.2, 0.0],  # 0 — ровный фон без пульса
		"pulse_depth": [0.0, 0.3, 0.5, 0.8, 0.0],  # глубина модуляции громкости 0..1
	},
	"ice": {
		"near_m": 1.5,  # ближе — полная громкость
		"far_m": 14.0,  # дальше — тишина (чуть больше дальности взгляда ICE, 12 м)
		"max_db": -8.0,
		"min_db": -50.0,
		# индекс = IceBrain.State: PATROL, SUSPICIOUS, SEARCH, HUNT (охота Black ICE)
		"base_hz": [140.0, 220.0, 330.0, 90.0],
		"warble_hz": [0.5, 3.0, 7.0, 11.0],  # частота подрагивания тона
		"state_gain_db": [0.0, 3.0, 6.0, 9.0],  # прибавка к громкости по состоянию
	},
	"flatline": {
		"duration_s": 1.6,  # звук флэтлайна: тон падает от start_hz к end_hz и гаснет
		"start_hz": 520.0,
		"end_hz": 40.0,
		"volume_db": -6.0,
	},
}


static func merged(overrides: Dictionary = {}) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	for key in overrides:
		if out.get(key) is Dictionary and overrides[key] is Dictionary:
			out[key].merge(overrides[key], true)
		else:
			out[key] = overrides[key]
	return out
