extends GdUnitTestSuite
## Black ICE (P4): охота, флэтлайн с «ждём мастера», мёртвая дека, сожжённая дека при выходе под охотой.
## Сервер (NetServer + GrayNode + фейковый Мост) и бот в одном процессе, как в gray_node_test.gd. Black ICE живёт в логове по тактам (TickBlack):
## часы тактов узла в этом наборе не тикают, такты Black ICE даёт тест (_black_tick), а охота и флэтлайн идут по тем же событиям узла, что и в игре.
## Все Soft ICE слепы (sight_range 0); охоту будит trace (≥ 50), а не зрение.

const LegacyLair := preload("res://tests/legacy_lair_util.gd")

static var _next_port := 18391
const SESSION := "s_fake000000000001"
const NODE := "node_07"
const DEAD_DECK := "it_fake000000d002"   # обычный демон: при флэтлайне остаётся в узле
const PROTECTED := "it_fake000000d001"   # защищённый: на телефон при любом исходе

var _root: Node
var _server: NetServer
var _node: GrayNode
var _bridge: FakeBridge
var _bot: BotClient
var _cfg: NetConfig
var _events: Array = []


var _croot: Node
var _sroot: Node
var _boots := 0


## Узел с Black ICE в логове (legacy-комната + логово). lair=false — раскладка без логова: Black ICE не селится, trace 100 выбрасывает Soft ICE.
func _setup(lair: bool = true) -> void:
	_root = Node.new()
	_root.name = "BlackTestRoot"
	add_child(_root)
	_croot = Node.new()
	_croot.name = "C"
	_root.add_child(_croot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), _croot.get_path())
	_cfg = NetConfig.new()
	_cfg.port = _next_port
	_next_port += 1
	_cfg.token = "t03:token-t03"
	_bridge = FakeBridge.new()
	_boot(lair)
	_bot = BotClient.new()
	_croot.add_child(_bot)


## Поднять сервер мира на общем Мосте (при «рестарте» — второй раз, на том же Мосте).
func _boot(lair: bool = true) -> void:
	_boots += 1
	_sroot = Node.new()
	_sroot.name = "S%d" % _boots
	_root.add_child(_sroot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), _sroot.get_path())
	_server = NetServer.new()
	_sroot.add_child(_server)
	assert_int(_server.start(_cfg, _bridge)).is_equal(OK)
	_node = GrayNode.new()
	_sroot.add_child(_node)
	if lair:
		LegacyLair.apply(_node)
	_node.ice_settings = {"sight_range": 0.0}
	_node.trace_settings = {"decay_per_sec": 0.0}
	_events = []
	_node.event.connect(func(ev: Dictionary): _events.append(ev))  # до start: с фейковым Мостом recover идёт синхронно
	_node.start(_server, _bridge)
	_node.enable_black_ice()
	assert_bool(_node.has_black_ice()).is_equal(lair)


## «Убийство» сервера мира: сокет закрыт без прощания, сопрограммы исчезают вместе с узлами.
func _kill_server() -> void:
	if _sroot != null and is_instance_valid(_sroot):
		_server.stop_net()
		_root.remove_child(_sroot)
		_sroot.free()
	_sroot = null


func after_test() -> void:
	if _bot != null and _bot.net != null:
		await _bot.net.drop()
	if _server != null and _sroot != null:
		_server.stop_net()
	if _root != null:
		_root.queue_free()


func _wait_for(cond: Callable, sec: float = 30.0) -> bool:
	var t := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _kinds() -> Array:
	return _events.map(func(e): return e["kind"])


func _owner(id: String) -> String:
	return str(_bridge.doc(BridgeApi.T_ITEM, id)["data"]["owner"])


func _session_data() -> Dictionary:
	return _bridge.doc(BridgeApi.T_SESSION, SESSION)["data"]


## Бот на связи, сессия узла создана; поднять trace до уровня TRACE (охота) без зрения.
func _bot_in_node_with_trace(value: float) -> void:
	_bot.start(_cfg, BotClient.Scenario.LOITER)
	assert_bool(await _wait_for(func(): return _node.session_state(SESSION) != null)).is_true()
	(_node.session_state(SESSION) as DaemonSession).trace.add_action("door_forced", _node.now(), value / 10.0)


