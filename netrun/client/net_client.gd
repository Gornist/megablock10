class_name NetClient
extends Node
## Клиент ENet: подключение к серверу мира, токен отправляется при аутентификации.
## Переподключение — новое подключение с тем же токеном (peer id будет другим, аватар — тот же).

signal connected
signal rejected
signal disconnected
## Сервер подтвердил взятие / отказал. Клиент сам объект не берёт — ждёт этих сигналов.
signal grab_confirmed(object_id: String)
signal grab_denied(object_id: String, reason: String)

## Снимок узла от сервера (WorldMsg.STATE) и событие (WorldMsg.EVENT: ended, daemon).
signal state_received(state: Dictionary)
signal event_received(ev: Dictionary)

var config: NetConfig
var is_connected_to_world := false


func start_client(cfg: NetConfig) -> Error:
	config = cfg
	return reconnect()


func reconnect() -> Error:
	var mp := multiplayer as SceneMultiplayer
	if mp.multiplayer_peer != null:
		mp.multiplayer_peer.close()
	mp.auth_callback = _on_auth
	mp.auth_timeout = 5.0
	if not mp.peer_authenticating.is_connected(_on_authenticating):
		mp.peer_authenticating.connect(_on_authenticating)
		mp.connected_to_server.connect(_on_connected)
		mp.server_disconnected.connect(_on_server_disconnected)
		mp.connection_failed.connect(_on_failed)
		mp.peer_packet.connect(_on_packet)
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_client(config.host, config.port)
	if err != OK:
		return err
	mp.multiplayer_peer = enet
	return OK


## Просьба взять объект; false — связи нет, просить некого.
func request_grab(object_id: String) -> bool:
	if not is_connected_to_world:
		return false
	(multiplayer as SceneMultiplayer).send_bytes(WorldMsg.encode(WorldMsg.GRAB, object_id), 1, MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	return true


## Своя позиция (пол под ногами) — сервер решает, что с ней делать (предел скорости, комната).
func send_pos(p: Vector3) -> bool:
	return _send(WorldMsg.encode_pos(p), false)


## Просьба применить демона из деки.
func request_use(daemon_id: String) -> bool:
	return _send(WorldMsg.encode_fields(WorldMsg.USE, {"id": daemon_id}))


## Просьба выйти чисто (сервер проверяет, что игрок на площадке выхода).
func request_leave() -> bool:
	return _send(WorldMsg.encode_fields(WorldMsg.LEAVE))


func _send(data: PackedByteArray, reliable: bool = true) -> bool:
	if not is_connected_to_world:
		return false
	var mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	return (multiplayer as SceneMultiplayer).send_bytes(data, 1, mode) == OK


func _on_packet(_peer_id: int, data: PackedByteArray) -> void:
	var msg := WorldMsg.decode(data)
	match msg.get("t", ""):
		WorldMsg.GRAB_OK:
			grab_confirmed.emit(str(msg.get("id", "")))
		WorldMsg.GRAB_NO:
			grab_denied.emit(str(msg.get("id", "")), str(msg.get("reason", "")))
		WorldMsg.STATE:
			state_received.emit(msg)
		WorldMsg.EVENT:
			event_received.emit(msg)


## Явное отключение (снял очки, тесты): корректно прощается с сервером, затем закрывает сокет.
## Тихий обрыв сети сервер замечает по таймауту ENet (см. NetServer.PEER_TIMEOUT_MS).
func drop() -> void:
	var mp := multiplayer as SceneMultiplayer
	var enet := mp.multiplayer_peer as ENetMultiplayerPeer
	if enet != null:
		enet.disconnect_peer(1)
		await get_tree().process_frame
		await get_tree().process_frame
		enet.close()
		mp.multiplayer_peer = null
	var was := is_connected_to_world
	is_connected_to_world = false
	if was:
		disconnected.emit()


## Запрос экстренного отключения (удержание кнопки, снял очки). Возвращает false, если связи нет.
func request_exit(reason: String) -> bool:
	if not is_connected_to_world:
		return false
	var data := WorldMsg.encode_exit(reason)
	return (multiplayer as SceneMultiplayer).send_bytes(data, 1, MultiplayerPeer.TRANSFER_MODE_RELIABLE) == OK


func _on_authenticating(peer_id: int) -> void:
	(multiplayer as SceneMultiplayer).send_auth(peer_id, config.token.to_utf8_buffer())


func _on_auth(peer_id: int, _data: PackedByteArray) -> void:
	(multiplayer as SceneMultiplayer).complete_auth(peer_id)


func _on_connected() -> void:
	is_connected_to_world = true
	connected.emit()


func _on_failed() -> void:
	rejected.emit()


func _on_server_disconnected() -> void:
	if is_connected_to_world:
		is_connected_to_world = false
		disconnected.emit()
	else:
		rejected.emit()
