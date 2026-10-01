class_name NetServer
extends Node
## Сетевая часть сервера мира: ENet, проверка токена в auth_callback, игрок = сессия (не peer id).
## Аватар — узел `node_07/avatar_<сессия>`; после обрыва живёт grace_sec и возвращается тому же игроку.

signal avatar_spawned(session: String)
signal avatar_removed(session: String)
signal session_joined(session: String, peer_id: int, resumed: bool)
signal session_lost(session: String)

## Тихий обрыв (Wi-Fi пропал) ENet по умолчанию замечает за десятки секунд; ужимаем до ~5 с.
const PEER_TIMEOUT_MS := 5000

var verifier: TokenVerifier
var grace_sec: float = NetConfig.DEFAULT_GRACE_SEC

var _world: Node3D
var _pending: Dictionary = {}        # peer_id -> сессия: токен принят, ждём конца аутентификации
var _peer_session: Dictionary = {}   # peer_id -> сессия (после проверки)
var _session_peer: Dictionary = {}   # сессия -> peer_id (-1, пока на связи никого)
var _deadline_ms: Dictionary = {}    # сессия -> момент удаления аватара (мс)


static func avatar_name(session: String) -> String:
	return "avatar_" + session


func start(config: NetConfig, token_verifier: TokenVerifier) -> Error:
	verifier = token_verifier
	grace_sec = config.grace_sec
	_world = Node3D.new()
	_world.name = NetConfig.WORLD_NODE
	add_child(_world)
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


func _on_auth(peer_id: int, data: PackedByteArray) -> void:
	var mp := multiplayer as SceneMultiplayer
	var session := verifier.verify(data.get_string_from_utf8())
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
			_deadline_ms.erase(session)
			_session_peer.erase(session)
			var a := get_avatar(session)
			if a != null:
				_world.remove_child(a)
				a.queue_free()
			print("[netrun-server] аватар ", session, " убран по таймеру")
			avatar_removed.emit(session)
