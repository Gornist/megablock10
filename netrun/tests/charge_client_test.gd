extends GdUnitTestSuite
## Заряд защитного демона сквозным путём без очков (К6): сервер узла + фейковый Мост + настоящий плоский клиент ProtoClient. Кнопка «ЗАРЯДИТЬ» на деке ->
## сетка на деке -> тапы по подсвеченным клеткам (автосолвер) -> «ГОТОВ К ЗАПУСКУ» -> запуск одним нажатием (левый X в VR, use_selected) -> «активен N с».

static var _next_port := 18991
const SESSION := "s_fake000000000001"
const FIXTURE := "res://tests/fixtures/charge_bridge_fixture.json"
const GHOST := "it_c_ghost"
const SKEW := "it_c_skew"
const BLACK := "it_c_black"

var _root: Node
var _server: NetServer
var _node: GrayNode
var _bridge: FakeBridge
var _cfg: NetConfig


func before_test() -> void:
	_root = Node.new()
	_root.name = "ChargeClientRoot"
	add_child(_root)
	var sroot := Node.new()
	sroot.name = "S"
	var croot := Node.new()
	croot.name = "C"
	_root.add_child(sroot)
	_root.add_child(croot)
	get_tree().set_multiplayer(SceneMultiplayer.new(), sroot.get_path())
	get_tree().set_multiplayer(SceneMultiplayer.new(), croot.get_path())
	_cfg = NetConfig.new()
	_cfg.port = _next_port
	_next_port += 1
	_cfg.token = "t03:token-t03"
	_bridge = FakeBridge.new(FIXTURE)
	_server = NetServer.new()
	sroot.add_child(_server)
	assert_int(_server.start(_cfg, _bridge)).is_equal(OK)
	_node = GrayNode.new()
	sroot.add_child(_node)
	_node.trace_settings = {"decay_per_sec": 0.0}
	_node.start(_server, _bridge)


func after_test() -> void:
	_server.stop_net()
	_root.queue_free()


func _wait_for(cond: Callable, sec: float = 15.0) -> bool:
	var t := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _client() -> ProtoClient:
	var proto := ProtoClient.new()
	_root.get_node("C").add_child(proto)
	proto.start(PackedStringArray(["--token=" + _cfg.token, "--port=%d" % _cfg.port]), "flat", false)
	return proto


func _ready_scene(proto: ProtoClient) -> Node3D:
	var scene: Node3D = proto.scene
	assert_bool(await _wait_for(func(): return scene.deck_state.size() == 4 and not scene.deck_info.is_empty())).is_true()
	return scene


## Зарядить программу как человек: выбрать, «ЗАРЯДИТЬ», сетка на деке, тапы только по подсвеченным клеткам (автосолвер).
func _charge_by_hand(scene: Node3D, id: String) -> void:
	var deck: DeckPanel = scene.world_ui.deck
	scene.selected_daemon = id
	scene.charge_selected()   # то же, что кнопка на деке: charge_requested -> сервер
	assert_bool(await _wait_for(func(): return deck.is_charging() and deck.charge_view().is_running())).is_true()
	var cv := deck.charge_view()
	var path := BreachAutoSolver.solve(cv.mirror.attempt)
	for i in path.size():
		if not cv.is_running():
			break
		assert_bool((cv.cell_nodes()[path[i]] as BreachCell).is_available()).is_true()   # подсвечена клиентом без ожидания сервера
		assert_bool(cv.tap_cell(path[i])).is_true()
		assert_bool(await _wait_for(func(): return cv.mirror == null or cv.mirror.pending == null or cv.mirror.finished)).is_true()
	assert_bool(await _wait_for(func(): return cv.mirror == null or cv.mirror.finished)).is_true()


