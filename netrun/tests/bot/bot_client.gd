class_name BotClient
extends Node
## Бот: headless-клиент серого узла без экрана и без сцены. Тот же NetClient, что у игрока, свой «ход» по комнате.
## Сценарии: GHOST_RUN — применить GHOST, дойти до шарда, взять, дойти до выхода, выйти чисто;
## EXPOSED_RUN — то же без GHOST (ICE замечает, выбрасывает). BLACK_RUN — идёт к патрулю Black ICE и ждёт: result = flatline (P4). LOITER — ходит кругами у входа, не заканчивается (нагрузка, P1). Итог — result и сигнал finished.
## С reconnect = true бот переживает перезапуск сервера мира (M5): связь пропала без причины — повторяет подключение с тем же
## токеном, начинает путь с точки входа и продолжает сценарий (шард уже взят — идёт к выходу). Из командной строки —
## `godot --headless --path netrun -- --bot=ghost_run --host=… --port=… --token=t03:… [--bot-reconnect]` (main.gd, run_bot).

signal finished(result: String)

## Учебный узел (W2) — GRAPH_RUN с read_signs и use_ghost: бот обходит таблички, применяет демона, берёт шард-заглушку, выходит.
## GRAPH_RUN (W1): идёт по графу узлов по маршруту `route` (id узлов, в которые надо пройти порталами), в последнем берёт шард
## и выходит чисто там же; `use_ghost` — сначала GHOST. Видит узел так, как его описал сервер (событие node): порталы и шарды.
enum Scenario { GHOST_RUN, EXPOSED_RUN, LOITER, BLACK_RUN, GRAPH_RUN }

