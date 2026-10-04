class_name NetClient
extends Node
## Клиент ENet: подключение к серверу мира, токен отправляется при аутентификации.
## Переподключение — новое подключение с тем же токеном (peer id будет другим, аватар — тот же).

signal connected
signal rejected
signal disconnected
## Автопереподключение: идёт попытка номер attempt (с 1) / попытки кончились.
signal reconnecting(attempt: int)
signal reconnect_gave_up
## Сервер подтвердил взятие / отказал. Клиент сам объект не берёт — ждёт этих сигналов.
signal grab_confirmed(object_id: String)
signal grab_denied(object_id: String, reason: String)
## Сервер отказал в телепорте: причина (WorldMsg.REASON_*), позиция аватара на сервере (риг возвращается туда), секунд перезарядки осталось.
signal teleport_denied(reason: String, server_pos: Vector3, left: float)

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

## Эмуляция плохой сети на стороне клиента (P7, tools/soak.sh; tc netem без root недоступен). По умолчанию выключена.
## Потеря — доля 0..1 ненадёжных пакетов (позиции вверх; снимки и позиции чужих вниз); у надёжных потеря — это
## повтор ENet, он выглядит как лишние ~RETRANSMIT_MS задержки. Задержка (+ случайные 0..jitter) — в каждую сторону, порядок сохраняется.
var impair_loss := 0.0
var impair_delay_ms := 0
var impair_jitter_ms := 0
## Сколько пакетов съела эмуляция потерь (вверх, вниз) — для сводки прогона.
var impair_dropped_up := 0
var impair_dropped_down := 0

const RETRANSMIT_MS := 200

## Автопереподключение (V6а, пункт 8 чек-листа). Потеряв связь, которая была, клиент сам повторяет подключение с тем же токеном
## каждые auto_reconnect_sec секунд — сервер держит аватар grace_sec (20 с), вернулся в окно — тот же игрок. Попыток не больше
## auto_reconnect_attempts (потом reconnect_gave_up). 0 — выключено: так сделано по умолчанию, бот и тесты возвращаются сами.
## Если связи ещё не было (плохой токен, сервер не запущен), клиент не долбит. stop_reconnect() — забег закончился или игрок вышел.
var auto_reconnect_sec := 0.0
var auto_reconnect_attempts := 60

var _retry_left := -1  # сколько попыток осталось; -1 — повтор не идёт
var _retry_stopped := false
var _retry_serial := 0
var _beat_window := BeatStats.new()
var _beat_last_ms := -1
var _impair_rng := RandomNumberGenerator.new()
var _out_queue: Array = []  # [момент отправки мс, данные, надёжно]
var _in_queue: Array = []   # [момент разбора мс, данные]
var _out_last_due := 0
var _in_last_due := 0


func start_client(cfg: NetConfig) -> Error:
	config = cfg
	return reconnect()


func reconnect() -> Error:
	_out_queue.clear()  # что копилось у прошлого соединения, новому не нужно
	_in_queue.clear()
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
	return _send(WorldMsg.encode(WorldMsg.GRAB, object_id))


## Своя позиция (пол под ногами) — сервер решает, что с ней делать (предел скорости, комната). pose — голова и руки для других игроков (AvatarPose).
func send_pos(p: Vector3, pose: AvatarPose = null) -> bool:
	return _send(WorldMsg.encode_pos(p, pose), false)


## Просьба телепортироваться в точку на полу (VR: единственный способ двигаться). Риг клиент двигает сам и сразу;
## сервер может отказать — тогда придёт teleport_denied.
func request_teleport(p: Vector3) -> bool:
	return _send(WorldMsg.encode_teleport(p))


## Просьба применить демона из деки.
func request_use(daemon_id: String) -> bool:
	return _send(WorldMsg.encode_fields(WorldMsg.USE, {"id": daemon_id}))


## Взлом хранилища (К3): начать выбранными демонами, нажать клетку ([строка, столбец]), завершить досрочно. Решает сервер.
func request_breach(vault: String, daemon_ids: Array) -> bool:
	return _send(WorldMsg.encode_fields(WorldMsg.BK_OPEN, {"vault": vault, "daemons": daemon_ids}))


func request_breach_tap(cell: Vector2i) -> bool:
	return _send(WorldMsg.encode_fields(WorldMsg.BK_TAP, {"cell": [cell.x, cell.y]}))


func request_breach_cancel() -> bool:
	return _send(WorldMsg.encode_fields(WorldMsg.BK_CANCEL))


## Просьба отдать предмет из ГРУЗа (К5б): to — {runner: id аватара из списка получателей} или {phone: ключ контакта}. Решает сервер, ответ — событие give.
func request_give(item_id: String, to: Dictionary) -> bool:
	return _send(WorldMsg.encode_fields(WorldMsg.GIVE, {"item": item_id, "to": to}))


## Просьба прислать список получателей-нетраннеров (событие give_list).
func request_give_list() -> bool:
	return _send(WorldMsg.encode_fields(WorldMsg.GIVE_LIST))


## Просьба выйти чисто (сервер проверяет, что игрок на площадке выхода).
func request_leave() -> bool:
	return _send(WorldMsg.encode_fields(WorldMsg.LEAVE))


