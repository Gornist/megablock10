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

## Тихий обрыв (Wi-Fi пропал) ENet по умолчанию замечает за десятки секунд; ужимаем до ~5 с.
const PEER_TIMEOUT_MS := 5000

var verifier: TokenVerifier
var grace_sec: float = NetConfig.DEFAULT_GRACE_SEC

var _world: Node3D
var _pending: Dictionary = {}        # peer_id -> сессия: токен принят, ждём конца аутентификации
var _peer_session: Dictionary = {}   # peer_id -> сессия (после проверки)
var _session_peer: Dictionary = {}   # сессия -> peer_id (-1, пока на связи никого)
var _deadline_ms: Dictionary = {}    # сессия -> момент удаления аватара (мс)
var _under_hunt: Dictionary = {}     # сессия -> true, пока за ней охотится Black ICE (ставит охота снаружи)
var _objects: Dictionary = {}        # id объекта -> сессия, которая его держит ("" — лежит)


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
		WorldMsg.EXIT:
			var reason := str(msg.get("reason", ""))
			if not ExitLogic.is_client_reason(reason):
				print("[netrun-server] сессия ", session, ": неизвестная причина выхода «", reason, "»")
				return
			_finish_exit(session, reason)


## Объект берётся, только если лежит (или уже у этого игрока).
func _handle_grab(peer_id: int, session: String, id: String) -> void:
	var reply: PackedByteArray
	if not _objects.has(id):
		reply = WorldMsg.encode(WorldMsg.GRAB_NO, id, {"reason": WorldMsg.REASON_UNKNOWN})
	elif _objects[id] != "" and _objects[id] != session:
		reply = WorldMsg.encode(WorldMsg.GRAB_NO, id, {"reason": WorldMsg.REASON_HELD})
	else:
		_objects[id] = session
		reply = WorldMsg.encode(WorldMsg.GRAB_OK, id)
		print("[netrun-server] ", session, " взял ", id)
		object_taken.emit(id, session)
	(multiplayer as SceneMultiplayer).send_bytes(reply, peer_id, MultiplayerPeer.TRANSFER_MODE_RELIABLE)


## Выход: событие, затем аватар убирается, связь закрывается. Обрыв сюда не попадает до конца окна возврата.
func _finish_exit(session: String, reason: String) -> void:
	var ev := ExitLogic.build_event(session, reason, _under_hunt.has(session))
	_under_hunt.erase(session)
	_deadline_ms.erase(session)
	var peer := peer_of(session)
	_session_peer.erase(session)
	if peer != -1:
		_peer_session.erase(peer)
	_remove_avatar(session)
	print("[netrun-server] выход ", session, ": ", reason, ", дека сгорела" if ev["deck_burned"] else "")
	exit_event.emit(ev)
	if peer != -1:
		(multiplayer as SceneMultiplayer).disconnect_peer(peer)


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
