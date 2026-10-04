class_name NetConfig
extends RefCounted
## Настройки сети мира. Значения по умолчанию — здесь, переопределяются аргументами после `--`:
## --host=, --port=, --token=, --grace=, --beat= (секунды между сообщениями о состоянии очков), --tokens=токен:сессия,токен:сессия (только сервер, пока нет Моста).
##
## Клиент очков берёт адрес и токен ещё и из необязательного файла netrun.cfg (`from_sources`): без пересборки APK, на очках у каждого
## свой токен. Ищется по порядку `default_paths()`, берётся первый прочитанный; аргументы (--host=, --port=, --token=) перекрывают поля файла.
## Кладёт файл `tools/pico.sh provision` (adb push во внешний каталог приложения — работает в любой сборке, не только отладочной).
##
## [net]
## host = "10.10.0.10"       ; адрес сервера мира
## port = 7777               ; необязательно
## token = "t03:секрет"      ; «терминал:токен», как в --token=

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 7777
## Сколько секунд аватар остаётся в мире после обрыва (docs/netrun.md: обрыв ≠ смерть).
const DEFAULT_GRACE_SEC := 20.0
## Узел мира, в котором появляются аватары (один мир, узлы разнесены в пространстве).
const WORLD_NODE := "node_07"
## Единственный берущийся объект прототипа (V3).
const PICKUP_ID := "pickup_01"
## Раз в сколько секунд очки сообщают состояние (P6).
const DEFAULT_BEAT_SEC := 5.0
## Файл настроек сети клиента (необязателен): имя, секция.
const FILE_NAME := "netrun.cfg"
const FILE_SECTION := "net"
## Внешний каталог приложения на очках: туда `adb push` пишет в любой сборке, приложение читает без разрешений. Идентификатор пакета —
## из export_presets.cfg (package/unique_name), сторож — tests/netrun_config_test.gd. Android удаляет каталог вместе с приложением
## (`adb uninstall`): после переустановки файл кладут заново.
const EXTERNAL_DIR := "/sdcard/Android/data/com.megablok10.netrun/files"
## Вместо значения токена в журнале.
const REDACTED := "<скрыт>"

var host: String = DEFAULT_HOST
var port: int = DEFAULT_PORT
var token: String = ""
var grace_sec: float = DEFAULT_GRACE_SEC
var beat_sec: float = DEFAULT_BEAT_SEC
## Откуда прочитан файл настроек ("" — файла не было).
var file_path: String = ""
## Что в файле не так (по строке; значения токена сюда не попадают) — клиент пишет в журнал `net.config.warn`.
var warnings: Array[String] = []

## Номер терминала из токена `терминал:токен` («t03:секрет») или JSON; "" — токен без терминала (старый путь).
func terminal_id() -> String:
	return str(parse_terminal_token(token).get("terminal", ""))


## Токен, который очки кладут в auth: JSON {"terminal","token"} или «терминал:токен». Возвращает {terminal, token} или {}.
## Живёт в shared/, а не в server/bridge (BridgeApi зовёт отсюда): server/ в APK очков не входит.
static func parse_terminal_token(raw: String) -> Dictionary:
	var t := raw.strip_edges()
	if t.begins_with("{"):
		var parsed: Variant = JSON.parse_string(t)
		if parsed is Dictionary and parsed.has("terminal") and parsed.has("token"):
			return {"terminal": str(parsed["terminal"]), "token": str(parsed["token"])}
		return {}
	var i := t.find(":")
	if i <= 0 or i == t.length() - 1:
		return {}
	return {"terminal": t.substr(0, i), "token": t.substr(i + 1)}


## Заглушка вместо Моста (F1/M5): токен -> сессия.
var tokens: Dictionary = {}


static func from_args(args: PackedStringArray) -> NetConfig:
	var c := NetConfig.new()
	c._apply_args(args)
	return c


## Где искать netrun.cfg: внешний каталог приложения (adb push), затем user:// (run-as в отладочной сборке; ПК).
static func default_paths() -> PackedStringArray:
	return PackedStringArray([EXTERNAL_DIR.path_join(FILE_NAME), "user://" + FILE_NAME])


## Настройки клиента: значения по умолчанию, поверх них первый прочитанный файл из paths, поверх файла — аргументы.
## Нет файла — не ошибка; файл не читается или поле неверно — предупреждение в `warnings`, поле остаётся прежним.
static func from_sources(args: PackedStringArray, paths: PackedStringArray = default_paths()) -> NetConfig:
	var c := NetConfig.new()
	for p in paths:
		if not FileAccess.file_exists(p):
			continue
		var cf := ConfigFile.new()
		var err := cf.load(p)
		if err != OK:
			c.warnings.append("файл %s не читается (%s)" % [p, error_string(err)])
			continue
		c.file_path = p
		c._apply_file(cf, p)
		break
	c._apply_args(args)
	return c


## Аргументы для журнала: значения токенов скрыты (`--token=`, `--tokens=`).
static func redact_args(args: PackedStringArray) -> String:
	var out: Array[String] = []
	for a in args:
		if a.begins_with("--token=") or a.begins_with("--tokens="):
			out.append(a.get_slice("=", 0) + "=" + REDACTED)
		else:
			out.append(a)
	return " ".join(out)


## Поля строки журнала `net.config …` (MbLog): откуда настройки, куда идём, какой терминал. Сам токен — никогда.
func log_fields() -> Dictionary:
	return {
		"file": file_path if not file_path.is_empty() else "none",
		"host": host, "port": port,
		"terminal": terminal_id(),
		"token": "set" if not token.is_empty() else "none",
	}


func _apply_file(cf: ConfigFile, path: String) -> void:
	if not cf.has_section(FILE_SECTION):
		warnings.append("%s: нет секции [%s]" % [path, FILE_SECTION])
		return
	for key in cf.get_section_keys(FILE_SECTION):
		var v: Variant = cf.get_value(FILE_SECTION, key)
		match key:
			"host":
				if v is String and not (v as String).strip_edges().is_empty():
					host = (v as String).strip_edges()
				else:
					warnings.append("host: нужна непустая строка — оставлено %s" % host)
			"port":
				var n := -1
				if v is int:
					n = v
				elif v is String and (v as String).is_valid_int():
					n = (v as String).to_int()
				if n >= 1 and n <= 65535:
					port = n
				else:
					warnings.append("port: нужно целое 1…65535 — оставлено %d" % port)
			"token":
				if v is String and not (v as String).strip_edges().is_empty():
					token = (v as String).strip_edges()
				else:
					warnings.append("token: нужна непустая строка — оставлено прежнее")
			_:
				warnings.append("неизвестный ключ «%s»: пропущен" % key)


func _apply_args(args: PackedStringArray) -> void:
	for a in args:
		if a.begins_with("--host="):
			host = a.trim_prefix("--host=")
		elif a.begins_with("--port="):
			port = int(a.trim_prefix("--port="))
		elif a.begins_with("--token="):
			token = a.trim_prefix("--token=")
		elif a.begins_with("--grace="):
			grace_sec = float(a.trim_prefix("--grace="))
		elif a.begins_with("--beat="):
			beat_sec = maxf(float(a.trim_prefix("--beat=")), 0.1)
		elif a.begins_with("--tokens="):
			for pair in a.trim_prefix("--tokens=").split(",", false):
				var kv := pair.split(":", false)
				if kv.size() == 2:
					tokens[kv[0]] = kv[1]
