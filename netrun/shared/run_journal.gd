class_name RunJournal
extends RefCounted
## Журнал попытки одиночной игры (docs/gamedesign/flat-playtest.md §2): своя папка `Документы\Мегаблок10\runs\<yyyyMMdd-HHmmss>-<сборка>\`
## на каждую попытку (учебная — тоже), внутри — тот же журнал клиента, что на очках (MbLog, `netrun-*.log`), плюс промахи прицела
## (`aim.miss`), итоговая строка `run.summary` и ответы анкеты (`survey.<вопрос> value=…`). Тестер шлёт папку одним zip.
## Папку открывает SoloStub; клиент узнаёт её из аргументов (client_args), сводку копит observe() по строкам журнала клиента.

## Подкаталог в «Документах» и папка попыток в нём.
const APP_DIR := "Мегаблок10"
const RUNS_DIR := "runs"
## Запасной базовый каталог: «Документы» недоступны на запись (или это не сборка для тестеров).
const FALLBACK_BASE := "user://runs"
## Явный базовый каталог (отладка, тесты): `--runs-dir=<путь>`.
const RUNS_DIR_ARG := "--runs-dir="
## Аргументы клиента одиночной игры: каталог журнала попытки и учебная ли она.
const DIR_ARG := "--journal-dir="
const TUTORIAL_ARG := "--journal-tutorial="
## Отказы телепорта по вине прицела (клиент и сервер): дальше досягаемости, вне комнаты, клетка занята или закрыта колонной,
## красная клетка не удержана 0,4 с. Перезарядка, тоннель и «уже сходил в этом такте» — не промах прицела.
const AIM_MISS_REASONS := [WorldMsg.REASON_FAR, WorldMsg.REASON_RANGE, WorldMsg.REASON_ROOM, WorldMsg.REASON_CELL, WorldMsg.REASON_BLOCKED, "hold"]
## Результат попытки, оборванной таймером `--exit-after=` (дымовой прогон).
const RESULT_EXIT_AFTER := "exit_after"
## Результат попытки, остановленной до конца забега (перезапуск из меню, закрытие окна).
const RESULT_STOPPED := "stopped"

## Папка попытки ("" — не открыта) и файл журнала клиента в ней (его путь сообщает SoloStub, когда клиент открыл журнал).
var dir := ""
var log_path := ""
var tutorial := false
var build := ""
var _start_ms := -1
var _node := ""
var _node_since_ms := -1
var _node_sec := {}   # узел -> секунды в нём (порядок — порядок входа)
var _alarm_peak := 0
var _trace_level_peak := 0
var _trace_peak := 0.0
var _breaches := 0
var _breaches_won := 0
var _shards := 0
var _aim_miss := 0


## Имя папки попытки: `yyyyMMdd-HHmmss-<сборка>`; сборка — только латиница, цифры, `-` и `_` (без `:` — Windows его не пускает в имя).
static func dir_name(t: Dictionary, build_: String) -> String:
	return "%04d%02d%02d-%02d%02d%02d-%s" % [t.year, t.month, t.day, t.hour, t.minute, t.second, safe_name(build_)]


static func safe_name(s: String) -> String:
	var out := RegEx.create_from_string("[^A-Za-z0-9_\\-]").sub(s, "_", true)
	return out if not out.is_empty() else "build"


## Желаемый базовый каталог: `--runs-dir=` из аргументов; в сборке для тестеров (метка solo) — «Документы»/Мегаблок10/runs;
## иначе (редактор, тесты, стенд) — запасной user://runs, чтобы прогоны разработки не сорили в «Документах».
static func preferred_base(args: PackedStringArray, documents: String, exported: bool) -> String:
	for a in args:
		if a.begins_with(RUNS_DIR_ARG) and a.length() > RUNS_DIR_ARG.length():
			return a.trim_prefix(RUNS_DIR_ARG)
	if exported and not documents.is_empty():
		return documents.path_join(APP_DIR).path_join(RUNS_DIR)
	return FALLBACK_BASE


