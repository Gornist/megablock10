class_name NetServer
extends Node
## Сетевая часть сервера мира: ENet, проверка токена в auth_callback, игрок = сессия (не peer id).
## Аватар — узел `node_07/avatar_<сессия>`; после обрыва живёт grace_sec и возвращается тому же игроку.

signal avatar_spawned(session: String)
signal avatar_removed(session: String)
signal session_joined(session: String, peer_id: int, resumed: bool)
signal session_lost(session: String)
## Выход из забега: {session, reason, under_hunt, deck_burned} (ExitLogic.build_event).
signal exit_event(event: Dictionary)
signal object_taken(object_id: String, session: String)
## Клиент просит применить демона / выйти чисто (решает узел: server/node/gray_node.gd).
signal daemon_requested(session: String, daemon_id: String)
signal leave_requested(session: String)
## Взлом хранилища (К3): клиент просит начать (vault — id слота, daemons — id выбранных демонов), нажал клетку ([строка, столбец]) или завершил досрочно.
## Решает узел (server/node/vault_breach.gd).
signal charge_requested(session: String, daemon_id: String)
signal decrypt_requested(session: String, item: String)
signal breach_open_requested(session: String, vault: String, daemon_ids: Array)
signal breach_tap_requested(session: String, cell: Array)
signal breach_cancel_requested(session: String)
## Игрок просит отдать предмет из ГРУЗа (to — как в WorldMsg.GIVE) и список получателей (К5б); решает GiveService.
signal give_requested(session: String, item_id: String, to: Dictionary)
signal give_list_requested(session: String)
## Состояние очков (P6) не чаще раза в период на терминал: {terminal, session ("" — очки без игрока), fps, worst, bat?, chg?, rtt?}.
signal beat_received(beat: Dictionary)
## Игрок телепортировался (принято сервером): откуда и куда. Задел под шум/trace от телепорта (RigMath.TELEPORT_TRACE, пока 0).
signal teleported(session: String, from: Vector3, to: Vector3)

## «Узел» сессии в цифровом тоннеле между узлами (W1): ни в одном узле, снимков и ICE нет, позиции от клиента не принимаются.
const TUNNEL_NODE := "~tunnel"
## Держатель опустевшего слота шарда (W1, пополнение): взять нельзя, пока слот не пополнится.
const EMPTY_HOLDER := "#empty"

## Тихий обрыв (Wi-Fi пропал) ENet по умолчанию замечает за десятки секунд; ужимаем до ~5 с.
const PEER_TIMEOUT_MS := 5000

## Поза тела (AvatarPose) приходит в `pos` в поле `b` ~20 раз/с. Чаще этого сервер её не принимает (защита от потока), а старше POSE_TTL_MS
## не пересылает: клиент замолчал — другим тело должно спрятаться (приёмник прячет его сам через 1,5 с без позы).
const POSE_MIN_GAP_MS := 30
const POSE_TTL_MS := 1000

var verifier: TokenVerifier
## Предел скорости аватара (м/с): позицию присылает клиент, сервер не даёт телепортироваться.
const MAX_SPEED := 8.0
## ENet при disconnect_peer сбрасывает неотправленную очередь: после последнего сообщения даём ему уйти.
const DISCONNECT_DELAY_SEC := 0.3
## Телепорт (VR): сервер не доверяет клиенту. Пределы — RigMath.TELEPORT_RANGE_LIMIT и TELEPORT_COOLDOWN_LIMIT (клиент по умолчанию
## ходит на 4,5 м раз в 1,2 с, настройка на очках не пускает за предел). Допуски: поза клиента запаздывает на пакет-другой, поэтому
## дальность считается с запасом, а перезарядка — с послаблением на дрожь сети.
const TELEPORT_RANGE_SLACK := 0.5
const TELEPORT_COOLDOWN_SLACK := 0.2
## Клетки 1 м: дальность прыжка считается от центра клетки аватара до центра цели (NodeGrid.REACH_M); запас на то, что аватар после
## площадки у хранилища и при запаздывании позы стоит не в центре клетки.
const TELEPORT_CELL_SLACK := 0.5