## Один такт Black ICE логова: игрок стоит в клетке cell (по умолчанию далеко от логова), скрыт, пока действует GHOST (как в узле).
## Сессии в узле нет (вышла) — такт не идёт.
func _black_tick(cell: Vector2i = LegacyLair.FAR) -> void:
	var ds := _node.session_state(SESSION)
	if ds == null:
		return
	_node._step_tick_black({SESSION: NodeGrid.center(cell)}, {SESSION: ds.is_ghost(_node.now())}, {}, {SESSION: ds.trace})


## Trace игрока уже ≥ 50: пробуждение (6 тактов) и первый такт охоты — Black ICE охотится, порталы закрыты.
func _hunt() -> void:
	for i in LegacyLair.TICKS_TO_HUNT:
		_black_tick()
	assert_bool(_node.black_ice().is_hunting()).is_true()


## Игрок стоит рядом с Black ICE: ожог за такт захвата, на третьем — флэтлайн (событие узла; ждёт ли исход мастера — решает узел).
func _catch() -> void:
	for i in 10:
		if "flatline" in _kinds():
			break
		var at := _node.black_ice().cell()
		_black_tick(Vector2i(at.x + 1, at.y))
	assert_array(_kinds()).contains(["flatline"])
	assert_int(int(_node.black_burns.get(SESSION, 0))).is_equal(3)


## Охота кончается: игрок скрыт (GHOST) и ушёл с засечённой клетки — два пинга подряд мимо, Black ICE теряет след и уходит в логово.
## (Если бы игрок стоял на засечённой клетке, ICE дошёл бы и «нащупал» его — это сбрасывает счёт промахов.)
func _lose_track() -> void:
	for i in 12:
		if not _node.black_ice().is_hunting():
			break
		_black_tick(LegacyLair.AWAY)
	assert_bool(_node.black_ice().is_hunting()).is_false()


func test_state_tells_the_client_when_it_is_hunted() -> void:
	# клиент по полю hunt закрывает порталы (portal_locked): охота идёт за этим игроком, а не вообще в узле
	_setup()
	_bot.start(_cfg, BotClient.Scenario.LOITER)
	assert_bool(await _wait_for(func(): return _node.session_state(SESSION) != null and _bot.last_state.has("ice"))).is_true()
	assert_bool(_bot.last_state.get("hunt", true)).is_false()  # ключ есть, охоты нет
	(_node.session_state(SESSION) as DaemonSession).trace.add_action("door_forced", _node.now(), 6.0)
	_hunt()
	assert_bool(await _wait_for(func(): return _bot.last_state.get("hunt", false))).is_true()


## session.data.world как его видит Мост (пусто, пока сервер мира ничего не писал).
func _world_of_session() -> Dictionary:
	var w: Variant = _session_data().get("world")
	return w if w is Dictionary else {}


## Записи world.hunt в сессию, в порядке вызовов: [{ok, hunt}] (отказанные тоже).
func _hunt_puts() -> Array:
	var out: Array = []
	for p in _bridge.put_log:
		if p["type"] != BridgeApi.T_SESSION or p["id"] != SESSION:
			continue
		var w: Variant = (p["data"] as Dictionary).get("world")
		if w is Dictionary and (w as Dictionary).has("hunt"):
			out.append({"ok": p["ok"], "hunt": (w as Dictionary)["hunt"]})
	return out


func _hunt_values() -> Array:
	return _hunt_puts().map(func(p): return p["hunt"])


## GHOST: Black ICE перестаёт видеть нетраннера (он выпадает из целей), охота кончается.
func _ghost_for(sec: float) -> void:
	(_node.session_state(SESSION) as DaemonSession).ghost_until = _node.now() + sec


## H1: Мост шлёт ice.hunt, когда у активной сессии world.hunt становится true. Сервер мира пишет его в начале охоты за сессией
## и снимает в конце; world.node и world.trace_level при этом остаются.
func test_hunt_is_written_to_session_world_and_cleared_when_it_ends() -> void:
	_setup()
	await _bot_in_node_with_trace(60.0)
	_hunt()
	assert_bool(await _wait_for(func(): return _world_of_session().get("hunt", false) == true)).is_true()
	var w := _world_of_session()
	assert_str(str(w.get("node", ""))).is_equal(NODE)
	assert_int(int(w.get("trace_level", -1))).is_equal(TraceMeter.Level.TRACE)
	_ghost_for(60.0)
	_lose_track()
	assert_bool(await _wait_for(func(): return _world_of_session().get("hunt", true) == false)).is_true()
	assert_str(str(_world_of_session().get("node", ""))).is_equal(NODE)  # снятие охоты остальное в world не трогает
	assert_int(int(_world_of_session().get("trace_level", -1))).is_equal(TraceMeter.Level.TRACE)


