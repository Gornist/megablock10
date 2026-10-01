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

## Тихий обрыв (Wi-Fi пропал) ENet по умолчанию замечает за десятки секунд; ужимаем до ~5 с.
const PEER_TIMEOUT_MS := 5000

var verifier: TokenVerifier
## Предел скорости аватара (м/с): позицию присылает клиент, сервер не даёт телепортироваться.
const MAX_SPEED := 8.0
## ENet при disconnect_peer сбрасывает неотправленную очередь: после последнего сообщения даём ему уйти.
const DISCONNECT_DELAY_SEC := 0.3

## Узел может запретить взятие (далеко и т.п.): func(session, object_id) -> bool. Не задан — берётся откуда угодно.
var grab_check: Callable
var grace_sec: float = NetConfig.DEFAULT_GRACE_SEC

var _world: Node3D
var _pending: Dictionary = {}        # peer_id -> сессия: токен принят, ждём конца аутентификации
var _peer_session: Dictionary = {}   # peer_id -> сессия (после проверки)
var _session_peer: Dictionary = {}   # сессия -> peer_id (-1, пока на связи никого)
var _deadline_ms: Dictionary = {}    # сессия -> момент удаления аватара (мс)
var _under_hunt: Dictionary = {}     # сессия -> true, пока за ней охотится Black ICE (ставит охота снаружи)
var _objects: Dictionary = {}        # id объекта -> сессия, которая его держит ("" — лежит)
var _pos_time_ms: Dictionary = {}    # сессия -> момент последней принятой позиции (мс)


static func avatar_name(session: String) -> String:
	return "avatar_" + session


func start(config: NetConfig, token_verifier: TokenVerifier) -> Error:
	verifier = token_verifier
	grace_sec = config.grace_sec
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
	mp.peer_authentication_failed.connect(func(i): _pending.erase(i))
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
	var mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	return (multiplayer as SceneMultiplayer).send_bytes(data, peer, mode) == OK


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
	if session.is_empty():
		return
	match msg.get("t", ""):
		WorldMsg.GRAB:
			_handle_grab(peer_id, session, str(msg.get("id", "")))
		WorldMsg.POS:
			_handle_pos(session, WorldMsg.decode_vec3(msg.get("p")))
		WorldMsg.USE:
			daemon_requested.emit(session, str(msg.get("id", "")))
		WorldMsg.LEAVE:
			leave_requested.emit(session)
		WorldMsg.EXIT:
			var reason := str(msg.get("reason", ""))
			if not ExitLogic.is_client_reason(reason):
				print("[netrun-server] сессия ", session, ": неизвестная причина выхода «", reason, "»")
				return
			_finish_exit(session, reason)


## Позиция от клиента: не дальше, чем позволяет скорость за прошедшее время; без выхода из комнаты.
func _handle_pos(session: String, p: Variant) -> void:
	var a := get_avatar(session)
	if a == null or p == null:
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


## Объект берётся, только если лежит (или уже у этого игрока).
func _handle_grab(peer_id: int, session: String, id: String) -> void:
	var reply: PackedByteArray
	if not _objects.has(id):
		reply = WorldMsg.encode(WorldMsg.GRAB_NO, id, {"reason": WorldMsg.REASON_UNKNOWN})
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
	var peer := peer_of(session)
	_session_peer.erase(session)
	if peer != -1:
		_peer_session.erase(peer)
	_remove_avatar(session)
	print("[netrun-server] выход ", session, ": ", reason, ", дека сгорела" if ev["deck_burned"] else "")
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
	var a := get_avatar(session)
	if a != null:
		_world.remove_child(a)
		a.queue_free()
		avatar_removed.emit(session)


func _on_auth(peer_id: int, data: PackedByteArray) -> void:
	var mp := multiplayer as SceneMultiplayer
	# Настоящий Мост отвечает по сети: верификатор может быть сопрограммой (BridgeApi.verify_async).
	@warning_ignore("redundant_await")
	var session: String = await verifier.verify_async(data.get_string_from_utf8())
	if session.is_empty() or not session.is_valid_identifier():
		print("[netrun-server] отказ peer ", peer_id, ": токен не принят")
		mp.disconnect_peer(peer_id)
		return
	_pending[peer_id] = session
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
	_pending.erase(peer_id)
	# Та же сессия уже на связи (обрыв ещё не замечен) — старое соединение вытесняется.
	var old := peer_of(session)
	if old != -1 and old != peer_id:
		_peer_session.erase(old)
		(multiplayer as SceneMultiplayer).disconnect_peer(old)
	_peer_session[peer_id] = session
	var resumed := has_avatar(session)
	_session_peer[session] = peer_id
	_deadline_ms.erase(session)
	if not resumed:
		var a := Node3D.new()
		a.name = avatar_name(session)
		_world.add_child(a)
		avatar_spawned.emit(session)
	print("[netrun-server] сессия ", session, " peer ", peer_id, " (вернулась)" if resumed else " (новый аватар)")
	session_joined.emit(session, peer_id, resumed)


func _on_peer_disconnected(peer_id: int) -> void:
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