## Сетка клеток комнаты: цель телепорта привязывается к центру клетки и проверяется по занятости (колонны) и линии (NodeGrid).
var grid: NodeGrid = NodeGrid.for_layout()

## Узел может запретить взятие (далеко и т.п.): func(session, object_id) -> bool. Не задан — берётся откуда угодно.
var grab_check: Callable
## Узел может не пустить сессию: func(session) -> bool (false — отказ в auth: забег уже завершается, исход пишется в Мост).
var join_check: Callable
## Привязка телепорта к площадке у хранилища (К3): func(session, to: Vector3) -> Dictionary {p, look} (NodeLayout.snap_to_vault_pad по хранилищам узла игрока).
## Не задан — цель как пришла. Клиент делает то же сам (XRRig.teleport_snap), сервер повторяет: клиенту верить нельзя.
var teleport_snap: Callable
## Тактовый режим (docs/gamedesign/time-and-movement.md, Т4): func(session) -> bool — нетраннер уже сходил в этом такте. Задан — вместо
## перезарядки телепорта один ход за такт: второй отказывается с WorldMsg.REASON_MOVED. Не задан — прежняя перезарядка.
var move_check: Callable
## Узел входа для нового аватара (W1, граф узлов): func(терминал, сессия) -> id узла ("" — как по умолчанию). Не вызывается для
## вернувшегося после обрыва и для сессии, чей узел уже известен (восстановление после рестарта).
var entry_node_for: Callable
## Узел сессии из документа Моста (session.node), как пришёл при входе: сессия -> id узла. Граф берёт из него учебный узел.
var session_node_hint: Dictionary = {}
var grace_sec: float = NetConfig.DEFAULT_GRACE_SEC
var beat_sec: float = NetConfig.DEFAULT_BEAT_SEC

var _world: Node3D
var _pending: Dictionary = {}        # peer_id -> сессия ("" — терминал без сессии): токен принят, ждём конца аутентификации
var _pending_terminal: Dictionary = {}  # peer_id -> терминал из токена
var _peer_terminal: Dictionary = {}  # peer_id -> терминал (в том числе у «idle»-пиров без сессии и аватара)
var _beat_last_ms: Dictionary = {}   # терминал -> момент последнего принятого состояния (мс)
var _peer_session: Dictionary = {}   # peer_id -> сессия (после проверки)
var _session_peer: Dictionary = {}   # сессия -> peer_id (-1, пока на связи никого)
var _deadline_ms: Dictionary = {}    # сессия -> момент удаления аватара (мс)
var _under_hunt: Dictionary = {}     # сессия -> true, пока за ней охотится Black ICE (ставит охота снаружи)
var _objects: Dictionary = {}        # id объекта -> сессия, которая его держит ("" — лежит)
var _pos_time_ms: Dictionary = {}    # сессия -> момент последней принятой позиции (мс)
var _tp_last_ms: Dictionary = {}     # сессия -> момент последнего принятого телепорта игрока (мс); нет записи — не было
var _tp_count: Dictionary = {}       # сессия -> сколько раз аватар прыгнул (телепорт игрока или перенос сервером); другие по нему видят скачок
var _session_node: Dictionary = {}   # сессия -> id узла (нет записи — NetConfig.WORLD_NODE); снимки уходят только своему узлу
var _avatar_ids: Dictionary = {}     # сессия -> короткий числовой id аватара для других игроков (в сообщениях вместо длинной сессии)
var _next_avatar_id := 1
var _poses: Dictionary = {}          # сессия -> {b: проверенная и заново закодированная поза (AvatarPose.encode), ms: когда принята}
## Сколько байт полезной нагрузки ушло игроку через send_to (без служебных заголовков ENet): сессия -> байты, и всего.
var bytes_sent: Dictionary = {}
var bytes_sent_total := 0


static func avatar_name(session: String) -> String:
	return "avatar_" + session