## Пишется смена охоты, а не каждый тик: за время охоты ровно одна запись true, на конце — одна false.
func test_hunt_is_written_only_when_it_changes() -> void:
	_setup()
	await _bot_in_node_with_trace(60.0)
	_hunt()
	assert_bool(await _wait_for(func(): return _world_of_session().get("hunt", false) == true)).is_true()
	await get_tree().create_timer(1.0).timeout  # десяток кадров охоты
	assert_array(_hunt_values()).is_equal([true])
	_ghost_for(60.0)
	_lose_track()
	assert_bool(await _wait_for(func(): return _world_of_session().get("hunt", true) == false)).is_true()
	await get_tree().create_timer(1.0).timeout
	assert_array(_hunt_values()).is_equal([true, false])


## Узел без охоты (trace ниже порога) в world.hunt не пишет вообще: ни true, ни лишнего false.
func test_no_hunt_no_world_hunt_writes() -> void:
	_setup()
	_bot.start(_cfg, BotClient.Scenario.LOITER)
	assert_bool(await _wait_for(func(): return _node.session_state(SESSION) != null and _bot.last_state.has("ice"))).is_true()
	for i in 12:
		_black_tick()   # trace 0: Black ICE спит, сколько бы тактов ни шло
	assert_int(_node.black_ice().phase).is_equal(TickBlack.Phase.SLEEP)
	await get_tree().create_timer(1.0).timeout
	assert_array(_hunt_values()).is_empty()
	assert_bool(_world_of_session().has("hunt")).is_false()


## Выход игрока под охотой снимает отметку: сессия закрывается, но охота за ней кончилась.
func test_hunt_is_cleared_when_the_player_leaves() -> void:
	_setup()
	await _bot_in_node_with_trace(60.0)
	_hunt()
	assert_bool(await _wait_for(func(): return _world_of_session().get("hunt", false) == true)).is_true()
	assert_bool(_bot.net.request_exit(ExitLogic.REASON_HEADSET_OFF)).is_true()
	assert_bool(await _wait_for(func(): return "finished" in _kinds())).is_true()
	assert_bool(await _wait_for(func(): return _world_of_session().get("hunt", true) == false)).is_true()
	assert_array(_hunt_values()).is_equal([true, false])


## Сессия уходит в другой узел (release_session при переходе по тоннелю): охота этого узла за ней кончилась.
func test_hunt_is_cleared_when_the_session_leaves_the_node() -> void:
	_setup()
	await _bot_in_node_with_trace(60.0)
	_hunt()
	assert_bool(await _wait_for(func(): return _world_of_session().get("hunt", false) == true)).is_true()
	assert_object(_node.release_session(SESSION)).is_not_null()
	assert_bool(await _wait_for(func(): return _world_of_session().get("hunt", true) == false)).is_true()
	assert_array(_hunt_values()).is_equal([true, false])


## Рестарт сервера мира: отметка охоты из прошлого процесса снимается, иначе следующая охота за сессией не дала бы ice.hunt
## (Мост ждёт перехода «не true → true»).
func test_stale_hunt_from_previous_process_is_cleared_on_restart() -> void:
	_setup()
	_kill_server()
	_bridge.doc(BridgeApi.T_SESSION, SESSION)["data"]["world"] = {"connected": false, "hunt": true}
	_boot()
	assert_bool(await _wait_for(func(): return _node.synced)).is_true()
	assert_array(_node.recovered_sessions).is_equal([SESSION])
	assert_bool(await _wait_for(func(): return _world_of_session().get("hunt", true) == false)).is_true()
	assert_bool(_world_of_session().get("connected", true)).is_false()  # остальное в world не тронуто


