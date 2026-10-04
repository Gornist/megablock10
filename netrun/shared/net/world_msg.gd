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
## Сервер -> клиент: позиции ДРУГИХ аватаров своего узла (~20 раз/с, без гарантий): {t: av, k: время сервера, a: [[id, x, z, n?], ...]}.
## id — короткий числовой id аватара (NetServer.avatar_id); пропавший из списка — вышел из узла. n — счётчик скачков (телепортов)
## аватара, есть, только если он прыгал или есть поза: между записями с разным n клиент позицию не плавит (StateBuffer). В `state` время сервера тоже в `k`.
## Пятым — поза тела b = AvatarPose.encode() (голова и руки от точки пола (x, 0, z) записи), если свежая поза от клиента есть; нет — записи из трёх-четырёх полей.
## Клиент присылает позу в `pos` (поле `b`), сервер проверяет (AvatarPose.decode) и пересылает только игрокам того же узла, самому владельцу — нет.
const AVATARS := "av"
## Клиент -> сервер (P6): состояние очков раз в N секунд, от терминала с сессией и без неё (очки ждут игрока).
## {t: beat, term, bat?, chg?, fps, worst, rtt?}; разбор и пересылка в Мост — NetServer / TerminalBeatRelay.
const BEAT := "beat"
## Виды события: ended (выход: reason), daemon (ok, daemon, error), shard (id взят).
## Граф узлов (W1): node — вход в узел (title, tier, alert, shards [{id, p, ready, enc?, kind? (shard | daemon), dead? (демон мёртвой деки)}] (enc — зашифрованный шард, модель shard_encrypted), dead [[x, z]] (мёртвые деки рядом с хранилищем демона погибшего, необязательно),
## portals [{to, title, tier, p, open}], r — радиус
## портала, arrive [x, z] — куда поставить риг; нет arrive — игрок остаётся где стоит); tunnel — переход начался (to, title, tier,
## sec — сколько длится: клиент затемняет экран без движения камеры, затем придёт node); portal_denied — портал не открылся
## (to, reason: lockdown | hunt | busy | not_linked, left — секунд до конца локдауна); shards — слоты шардов узла изменились.
const EV_NODE := "node"
const EV_TUNNEL := "tunnel"
const EV_PORTAL_DENIED := "portal_denied"
const EV_SHARDS := "shards"
## deck — дека для вкладок ДЕКА и ДОБЫЧА (шлётся при входе игрока в узел и при изменении груза): ram (ёмкость в ячейках), ram_default (true — Мост
## ёмкость не прислал, показано значение по умолчанию), used (занято ячейками рабочих демонов), daemons [{id, name, effect, tier, cells [коды],
## prot, loaded, unsupported?}] (рабочие — принесённые с телефона; unsupported — причина, почему эффект в Сети не работает),
## loot [{id, kind: shard | daemon, tier, title, enc}] (enc — зашифрован), eddies (эдди в грузе). Состояние демонов во времени — в `state.cd`:
## {id, name, left, st: ready | cooldown | active | unsupported, until} (until — время сервера `k`, когда состояние кончится).
const EV_DECK := "deck"
## Взлом хранилища на панели (К3, docs/netrun-deck-design.md §6.1). Клиент -> сервер: bk_open {vault: id слота, daemons: [id рабочих демонов]} — начать,
## bk_tap {cell: [строка, столбец]} — выбрать клетку, bk_cancel — завершить досрочно (итог по собранному). Сервер -> клиент (события):
##   bk — попытка началась: {mode, vault, n, tier, grid: {size, cells, traps (только мёртвые — порченые не выдаём), dead_marker}, targets [{id, name, effect, cells}],
##        buffer, sec, ice (реплика INTRO)};
##   bk_tick — {cell?: [r, c], ok?, trap?, matched [id], left, ice?} на каждый принятый или отклонённый тап и раз в секунду без cell;
##   bk_end — {outcome, matched, eddies, opened [слоты], alert (строка), cooldown, early?, error?};
##   bk_no — {reason (busy | far | empty | cooldown | open | bad_daemons | tutorial | active | not_ready | bridge), left?}: взлом не начат.
const EV_BK := "bk"
const EV_BK_TICK := "bk_tick"
const EV_BK_END := "bk_end"
const EV_BK_NO := "bk_no"
const BK_OPEN := "bk_open"
const BK_TAP := "bk_tap"
const BK_CANCEL := "bk_cancel"
## Отправка добычи другому игроку (К5б). Клиент -> сервер: {t: give, item, to: {runner: id аватара} | {phone: ключ контакта}} — отдать шард или демона
## из ГРУЗа; {t: give_list} — запросить получателей. Решает сервер (проверки в GiveService, ценности двигает Мост: op.give_item).
## Сервер -> клиент: give_list {runners: [{id, name, same}]} (нетраннеры в Сети; same — в том же узле) и give {dir: out | in, ok, item, title, via:
## runner | phone, who?, error?}: out — исход отправителю (ok false — error из GIVE_ERRORS), in — получателю-нетраннеру, что у него в ГРУЗе новый
## предмет (from — позывной отправителя, tier, kind).
const GIVE := "give"
const GIVE_LIST := "give_list"
const EV_GIVE := "give"
const EV_GIVE_LIST := "give_list"
const GIVE_OUT := "out"
const GIVE_IN := "in"
const VIA_RUNNER := "runner"
const VIA_PHONE := "phone"
## Причины отказа отправки (поле error события give): не груз (защищённый, рабочий, чужой), нет такого получателя, нельзя себе, контакт не разбирается,
## предмет уже не в деке, идёт исход (свой или получателя), Мост отказал, нет связи с Мостом, Моста нет.
const GIVE_NOT_LOOT := "not_loot"
const GIVE_NO_RECIPIENT := "no_recipient"
const GIVE_SELF := "self"
const GIVE_BAD_CONTACT := "bad_contact"
const GIVE_GONE := "gone"
const GIVE_BUSY := "busy"
const GIVE_REFUSED := "refused"
const GIVE_UNAVAILABLE := "unavailable"
const GIVE_NO_BRIDGE := "no_bridge"
const GIVE_ERRORS: PackedStringArray = [GIVE_NOT_LOOT, GIVE_NO_RECIPIENT, GIVE_SELF, GIVE_BAD_CONTACT, GIVE_GONE, GIVE_BUSY, GIVE_REFUSED, GIVE_UNAVAILABLE, GIVE_NO_BRIDGE]
## Заряд защитного демона на запястье (К6, design §3.3). Клиент -> сервер: charge {daemon: id рабочего демона} — начать мини-игру заряда (режим
## for_charge: цепочка демона, буфер = длина + 2, ловушек нет); дальше те же bk_tap и bk_cancel, что у взлома. Сервер -> клиент: те же события
## bk / bk_tick / bk_end / bk_no с mode = "charge" (bk_end: {outcome, daemon, charged, early?}; bk_no: {reason: active | cooldown | charged | not_chargeable |
## bad_daemon | not_ready, left?}). Заряженный демон в `state.cd` имеет st = "charged"; запуск — прежнее `use` (без заряда: daemon {ok: false, error: not_charged}).
const CHARGE := "charge"
const MODE_CHARGE := "charge"
## Расшифровка шарда на запястье (К7, design §3.1, Мост — 6.8). Клиент -> сервер: decrypt {item: id шарда в ГРУЗе} — начать мини-игру (режим for_decrypt: цепочка
## шифр-замка по тиру шарда, буфер = цепочка + 2, ловушек нет; нужен рабочий DECRYPT тира не ниже тира шарда); дальше те же bk_tap и bk_cancel. Сервер -> клиент: те же
## bk / bk_tick / bk_end / bk_no с mode = "decrypt" (bk: item, title; bk_end: {outcome, item, title, decrypted, early?, error?}; bk_no: {reason: not_ready | active |
## no_bridge | gone | not_shard | open | no_decrypter}). После успеха сервер присылает свежий ev deck: шард в ГРУЗе уже «ОТКРЫТ».
const DECRYPT := "decrypt"
const MODE_DECRYPT := "decrypt"
const EV_ENDED := "ended"
const EV_DAEMON := "daemon"
## Телепорт (VR: движение только им). Клиент -> сервер: {t: tp, p: [x, z]} — цель на полу; решает сервер. Успех ответа не имеет
## (аватар просто на месте, остальные видят скачок по счётчику в `av`); отказ — {t: tp_no, reason, p: [x, z], left}: позиция аватара
## на сервере (клиент возвращает туда риг) и сколько секунд перезарядки осталось.
const TELEPORT := "tp"
const TELEPORT_NO := "tp_no"
const REASON_FAR := "far"
## Причины отказа телепорта (RigMath.teleport_verdict): дальше предела, не прошла перезарядка, идёт цифровой тоннель, цель вне комнаты.
const REASON_RANGE := "range"
const REASON_COOLDOWN := "cooldown"
const REASON_TUNNEL := "tunnel"
const REASON_ROOM := "room"
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