func start(config: NetConfig, token_verifier: TokenVerifier) -> Error:
	verifier = token_verifier
	grace_sec = config.grace_sec
	beat_sec = config.beat_sec
	_world = Node3D.new()
	_world.name = NetConfig.WORLD_NODE
	add_child(_world)
	_add_object(NetConfig.PICKUP_ID, Vector3(0, 1.0, -1.5))
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_server(config.port, 32)
	if err != OK:
		push_error("[netrun-server] не открыть порт %d: %s" % [config.port, error_string(err)])
		return err
	var mp := multiplayer as SceneMultiplayer
	mp.auth_callback = _on_auth
	mp.auth_timeout = 5.0
	mp.multiplayer_peer = enet
	mp.peer_disconnected.connect(_on_peer_disconnected)
	mp.peer_connected.connect(_on_peer_connected)
	mp.peer_packet.connect(_on_packet)
	mp.peer_authentication_failed.connect(func(i):
		_pending.erase(i)
		_pending_terminal.erase(i))
	set_process(true)
	print("[netrun-server] ENet слушает порт ", config.port)
	return OK


func stop_net() -> void:
	multiplayer.multiplayer_peer = null


func has_avatar(session: String) -> bool:
	return _world.has_node(avatar_name(session))


func get_avatar(session: String) -> Node3D:
	return _world.get_node_or_null(avatar_name(session)) as Node3D


func peer_of(session: String) -> int:
	return int(_session_peer.get(session, -1))


## Охота ставит и снимает флаг снаружи (server/ice); здесь он только попадает в событие выхода.
func set_under_hunt(session: String, hunted: bool) -> void:
	if hunted:
		_under_hunt[session] = true
	else:
		_under_hunt.erase(session)


## Восстановление после перезапуска сервера мира (M5): Мост считает сессию active, а аватара и связи уже нет. Начинаем окно
## возврата как после обрыва: вернётся клиент — тот же забег, нет — по истечении выход connection_lost (run.finish emergency).
func expect_session(session: String) -> void:
	if has_avatar(session) or _session_peer.has(session):
		return  # игрок уже вернулся или окно уже идёт
	_session_peer[session] = -1
	_deadline_ms[session] = Time.get_ticks_msec() + int(grace_sec * 1000.0)
	print("[netrun-server] сессия ", session, " из Моста: ждём возврата игрока ", grace_sec, " с")


## Новый берущийся объект (шард узла графа). Уже есть — ничего не меняет.
func add_object(object_id: String, pos: Vector3) -> void:
	if not _objects.has(object_id):
		_add_object(object_id, pos)


func remove_object(object_id: String) -> void:
	var o := _world.get_node_or_null(object_id)
	if o != null:
		_world.remove_child(o)
		o.queue_free()
	_objects.erase(object_id)


## Слот пуст (шард вынесен, ждёт пополнения): взять нельзя, ответ клиенту — empty. Объект, который кто-то держит, не трогаем.
func lock_object(object_id: String) -> void:
	if _objects.has(object_id) and _objects[object_id] == "":
		_objects[object_id] = EMPTY_HOLDER


func unlock_object(object_id: String) -> void:
	if _objects.get(object_id) == EMPTY_HOLDER:
		_objects[object_id] = ""


func is_object_locked(object_id: String) -> bool:
	return _objects.get(object_id) == EMPTY_HOLDER


## Поставить аватар в точку (переход через портал): сервер двигает его сам, предел скорости не мешает следующим позициям клиента.
func teleport(session: String, pos: Vector3) -> void:
	var a := get_avatar(session)
	if a != null:
		a.position = NodeLayout.clamp_to_room(Vector3(pos.x, 0.0, pos.z))
		_pos_time_ms[session] = Time.get_ticks_msec()
		_tp_count[session] = teleport_count(session) + 1


## Сколько раз аватар прыгнул (телепорт игрока или перенос сервером). Растёт только; убранный аватар — 0.
func teleport_count(session: String) -> int:
	return int(_tp_count.get(session, 0))


## Запись аватара для других игроков (сообщение `av`): [id, x, z] и четвёртым — счётчик скачков, если аватар хоть раз прыгал.
## По счётчику клиент не плавит позицию между «до» и «после» прыжка (StateBuffer): телепорт не должен «ползти».
func avatar_entry(session: String) -> Array:
	var p := get_avatar(session).position
	var e: Array = [avatar_id(session), snappedf(p.x, 0.01), snappedf(p.z, 0.01)]
	var n := teleport_count(session)
	var b: Variant = pose_of(session)
	if n > 0 or b != null:
		e.append(n)
	if b != null:
		e.append(b)  # пятым — поза тела (WorldMsg.AVATARS)
	return e