## Бот двигается так же, как игрок в VR: прыжками-телепортами (не дальше RigMath.TELEPORT_RANGE, пауза — перезарядка), не ходьбой.
const HOP_PAUSE := RigMath.TELEPORT_COOLDOWN + 0.05  # с между прыжками (сервер пускает чаще, но бот ходит по правилам игрока)
const LOITER_MAX_ARC := 0.8  # рад: дуга за один прыжок по кругу (хорда не длиннее 0,8 радиуса)
const SEND_PERIOD := 0.05
const ARRIVE := 1.0
const BLACK_SPOT := Vector3(0, 0, -9)  # у линии патруля Black ICE (NodeLayout.BLACK_ICE), в его конусе
const SIGN_REACH := 2.0    # на таком расстоянии от таблички она прочитана
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
## Прыжки бота: сколько, [время бота, длина] каждого (тест проверяет правила), причины отказов сервера.
var hops := 0
var hop_log: Array = []
var tp_denied: Array[String] = []
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
## Поза тела, которую бот шлёт вместе с позицией (тесты рассылки позы). null — не шлёт.
var pose: AvatarPose = null
var chaos_after := 2.0
## Для GRAPH_RUN: куда идти дальше (первый — следующий узел), где бот сейчас, какие узлы прошёл, что видел о узле, сколько туннелей.
var route: Array[String] = []
var use_ghost := false
## Учебный узел: сначала обойти все таблички из события node (signs), считая прочитанные.
var read_signs := false
var signs_read := 0
var current_node := ""
var visited: Array[String] = []
var node_info: Dictionary = {}
var tunnels_seen := 0
var denied_reasons: Array[String] = []
## Взлом хранилища (К3): перед взятием шарда из закрытого хранилища бот взламывает его автосолвером (BreachAutoSolver) по сетке, как её видит клиент.
var deck_info: Dictionary = {}       # последнее событие `ev deck`: рабочие демоны с цепочками и RAM
var breach_enabled := true
var breach_log: Array = []           # события bk_end по порядку
var breach_tries := 0
const BREACH_MAX_TRIES := 3
const BREACH_TAP_PERIOD := 0.12      # с между тапами: быстрый, но человеческий темп
## Заряд демона (К6): GHOST вне взлома срабатывает только заряженным — бот сначала собирает сетку заряда автосолвером, потом запускает.
var charge_log: Array = []           # события bk_end заряда по порядку
var _ch: BreachMirror
var _ch_path: Array[Vector2i] = []
var _ch_next_tap := 0.0
var _ch_asked_at := -100.0
## Проба отказа (стенд e2e): взлом начинается, даже если сервер показывает «ОСТЫВАЕТ» — бот просит взлом и запоминает причину отказа
## (breach_denied), после чего идёт к выходу и выходит чисто. Шард в этом забеге не берётся.
var force_breach := false
var breach_denied := ""
## Отправка добычи (К5б, стенд e2e): после взятия шарда бот отдаёт его контакту телефона (ключ) и только потом идёт к выходу.
## give_log — события give (dir out) по порядку.
var give_phone := ""
var give_log: Array = []
var _bk: BreachMirror
var _bk_path: Array[Vector2i] = []
var _bk_next_tap := 0.0
var _bk_return := ""                 # шаг, в который вернуться после взлома
var _bk_vault := ""
var _bk_no := ""
var _bk_done: Dictionary = {}        # id хранилищ, открытых нашим взломом
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
var _next_hop_at := 0.0


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
	net.teleport_denied.connect(func(reason: String, server_pos: Vector3, _left: float):
		tp_denied.append(reason)
		position = server_pos  # как игрок: сервер отказал — стоим там, где он нас видит
		if verbose:
			print("[bot] телепорт отклонён: ", reason))
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
		WorldMsg.EV_DECK:
			deck_info = ev
		WorldMsg.EV_BK:
			if ev.get("mode", "") == WorldMsg.MODE_CHARGE:
				_ch = BreachMirror.from_event(ev)
				_ch_path = []
			else:
				_bk = BreachMirror.from_event(ev)
				_bk_path = []
		WorldMsg.EV_BK_TICK:
			if ev.get("mode", "") == WorldMsg.MODE_CHARGE:
				if _ch != null:
					_ch.apply_tick(ev)
			elif _bk != null:
				_bk.apply_tick(ev)
		WorldMsg.EV_BK_END:
			if ev.get("mode", "") == WorldMsg.MODE_CHARGE:
				if _ch != null:
					_ch.apply_end(ev)
				charge_log.append(ev)
			else:
				if _bk != null:
					_bk.apply_end(ev)
				breach_log.append(ev)
		WorldMsg.EV_BK_NO:
			if ev.get("mode", "") != WorldMsg.MODE_CHARGE:   # отказ заряда — повторим по таймеру шага «ghost»
				_bk_no = str(ev.get("reason", ""))
		WorldMsg.EV_PORTAL_DENIED:
			denied_reasons.append(str(ev.get("reason", "")))
		WorldMsg.EV_GIVE:
			if ev.get("dir", "") == WorldMsg.GIVE_OUT:
				give_log.append(ev)
				if verbose:
					print("[bot] отправка: ", "ok" if ev.get("ok", false) else "отказ " + str(ev.get("error", "")))


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


## Шаг пути к цели прыжками: когда перезарядка прошла — прыжок в сторону цели не дальше дальности (hop_scale < 1 — осторожный путь,
## короткими прыжками). true — уже на месте (не дальше stop_at от цели). Параметр кадра оставлен для старых вызовов.
func _walk_to(goal: Vector3, _delta: float, stop_at: float, hop_scale: float = 1.0) -> bool:
	var d := Vector3(goal.x - position.x, 0.0, goal.z - position.z)
	if d.length() <= stop_at:
		return true
	if _clock >= _next_hop_at:
		_hop(position + d.normalized() * minf(d.length(), RigMath.TELEPORT_RANGE * hop_scale))
	return false


## Прыжок: просьба серверу, позиция бота меняется сразу (как у риг-а), дальше — перезарядка.
func _hop(to: Vector3) -> void:
	hop_log.append([_clock, NodeLayout.flat_distance(position, to)])
	hops += 1
	position = Vector3(to.x, 0.0, to.z)
	_next_hop_at = _clock + HOP_PAUSE
	net.request_teleport(position)


