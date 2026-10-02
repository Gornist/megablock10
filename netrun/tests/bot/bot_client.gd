class_name BotClient
extends Node
## Бот: headless-клиент серого узла без экрана и без сцены. Тот же NetClient, что у игрока, свой «ход» по комнате.
## Сценарии: GHOST_RUN — применить GHOST, дойти до шарда, взять, дойти до выхода, выйти чисто;
## EXPOSED_RUN — то же без GHOST (ICE замечает, выбрасывает). LOITER — ходит кругами у входа, не заканчивается (нагрузка, P1). Итог — result и сигнал finished.
## С reconnect = true бот переживает перезапуск сервера мира (M5): связь пропала без причины — повторяет подключение с тем же
## токеном, начинает путь с точки входа и продолжает сценарий (шард уже взят — идёт к выходу). Из командной строки —
## `godot --headless --path netrun -- --bot=ghost_run --host=… --port=… --token=t03:… [--bot-reconnect]` (main.gd, run_bot).

signal finished(result: String)

enum Scenario { GHOST_RUN, EXPOSED_RUN, LOITER }

const SPEED := 4.0         # м/с (ходьба игрока в плоской сборке — около 2.5)
const SEND_PERIOD := 0.05
const ARRIVE := 1.0
const GRAB_FROM := 1.5     # на таком расстоянии от шарда просим взять
const STEP_TIMEOUT := 25.0 # с на один шаг сценария — иначе result = "timeout:<шаг>"
const RECONNECT_SEC := 1.0 # пауза между попытками подключения после обрыва
const GHOST_RETRY_SEC := 1.0 # повтор запроса GHOST, пока он не включился

var net: NetClient
var scenario: int = Scenario.GHOST_RUN
var position := NodeLayout.SPAWN
var result := ""           # "" пока идёт; clean | ejected | flatline | lost | timeout:<шаг>
var last_state: Dictionary = {}
var events: Array = []
var shard_taken := false
var steps: Array[String] = []
## Чужие аватары и ICE так, как их видит клиент (буфер состояний), и сколько пакетов позиций пришло.
var remote := RemoteTracks.new()
var avatar_packets := 0
## Для LOITER: центр и радиус круга, скорость обхода (рад/с).
var loiter_center := Vector3(0, 0, -1)
var loiter_radius := 1.0
var loiter_omega := 1.0
## Переподключаться после обрыва связи (перезапуск сервера мира); сколько раз уже вернулись.
var reconnect := false
var reconnects := 0
## Сколько секунд стоять после взятия шарда (до выхода): окно, в которое стенд убивает сервер мира (M5). 0 — не ждать.
var hold_after_grab := 0.0
## Печатать шаги и события в stdout (запуск из командной строки: по этим строкам скрипт знает, когда убивать сервер).
var verbose := false
## Какого демона бот применяет как GHOST. У деки из Моста id демонов — id предметов (M5), стенд e2e с настоящим телефоном (M6)
## подставляет id предмета через `--bot-daemon=`; без него — `ghost_1` из деки по умолчанию.
var ghost_daemon := "ghost_1"
var _loiter_angle := 0.0
var _reconnect_at := -1.0

var _step := "connect"
var _step_started := 0.0
var _clock := 0.0
var _send_acc := 0.0
var _asked := false
var _asked_at := 0.0


func start(cfg: NetConfig, scenario_kind: int = Scenario.GHOST_RUN) -> void:
	scenario = scenario_kind
	net = NetClient.new()
	net.name = "Net"
	add_child(net)
	net.state_received.connect(func(s: Dictionary):
		last_state = s
		remote.on_state(s, _clock))
	net.avatars_received.connect(func(m: Dictionary):
		avatar_packets += 1
		remote.on_avatars(m, _clock))
	net.event_received.connect(_on_event)
	net.grab_confirmed.connect(func(_id: String):
		shard_taken = true
		if verbose:
			print("[bot] шард взят"))
	net.disconnected.connect(_on_disconnected)
	net.start_client(cfg)
	_enter("connect")


func _enter(step: String) -> void:
	_step = step
	_step_started = _clock
	_asked = false
	steps.append(step)
	if verbose:
		print("[bot] шаг ", step)


