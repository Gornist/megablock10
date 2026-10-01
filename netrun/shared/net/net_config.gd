class_name NetConfig
extends RefCounted
## Настройки сети мира. Значения по умолчанию — здесь, переопределяются аргументами после `--`:
## --host=, --port=, --token=, --grace=, --beat= (секунды между сообщениями о состоянии очков), --tokens=токен:сессия,токен:сессия (только сервер, пока нет Моста).

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

var host: String = DEFAULT_HOST
var port: int = DEFAULT_PORT
var token: String = ""
var grace_sec: float = DEFAULT_GRACE_SEC
var beat_sec: float = DEFAULT_BEAT_SEC
## Номер терминала из токена `терминал:токен` («t03:секрет») или JSON; "" — токен без терминала (старый путь).
func terminal_id() -> String:
	return str(BridgeApi.parse_terminal_token(token).get("terminal", ""))


## Заглушка вместо Моста (F1/M5): токен -> сессия.
var tokens: Dictionary = {}


static func from_args(args: PackedStringArray) -> NetConfig:
	var c := NetConfig.new()
	for a in args:
		if a.begins_with("--host="):
			c.host = a.trim_prefix("--host=")
		elif a.begins_with("--port="):
			c.port = int(a.trim_prefix("--port="))
		elif a.begins_with("--token="):
			c.token = a.trim_prefix("--token=")
		elif a.begins_with("--grace="):
			c.grace_sec = float(a.trim_prefix("--grace="))
		elif a.begins_with("--beat="):
			c.beat_sec = maxf(float(a.trim_prefix("--beat=")), 0.1)
		elif a.begins_with("--tokens="):
			for pair in a.trim_prefix("--tokens=").split(",", false):
				var kv := pair.split(":", false)
				if kv.size() == 2:
					c.tokens[kv[0]] = kv[1]
	return c