func _loiter_point(angle: float) -> Vector3:
	return loiter_center + Vector3(loiter_radius * sin(angle), 0, loiter_radius * (1.0 - cos(angle)) - loiter_radius)


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
		net.send_pos(position, pose)
	match _step:
		"connect":
			if net.is_connected_to_world:
				if scenario == Scenario.LOITER:
					_enter("loiter")
				elif scenario == Scenario.BLACK_RUN:
					_enter("to_black")
				elif scenario == Scenario.GRAPH_RUN:
					_enter("tut_signs" if read_signs else ("ghost" if use_ghost else "g_wait"))
				else:
					_enter("ghost" if scenario == Scenario.GHOST_RUN else "to_shard")
		"loiter":
			_step_started = _clock  # без таймаута шага: бот гуляет, пока его не остановят
			# Выходим на круг, потом раз в перезарядку прыгаем на следующую точку круга.
			if _walk_to(_loiter_point(_loiter_angle), delta, 0.05) and _clock >= _next_hop_at:
				_loiter_angle += minf(loiter_omega * HOP_PAUSE, LOITER_MAX_ARC)
				_hop(_loiter_point(_loiter_angle))
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
			elif _is_charged(ghost_daemon):
				if not _asked or _clock - _asked_at >= GHOST_RETRY_SEC:
					_asked = net.request_use(ghost_daemon)
					_asked_at = _clock
			else:
				_step_charge()
		"tut_signs":
			# Новичок обходит таблички учебного узла по порядку (подошёл на SIGN_REACH — прочитал), потом GHOST и дальше как GRAPH_RUN.
			if node_info.is_empty():
				return
			var signs: Array = node_info.get("signs", [])
			if signs_read >= signs.size():
				_enter("ghost" if use_ghost else "g_wait")
			elif _walk_to(Vector3(float(signs[signs_read]["p"][0]), 0.0, float(signs[signs_read]["p"][1])), delta, SIGN_REACH):
				signs_read += 1
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
		"breach":
			_step_breach()
		"g_grab":
			if not _asked and _needs_breach(_goal_shard):
				_start_breach(_goal_shard, "g_grab")
			elif not _asked:
				_asked = net.request_grab(_goal_shard)
			elif shard_taken:
				_enter(_after_grab_step())
		"to_shard":
			# Без GHOST идём осторожно: ICE успевает заметить и догнать раньше шарда.
			var speed_scale := 1.0 if scenario == Scenario.GHOST_RUN else 0.25
			if _walk_to(_plain_shard()["pos"], delta, GRAB_FROM, speed_scale):
				_enter("to_exit" if no_shard else "grab")
		"grab":
			if not _asked and _needs_breach(_plain_shard()["id"]):
				_start_breach(_plain_shard()["id"], "grab")
			elif not _asked:
				_asked = net.request_grab(_plain_shard()["id"])
			elif shard_taken:
				_enter(_after_grab_step())
		"give":
			_step_give()
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


# ---------------------------------------------------------------- взлом хранилища (К3)

## Хранилище закрыто, взлом доступен и мы его ещё не открывали — надо взламывать.
func _needs_breach(vault: String) -> bool:
	if not breach_enabled or _bk_done.has(vault):
		return false
	for sh in node_info.get("shards", []):
		if str(sh["id"]) == vault:
			return str(sh.get("vault", "open")) == "closed" and (force_breach or str(sh.get("access", "ok")) == "ok")
	return false


## Куда после взятия шарда: отправить контакту (give_phone), постоять (hold) или сразу к выходу.
func _after_grab_step() -> String:
	if give_phone != "":
		return "give"
	return "hold" if hold_after_grab > 0.0 else "to_exit"


## Шаг «give»: строка шарда в ГРУЗе (событие deck) -> просьба отдать контакту -> событие give от сервера. Отказ — итог give_failed:<причина>.
func _step_give() -> void:
	if not give_log.is_empty():
		var ev: Dictionary = give_log[give_log.size() - 1]
		if bool(ev.get("ok", false)):
			_enter("to_exit")
		else:
			_finish("give_failed:" + str(ev.get("error", "")))
		return
	if _asked:
		return
	for row in deck_info.get("loot", []):
		if str(row.get("kind", "")) == "shard" and bool(row.get("give", false)):
			_asked = net.request_give(str(row["id"]), {"phone": give_phone})
			return


