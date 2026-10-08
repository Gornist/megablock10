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
	"tick": {
		# Такт узла слышно: тихий пульс на каждом такте и щелчки перед шагом ближайшего ICE (учащаются к концу окна).
		"pulse_db": -24.0,
		"pulse_hz": 70.0,
		"pulse_sec": 0.16,
		"click_db": -16.0,
		"click_hz": 1400.0,
		"click_sec": 0.03,
		# Стингеры состояний Стража (карточка Game w3-p4-sound-vault): громкость — смещение в дБ к пульсу такта (0 дБ), подбирается на очках.
		# «?» — восходящий двухнотный сигнал, «!» — резкий стингер + низкий удар ≈1 с (самый громкий), «…» — мягкий нисходящий тон.
		"q_db": 3.0,
		"q_hz": 520.0,
		"q_hz2": 780.0,
		"q_sec": 0.30,
		"alert_db": 9.0,
		"alert_hz": 1100.0,
		"alert_low_hz": 90.0,
		"alert_low_end_hz": 45.0,
		"alert_sec": 1.0,
		"alert_hit_sec": 0.1,
		"lost_db": 0.0,
		"lost_hz": 600.0,
		"lost_end_hz": 380.0,
		"lost_sec": 0.40,
		# Тревожный слой: пока любой ICE в Поиске, пульс такта выше тоном и громче на alarm_db.
		"alarm_db": 2.0,
		"alarm_hz_mult": 1.6,
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
