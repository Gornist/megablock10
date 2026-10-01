class_name BatteryProbe
extends RefCounted
## Заряд очков (P6). На Android — JNI-синглтон `NetrunBattery` (методы get_percent() -> int, is_charging() -> bool);
## плагина пока нет (появится вместе с очками), на ПК и без плагина — «нет данных»: заряд null.

const SINGLETON := "NetrunBattery"

## Подмена для тестов: Callable() -> {"percent": int, "charging": bool} или {}.
var provider: Callable


## {"percent": int|null, "charging": bool|null}
func read() -> Dictionary:
	var raw: Dictionary = {}
	if provider.is_valid():
		raw = provider.call()
	elif OS.get_name() == "Android" and Engine.has_singleton(SINGLETON):
		var s := Engine.get_singleton(SINGLETON)
		raw = {"percent": s.call("get_percent"), "charging": s.call("is_charging")}
	var pct := BeatStats.battery_pct(raw.get("percent"))
	var chg: Variant = raw.get("charging")
	return {"percent": pct if pct >= 0 else null, "charging": chg if chg is bool else null}
