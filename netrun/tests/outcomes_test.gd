extends GdUnitTestSuite
## Исходы забега (P2): таблица «Забег» из docs/netrun.md по строкам, каждая — до итогового состояния предметов в Мосте.
## Сервер (NetServer + GrayNode + фейковый Мост) и бот в одном процессе, как в black_ice_test.gd. Во всех проверках
## у игрока есть шард из узла (добыча), обычный демон (его судьба зависит от исхода) и защищённый демон (всегда на телефон).
## Все Soft ICE слепы (sight_range 0): забег решают trace, выход и обрыв, а не случайная встреча с ICE.
## Чего здесь нет и быть не может: паузы повторного входа и локдауна узла у настоящего Моста (FakeBridge правил Моста не знает) —
## их проверяет ValueOpsTest (Kotlin); сторона Godot — outcomes_graph_test.gd.

static var _next_port := 18691
const SESSION := "s_fake000000000001"
const NODE := "node_07"
const SHARD := "it_fake00000000a001"      # добыча забега: шард узла
const DAEMON := "it_fake000000d002"      # обычный демон деки
const PROTECTED := "it_fake000000d001"   # защищённый демон: на телефон при любом исходе
const PHONE := "outbox:KEY_ALICE"
const IN_NODE := "node:node_07"

var _root: Node
var _server: NetServer
var _node: GrayNode
var _bridge: FakeBridge
var _bot: BotClient
var _cfg: NetConfig
var _events: Array = []


## black — в узле Black ICE (тир NIGHTMARE); hunt_speed — его скорость охоты; grace — окно возврата после обрыва;
## await_master — флэтлайн ждёт решения мастера (settings/global.await_flatline).
func _setup(black: bool = false, hunt_speed: float = 2.0, grace: float = 1.5, await_master: bool = false) -> void:
	_root = Node.new()
	_root.name = "OutcomesTestRoot"
	add_child(_root)
	var croot := Node.new()
	croot.name = "C"
	_root.add_child(croot)
	var sroot := Node.new()
	sroot.name = "S"
	_root.add_child(sroot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), croot.get_path())
	get_tree().set_multiplayer(SceneMultiplayer.new(), sroot.get_path())
	_cfg = NetConfig.new()
	_cfg.port = _next_port
	_next_port += 1
	_cfg.token = "t03:token-t03"
	_cfg.grace_sec = grace
	_bridge = FakeBridge.new()
	if await_master:
		_bridge.doc("settings", "global")["data"]["await_flatline"] = 1
	_server = NetServer.new()
	sroot.add_child(_server)
	assert_int(_server.start(_cfg, _bridge)).is_equal(OK)
	_node = GrayNode.new()
	sroot.add_child(_node)
	_node.ice_settings = {"sight_range": 0.0}
	_node.trace_settings = {"decay_per_sec": 0.0}
	_node.black_ice_settings = {"hunt_speed": hunt_speed}
	_events = []
	_node.event.connect(func(ev: Dictionary): _events.append(ev))
	_node.start(_server, _bridge)
	if black:
		_node.enable_black_ice()
	_bot = BotClient.new()
	croot.add_child(_bot)


func after_test() -> void:
	if _bot != null and _bot.net != null:
		await _bot.net.drop()
	if _server != null:
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


## Позиция аватара на сервере; аватара нет — точка далеко за комнатой (условия ожидания не должны падать на null).
func _avatar_pos() -> Vector3:
	var a := _server.get_avatar(SESSION)
	return a.position if a != null else Vector3(1e6, 0, 1e6)


func _hunt_events(on: bool) -> Array:
	return _events.filter(func(e): return e["kind"] == "hunt" and e["on"] == on)


