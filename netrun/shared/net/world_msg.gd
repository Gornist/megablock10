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
## Сервер -> клиент: снимок узла (раз в 0.1 с, без гарантий порядка доставки) и события (надёжно). В снимке: trace, level, ghost, cd, ice
## [{id, p, f, s, b}] и hunt — за этим игроком идёт охота Black ICE (клиент рисует порталы закрытыми, props/portal_locked).
const STATE := "state"
const EVENT := "ev"
## Сервер -> клиент: позиции ДРУГИХ аватаров своего узла (~20 раз/с, без гарантий): {t: av, k: время сервера, a: [[id, x, z], ...]}.
## id — короткий числовой id аватара (NetServer.avatar_id); пропавший из списка — вышел из узла. В `state` время сервера тоже в `k`.
const AVATARS := "av"
## Клиент -> сервер (P6): состояние очков раз в N секунд, от терминала с сессией и без неё (очки ждут игрока).
## {t: beat, term, bat?, chg?, fps, worst, rtt?}; разбор и пересылка в Мост — NetServer / TerminalBeatRelay.
const BEAT := "beat"
## Виды события: ended (выход: reason), daemon (ok, daemon, error), shard (id взят).
## Граф узлов (W1): node — вход в узел (title, tier, alert, shards [{id, p, ready, enc?}] (enc — зашифрованный шард, модель shard_encrypted), dead [[x, z]] (мёртвые деки в узле, необязательно),
## portals [{to, title, tier, p, open}], r — радиус
## портала, arrive [x, z] — куда поставить риг; нет arrive — игрок остаётся где стоит); tunnel — переход начался (to, title, tier,
## sec — сколько длится: клиент затемняет экран без движения камеры, затем придёт node); portal_denied — портал не открылся
## (to, reason: lockdown | hunt | busy | not_linked, left — секунд до конца локдауна); shards — слоты шардов узла изменились.
const EV_NODE := "node"
const EV_TUNNEL := "tunnel"
const EV_PORTAL_DENIED := "portal_denied"
const EV_SHARDS := "shards"
const EV_ENDED := "ended"
const EV_DAEMON := "daemon"
const REASON_FAR := "far"
const REASON_HELD := "held"
const REASON_UNKNOWN := "unknown"
## Слот шарда пуст: вынесен, ждёт пополнения (W1).
const REASON_EMPTY := "empty"


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
