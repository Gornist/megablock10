class_name NetClient
extends Node
## Клиент ENet: подключение к серверу мира, токен отправляется при аутентификации.
## Переподключение — новое подключение с тем же токеном (peer id будет другим, аватар — тот же).

signal connected
signal rejected
signal disconnected

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
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_client(config.host, config.port)
	if err != OK:
		return err
	mp.multiplayer_peer = enet
	return OK


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