## Бот в узле (ходит кругами у входа). take_shard — идёт к постаменту, берёт шард: он у игрока в деке (в Мосте deck:<сессия>).
func _enter_node(take_shard: bool = false) -> void:
	if take_shard:
		_bot.loiter_center = Vector3(NodeLayout.SHARD_POS.x, 0, NodeLayout.SHARD_POS.z + 1.0)  # круг у хранилища шарда
		_bot.loiter_radius = 0.5
	_bot.start(_cfg, BotClient.Scenario.LOITER)
	assert_bool(await _wait_for(func(): return _node.session_state(SESSION) != null and _bot.net.is_connected_to_world)).is_true()
	if not take_shard:
		return
	assert_bool(await _wait_for(func(): return NodeLayout.flat_distance(_avatar_pos(), NodeLayout.SHARD_POS) < 2.5)).is_true()
	assert_bool(_bot.net.request_grab(NetConfig.PICKUP_ID)).is_true()
	assert_bool(await _wait_for(func(): return _bot.shard_taken and _owner(SHARD) == "deck:" + SESSION)).is_true()


## Поднять trace игрока до value (door_forced весит 10; спад в этом узле выключен).
func _trace(value: float) -> void:
	(_node.session_state(SESSION) as DaemonSession).trace.add_action("door_forced", _node.now(), value / 10.0)


func _wait_finished(sec: float = 15.0) -> void:
	assert_bool(await _wait_for(func(): return "finished" in _kinds(), sec)).is_true()


## Что осталось в Мосте после исхода: куда ушли добыча, обычный и защищённый демоны. Защищённый — всегда на телефон.
func _assert_items(shard: String, daemon: String) -> void:
	assert_str(_owner(SHARD)).is_equal(shard)
	assert_str(_owner(DAEMON)).is_equal(daemon)
	assert_str(_owner(PROTECTED)).is_equal(PHONE)


# ---------------------------------------------------------------- чистый выход

func test_clean_exit_brings_loot_and_whole_deck_to_phone() -> void:
	_setup()
	_bot.start(_cfg, BotClient.Scenario.GHOST_RUN)
	assert_bool(await _wait_for(func(): return not _bot.result.is_empty())).is_true()
	assert_str(_bot.result).is_equal("clean")
	await _wait_finished()
	assert_str(str(_session_data()["state"])).is_equal("closed")
	assert_str(str(_session_data()["outcome"])).is_equal("clean")
	assert_bool(bool(_session_data().get("disconnect", false))).is_false()
	_assert_items(PHONE, PHONE)


func test_leave_works_only_on_the_exit_pad() -> void:
	_setup()
	_bot.loiter_center = NodeLayout.EXIT_POS + Vector3(0, 0, 0.5)  # круг радиуса 0.5 на площадке выхода
	_bot.loiter_radius = 0.5
	_bot.start(_cfg, BotClient.Scenario.LOITER)
	assert_bool(await _wait_for(func(): return _node.session_state(SESSION) != null and _bot.net.is_connected_to_world)).is_true()
	# бот ещё у входа (в 5 м от площадки): просьба выйти чисто сервером отклоняется
	assert_bool(NodeLayout.on_exit_pad(_avatar_pos())).is_false()
	assert_bool(_bot.net.request_leave()).is_true()
	await get_tree().create_timer(0.4).timeout
	assert_array(_kinds()).not_contains(["exit"])
	assert_bool(_server.has_avatar(SESSION)).is_true()
	assert_str(str(_session_data()["state"])).is_equal("active")
	# дошёл до площадки — та же просьба закрывает забег чисто
	assert_bool(await _wait_for(func(): return NodeLayout.on_exit_pad(_avatar_pos()), 10.0)).is_true()
	assert_bool(_bot.net.request_leave()).is_true()
	await _wait_finished()
	assert_str(str(_session_data()["outcome"])).is_equal("clean")


# ---------------------------------------------------------------- аварийное отключение

func test_emergency_exit_without_hunt_keeps_deck_and_leaves_loot_in_node() -> void:
	_setup()
	await _enter_node(true)
	assert_bool(_bot.net.request_exit(ExitLogic.REASON_MANUAL_HOLD)).is_true()
	await _wait_finished()
	assert_str(str(_session_data()["outcome"])).is_equal("emergency")
	assert_bool(bool(_session_data()["disconnect"])).is_false()  # снял очки сам: это не обрыв
	_assert_items(IN_NODE, PHONE)
	assert_str(_server.holder_of(NetConfig.PICKUP_ID)).is_empty()  # шард снова на постаменте


