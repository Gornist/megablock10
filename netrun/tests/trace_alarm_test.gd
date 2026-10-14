extends GdUnitTestSuite
## Т3a (docs/gamedesign/ice.md §3–§4, §9): trace без пассивного спада, дрейф по тиру, спад только в хабе, события; тревога узла 0–100:
## за такт/секунду присутствия, события, остывание только пустого узла, уровни 0–4 и их эффекты. Узел графа — фикстура graph_test.json.

static var _next_port := 18711
const GRAPH := "res://tests/fixtures/graph_test.json"
const BRIDGE := "res://tests/fixtures/graph_bridge_fixture.json"

var _root: Node
var _sroot: Node
var _croot: Node
var _server: NetServer
var _world: GraphWorld
var _bridge: FakeBridge
var _bot: BotClient
var _cfg: NetConfig


func before_test() -> void:
	_root = Node.new()
	add_child(_root)
	_sroot = Node.new()
	_sroot.name = "S"
	_croot = Node.new()
	_croot.name = "C"
	_root.add_child(_sroot)
	_root.add_child(_croot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), _sroot.get_path())
	get_tree().set_multiplayer(SceneMultiplayer.new(), _croot.get_path())
	_cfg = NetConfig.new()
	_cfg.port = _next_port
	_next_port += 1
	_cfg.token = "t03:token-t03"
	_bridge = FakeBridge.new(BRIDGE)
	_server = NetServer.new()
	_sroot.add_child(_server)
	assert_int(_server.start(_cfg, _bridge)).is_equal(OK)
	_world = GraphWorld.new()
	_world.ice_settings = {"sight_range": 0.0}   # ICE слепы: тревогу и trace трогаем только сами
	_sroot.add_child(_world)
	_world.start(_server, _bridge, NodeGraph.load_file(GRAPH))
	_bot = BotClient.new()
	_croot.add_child(_bot)


func after_test() -> void:
	if _bot.net != null:
		await _bot.net.drop()
	_server.stop_net()
	_root.queue_free()


func _wait_for(cond: Callable, sec: float = 10.0) -> bool:
	var t := 0.0
	while t < sec:
		if cond.call():
			return true
		await get_tree().create_timer(0.05).timeout
		t += 0.05
	return cond.call()


func _meter() -> TraceMeter:
	return TraceMeter.new({"weights": {"seen_by_ice": 0.0}})


# --- trace

func test_пассивного_спада_нет() -> void:
	var m := _meter()
	m.add_amount(30.0, 0.0)
	m.tick(100.0, true)   # скрыт, прошло 100 с — раньше −1/с обнулило бы
	assert_float(m.value()).is_equal(30.0)


func test_дрейф_по_тиру_узла() -> void:
	assert_float(_world.node_of("g_a").trace_drift_rate()).is_equal_approx(1.0 / 60.0, 0.00001)   # BASE
	assert_float(_world.node_of("g_c").trace_drift_rate()).is_equal_approx(1.0 / 30.0, 0.00001)   # HARD
	assert_float(_world.node_of("g_d").trace_drift_rate()).is_equal_approx(1.0 / 15.0, 0.00001)   # NIGHTMARE
	var m := _meter()
	m.tick(0.0, true, 1.0 / 30.0)
	m.tick(60.0, true, 1.0 / 30.0)   # минута в HARD — +2
	assert_float(m.value()).is_equal_approx(2.0, 0.001)


func test_хаб_спадает_и_не_дрейфует() -> void:
	var hub: GrayNode = _world.node_of("g_a")
	hub.node_def["hub"] = true
	assert_bool(hub.is_hub()).is_true()
	assert_float(hub.trace_drift_rate()).is_equal_approx(-0.1, 0.00001)   # −1 за 10 с
	var m := _meter()
	m.add_amount(20.0, 0.0)
	m.tick(0.0, true, hub.trace_drift_rate())
	m.tick(50.0, true, hub.trace_drift_rate())
	assert_float(m.value()).is_equal_approx(15.0, 0.001)


func test_jitter_замораживает_и_рост_и_спад() -> void:
	var m := _meter()
	m.add_amount(10.0, 0.0)
	m.freeze(0.0, 10.0)
	m.tick(20.0, true, 0.1)   # 10 с заморозки не считаются: +1 за оставшиеся 10 с
	assert_float(m.value()).is_equal_approx(11.0, 0.001)
	m.freeze(20.0, 10.0)
	m.tick(30.0, true, -0.1)  # весь отрезок под заморозкой — спада нет
	assert_float(m.value()).is_equal_approx(11.0, 0.001)