func test_the_deck_offers_charge_buttons_only_for_protective_programs() -> void:
	var proto := _client()
	var scene := await _ready_scene(proto)
	var deck: DeckPanel = scene.world_ui.deck
	assert_bool(await _wait_for(func(): return "\n".join(deck.row_texts()).contains("не заряжен"))).is_true()
	var buttons: Array = DeckUi.buttons(deck).filter(func(b: MbButton) -> bool: return b.text == "ЗАРЯДИТЬ")
	assert_int(buttons.size()).is_equal(3)   # Призрак, Сдвиг, Затмение; у Извлечения кнопки нет
	assert_str("\n".join(deck.row_texts())).contains("4 Извлечение  готов")
	await proto.net.drop()


func test_charge_then_launch_with_one_press_opens_the_window_and_shows_active() -> void:
	var proto := _client()
	var scene := await _ready_scene(proto)
	var deck: DeckPanel = scene.world_ui.deck
	await _charge_by_hand(scene, GHOST)
	# Итог ЗАРЯЖЕН, потом дека возвращается к списку с «ГОТОВ К ЗАПУСКУ».
	assert_bool(await _wait_for(func(): return not deck.is_charging(), 6.0)).is_true()
	assert_bool(await _wait_for(func(): return "\n".join(deck.row_texts()).contains("1 Призрак  ГОТОВ К ЗАПУСКУ"))).is_true()
	assert_str("\n".join(deck.row_texts())).contains(HudLogic.LAUNCH_HINT)
	assert_array(scene.charged_ids()).is_equal([GHOST])
	# Левый X: запуск одним нажатием, без выбора (выбран другой демон — X берёт заряженного).
	scene.selected_daemon = SKEW
	assert_str(scene.launch_target()).is_equal(GHOST)
	scene.use_selected()
	assert_bool(await _wait_for(func(): return "\n".join(deck.row_texts()).contains("1 Призрак  активен"))).is_true()
	assert_array(_node.session_state(SESSION).active_effects(_node.now())).is_equal(["GHOST"])
	assert_bool(await _wait_for(func(): return scene.charged_ids().is_empty())).is_true()
	await proto.net.drop()


func test_launch_without_a_charge_says_so_in_words() -> void:
	var proto := _client()
	var scene := await _ready_scene(proto)
	var deck: DeckPanel = scene.world_ui.deck
	scene.use_slot(0)
	assert_bool(await _wait_for(func(): return deck.notice_text().contains("ЗАРЯДИТЬ"))).is_true()
	assert_array(_node.session_state(SESSION).active_effects(_node.now())).is_empty()
	await proto.net.drop()


func test_next_cycles_through_charged_programs_first() -> void:
	var proto := _client()
	var scene := await _ready_scene(proto)
	_node.session_state(SESSION).set_charged(SKEW)
	_node.session_state(SESSION).set_charged(BLACK)
	assert_bool(await _wait_for(func(): return scene.charged_ids().size() == 2)).is_true()
	scene.selected_daemon = SKEW
	scene.select_next()
	assert_str(scene.selected_daemon).is_equal(BLACK)
	scene.select_next()
	assert_str(scene.selected_daemon).is_equal(SKEW)   # незаряженные пропускаются
	await proto.net.drop()


func test_cancel_on_the_deck_stops_the_charge() -> void:
	var proto := _client()
	var scene := await _ready_scene(proto)
	var deck: DeckPanel = scene.world_ui.deck
	scene.selected_daemon = GHOST
	scene.charge_selected()
	assert_bool(await _wait_for(func(): return deck.is_charging() and deck.charge_view().is_running())).is_true()
	var cancel: Array = DeckUi.buttons(deck).filter(func(b: MbButton) -> bool: return b.text == "ОТМЕНА")
	(cancel[0] as MbButton).click()
	assert_bool(await _wait_for(func(): return not _node.charge.has_attempt(SESSION))).is_true()
	assert_bool(_node.session_state(SESSION).is_charged(GHOST)).is_false()
	assert_bool(await _wait_for(func(): return not deck.is_charging(), 6.0)).is_true()
	await proto.net.drop()