## Свежая поза тела сессии (то, что уйдёт другим игрокам узла: проверенный и заново закодированный AvatarPose.encode) или null.
func pose_of(session: String) -> Variant:
	var rec: Variant = _poses.get(session)
	if rec == null or Time.get_ticks_msec() - int(rec["ms"]) > POSE_TTL_MS:
		return null
	return rec["b"]


## Объект (шард) уже у игрока по данным Моста. Не трогает объект, который держит кто-то другой.
func restore_holder(object_id: String, session: String) -> void:
	if _objects.has(object_id) and _objects[object_id] == "":
		_objects[object_id] = session


func holder_of(object_id: String) -> String:
	return str(_objects.get(object_id, ""))


## Переставить объект (шард узла); держит его кто-то или нет — не меняется.
func place_object(object_id: String, pos: Vector3) -> void:
	var o := _world.get_node_or_null(object_id) as Node3D
	if o != null:
		o.position = pos


func object_position(object_id: String) -> Vector3:
	var o := _world.get_node_or_null(object_id) as Node3D
	return o.position if o != null else Vector3.ZERO


## Узел игрока. Снимки и позиции чужих аватаров получают только сессии того же узла.
func node_of(session: String) -> String:
	return str(_session_node.get(session, NetConfig.WORLD_NODE))


func set_node(session: String, node_id: String) -> void:
	_session_node[session] = node_id


## Сессии с аватаром в этом узле.
func sessions_in(node_id: String) -> Array:
	return sessions().filter(func(s: String) -> bool: return node_of(s) == node_id)


## Короткий id аватара (0 — аватара нет). Не меняется, пока аватар жив, в том числе при возврате после обрыва.
func avatar_id(session: String) -> int:
	return int(_avatar_ids.get(session, 0))


## Сессия по короткому id аватара ("" — такого нет); id уходят клиентам в `av` и в списке получателей, настоящую сессию клиент не видит.
func session_of_avatar(id: int) -> String:
	if id <= 0:
		return ""
	for s in _avatar_ids:
		if int(_avatar_ids[s]) == id:
			return str(s)
	return ""


## Сессии с аватаром (в том числе в окне возврата).
func sessions() -> Array:
	var out: Array = []
	for a in _world.get_children():
		if str(a.name).begins_with("avatar_"):
			out.append(str(a.name).trim_prefix("avatar_"))
	return out


## Сообщение игроку; false — связи сейчас нет. Снимки — ненадёжно (старый не нужен), события — надёжно.
func send_to(session: String, data: PackedByteArray, reliable: bool = true) -> bool:
	var peer := peer_of(session)
	if peer == -1 or not peer in (multiplayer as SceneMultiplayer).get_peers():
		return false
	# Клиент уже попрощался, а ENet ещё держит его в списке: отправка даёт «Unable to send packet on channel 0, max channels: 0».
	var enet := (multiplayer as SceneMultiplayer).multiplayer_peer as ENetMultiplayerPeer
	var pp := enet.get_peer(peer) if enet != null else null
	if pp != null and pp.get_state() != ENetPacketPeer.STATE_CONNECTED:
		return false
	var mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	var ok := (multiplayer as SceneMultiplayer).send_bytes(data, peer, mode) == OK
	if ok:
		bytes_sent[session] = int(bytes_sent.get(session, 0)) + data.size()
		bytes_sent_total += data.size()
	return ok


## Серверный выход (чистый, выброс ICE, флэтлайн): игроку — сообщение с причиной, затем обычный выход.
func end_session(session: String, reason: String) -> void:
	if not has_avatar(session):
		return
	send_to(session, WorldMsg.encode_fields(WorldMsg.EVENT, {"kind": WorldMsg.EV_ENDED, "reason": reason}))
	_finish_exit(session, reason, DISCONNECT_DELAY_SEC)