func test_пример_ice_md_3_около_51_за_забег() -> void:
	# 5 минут BASE (+5), 10 минут HARD (+20), один Поиск (+10), две ловушки HARD (+16) — 51
	var m := _meter()
	var base := 1.0 / 60.0
	var hard := 1.0 / 30.0
	m.tick(0.0, true, base)
	m.tick(300.0, true, base)
	m.tick(300.0, true, hard)
	m.tick(900.0, true, hard)
	m.add_action("search", 900.0)
	m.add_amount(8.0, 900.0)
	m.add_amount(8.0, 900.0)
	assert_float(m.value()).is_equal_approx(51.0, 0.01)
	assert_int(m.level()).is_equal(TraceMeter.Level.TRACE)


func test_события_trace_из_настроек() -> void:
	var node: GrayNode = _world.node_of("g_a")
	assert_float(float(node.settings["trace_events"]["search"])).is_equal(10.0)
	assert_float(float(node.settings["trace_events"]["fail"])).is_equal(5.0)
	assert_float(float(node.settings["trace_events"]["tracer"])).is_equal(15.0)


# --- тревога узла

func test_уровни_тревоги() -> void:
	assert_int(GrayNode.alarm_level_for(0.0)).is_equal(0)
	assert_int(GrayNode.alarm_level_for(24.9)).is_equal(0)
	assert_int(GrayNode.alarm_level_for(25.0)).is_equal(1)
	assert_int(GrayNode.alarm_level_for(50.0)).is_equal(2)
	assert_int(GrayNode.alarm_level_for(75.0)).is_equal(3)
	assert_int(GrayNode.alarm_level_for(100.0)).is_equal(4)


func test_события_тревоги_и_прежнее_alert_0_1() -> void:
	var node: GrayNode = _world.node_of("g_a")
	assert_float(node.alarm).is_equal(0.0)
	node.alarm_event("search")
	assert_float(node.alarm).is_equal_approx(10.0, 0.001)
	assert_float(node.alert).is_equal_approx(0.1, 0.0001)   # наружу прежняя шкала 0…1 = тревога / 100
	node.alarm_event("eject")
	assert_float(node.alarm).is_equal_approx(30.0, 0.001)
	node.alarm_event("fail")
	node.alarm_event("sensor")
	node.alarm_event("barrier")
	node.alarm_event("tracer")
	assert_float(node.alarm).is_equal_approx(30.0 + 10.0 + 5.0 + 10.0 + 10.0, 0.001)
	node.raise_alert(1.0)   # прежний вызов в шкале 0…1: до потолка
	assert_float(node.alarm).is_equal(100.0)
	assert_float(node.alert).is_equal(1.0)


func test_уровень_1_включает_спящие_датчики_и_уровень_2_даёт_зрение_ice() -> void:
	var node: GrayNode = _world.node_of("g_a")
	assert_bool(node.sensors_armed).is_false()
	node.raise_alarm(25.0)
	assert_int(node.alarm_level).is_equal(1)
	assert_bool(node.sensors_armed).is_true()
	node.raise_alarm(25.0)
	assert_int(node.alarm_level).is_equal(2)


func test_остывание_только_пустого_узла_минус_1_за_6_с() -> void:
	var node: GrayNode = _world.node_of("g_a")
	node.settings["alert_cool_sec_per_point"] = 6.0
	node.raise_alarm(50.0)
	node._alert_t = node._now
	node._now += 12.0
	node._tick_alert()   # пустой узел: −2 пункта
	assert_float(node.alarm).is_equal_approx(48.0, 0.001)


func test_присутствие_нетраннера_поднимает_тревогу_и_не_даёт_остыть() -> void:
	var node: GrayNode = _world.node_of("g_a")
	node.raise_alarm(20.0)
	_bot.route.assign([])
	_bot.use_ghost = false
	_bot.start(_cfg, BotClient.Scenario.GRAPH_RUN)
	assert_bool(await _wait_for(func(): return node._node_occupied())).is_true()
	var before := node.alarm
	await get_tree().create_timer(1.5).timeout
	assert_float(node.alarm).is_greater(before - 0.001)   # с нетраннером в узле тревога не остывает


func test_уровень_4_закрывает_порталы_через_10_тактов() -> void:
	var node: GrayNode = _world.node_of("g_b")
	node.raise_alarm(100.0)
	assert_int(node.alarm_level).is_equal(4)
	assert_bool(node.is_locked_down()).is_false()   # сразу не закрывается: ждём alert_lockdown_ticks тактов
	for i in 9:
		node._alarm_on_tick()
	assert_bool(node.is_locked_down()).is_false()
	node._alarm_on_tick()   # десятый такт
	assert_bool(node.is_locked_down()).is_true()
	assert_float(node.lockdown_left_sec()).is_greater(1.0)