## Копим кадры; раз в config.beat_sec шлём состояние очков (P6). Работает и без сессии — терминал «idle» тоже на связи.
func _process(delta: float) -> void:
	_flush_impaired()
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
	if impair_loss > 0.0 or impair_delay_ms > 0:
		var extra := 0
		if _impair_rng.randf() < impair_loss:
			if not reliable:
				impair_dropped_up += 1
				return true
			extra = RETRANSMIT_MS
		var due := maxi(Time.get_ticks_msec() + _impair_delay() + extra, _out_last_due)
		_out_last_due = due
		_out_queue.append([due, data, reliable])
		return true
	return _send_now(data, reliable)


func _send_now(data: PackedByteArray, reliable: bool) -> bool:
	var mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	var ok := (multiplayer as SceneMultiplayer).send_bytes(data, 1, mode) == OK
	if ok:
		tx_bytes += data.size()
	return ok


func _on_packet(_peer_id: int, data: PackedByteArray) -> void:
	rx_bytes += data.size()
	if impair_loss > 0.0 or impair_delay_ms > 0:
		var t: String = WorldMsg.decode(data).get("t", "")
		if (t == WorldMsg.STATE or t == WorldMsg.AVATARS) and _impair_rng.randf() < impair_loss:
			impair_dropped_down += 1
			return
		var due := maxi(Time.get_ticks_msec() + _impair_delay(), _in_last_due)
		_in_last_due = due
		_in_queue.append([due, data])
		return
	_dispatch(data)


func _impair_delay() -> int:
	return impair_delay_ms + (_impair_rng.randi_range(0, impair_jitter_ms) if impair_jitter_ms > 0 else 0)


## Выдать накопленное, чему пришёл срок (эмуляция задержки). Вызывается каждый кадр и из тестов.
func _flush_impaired() -> void:
	if _out_queue.is_empty() and _in_queue.is_empty():
		return
	var now := Time.get_ticks_msec()
	while not _out_queue.is_empty() and int(_out_queue[0][0]) <= now:
		var e: Array = _out_queue.pop_front()
		if is_connected_to_world:
			_send_now(e[1], e[2])
	while not _in_queue.is_empty() and int(_in_queue[0][0]) <= now:
		_dispatch(_in_queue.pop_front()[1])


func _dispatch(data: PackedByteArray) -> void:
	var msg := WorldMsg.decode(data)
	match msg.get("t", ""):
		WorldMsg.GRAB_OK:
			grab_confirmed.emit(str(msg.get("id", "")))
		WorldMsg.GRAB_NO:
			grab_denied.emit(str(msg.get("id", "")), str(msg.get("reason", "")))
		WorldMsg.TELEPORT_NO:
			var pos: Variant = WorldMsg.decode_xz(msg.get("p"))
			teleport_denied.emit(str(msg.get("reason", "")), pos if pos != null else Vector3.ZERO, float(msg.get("left", 0.0)))
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
	return _send(WorldMsg.encode_exit(reason))


func _on_authenticating(peer_id: int) -> void:
	(multiplayer as SceneMultiplayer).send_auth(peer_id, config.token.to_utf8_buffer())


func _on_auth(peer_id: int, _data: PackedByteArray) -> void:
	(multiplayer as SceneMultiplayer).complete_auth(peer_id)


## Тихий обрыв (сервер убит, Wi-Fi пропал) ENet по умолчанию замечает за десятки секунд; как на сервере — ~5 с.
const PEER_TIMEOUT_MS := 5000


## Прекратить автопереподключение: забег закончился (ended) или игрок вышел сам — сервер всё равно не пустит.
func stop_reconnect() -> void:
	_retry_stopped = true
	_retry_left = -1
	_retry_serial += 1  # отменяет уже заведённый таймер


## lost — связь, которая была, оборвалась (начинает серию попыток заново); иначе — неудача очередной попытки.
func _retry_later(lost: bool) -> void:
	if auto_reconnect_sec <= 0.0 or _retry_stopped:
		return
	if lost:
		_retry_left = auto_reconnect_attempts
	elif _retry_left < 0:
		return
	if _retry_left == 0:
		_retry_left = -1
		reconnect_gave_up.emit()
		return
	var attempt := auto_reconnect_attempts - _retry_left + 1
	_retry_left -= 1
	_retry_serial += 1
	var serial := _retry_serial
	await get_tree().create_timer(auto_reconnect_sec).timeout
	if serial != _retry_serial or _retry_stopped or is_connected_to_world:
		return
	reconnecting.emit(attempt)
	reconnect()


func _on_connected() -> void:
	var enet := (multiplayer as SceneMultiplayer).multiplayer_peer as ENetMultiplayerPeer
	var pp := enet.get_peer(1) if enet != null else null
	if pp != null:
		pp.set_timeout(PEER_TIMEOUT_MS, PEER_TIMEOUT_MS, PEER_TIMEOUT_MS)
	_beat_last_ms = -1  # первое состояние — сразу после подключения
	_retry_left = -1
	is_connected_to_world = true
	connected.emit()


func _on_failed() -> void:
	rejected.emit()
	_retry_later(false)


func _on_server_disconnected() -> void:
	if is_connected_to_world:
		is_connected_to_world = false
		disconnected.emit()
		_retry_later(true)
	else:
		rejected.emit()
		_retry_later(false)