func _add_object(object_id: String, pos: Vector3) -> void:
	var o := Node3D.new()
	o.name = object_id
	o.position = pos
	_world.add_child(o)
	_objects[object_id] = ""


## Клиент просит — сервер решает (grab) или исполняет выход (exit). Разбор — WorldMsg.
func _on_packet(peer_id: int, data: PackedByteArray) -> void:
	var session: String = _peer_session.get(peer_id, "")
	var msg := WorldMsg.decode(data)
	if msg.get("t", "") == WorldMsg.BEAT:
		_handle_beat(peer_id, session, msg)
		return
	if session.is_empty():
		return
	match msg.get("t", ""):
		WorldMsg.GRAB:
			_handle_grab(peer_id, session, str(msg.get("id", "")))
		WorldMsg.POS:
			_handle_pos(session, WorldMsg.decode_vec3(msg.get("p")))
			if msg.has("b"):
				_handle_pose(session, msg["b"])
		WorldMsg.TELEPORT:
			_handle_teleport(session, WorldMsg.decode_xz(msg.get("p")))
		WorldMsg.USE:
			daemon_requested.emit(session, str(msg.get("id", "")))
		WorldMsg.LEAVE:
			leave_requested.emit(session)
		WorldMsg.BK_OPEN:
			var ids: Variant = msg.get("daemons")
			breach_open_requested.emit(session, str(msg.get("vault", "")), (ids as Array).map(func(i): return str(i)) if ids is Array else [])
		WorldMsg.CHARGE:
			charge_requested.emit(session, str(msg.get("daemon", "")))
		WorldMsg.DECRYPT:
			decrypt_requested.emit(session, str(msg.get("item", "")))
		WorldMsg.BK_TAP:
			var cell: Variant = msg.get("cell")
			if cell is Array and (cell as Array).size() == 2 and (cell[0] is float or cell[0] is int) and (cell[1] is float or cell[1] is int):
				breach_tap_requested.emit(session, [int(cell[0]), int(cell[1])])
		WorldMsg.BK_CANCEL:
			breach_cancel_requested.emit(session)
		WorldMsg.GIVE:
			var to: Variant = msg.get("to")
			give_requested.emit(session, str(msg.get("item", "")), to if to is Dictionary else {})
		WorldMsg.GIVE_LIST:
			give_list_requested.emit(session)
		WorldMsg.EXIT:
			var reason := str(msg.get("reason", ""))
			if not ExitLogic.is_client_reason(reason):
				print("[netrun-server] сессия ", session, ": неизвестная причина выхода «", reason, "»")
				return
			_finish_exit(session, reason)


## Состояние очков. Терминал берётся из проверенного токена, а не из сообщения; чаще допустимого — отбрасывается.
func _handle_beat(peer_id: int, session: String, msg: Dictionary) -> void:
	var terminal: String = _peer_terminal.get(peer_id, "")
	if terminal.is_empty():
		return
	var now := Time.get_ticks_msec()
	if not BeatStats.due(now, int(_beat_last_ms.get(terminal, -1)), BeatStats.server_gap_ms(beat_sec)):
		return
	_beat_last_ms[terminal] = now
	var beat := {"terminal": terminal, "session": session, "fps": maxi(int(msg.get("fps", 0)), 0), "worst": maxi(int(msg.get("worst", 0)), 0)}
	if msg.get("bat") is float or msg.get("bat") is int:
		beat["bat"] = BeatStats.battery_pct(msg["bat"])
	if msg.get("chg") is bool:
		beat["chg"] = msg["chg"]
	if msg.get("rtt") is float or msg.get("rtt") is int:
		beat["rtt"] = maxi(int(msg["rtt"]), 0)
	beat_received.emit(beat)


## Позиция от клиента: не дальше, чем позволяет скорость за прошедшее время; без выхода из комнаты.
func _handle_pos(session: String, p: Variant) -> void:
	var a := get_avatar(session)
	if a == null or p == null or node_of(session) == TUNNEL_NODE:
		return
	var now := Time.get_ticks_msec()
	var dt := minf((now - int(_pos_time_ms.get(session, now))) / 1000.0, 1.0)
	_pos_time_ms[session] = now
	var target := NodeLayout.clamp_to_room(Vector3(p.x, 0.0, p.z))
	var allowed := MAX_SPEED * dt + 0.3
	var d := target - a.position
	if d.length() > allowed:
		target = a.position + d.normalized() * allowed
	a.position = target


