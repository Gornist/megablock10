class_name RunMode
extends RefCounted
## Выбор режима запуска по метке сборки и аргументам. Чистая функция — проверяется тестом.

enum Mode { SERVER, CLIENT, FLAT }

## features — результат OS.has_feature по нужным меткам (передаём словарём, чтобы тестировать),
## args — пользовательские аргументы после `--`.
static func detect(features: Dictionary, args: PackedStringArray) -> Mode:
	if "--server" in args or features.get("dedicated_server", false):
		return Mode.SERVER
	if "--flat" in args:
		return Mode.FLAT
	if "--client" in args or features.get("android", false):
		return Mode.CLIENT
	# Запуск с рабочего стола без аргументов — плоская отладочная сборка.
	return Mode.FLAT


static func name_of(mode: Mode) -> String:
	return Mode.keys()[mode].to_lower()