func test_emergency_exit_under_hunt_burns_deck_loot_stays_protected_goes_home() -> void:
	_setup(true, 0.2)  # медленный охотник: до выхода не догонит
	await _enter_node(true)
	_trace(60.0)
	assert_bool(await _wait_for(func(): return not _hunt_events(true).is_empty())).is_true()
	assert_bool(_bot.net.request_exit(ExitLogic.REASON_HEADSET_OFF)).is_true()
	await _wait_finished()
	assert_str(str(_session_data()["outcome"])).is_equal("emergency")
	assert_bool(bool(_session_data()["disconnect"])).is_false()
	_assert_items(IN_NODE, "burned:" + SESSION)  # добычу огонь не берёт: она остаётся в узле
	assert_array(_kinds()).not_contains(["flatline"])


func test_ghost_breaks_the_hunt_so_emergency_exit_keeps_deck() -> void:
	_setup(true, 0.2)
	await _enter_node()
	_trace(60.0)
	assert_bool(await _wait_for(func(): return not _hunt_events(true).is_empty())).is_true()
	(_node.session_state(SESSION)).set_charged("ghost_1")   # защитный демон вне взлома работает только заряженным (К6)
	assert_bool(_bot.net.request_use("ghost_1")).is_true()  # охота идёт по позиции, спрятанного GHOST'ом она не видит
	assert_bool(await _wait_for(func(): return not _hunt_events(false).is_empty())).is_true()
	assert_bool(_bot.net.request_exit(ExitLogic.REASON_MANUAL_HOLD)).is_true()
	await _wait_finished()
	assert_str(str(_session_data()["outcome"])).is_equal("emergency")
	_assert_items(IN_NODE, PHONE)  # шард в этом тесте не брали: он как лежал в узле, так и лежит


# ---------------------------------------------------------------- Soft ICE

func test_soft_ice_eject_returns_deck_and_leaves_loot_in_node() -> void:
	_setup()  # без Black ICE: trace 100 — выброс
	await _enter_node(true)
	_trace(100.0)
	assert_bool(await _wait_for(func(): return not _bot.result.is_empty())).is_true()
	assert_str(_bot.result).is_equal("ejected")  # игрок видит причину
	await _wait_finished()
	assert_array(_kinds()).contains(["ice_eject"])
	assert_array(_kinds()).not_contains(["flatline"])
	assert_str(str(_session_data()["outcome"])).is_equal("soft_ice")
	assert_bool(bool(_session_data()["disconnect"])).is_false()
	_assert_items(IN_NODE, PHONE)
	assert_bool(_server.has_avatar(SESSION)).is_false()


## Мёртвая дека чужого (`phone:<чужой>`) лежит в грузе: при Soft ICE она добыча и остаётся в узле. Раньше сервер делил по origin и слал её
## на телефон — настоящий Мост отвечал `bad_request` без повтора, сессия зависала (FakeBridge правил исхода не знает: проверяем владельца).
func test_soft_ice_leaves_foreign_phone_cargo_in_node() -> void:
	_setup()
	const CARGO := "it_fake000000d0c1"
	var cargo := {"owner": "deck:" + SESSION, "kind": "DAEMON", "payload": "pc", "protected": false, "origin": "phone:KEY_BOB"}
	assert_bool((await _bridge.put_doc(BridgeApi.T_ITEM, CARGO, 0, cargo)).get("ok", false)).is_true()
	_session_data()["loaded"] = [PROTECTED, DAEMON]   # сданное при входе: чужой демон в `loaded` не входит
	await _enter_node(true)
	_trace(100.0)
	assert_bool(await _wait_for(func(): return not _bot.result.is_empty())).is_true()
	await _wait_finished()
	assert_str(str(_session_data()["outcome"])).is_equal("soft_ice")
	assert_str(_owner(CARGO)).is_equal(IN_NODE)
	_assert_items(IN_NODE, PHONE)


# ---------------------------------------------------------------- Black ICE