## Поза тела из `pos`: проверка AvatarPose.decode (мусор, голова дальше 4 м, нулевой кватернион — отбрасывается, прежняя поза доживает до POSE_TTL_MS),
## не чаще POSE_MIN_GAP_MS. В цифровом тоннеле позы не принимаются. Хранится перекодированной: лишние поля клиента дальше сервера не уходят.
func _handle_pose(session: String, raw: Variant) -> void:
	if get_avatar(session) == null or node_of(session) == TUNNEL_NODE:
		return
	var now := Time.get_ticks_msec()
	if _poses.has(session) and now - int(_poses[session]["ms"]) < POSE_MIN_GAP_MS:
		return
	var pose := AvatarPose.decode(raw)
	if pose == null:
		return
	_poses[session] = {"b": pose.encode(), "ms": now}


## Телепорт по просьбе клиента (VR: движение только им). Правила — RigMath.teleport_verdict с пределами сервера и допусками:
## аватар не в тоннеле, цель в комнате и не дальше предела от текущей позиции аватара, с прошлого телепорта прошла перезарядка;
## затем цель привязывается к центру своей клетки 1 м и проверяется по клетке (_cell_verdict: занята / дальше 4,5 м / за колонной).
## Успех: аватар мгновенно в точке, база для предела скорости потока поз сбрасывается (иначе запоздавшая поза со старого места
## втянула бы аватар обратно), счётчик скачков растёт — другие игроки не плавят прыжок. Отказ: причина и позиция сервера клиенту.
func _handle_teleport(session: String, p: Variant) -> void:
	var a := get_avatar(session)
	if a == null or p == null:
		return
	var now := Time.get_ticks_msec()
	var since := (now - int(_tp_last_ms[session])) / 1000.0 if _tp_last_ms.has(session) else INF
	var to := Vector3(p.x, 0.0, p.z)
	var tick_rule := move_check.is_valid()
	var cooldown := 0.0 if tick_rule else RigMath.TELEPORT_COOLDOWN_LIMIT - TELEPORT_COOLDOWN_SLACK   # такты: перезарядки нет, ход один за такт
	var reason := RigMath.teleport_verdict(a.position, to, since, node_of(session) == TUNNEL_NODE,
		RigMath.TELEPORT_RANGE_LIMIT + TELEPORT_RANGE_SLACK, cooldown)
	if reason.is_empty() and tick_rule and bool(move_check.call(session)):
		reason = WorldMsg.REASON_MOVED
	if reason.is_empty():
		to = NodeGrid.center(NodeGrid.cell_of(to))   # прыжок — на центр клетки; площадка у хранилища переставит точку ниже
		reason = _cell_verdict(session, a.position, to)
	var cell := NodeGrid.cell_of(to)
	if not reason.is_empty():
		var left := RigMath.cooldown_left(since, RigMath.TELEPORT_COOLDOWN_LIMIT) if reason == WorldMsg.REASON_COOLDOWN else 0.0
		print("[netrun-server] teleport denied ", session, " reason=", reason, " from=%.1f,%.1f to=%.1f,%.1f cell=%d,%d" % [a.position.x, a.position.z, to.x, to.z, cell.x, cell.y])
		send_to(session, WorldMsg.encode_teleport_denied(reason, a.position, left))
		return
	var from := a.position
	if teleport_snap.is_valid():
		to = (teleport_snap.call(session, to) as Dictionary)["p"]
	teleport(session, to)
	_tp_last_ms[session] = now
	print("[netrun-server] teleport ok ", session, " from=%.1f,%.1f to=%.1f,%.1f dist=%.1f cell=%d,%d" % [from.x, from.z, a.position.x, a.position.z, NodeLayout.flat_distance(from, a.position), cell.x, cell.y])
	teleported.emit(session, from, a.position)


