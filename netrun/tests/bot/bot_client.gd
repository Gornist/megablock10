class_name BotClient
extends Node
## Бот: headless-клиент серого узла без экрана и без сцены. Тот же NetClient, что у игрока, свой «ход» по комнате.
## Сценарии: GHOST_RUN — применить GHOST, дойти до шарда, взять, дойти до выхода, выйти чисто;
## EXPOSED_RUN — то же без GHOST (ICE замечает, выбрасывает). BLACK_RUN — идёт к патрулю Black ICE и ждёт: result = flatline (P4). LOITER — ходит кругами у входа, не заканчивается (нагрузка, P1). Итог — result и сигнал finished.
## С reconnect = true бот переживает перезапуск сервера мира (M5): связь пропала без причины — повторяет подключение с тем же
## токеном, начинает путь с точки входа и продолжает сценарий (шард уже взят — идёт к выходу). Из командной строки —
## `godot --headless --path netrun -- --bot=ghost_run --host=… --port=… --token=t03:… [--bot-reconnect]` (main.gd, run_bot).

signal finished(result: String)

## GRAPH_RUN (W1): идёт по графу узлов по маршруту `route` (id узлов, в которые надо пройти порталами), в последнем берёт шард
## и выходит чисто там же; `use_ghost` — сначала GHOST. Видит узел так, как его описал сервер (событие node): порталы и шарды.
enum Scenario { GHOST_RUN, EXPOSED_RUN, LOITER, BLACK_RUN, GRAPH_RUN }

const SPEED := 4.0         # м/с (ходьба игрока в плоской сборке — около 2.5)
const SEND_PERIOD := 0.05
const ARRIVE := 1.0
const BLACK_SPOT := Vector3(0, 0, -9)  # у линии патруля Black ICE (NodeLayout.BLACK_ICE), в его конусе
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
## Не брать шард (P7: шард в узле один, остальным ботам он не нужен): после GHOST/осторожного пути — сразу к выходу.
var no_shard := false
## Сбой по ходу пути (P7), срабатывает один раз через chaos_after секунд после выхода на последний отрезок (to_exit):
## "emergency" — удержание кнопки (причина manual_hold), "drop_return" — обрыв связи и возврат через 2–8 с,
## "drop_gone" — обрыв без возврата (сервер закроет забег по окну возврата). "" — без сбоя.
var chaos := ""
var chaos_after := 2.0
## Для GRAPH_RUN: куда идти дальше (первый — следующий узел), где бот сейчас, какие узлы прошёл, что видел о узле, сколько туннелей.
var route: Array[String] = []
var use_ghost := false
var current_node := ""
var visited: Array[String] = []
var node_info: Dictionary = {}
var tunnels_seen := 0
var denied_reasons: Array[String] = []
var _goal := Vector3.ZERO
var _goal_shard := ""
var _loiter_angle := 0.0
var _chaos_done := false
var _chaos_gap := 0.0
var _resume_keep_ghost := false
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
	match str(ev.get("kind", "")):
		WorldMsg.EV_ENDED:
			_finish("clean" if ev.get("reason") == ExitLogic.REASON_CLEAN else str(ev.get("reason")))
		WorldMsg.EV_NODE:
			node_info = ev
			current_node = str(ev.get("node", ""))
			visited.append(current_node)
			var a: Variant = ev.get("arrive")
			if a is Array and (a as Array).size() == 2:
				position = Vector3(float(a[0]), 0.0, float(a[1]))
			if _step == "g_tunnel":
				route.pop_front()
				_enter("g_wait")
		WorldMsg.EV_TUNNEL:
			tunnels_seen += 1
			_enter("g_tunnel")
		WorldMsg.EV_SHARDS:
			node_info["shards"] = ev.get("shards", [])
		WorldMsg.EV_PORTAL_DENIED:
			denied_reasons.append(str(ev.get("reason", "")))


func _on_disconnected() -> void:
	# Событие «ended» приходит раньше разрыва; пустой результат здесь — связь пропала без причины.
	if not result.is_empty():
		return
	if reconnect:
		_reconnect_at = _clock + (_chaos_gap if _chaos_gap > 0.0 else RECONNECT_SEC)
		_chaos_gap = 0.0
		if verbose:
			print("[bot] связь потеряна, переподключаюсь")
		return
	_finish("lost")