## Поимка Black ICE (флэтлайн) — тоже конец охоты.
func test_hunt_is_cleared_when_black_ice_catches() -> void:
	_setup()
	await _bot_in_node_with_trace(60.0)
	_hunt()
	assert_bool(await _wait_for(func(): return _world_of_session().get("hunt", false) == true)).is_true()
	_catch()
	assert_bool(await _wait_for(func(): return "finished" in _kinds())).is_true()
	assert_bool(await _wait_for(func(): return _world_of_session().get("hunt", true) == false)).is_true()
	# Пометка флэтлайна (_mark_finish) переписывает весь world и несёт hunt с собой, поэтому точный список не сравниваем.
	var values := _hunt_values()
	assert_bool(values.front()).is_true()
	assert_bool(values.back()).is_false()
	assert_int(values.count(true)).is_equal(1)


## Мост не отвечает на запись: игра идёт дальше (клиент получает hunt в снимке), попыток ограниченное число, очереди нет;
## связь вернулась — следующая смена охоты записывается.
func test_hunt_write_to_unreachable_bridge_is_bounded_and_recovers() -> void:
	_setup()
	_node.hunt_retry_sec = 0.01
	_bot.start(_cfg, BotClient.Scenario.LOITER)
	assert_bool(await _wait_for(func(): return _node.session_state(SESSION) != null and _bot.last_state.has("ice"))).is_true()
	_bridge.put_offline = true
	(_node.session_state(SESSION) as DaemonSession).trace.add_action("door_forced", _node.now(), 6.0)
	_hunt()
	assert_bool(await _wait_for(func(): return _bot.last_state.get("hunt", false))).is_true()  # игра охоту ведёт и без Моста
	assert_bool(await _wait_for(func(): return not _hunt_puts().is_empty())).is_true()
	assert_bool(await _wait_for(func(): return not _node.is_hunt_writing())).is_true()  # писатель сдался
	var tried := _hunt_puts().size()
	assert_int(tried).is_less_equal(GrayNode.HUNT_ATTEMPTS)
	await get_tree().create_timer(1.0).timeout
	assert_int(_hunt_puts().size()).is_equal(tried)  # сдался насовсем: тики не плодят попыток
	assert_bool(_hunt_puts().all(func(p): return not p["ok"])).is_true()
	assert_bool(_world_of_session().has("hunt")).is_false()
	_bridge.put_offline = false
	_ghost_for(60.0)  # охота кончилась (в Мосте её и не было) — писать нечего
	_lose_track()
	assert_bool(await _wait_for(func(): return not _bot.last_state.get("hunt", true))).is_true()
	await get_tree().create_timer(0.5).timeout
	assert_int(_hunt_puts().size()).is_equal(tried)
	(_node.session_state(SESSION) as DaemonSession).ghost_until = -INF  # охота началась снова: Мост уже отвечает
	_node.wake_black_ice()   # после потери следа Black ICE в чутком сне: порог trace выше, будим его мастером
	for i in 20:
		if _node.black_ice().is_hunting():
			break
		_black_tick()
	assert_bool(_node.black_ice().is_hunting()).is_true()
	assert_bool(await _wait_for(func(): return _world_of_session().get("hunt", false) == true)).is_true()


## world.node и trace_level пишутся по-прежнему (Мост по ним решает про сигнал СБ и ценности).
func test_session_world_keeps_node_and_trace_level() -> void:
	_setup()
	await _bot_in_node_with_trace(60.0)
	_hunt()
	assert_bool(await _wait_for(func(): return int(_world_of_session().get("trace_level", -1)) == TraceMeter.Level.TRACE)).is_true()
	var w := _world_of_session()
	assert_str(str(w.get("node", ""))).is_equal(NODE)
	assert_int(int(w.get("trace", -1))).is_equal(60)
	assert_bool(w.get("connected", false)).is_true()


func test_black_ice_catch_is_flatline_dead_deck_stays_protected_goes_home() -> void:
	_setup()
	await _bot_in_node_with_trace(60.0)
	_hunt()
	_catch()
	assert_bool(await _wait_for(func(): return not _bot.result.is_empty())).is_true()
	assert_str(_bot.result).is_equal("flatline")
	assert_bool(await _wait_for(func(): return "finished" in _kinds())).is_true()
	assert_array(_kinds()).contains(["flatline"])
	assert_array(_kinds()).not_contains(["ice_eject"])
	assert_str(str(_session_data()["outcome"])).is_equal("black_ice")
	assert_bool(_session_data().get("disconnect", false)).is_false()
	assert_str(_owner(DEAD_DECK)).is_equal("node:" + NODE)  # мёртвая дека — в узле, её может подобрать другой
	assert_str(_owner(PROTECTED)).is_equal("outbox:KEY_ALICE")  # защищённый демон уходит на телефон
	# Код ничего не помечает мёртвым: в документе сессии нет «dead»/«killed», только закрытая сессия с исходом.
	assert_bool(_session_data().has("dead")).is_false()