## Проверка клетки цели (to — уже центр клетки): "" — можно; REASON_CELL — занята колонной, вне комнаты или в ней стоит другой аватар
## этого узла; REASON_RANGE — дальше NodeGrid.REACH_M (+ TELEPORT_CELL_SLACK) от центра клетки аватара; REASON_BLOCKED — линия закрыта.
func _cell_verdict(session: String, from: Vector3, to: Vector3) -> String:
	var b := NodeGrid.cell_of(to)
	if grid.is_occupied(b):
		return WorldMsg.REASON_CELL
	var a := NodeGrid.cell_of(from)
	if Vector2(b - a).length() * NodeGrid.CELL_M > NodeGrid.REACH_M + TELEPORT_CELL_SLACK:
		return WorldMsg.REASON_RANGE
	if not grid.line_clear(a, b):
		return WorldMsg.REASON_BLOCKED
	for other: String in sessions_in(node_of(session)):
		var av := get_avatar(other)
		if other != session and av != null and NodeGrid.cell_of(av.position) == b:
			return WorldMsg.REASON_CELL
	return ""


## Объект берётся, только если лежит (или уже у этого игрока).
func _handle_grab(peer_id: int, session: String, id: String) -> void:
	var reply: PackedByteArray
	if not _objects.has(id):
		reply = WorldMsg.encode(WorldMsg.GRAB_NO, id, {"reason": WorldMsg.REASON_UNKNOWN})
	elif _objects[id] == EMPTY_HOLDER:
		reply = WorldMsg.encode(WorldMsg.GRAB_NO, id, {"reason": WorldMsg.REASON_EMPTY})
	elif _objects[id] != "" and _objects[id] != session:
		reply = WorldMsg.encode(WorldMsg.GRAB_NO, id, {"reason": WorldMsg.REASON_HELD})
	elif grab_check.is_valid() and not grab_check.call(session, id):
		reply = WorldMsg.encode(WorldMsg.GRAB_NO, id, {"reason": WorldMsg.REASON_FAR})
	else:
		_objects[id] = session
		reply = WorldMsg.encode(WorldMsg.GRAB_OK, id)
		print("[netrun-server] ", session, " взял ", id)
		object_taken.emit(id, session)
	(multiplayer as SceneMultiplayer).send_bytes(reply, peer_id, MultiplayerPeer.TRANSFER_MODE_RELIABLE)


## Выход: событие, затем аватар убирается, связь закрывается. Обрыв сюда не попадает до конца окна возврата.
func _finish_exit(session: String, reason: String, disconnect_delay: float = 0.0) -> void:
	var ev := ExitLogic.build_event(session, reason, _under_hunt.has(session))
	_under_hunt.erase(session)
	_deadline_ms.erase(session)
	_pos_time_ms.erase(session)
	_session_node.erase(session)
	var peer := peer_of(session)
	_session_peer.erase(session)
	if peer != -1:
		_peer_session.erase(peer)
	_remove_avatar(session)
	var deck_note := ExitLogic.deck_note(ev)
	print("[netrun-server] выход ", session, ": ", reason, ", " + deck_note if not deck_note.is_empty() else "")
	exit_event.emit(ev)
	if peer == -1:
		return
	if disconnect_delay > 0.0:
		await get_tree().create_timer(disconnect_delay).timeout
	var mp := multiplayer as SceneMultiplayer
	if mp.multiplayer_peer != null and peer in mp.get_peers():
		mp.disconnect_peer(peer)


func _remove_avatar(session: String) -> void:
	for id in _objects:
		if _objects[id] == session:
			_objects[id] = ""  # аватара нет — объект снова лежит
	_avatar_ids.erase(session)
	_poses.erase(session)
	_tp_count.erase(session)
	_tp_last_ms.erase(session)
	var a := get_avatar(session)
	if a != null:
		_world.remove_child(a)
		a.queue_free()
		avatar_removed.emit(session)