## Вернулись после обрыва: сервер мира новый, аватар в точке входа, демоны без перезарядки — путь с начала, шард не берём повторно.
func _resume() -> void:
	reconnects += 1
	position = NodeLayout.SPAWN
	last_state = {}  # «ghost: true» от прошлого сервера не в счёт
	if scenario == Scenario.GHOST_RUN and not _resume_keep_ghost:
		_enter("ghost")
	else:
		_enter("to_exit" if shard_taken or (no_shard and _resume_keep_ghost) else "to_shard")
	_resume_keep_ghost = false


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
				elif scenario == Scenario.BLACK_RUN:
					_enter("to_black")
				elif scenario == Scenario.GRAPH_RUN:
					_enter("ghost" if use_ghost else "g_wait")
				else:
					_enter("ghost" if scenario == Scenario.GHOST_RUN else "to_shard")
		"loiter":
			_step_started = _clock  # без таймаута шага: бот гуляет, пока его не остановят
			var start := loiter_center + Vector3(loiter_radius * sin(_loiter_angle), 0, loiter_radius * (1.0 - cos(_loiter_angle)) - loiter_radius)
			if _walk_to(start, delta, 0.05):
				_loiter_angle += loiter_omega * delta
				position = loiter_center + Vector3(loiter_radius * sin(_loiter_angle), 0, loiter_radius * (1.0 - cos(_loiter_angle)) - loiter_radius)
		"to_black":
			if _walk_to(BLACK_SPOT, delta, 0.5):
				_enter("lurk")
		"lurk":
			pass  # стоим на виду у Black ICE; шаг кончается событием «ended» или таймаутом шага
		"ghost":
			# Дека из Моста приходит серверу мира асинхронно (список предметов): первый запрос может прийти раньше деки
			# (not_in_deck) — повторяем раз в секунду, пока ghost не включился.
			if last_state.get("ghost", false):
				if scenario == Scenario.GRAPH_RUN:
					_enter("g_wait")
				else:
					_enter("to_exit" if shard_taken or no_shard else "to_shard")
			elif not _asked or _clock - _asked_at >= GHOST_RETRY_SEC:
				_asked = net.request_use(ghost_daemon)
				_asked_at = _clock
		"g_wait":
			# Узел известен (событие node) — решаем, куда идти: к порталу следующего узла маршрута или к шарду.
			if not node_info.is_empty():
				_graph_next()
		"g_portal":
			if _walk_to(_goal, delta, 0.4):
				_enter("g_stand")
		"g_stand":
			pass  # сервер сам запускает переход, когда простоял у портала; шаг кончается событием tunnel/node или таймаутом шага
		"g_tunnel":
			_step_started = _clock  # тоннель идёт, ход заблокирован; таймаут шага не идёт
		"g_shard":
			if _walk_to(_goal, delta, GRAB_FROM):
				_enter("g_grab")
		"g_grab":
			if not _asked:
				_asked = net.request_grab(_goal_shard)
			elif shard_taken:
				_enter("hold" if hold_after_grab > 0.0 else "to_exit")
		"to_shard":
			# Без GHOST идём осторожно: ICE успевает заметить и догнать раньше шарда.
			var speed_scale := 1.0 if scenario == Scenario.GHOST_RUN else 0.25
			if _walk_to(NodeLayout.SHARD_POS, delta * speed_scale, GRAB_FROM):
				_enter("to_exit" if no_shard else "grab")
		"grab":
			if not _asked:
				_asked = net.request_grab(NetConfig.PICKUP_ID)
			elif shard_taken:
				_enter("hold" if hold_after_grab > 0.0 else "to_exit")
		"hold":
			if _clock - _step_started >= hold_after_grab:
				_enter("to_exit")
		"to_exit":
			if chaos != "" and not _chaos_done and _clock - _step_started >= chaos_after:
				_chaos_done = true
				_do_chaos()
				return
			if _walk_to(NodeLayout.EXIT_POS, delta, ARRIVE):
				_enter("leave")
		"leave":
			if not _asked:
				_asked = net.request_leave()


## GRAPH_RUN: следующий шаг в узле. Маршрут не кончился — к порталу в следующий узел; кончился — к первому лежащему шарду
## (нет шарда — сразу к выходу).
func _graph_next() -> void:
	if not route.is_empty():
		var next: String = route[0]
		for pt in node_info.get("portals", []):
			if pt["to"] == next:
				_goal = Vector3(float(pt["p"][0]), 0.0, float(pt["p"][1]))
				_enter("g_portal")
				return
		_finish("no_portal:" + next)
		return
	for sh in node_info.get("shards", []):
		if sh.get("ready", false):
			_goal_shard = str(sh["id"])
			_goal = Vector3(float(sh["p"][0]), 0.0, float(sh["p"][2]))
			_enter("g_shard")
			return
	_enter("to_exit")


func _do_chaos() -> void:
	if verbose:
		print("[bot] сбой ", chaos)
	match chaos:
		"emergency":
			# Сервер на клиентский выход «ended» не шлёт (клиент сам знает причину) — итог ставим сами.
			if net.request_exit(ExitLogic.REASON_MANUAL_HOLD):
				_finish(ExitLogic.REASON_MANUAL_HOLD)
		"drop_return":
			_chaos_gap = randf_range(2.0, 8.0)
			_resume_keep_ghost = true
			reconnect = true
			net.drop()
		"drop_gone":
			reconnect = false
			net.drop()
