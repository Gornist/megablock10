class_name WorldMsg
extends RefCounted
## Сообщения клиент <-> сервер мира поверх SceneMultiplayer.send_bytes (JSON, UTF-8).
## Не RPC: RPC требуют одинаковых путей узлов на обеих сторонах, а у сервера и клиента разные сцены.
## Клиент только просит (`grab`), решает сервер (`grab_ok` / `grab_no`).

const GRAB := "grab"
const GRAB_OK := "grab_ok"
const GRAB_NO := "grab_no"
## Экстренный выход (N6): {t: exit, reason}; id нет.
const EXIT := "exit"
const REASON_HELD := "held"
const REASON_UNKNOWN := "unknown"


static func encode(type: String, id: String, extra: Dictionary = {}) -> PackedByteArray:
	var d := {"t": type, "id": id}
	d.merge(extra)
	return JSON.stringify(d).to_utf8_buffer()


static func encode_exit(reason: String) -> PackedByteArray:
	return JSON.stringify({"t": EXIT, "reason": reason}).to_utf8_buffer()


## Пустой словарь — мусор или чужой формат.
static func decode(data: PackedByteArray) -> Dictionary:
	var v: Variant = JSON.parse_string(data.get_string_from_utf8())
	if v is Dictionary and v.has("t"):
		return v
	return {}