func test_black_ice_flatline_dead_deck_and_loot_stay_in_node_protected_goes_home() -> void:
	_setup(true, 8.0)
	await _enter_node(true)
	_trace(60.0)
	assert_bool(await _wait_for(func(): return not _bot.result.is_empty())).is_true()
	assert_str(_bot.result).is_equal("flatline")
	await _wait_finished()
	assert_str(str(_session_data()["outcome"])).is_equal("black_ice")
	assert_bool(bool(_session_data()["disconnect"])).is_false()
	_assert_items(IN_NODE, IN_NODE)  # мёртвая дека — в узле, как и добыча
	assert_array(_kinds()).not_contains(["ice_eject"])
	# Никакой автосмерти: единственный исход ушёл в Мост один раз, помечать персонажа мёртвым код не умеет.
	assert_array(_bridge.finish_attempts.map(func(a): return a["outcome"])).is_equal(["black_ice"])
	for key in ["dead", "killed", "died", "death"]:
		assert_bool(_session_data().has(key)).is_false()


func test_pardon_before_flatline_is_the_soft_ice_outcome() -> void:
	_setup(true, 8.0, 1.5, true)
	await _enter_node(true)
	_trace(60.0)
	assert_bool(await _wait_for(func(): return "waiting_master" in _kinds())).is_true()
	# пока мастер не решил, ничего не применено, персонаж жив
	assert_str(str(_session_data()["state"])).is_equal("active")
	assert_array(_bridge.finish_attempts).is_empty()
	_bridge.decide_gate("flatline", SESSION, "deny")
	await _wait_finished()
	assert_str(str(_session_data()["outcome"])).is_equal("soft_ice")
	assert_bool(bool(_session_data()["disconnect"])).is_false()
	_assert_items(IN_NODE, PHONE)  # как у Soft ICE: добыча в узле, дека домой (не мёртвая)


# ---------------------------------------------------------------- обрыв связи

func test_drop_is_emergency_after_grace_deck_kept_loot_in_node() -> void:
	_setup()
	await _enter_node(true)
	await _bot.net.drop()
	assert_bool(await _wait_for(func(): return _server.peer_of(SESSION) == -1)).is_true()
	# окно возврата: аватар ещё в Сети, забег не закрыт
	await get_tree().create_timer(0.6).timeout
	assert_bool(_server.has_avatar(SESSION)).is_true()
	assert_object(_node.session_state(SESSION)).is_not_null()
	assert_array(_bridge.finish_attempts).is_empty()
	assert_str(str(_session_data()["state"])).is_equal("active")
	await _wait_finished()
	var exits := _events.filter(func(e): return e["kind"] == "exit")
	assert_str(exits[0]["reason"]).is_equal(ExitLogic.REASON_CONNECTION_LOST)
	assert_str(str(_session_data()["outcome"])).is_equal("emergency")
	assert_bool(bool(_session_data()["disconnect"])).is_true()
	_assert_items(IN_NODE, PHONE)


func test_drop_under_hunt_burns_deck_after_grace() -> void:
	_setup(true, 0.2)
	await _enter_node(true)
	_trace(60.0)
	assert_bool(await _wait_for(func(): return not _hunt_events(true).is_empty())).is_true()
	await _bot.net.drop()
	await _wait_finished()
	assert_array(_kinds()).not_contains(["flatline"])
	assert_str(str(_session_data()["outcome"])).is_equal("emergency")
	assert_bool(bool(_session_data()["disconnect"])).is_true()
	_assert_items(IN_NODE, "burned:" + SESSION)  # обрыв под охотой — не бесплатное бегство


func test_return_within_grace_continues_the_same_run() -> void:
	_setup(false, 2.0, 6.0)
	await _enter_node()
	_trace(30.0)
	var avatar_id := _server.avatar_id(SESSION)
	await _bot.net.drop()
	assert_bool(await _wait_for(func(): return _server.peer_of(SESSION) == -1)).is_true()
	_bot.net.reconnect()
	assert_bool(await _wait_for(func(): return _server.peer_of(SESSION) != -1)).is_true()
	await get_tree().create_timer(0.5).timeout
	assert_int(_server.avatar_id(SESSION)).is_equal(avatar_id)  # тот же аватар
	assert_float((_node.session_state(SESSION) as DaemonSession).trace.value()).is_equal(30.0)  # trace не сбросился
	assert_array(_bridge.finish_attempts).is_empty()
	# ... и дальше обычный исход, не обрыв
	assert_bool(_bot.net.request_exit(ExitLogic.REASON_MANUAL_HOLD)).is_true()
	await _wait_finished()
	assert_str(str(_session_data()["outcome"])).is_equal("emergency")
	assert_bool(bool(_session_data()["disconnect"])).is_false()


