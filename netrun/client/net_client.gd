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
## Позиции других аватаров узла (WorldMsg.AVATARS).
signal avatars_received(msg: Dictionary)

var config: NetConfig
var is_connected_to_world := false
## Байты полезной нагрузки (без заголовков ENet): принято от сервера / отправлено ему. Для замеров трафика.
var rx_bytes := 0
var tx_bytes := 0
## Датчик заряда (на ПК — «нет данных»); тесты подменяют provider.
var battery := BatteryProbe.new()
## Последнее отправленное состояние (для журнала и тестов).
var last_beat_sent: Dictionary = {}
var beats_sent := 0

var _beat_window := BeatStats.new()
var _beat_last_ms := -1


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


## Копим кадры; раз в config.beat_sec шлём состояние очков (P6). Работает и без сессии — терминал «idle» тоже на связи.
func _process(delta: float) -> void:
	_beat_window.add_frame(delta)
	if config == null or not is_connected_to_world or config.terminal_id().is_empty():
		return
	var now := Time.get_ticks_msec()
	if not BeatStats.due(now, _beat_last_ms, int(config.beat_sec * 1000.0)):
		return
	_beat_last_ms = now
	send_beat()


## Состояние очков сейчас: заряд, FPS и худший кадр за окно, RTT до сервера. Окно кадров начинается заново.
func send_beat() -> bool:
	var w := _beat_window.take()
	var b := battery.read()
	var fields := BeatStats.make_fields(config.terminal_id(), BeatStats.battery_pct(b["percent"]), b["charging"], int(w["fps"]), int(w["worst_ms"]), rtt_ms())
	var ok := _send(WorldMsg.encode_fields(WorldMsg.BEAT, fields))
	if ok:
		last_beat_sent = fields
		beats_sent += 1
	return ok


## RTT до сервера (мс) по статистике ENet; -1 — связи нет.
func rtt_ms() -> int:
	var enet := (multiplayer as SceneMultiplayer).multiplayer_peer as ENetMultiplayerPeer
	var pp := enet.get_peer(1) if enet != null else null
	if pp == null:
		return -1
	return int(pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


func _send(data: PackedByteArray, reliable: bool = true) -> bool:
	if not is_connected_to_world:
		return false
	var mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	var ok := (multiplayer as SceneMultiplayer).send_bytes(data, 1, mode) == OK
	if ok:
		tx_bytes += data.size()
	return ok


func _on_packet(_peer_id: int, data: PackedByteArray) -> void:
	rx_bytes += data.size()
	var msg := WorldMsg.decode(data)
	match msg.get("t", ""):
		WorldMsg.GRAB_OK:
			grab_confirmed.emit(str(msg.get("id", "")))
		WorldMsg.GRAB_NO:
			grab_denied.emit(str(msg.get("id", "")), str(msg.get("reason", "")))
		WorldMsg.STATE:
			state_received.emit(msg)
		WorldMsg.AVATARS:
			avatars_received.emit(msg)
		WorldMsg.EVENT:
			event_received.emit(msg)


## Явное отключение (снял очки, тесты): корректно прощается с сервером, затем закрывает сокет.
## Тихий обрыв сети сервер замечает по таймауту ENet (см. NetServer.PEER_TIMEOUT_MS).
func drop() -> void:
	var mp := multiplayer as SceneMultiplayer
	var enet := mp.multiplayer_peer as ENetMultiplayerPeer
	var was := is_connected_to_world
	is_connected_to_world = false  # пока прощаемся, ничего не отправляем (иначе «max channels: 0» в журнале)
	if enet != null:
		if was:
			enet.disconnect_peer(1)
		await get_tree().process_frame
		await get_tree().process_frame
		enet.close()
		mp.multiplayer_peer = null
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
	_beat_last_ms = -1  # первое состояние — сразу после подключения
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