## Позиция; с позой тела (AvatarPose, поле `b`) — одним пакетом ~20 раз/с: отдельного сообщения не нужно, голова и руки едут вместе с точкой пола.
static func encode_pos(p: Vector3, pose: AvatarPose = null) -> PackedByteArray:
	var f := {"p": [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]}
	if pose != null:
		f["b"] = pose.encode()
	return encode_fields(POS, f)


## Просьба телепортироваться: цель на полу [x, z].
static func encode_teleport(p: Vector3) -> PackedByteArray:
	return encode_fields(TELEPORT, {"p": [snappedf(p.x, 0.001), snappedf(p.z, 0.001)]})


## Отказ: причина, позиция аватара на сервере (куда вернуть риг) и сколько секунд перезарядки осталось.
static func encode_teleport_denied(reason: String, pos: Vector3, left: float) -> PackedByteArray:
	return encode_fields(TELEPORT_NO, {"reason": reason, "p": [snappedf(pos.x, 0.001), snappedf(pos.z, 0.001)], "left": snappedf(left, 0.01)})


## [x, z] -> Vector3(x, 0, z); не пара чисел — null.
static func decode_xz(v: Variant) -> Variant:
	if v is Array and v.size() == 2 and (v[0] is float or v[0] is int) and (v[1] is float or v[1] is int):
		var x := float(v[0])
		var z := float(v[1])
		if is_finite(x) and is_finite(z):
			return Vector3(x, 0.0, z)
	return null


static func decode_vec3(v: Variant) -> Variant:
	if v is Array and v.size() == 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return null