func test_flatline_waits_for_master_when_enabled_then_approve() -> void:
	_setup()
	_bridge.doc("settings", "global")["data"]["await_flatline"] = 1
	await _bot_in_node_with_trace(60.0)
	_hunt()
	_catch()
	assert_bool(await _wait_for(func(): return "waiting_master" in _kinds())).is_true()
	assert_bool(await _wait_for(func(): return _bridge.gate_calls.get("flatline:" + SESSION, 0) >= 2, 10.0)).is_true()  # опрос идёт
	assert_str(str(_session_data()["state"])).is_equal("active")  # исход не применён, пока мастер не решил
	assert_array(_kinds()).not_contains(["finished"])
	_bridge.decide_gate("flatline", SESSION, "approve")
	assert_bool(await _wait_for(func(): return "finished" in _kinds(), 10.0)).is_true()
	assert_str(str(_session_data()["outcome"])).is_equal("black_ice")
	assert_str(_owner(DEAD_DECK)).is_equal("node:" + NODE)


func test_flatline_denied_by_master_becomes_soft_outcome() -> void:
	_setup()
	_bridge.doc("settings", "global")["data"]["await_flatline"] = 1
	await _bot_in_node_with_trace(60.0)
	_hunt()
	_catch()
	assert_bool(await _wait_for(func(): return "waiting_master" in _kinds())).is_true()
	_bridge.decide_gate("flatline", SESSION, "deny")
	assert_bool(await _wait_for(func(): return "finished" in _kinds(), 10.0)).is_true()
	assert_str(str(_session_data()["outcome"])).is_equal("soft_ice")
	assert_str(_owner(DEAD_DECK)).is_equal("outbox:KEY_ALICE")  # пощадили: дека не мёртвая


func test_emergency_exit_under_hunt_burns_deck_but_not_protected() -> void:
	_setup()
	await _bot_in_node_with_trace(60.0)
	_hunt()
	assert_bool(await _wait_for(func(): return "hunt" in _kinds())).is_true()
	assert_bool(_bot.net.request_exit(ExitLogic.REASON_HEADSET_OFF)).is_true()
	assert_bool(await _wait_for(func(): return "finished" in _kinds())).is_true()
	assert_str(str(_session_data()["outcome"])).is_equal("emergency")
	assert_str(_owner(DEAD_DECK)).is_equal("burned:" + SESSION)
	assert_str(_owner(PROTECTED)).is_equal("outbox:KEY_ALICE")


func test_emergency_exit_without_hunt_keeps_deck() -> void:
	_setup()
	_bot.start(_cfg, BotClient.Scenario.LOITER)
	assert_bool(await _wait_for(func(): return _node.session_state(SESSION) != null)).is_true()
	assert_bool(await _wait_for(func(): return _bot.net.is_connected_to_world)).is_true()
	for i in 12:
		_black_tick()   # trace 0: Black ICE спит
	assert_bool(_node.black_ice().is_hunting()).is_false()
	assert_bool(_bot.net.request_exit(ExitLogic.REASON_HEADSET_OFF)).is_true()
	assert_bool(await _wait_for(func(): return "finished" in _kinds())).is_true()
	assert_str(_owner(DEAD_DECK)).is_equal("outbox:KEY_ALICE")
	assert_array(_kinds()).not_contains(["hunt"])


## Узел без Black ICE: trace 100 — выброс Soft ICE, а не флэтлайн.
func test_trace_100_without_black_ice_is_soft_eject() -> void:
	_setup(false)
	assert_bool(_node.has_black_ice()).is_false()   # раскладка без логова: Black ICE не селится
	await _bot_in_node_with_trace(100.0)
	assert_bool(await _wait_for(func(): return "finished" in _kinds())).is_true()
	assert_array(_kinds()).contains(["ice_eject"])
	assert_array(_kinds()).not_contains(["flatline"])
	assert_str(str(_session_data()["outcome"])).is_equal("soft_ice")


