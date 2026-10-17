class_name MbLog
extends RefCounted
## Журнал в файл: строки `событие ключ=значение`, как у журнала приложения Мегаблока (Mb10Log).
## На очках файл лежит в user://logs/ (забирает pico.sh log); одиночная игра для тестеров открывает журнал в папке попытки (RunJournal).
## Формат — чистая функция `format`, её проверяет тест. Каждая строка сразу сбрасывается на диск: журнал переживает падение.

## Каталог журнала по умолчанию (очки, стенд).
const DIR := "user://logs"

## Строка записана (и в файл, если он открыт): event, fields — как в log(), t_ms — время строки. Сводку попытки считает RunJournal.
signal logged(event: String, fields: Dictionary, t_ms: int)

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


## Строка файла: `t=<мс> событие ключ=значение`.
static func line(event: String, fields: Dictionary, t_ms: int) -> String:
	return "t=%d %s" % [t_ms, format(event, fields)]


## Имя файла журнала по времени: `netrun-<дата-время>.log`.
static func file_name(t: Dictionary) -> String:
	return "netrun-%04d%02d%02d-%02d%02d%02d.log" % [t.year, t.month, t.day, t.hour, t.minute, t.second]


## Открывает новый файл `netrun-<дата-время>.log` в каталоге dir (по умолчанию user://logs, как на очках);
## `file_path` — явный путь (для тестов), тогда dir не нужен.
func open(file_path: String = "", dir: String = DIR) -> Error:
	if file_path.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
		file_path = dir.path_join(file_name(Time.get_datetime_dict_from_system()))
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
	var t_ms := Time.get_ticks_msec()
	var s := line(event, fields, t_ms)
	print("[netrun-log] ", s)
	if _file != null:
		_file.store_line(s)
		_file.flush()
	logged.emit(event, fields, t_ms)
	return s


## Журнал открыт: строки идут в файл.
func is_open() -> bool:
	return _file != null


func close() -> void:
	if _file != null:
		_file.close()
	_file = null


## Дописывает строку в конец закрытого журнала (ответы анкеты после конца забега). Пока файл открыт другим MbLog — не звать:
## его запись пойдёт поверх.
static func append(file_path: String, event: String, fields: Dictionary = {}) -> Error:
	var f := FileAccess.open(file_path, FileAccess.READ_WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.seek_end()
	f.store_line(line(event, fields, Time.get_ticks_msec()))
	f.close()
	return OK