func _start_breach(vault: String, return_step: String) -> void:
	_bk_vault = vault
	_bk_return = return_step
	_bk = null
	_bk_no = ""
	_enter("breach")


## Демоны для взлома: сначала EXTRACT_SHARD (открывает хранилище), остальные не берём — короче цепочка, проще сетка. Влезают в RAM.
func breach_pick() -> Array:
	var ids: Array = []
	var used := 0
	var ram := int(deck_info.get("ram", 6))
	for d in deck_info.get("daemons", []):
		var cells: Array = d.get("cells", [])
		if str(d.get("effect", "")) == "EXTRACT_SHARD" and bool(d.get("loaded", true)) and not cells.is_empty() and used + cells.size() <= ram:
			ids.append(str(d["id"]))
			used += cells.size()
	return ids


## Заряжен ли демон по последнему снимку узла (state.cd: st == "charged").
func _is_charged(daemon: String) -> bool:
	for d in last_state.get("cd", []):
		if str(d.get("id", "")) == daemon:
			return str(d.get("st", "")) == "charged"
	return false


## Заряд GHOST: просьба (повтор раз в секунду: дека из Моста приходит позже входа), потом тапы автосолвером в человеческом темпе.
func _step_charge() -> void:
	if _ch != null and _ch.finished:
		_ch = null
		_ch_path = []
	if _ch == null:
		if _clock - _ch_asked_at >= GHOST_RETRY_SEC:
			_ch_asked_at = _clock
			net.request_charge(ghost_daemon)
		return
	if _clock < _ch_next_tap or _ch.pending != null:
		return
	_ch_next_tap = _clock + BREACH_TAP_PERIOD
	var have := _ch.selected().size()
	if _ch_path.is_empty() or _ch_path.size() < have or _ch_path.slice(0, have) != _ch.selected():
		_ch_path = BreachAutoSolver.solve(_ch.attempt)
	if _ch_path.size() > have and _ch.tap(_ch_path[have]):
		net.request_breach_tap(_ch_path[have])


func _step_breach() -> void:
	if _bk_no != "":
		if force_breach:   # проба отказа: причина записана, дальше — к выходу без шарда
			breach_denied = _bk_no
			if verbose:
				print("[bot] взлом отклонён: ", breach_denied)
			_bk_no = ""
			_enter("to_exit")
			return
		_finish("breach_no:" + _bk_no)
		return
	if _bk == null:
		if not _asked:
			var ids := breach_pick()
			if ids.is_empty():
				_finish("breach_no_daemons")
				return
			breach_tries += 1
			_asked = net.request_breach(_bk_vault, ids)
			_step_started = _clock
		return
	if _bk.finished:
		var opened: Array = _bk.result.get("opened", [])
		if opened.has(_bk_vault):
			_bk_done[_bk_vault] = true
		elif breach_tries >= BREACH_MAX_TRIES:
			_finish("breach_failed")
			return
		_bk = null
		_bk_path = []
		_enter(_bk_return if _bk_done.has(_bk_vault) else "breach")
		return
	if _clock < _bk_next_tap or _bk.pending != null:
		return
	_bk_next_tap = _clock + BREACH_TAP_PERIOD
	var have := _bk.selected().size()
	# Путь строим один раз; тап отклонён (подсветка откатилась) — строим заново от выбранного.
	if _bk_path.is_empty() or _bk_path.size() < have or _bk_path.slice(0, have) != _bk.selected():
		_bk_path = BreachAutoSolver.solve(_bk.attempt)
	if _bk_path.size() > have and _bk.tap(_bk_path[have]):
		net.request_breach_tap(_bk_path[have])


## Шард для сценариев GHOST/EXPOSED: в узле графа — первый лежащий из события node (id слота), в одиночном — pickup_01.
func _plain_shard() -> Dictionary:
	for sh in node_info.get("shards", []):
		if sh.get("ready", false):
			return {"id": str(sh["id"]), "pos": Vector3(float(sh["p"][0]), 0.0, float(sh["p"][2]))}
	return {"id": NetConfig.PICKUP_ID, "pos": NodeLayout.SHARD_POS}


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