func test_outcome_plan_marks_disconnect_flatline() -> void:
	var plan := GrayNode.outcome_plan({"reason": "flatline", "disconnect": true})
	assert_str(plan["outcome"]).is_equal("black_ice")
	assert_bool(plan["disconnect"]).is_true()
	assert_bool(GrayNode.outcome_plan({"reason": "flatline"})["disconnect"]).is_false()


## Ждём мастера: бот уже во флэтлайне, ожидание идёт.
func _flatline_waiting() -> void:
	_setup()
	_bridge.doc("settings", "global")["data"]["await_flatline"] = 1
	await _bot_in_node_with_trace(60.0)
	_hunt()
	_catch()
	assert_bool(await _wait_for(func(): return "waiting_master" in _kinds())).is_true()


func test_restart_during_master_wait_keeps_flatline_and_finishes_once() -> void:
	await _flatline_waiting()
	# Пометка в Мосте записана ДО ожидания.
	assert_bool(await _wait_for(func(): return (_session_data().get("world", {}) as Dictionary).get("finish", "") == "flatline")).is_true()
	assert_str(str(_session_data()["state"])).is_equal("active")
	_kill_server()
	_boot()
	assert_bool(await _wait_for(func(): return _node.synced)).is_true()
	assert_array(_node.recovered_flatlines).is_equal([SESSION])
	assert_array(_node.recovered_sessions).is_empty()  # окна возврата с emergency нет
	assert_bool(await _wait_for(func(): return "waiting_master" in _kinds())).is_true()
	assert_str(str(_session_data()["state"])).is_equal("active")
	_bridge.decide_gate("flatline", SESSION, "approve")
	assert_bool(await _wait_for(func(): return "finished" in _kinds(), 10.0)).is_true()
	assert_str(str(_session_data()["outcome"])).is_equal("black_ice")
	assert_int(_bridge.finish_calls).is_equal(1)
	assert_array(_bridge.finish_attempts.map(func(a): return a["outcome"])).is_equal(["black_ice"])
	assert_str(_owner(DEAD_DECK)).is_equal("node:" + NODE)


func test_return_of_player_during_master_wait_is_refused() -> void:
	await _flatline_waiting()
	var second := BotClient.new()
	_croot.add_child(second)
	second.start(_cfg, BotClient.Scenario.LOITER)
	await get_tree().create_timer(3.0).timeout
	assert_bool(second.net.is_connected_to_world).is_false()
	assert_bool(_server.has_avatar(SESSION)).is_false()
	_bridge.decide_gate("flatline", SESSION, "approve")
	assert_bool(await _wait_for(func(): return "finished" in _kinds(), 10.0)).is_true()
	assert_array(_bridge.finish_attempts.map(func(a): return a["outcome"])).is_equal(["black_ice"])
	assert_str(str(_session_data()["outcome"])).is_equal("black_ice")
	await second.net.drop()
	# Сессия закрыта: узел снова в доступном состоянии (_finishing снят) — второй вход не заблокирован самим узлом.
	assert_bool(_node.join_blocked(SESSION)).is_false()


func test_bridge_outage_during_master_wait_does_not_approve() -> void:
	await _flatline_waiting()
	_bridge.gate_offline = true
	await get_tree().create_timer(3.5).timeout
	assert_str(str(_session_data()["state"])).is_equal("active")
	assert_array(_bridge.finish_attempts).is_empty()  # самовольного исхода нет
	_bridge.gate_offline = false
	_bridge.decide_gate("flatline", SESSION, "deny")
	assert_bool(await _wait_for(func(): return "finished" in _kinds(), 10.0)).is_true()
	assert_str(str(_session_data()["outcome"])).is_equal("soft_ice")
	assert_str(_owner(DEAD_DECK)).is_equal("outbox:KEY_ALICE")


func test_mark_finish_кладёт_журнал_black_log_в_world_сессии() -> void:
	_setup()
	await _bot_in_node_with_trace(10.0)
	var log := [{"t": 1, "ev": "wake", "why": "trace"}, {"t": 8, "ev": "flatline", "s": SESSION}]
	await _node._mark_finish(SESSION, "flatline", false, {"black_log": log})
	var w: Dictionary = _session_data()["world"]
	assert_str(str(w["finish"])).is_equal("flatline")
	assert_int((w["black_log"] as Array).size()).is_equal(2)
	assert_str(str(w["black_log"][0]["why"])).is_equal("trace")