## В каталог можно писать: создаём его и пробный файл.
static func writable(base: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(base) != OK and not DirAccess.dir_exists_absolute(base):
		return false
	var probe := base.path_join(".write_probe")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(probe)
	return true


## Базовый каталог для попыток: желаемый, если в него пишется, иначе запасной.
static func pick_base(preferred: String) -> String:
	if writable(preferred):
		return preferred
	push_warning("[netrun-journal] не пишется в %s, журнал попыток — в %s" % [preferred, FALLBACK_BASE])
	return FALLBACK_BASE


## Свободное имя папки: `name`, при повторе в ту же секунду (быстрый перезапуск) — `name-2`, `name-3`…
static func unique_dir(base: String, name: String) -> String:
	var p := base.path_join(name)
	var n := 2
	while DirAccess.dir_exists_absolute(p) and n < 100:
		p = base.path_join("%s-%d" % [name, n])
		n += 1
	return p


## Аргументы клиенту: где открыть журнал попытки и учебная ли она.
static func client_args(dir_: String, tutorial_: bool) -> PackedStringArray:
	return PackedStringArray([DIR_ARG + dir_, TUTORIAL_ARG + ("true" if tutorial_ else "false")])


## Из аргументов клиента: {dir, fields} — каталог журнала ("" — журнал очков, user://logs) и поля для строки `start`
## (build, solo, tutorial — только у одиночной игры).
static func client_options(args: PackedStringArray) -> Dictionary:
	var out := {"dir": "", "fields": {}}
	var tut := false
	for a in args:
		if a.begins_with(DIR_ARG):
			out["dir"] = a.trim_prefix(DIR_ARG)
		elif a.begins_with(TUTORIAL_ARG):
			tut = a.trim_prefix(TUTORIAL_ARG) == "true"
	if not str(out["dir"]).is_empty():
		out["fields"] = {"build": BuildInfo.BUILD, "solo": true, "tutorial": tut}
	return out


## Отказ телепорта — промах прицела (строка `aim.miss`).
static func is_aim_miss(reason: String) -> bool:
	return reason in AIM_MISS_REASONS


## Открыть папку новой попытки в base и обнулить сводку. t — дата-время для имени, start_ms — начало попытки (мс движка); по умолчанию — сейчас.
## Возвращает путь папки, "" — не создать.
func begin(base: String, build_: String, tutorial_: bool, t: Dictionary = {}, start_ms: int = -1) -> String:
	var when := t if not t.is_empty() else Time.get_datetime_dict_from_system()
	var p := unique_dir(base, dir_name(when, build_))
	if DirAccess.make_dir_recursive_absolute(p) != OK:
		push_warning("[netrun-journal] не создать папку попытки %s" % p)
		return ""
	dir = p
	log_path = ""
	build = build_
	tutorial = tutorial_
	_start_ms = start_ms if start_ms >= 0 else Time.get_ticks_msec()
	_node = ""
	_node_since_ms = -1
	_node_sec = {}
	_alarm_peak = 0
	_trace_level_peak = 0
	_trace_peak = 0.0
	_breaches = 0
	_breaches_won = 0
	_shards = 0
	_aim_miss = 0
	return p


## Строка журнала клиента (сигнал MbLog.logged): копит сводку попытки.
func observe(event: String, fields: Dictionary, t_ms: int) -> void:
	match event:
		"graph.node":
			_leave_node(t_ms)
			_node = str(fields.get("node", ""))
			_node_since_ms = t_ms
			if not _node_sec.has(_node):
				_node_sec[_node] = 0.0
		"alarm.level":
			_alarm_peak = maxi(_alarm_peak, int(fields.get("level", 0)))
		"trace.level":
			_trace_level_peak = maxi(_trace_level_peak, int(fields.get("level", 0)))
			_trace_peak = maxf(_trace_peak, float(fields.get("value", 0.0)))
		"breach.start":
			_breaches += 1
		"breach.end":
			if int(fields.get("opened", 0)) > 0:
				_breaches_won += 1
		"shard.stowed":
			_shards += 1
		"aim.miss":
			_aim_miss += 1


## Снимок узла: пик trace (строка `trace.level` пишется только при смене уровня — значение пика берём из снимков).
func observe_state(state: Dictionary) -> void:
	_trace_peak = maxf(_trace_peak, float(state.get("trace", 0.0)))
	_trace_level_peak = maxi(_trace_level_peak, int(state.get("level", 0)))


func _leave_node(t_ms: int) -> void:
	if not _node.is_empty() and _node_since_ms >= 0:
		_node_sec[_node] = float(_node_sec.get(_node, 0.0)) + maxf(t_ms - _node_since_ms, 0) / 1000.0
	_node_since_ms = t_ms


## Поля строки `run.summary`: результат (ExitLogic.REASON_* или exit_after), учебная ли, секунд всего, узлов пройдено и секунд на каждом
## (`node_00:12.3,node_03:40.1`), пик тревоги узла, пик уровня и значения trace, взломы (начато и открыто), шарды, поимки ICE, промахи прицела.
func summary(result: String, t_ms: int = -1) -> Dictionary:
	var now := t_ms if t_ms >= 0 else Time.get_ticks_msec()
	_leave_node(now)
	var per := PackedStringArray()
	for n: String in _node_sec:
		per.append("%s:%.1f" % [n, float(_node_sec[n])])
	return {"result": result, "tutorial": tutorial, "build": build, "sec": snappedf(maxf(now - _start_ms, 0) / 1000.0, 0.1),
		"nodes": _node_sec.size(), "node_sec": ",".join(per), "alarm_peak": _alarm_peak, "trace_level_peak": _trace_level_peak,
		"trace_peak": snappedf(_trace_peak, 0.1), "breaches": _breaches, "breaches_won": _breaches_won, "shards": _shards,
		"caught": 1 if result in [ExitLogic.REASON_EJECTED, ExitLogic.REASON_FLATLINE] else 0, "aim_miss": _aim_miss}


## Ответы анкеты (К5) — в журнал попытки: строка `survey.<вопрос> value=<ответ>` на каждый ответ, в порядке словаря.
## Журнал клиента к этому времени закрыт (конец забега) — строки дописываются в конец файла. Нет файла — ERR_FILE_NOT_FOUND.
func log_survey(answers: Dictionary) -> Error:
	if log_path.is_empty():
		return ERR_FILE_NOT_FOUND
	for q in answers:
		var err := MbLog.append(log_path, "survey." + str(q), {"value": answers[q]})
		if err != OK:
			return err
	return OK
