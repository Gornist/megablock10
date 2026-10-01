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
## Узел (N7). Клиент -> сервер: позиция, применить демона, выйти чисто (на площадке выхода).
const POS := "pos"
const USE := "use"
const LEAVE := "leave"
## Сервер -> клиент: снимок узла (раз в 0.1 с, без гарантий порядка доставки) и события (надёжно).
const STATE := "state"
const EVENT := "ev"
## Сервер -> клиент: позиции ДРУГИХ аватаров своего узла (~20 раз/с, без гарантий): {t: av, k: время сервера, a: [[id, x, z], ...]}.
## id — короткий числовой id аватара (NetServer.avatar_id); пропавший из списка — вышел из узла. В `state` время сервера тоже в `k`.
const AVATARS := "av"
## Клиент -> сервер (P6): состояние очков раз в N секунд, от терминала с сессией и без неё (очки ждут игрока).
## {t: beat, term, bat?, chg?, fps, worst, rtt?}; разбор и пересылка в Мост — NetServer / TerminalBeatRelay.
const BEAT := "beat"
## Виды события: ended (выход: reason), daemon (ok, daemon, error), shard (id взят).
const EV_ENDED := "ended"
const EV_DAEMON := "daemon"
const REASON_FAR := "far"
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


## Произвольное сообщение: {t, ...поля}.
static func encode_fields(type: String, fields: Dictionary = {}) -> PackedByteArray:
	var d := {"t": type}
	d.merge(fields)
	return JSON.stringify(d).to_utf8_buffer()


static func encode_pos(p: Vector3) -> PackedByteArray:
	return encode_fields(POS, {"p": [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]})


static func decode_vec3(v: Variant) -> Variant:
	if v is Array and v.size() == 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return null
