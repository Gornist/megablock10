class_name MbLog
extends RefCounted
## Журнал в файл: строки `событие ключ=значение`, как у журнала приложения Мегаблока (Mb10Log).
## На очках файл лежит в user://logs/ (забирает pico.sh log). Формат — чистая функция `format`, её проверяет тест.

const DIR := "user://logs"

var path := ""
var _file: FileAccess


## Строка без времени: `событие ключ=значение ключ=значение`. Значения с пробелом, `=` или кавычкой — в кавычках.
static func format(event: String, fields: Dictionary = {}) -> String:
	var parts := PackedStringArray([event])
	for k in fields:
		parts.append("%s=%s" % [k, _value(fields[k])])
	return " ".join(parts)


static func _value(v: Variant) -> String:
	var s: String
	if v is float:
		s = "%.2f" % v
	elif v is bool:
		s = "true" if v else "false"
	else:
		s = str(v)
	if s.is_empty() or s.contains(" ") or s.contains("=") or s.contains("\"") or s.contains("\n"):
		return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") + "\""
	return s


## Открывает новый файл `netrun-<дата-время>.log`; `file_path` — явный путь (для тестов).
func open(file_path: String = "") -> Error:
	if file_path.is_empty():
		DirAccess.make_dir_recursive_absolute(DIR)
		var t := Time.get_datetime_dict_from_system()
		file_path = "%s/netrun-%04d%02d%02d-%02d%02d%02d.log" % [DIR, t.year, t.month, t.day, t.hour, t.minute, t.second]
	else:
		DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
	_file = FileAccess.open(file_path, FileAccess.WRITE)
	if _file == null:
		push_warning("[netrun-log] не открыть %s: %s" % [file_path, error_string(FileAccess.get_open_error())])
		return FileAccess.get_open_error()
	path = file_path
	return OK


## Пишет строку с временем с запуска движка (мс) и сразу сбрасывает на диск: приложение на очках могут убить в любой момент.
func log(event: String, fields: Dictionary = {}) -> String:
	var line := "t=%d %s" % [Time.get_ticks_msec(), format(event, fields)]
	print("[netrun-log] ", line)
	if _file != null:
		_file.store_line(line)
		_file.flush()
	return line


func close() -> void:
	_file = null