func test_black_ice_catches_dropped_avatar_within_grace_is_disconnect_flatline() -> void:
	_setup(true, 8.0, 15.0, true)
	await _enter_node(true)
	await _bot.net.drop()
	assert_bool(await _wait_for(func(): return _server.peer_of(SESSION) == -1)).is_true()
	_trace(60.0)  # аватар в Сети, trace растёт — охота
	assert_bool(await _wait_for(func(): return "waiting_master" in _kinds())).is_true()
	assert_array(_kinds()).contains(["flatline"])
	# Мастер ещё решает: пометка в Мосте уже несёт «обрыв до флэтлайна», персонаж жив
	var world: Dictionary = _session_data()["world"]
	assert_str(str(world["finish"])).is_equal("flatline")
	assert_bool(bool(world["disconnect"])).is_true()
	assert_str(str(_session_data()["state"])).is_equal("active")
	_bridge.decide_gate("flatline", SESSION, "approve")
	await _wait_finished()
	assert_str(str(_session_data()["outcome"])).is_equal("black_ice")
	assert_bool(bool(_session_data()["disconnect"])).is_true()  # из этого флага Мост пишет «обрыв до флэтлайна»
	_assert_items(IN_NODE, IN_NODE)


func test_pardon_of_disconnect_flatline_is_plain_soft_ice() -> void:
	_setup(true, 8.0, 15.0, true)
	await _enter_node(true)
	await _bot.net.drop()
	assert_bool(await _wait_for(func(): return _server.peer_of(SESSION) == -1)).is_true()
	_trace(60.0)
	assert_bool(await _wait_for(func(): return "waiting_master" in _kinds())).is_true()
	_bridge.decide_gate("flatline", SESSION, "deny")
	await _wait_finished()
	assert_str(str(_session_data()["outcome"])).is_equal("soft_ice")
	assert_bool(bool(_session_data()["disconnect"])).is_false()  # пощада снимает и пометку обрыва
	_assert_items(IN_NODE, PHONE)


# ---------------------------------------------------------------- таблица целиком

## Таблица «Забег» (docs/netrun.md) как данные: причина выхода сервера -> исход Моста и судьба добычи/деки.
func test_outcome_plan_matches_the_docs_table() -> void:
	var rows := [
		# [событие выхода, исход, добыча, обычный демон, disconnect]
		[{"reason": "clean"}, "clean", "phone", "phone", false],
		[{"reason": "manual_hold", "deck_burned": false}, "emergency", "node", "phone", false],
		[{"reason": "headset_off", "deck_burned": false}, "emergency", "node", "phone", false],
		[{"reason": "manual_hold", "deck_burned": true}, "emergency", "node", "burned", false],
		[{"reason": "headset_off", "deck_burned": true}, "emergency", "node", "burned", false],
		[{"reason": "connection_lost", "deck_burned": false}, "emergency", "node", "phone", true],
		[{"reason": "connection_lost", "deck_burned": true}, "emergency", "node", "burned", true],
		[{"reason": "ejected"}, "soft_ice", "node", "phone", false],
		[{"reason": "flatline"}, "black_ice", "node", "node", false],
		[{"reason": "flatline", "disconnect": true}, "black_ice", "node", "node", true],
	]
	for r in rows:
		var plan := GrayNode.outcome_plan(r[0])
		var what := str(r[0])
		assert_str(plan["outcome"]).override_failure_message("исход %s" % what).is_equal(r[1])
		assert_str(plan["loot"]).override_failure_message("добыча %s" % what).is_equal(r[2])
		assert_str(plan["daemon"]).override_failure_message("демон %s" % what).is_equal(r[3])
		assert_bool(plan["disconnect"]).override_failure_message("disconnect %s" % what).is_equal(r[4])