func _finish(r: String) -> void:
	if not result.is_empty():
		return
	result = r
	finished.emit(r)


func _on_event(ev: Dictionary) -> void:
	events.append(ev)
	if ev.get("kind") == WorldMsg.EV_ENDED:
		_finish("clean" if ev.get("reason") == ExitLogic.REASON_CLEAN else str(ev.get("reason")))


func _on_disconnected() -> void:
	# Событие «ended» приходит раньше разрыва; пустой результат здесь — связь пропала без причины.
	if not result.is_empty():
		return
	if reconnect:
		_reconnect_at = _clock + RECONNECT_SEC
		if verbose:
			print("[bot] связь потеряна, переподключаюсь")
		return
	_finish("lost")


## Вернулись после обрыва: сервер мира новый, аватар в точке входа, демоны без перезарядки — путь с начала, шард не берём повторно.
func _resume() -> void:
	reconnects += 1
	position = NodeLayout.SPAWN
	last_state = {}  # «ghost: true» от прошлого сервера не в счёт
	if scenario == Scenario.GHOST_RUN:
		_enter("ghost")
	else:
		_enter("to_exit" if shard_taken else "to_shard")


func _walk_to(goal: Vector3, delta: float, stop_at: float) -> bool:
	var d := Vector3(goal.x - position.x, 0.0, goal.z - position.z)
	if d.length() <= stop_at:
		return true
	position += d.normalized() * minf(SPEED * delta, d.length())
	return false


func _process(delta: float) -> void:
	if net == null or not result.is_empty():
		return
	_clock += delta
	if _reconnect_at >= 0.0:
		_step_started = _clock  # без связи таймаут шага не идёт
		if net.is_connected_to_world:
			_reconnect_at = -1.0
			_resume()
		elif _clock >= _reconnect_at:
			net.reconnect()
			_reconnect_at = _clock + RECONNECT_SEC * 3.0
		return
	if _clock - _step_started > STEP_TIMEOUT:
		_finish("timeout:" + _step)
		return
	_send_acc += delta
	if _send_acc >= SEND_PERIOD and net.is_connected_to_world:
		_send_acc = 0.0
		net.send_pos(position)
	match _step:
		"connect":
			if net.is_connected_to_world:
				if scenario == Scenario.LOITER:
					_enter("loiter")
				else:
					_enter("ghost" if scenario == Scenario.GHOST_RUN else "to_shard")
		"loiter":
			_step_started = _clock  # без таймаута шага: бот гуляет, пока его не остановят
			var start := loiter_center + Vector3(loiter_radius * sin(_loiter_angle), 0, loiter_radius * (1.0 - cos(_loiter_angle)) - loiter_radius)
			if _walk_to(start, delta, 0.05):
				_loiter_angle += loiter_omega * delta
				position = loiter_center + Vector3(loiter_radius * sin(_loiter_angle), 0, loiter_radius * (1.0 - cos(_loiter_angle)) - loiter_radius)
		"ghost":
			# Дека из Моста приходит серверу мира асинхронно (список предметов): первый запрос может прийти раньше деки
			# (not_in_deck) — повторяем раз в секунду, пока ghost не включился.
			if last_state.get("ghost", false):
				_enter("to_exit" if shard_taken else "to_shard")
			elif not _asked or _clock - _asked_at >= GHOST_RETRY_SEC:
				_asked = net.request_use(ghost_daemon)
				_asked_at = _clock
		"to_shard":
			# Без GHOST идём осторожно: ICE успевает заметить и догнать раньше шарда.
			var speed_scale := 1.0 if scenario == Scenario.GHOST_RUN else 0.25
			if _walk_to(NodeLayout.SHARD_POS, delta * speed_scale, GRAB_FROM):
				_enter("grab")
		"grab":
			if not _asked:
				_asked = net.request_grab(NetConfig.PICKUP_ID)
			elif shard_taken:
				_enter("hold" if hold_after_grab > 0.0 else "to_exit")
		"hold":
			if _clock - _step_started >= hold_after_grab:
				_enter("to_exit")
		"to_exit":
			if _walk_to(NodeLayout.EXIT_POS, delta, ARRIVE):
				_enter("leave")
		"leave":
			if not _asked:
				_asked = net.request_leave()