func _on_auth(peer_id: int, data: PackedByteArray) -> void:
	var mp := multiplayer as SceneMultiplayer
	# Настоящий Мост отвечает по сети: верификатор может быть сопрограммой (BridgeApi.verify_async).
	@warning_ignore("redundant_await")
	var who: Dictionary = await verifier.verify_terminal_async(data.get_string_from_utf8())
	var session: String = who["session"]
	var terminal: String = who["terminal"]
	# Терминал без сессии (очки ждут игрока, P6) пускаем «idle»: на связи ради состояния, аватара нет.
	var idle := session.is_empty() and not terminal.is_empty()
	if (session.is_empty() and not idle) or (not session.is_empty() and not session.is_valid_identifier()):
		print("[netrun-server] отказ peer ", peer_id, ": токен не принят")
		mp.disconnect_peer(peer_id)
		return
	if not session.is_empty() and join_check.is_valid() and not join_check.call(session):
		print("[netrun-server] отказ peer ", peer_id, ": сессия ", session, " завершается")
		mp.disconnect_peer(peer_id)
		return
	_pending[peer_id] = session
	_pending_terminal[peer_id] = terminal
	if not session.is_empty() and not str(who.get("node", "")).is_empty():
		session_node_hint[session] = str(who["node"])
	mp.send_auth(peer_id, "ok".to_utf8_buffer())
	mp.complete_auth(peer_id)


## Аутентификация закончена с обеих сторон — только теперь игрок на связи, аватар создаётся или возвращается.
func _on_peer_connected(peer_id: int) -> void:
	var enet := (multiplayer as SceneMultiplayer).multiplayer_peer as ENetMultiplayerPeer
	var pp := enet.get_peer(peer_id) if enet != null else null
	if pp != null:
		pp.set_timeout(PEER_TIMEOUT_MS, PEER_TIMEOUT_MS, PEER_TIMEOUT_MS)
	if not _pending.has(peer_id):
		return
	var session: String = _pending[peer_id]
	var terminal: String = _pending_terminal.get(peer_id, "")
	_pending.erase(peer_id)
	_pending_terminal.erase(peer_id)
	if not terminal.is_empty():
		_peer_terminal[peer_id] = terminal
	if session.is_empty():
		print("[netrun-server] терминал ", terminal, " peer ", peer_id, " без сессии (ждёт игрока)")
		return
	# Та же сессия уже на связи (обрыв ещё не замечен) — старое соединение вытесняется.
	var old := peer_of(session)
	if old != -1 and old != peer_id:
		_peer_session.erase(old)
		(multiplayer as SceneMultiplayer).disconnect_peer(old)
	_peer_session[peer_id] = session
	var resumed := has_avatar(session)
	_session_peer[session] = peer_id
	_deadline_ms.erase(session)
	if not resumed and entry_node_for.is_valid() and not _session_node.has(session):
		var entry := str(entry_node_for.call(terminal, session))
		if not entry.is_empty():
			_session_node[session] = entry
	if not resumed:
		var a := Node3D.new()
		a.name = avatar_name(session)
		a.position = NodeLayout.SPAWN  # клиент ставит риг в ту же точку; иначе первые позиции упрутся в предел скорости
		_world.add_child(a)
		_avatar_ids[session] = _next_avatar_id
		_next_avatar_id += 1
		avatar_spawned.emit(session)
	print("[netrun-server] сессия ", session, " peer ", peer_id, " (вернулась)" if resumed else " (новый аватар)")
	session_joined.emit(session, peer_id, resumed)


func _on_peer_disconnected(peer_id: int) -> void:
	_peer_terminal.erase(peer_id)
	_pending.erase(peer_id)
	_pending_terminal.erase(peer_id)
	if not _peer_session.has(peer_id):
		return
	var session: String = _peer_session[peer_id]
	_peer_session.erase(peer_id)
	if peer_of(session) != peer_id:
		return
	_session_peer[session] = -1
	_deadline_ms[session] = Time.get_ticks_msec() + int(grace_sec * 1000.0)
	print("[netrun-server] сессия ", session, " оборвалась, аватар ждёт ", grace_sec, " с")
	session_lost.emit(session)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for session in _deadline_ms.keys():
		if now >= _deadline_ms[session]:
			print("[netrun-server] аватар ", session, " убран по таймеру")
			_finish_exit(session, ExitLogic.REASON_CONNECTION_LOST)
