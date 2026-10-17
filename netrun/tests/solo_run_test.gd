extends GdUnitTestSuite
## Забег одиночной игры (client/solo_stub.gd, flat-playtest.md п. 6 и 10): первый вход — учебный узел, конец сессии — run_finished,
## restart() — новая попытка без перезапуска exe с Архива (или снова учебный), порт прошлой попытки освобождается.

const SoloStubScript := preload("res://client/solo_stub.gd")
const SESSION := "s_fake000000000001"
const ARCHIVE := "node_03"
const LOCK_SIGN := "СНАЧАЛА ЗАМОК, ПОТОМ ДЕМОНЫ"
## Слова управления, которых не должно быть в табличках мира: клавиши — на картинке управления и в подсказках H.
const KEY_WORDS := ["WASD", "мыш", "стик", "кнопк", "клавиш", "(1)"]

var _solo: Node
var _results: Array = []


func before_test() -> void:
	_results = []


func after_test() -> void:
	if _solo != null:
		await _solo.stop()
		_solo.free()
		_solo = null


func _wait_for(cond: Callable, sec: float = 15.0) -> bool:
	var t := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _start(args: PackedStringArray = PackedStringArray()) -> void:
	_solo = SoloStubScript.new()
	add_child(_solo)
	_solo.run_finished.connect(func(result: String, tutorial: bool): _results.append([result, tutorial]))
	var run_args := PackedStringArray(args)
	run_args.append(SoloStubScript.NO_UI_ARG)   # здесь проверяем забег и порты, экраны тестера — в solo_ui_test
	assert_bool(_solo.start(run_args)).is_true()


## Узел, где клиент стоит по последнему EV_NODE.
func _client_node() -> String:
	var proto := _solo.flat.get_node_or_null("Proto") as ProtoClient if _solo.flat != null else null
	return proto.scene.current_node if proto != null and proto.scene != null else ""


## Игрок вошёл: аватар на сервере в узле id и клиент получил описание этого узла.
func _arrived(id: String) -> bool:
	return await _wait_for(func(): return _solo.server.net.has_avatar(SESSION) and _solo.server.graph_world.where(SESSION) == id and _client_node() == id)


func test_данные_граф_без_ошибок_учебный_узел_вне_входов() -> void:
	var g := NodeGraph.load_file(SoloStubScript.GRAPH)
	assert_array(g.errors()).is_empty()
	assert_bool(g.is_tutorial(SoloStubScript.NODE_TUTORIAL)).is_true()
	assert_str(g.entry_for(SoloStubScript.TERMINAL)).is_equal(ARCHIVE)


func test_фикстура_попытки_новичок_в_учебном_прошедший_в_узле_терминала() -> void:
	var path := "user://solo_run_test/bridge_fixture.json"
	for with_tutorial: bool in [true, false]:
		assert_str(SoloStubScript.write_fixture(with_tutorial, path)).is_equal(path)
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert_str(str(d["sessions"][SESSION]["node"])).is_equal(SoloStubScript.NODE_TUTORIAL if with_tutorial else ARCHIVE)
		assert_bool(bool(d["runners"][SoloStubScript.RUNNER_DOC]["tutorial_done"])).is_equal(not with_tutorial)
	DirAccess.remove_absolute(path)


func test_таблички_без_клавиш_и_у_хранилища_про_замок() -> void:
	var texts: Array = []
	var layout := LayoutData.load_named("foyer_tutorial")
	for s: Dictionary in layout.signs:
		texts.append(str(s["text"]))
	var g := NodeGraph.load_file(SoloStubScript.GRAPH)
	for s: Dictionary in g.nodes[SoloStubScript.NODE_TUTORIAL]["signs"]:
		texts.append(str(s["text"]))
	for t: String in texts:
		for w: String in KEY_WORDS:
			assert_bool(t.contains(w)).override_failure_message("табличка «%s» говорит про управление (%s)" % [t, w]).is_false()
	var lock_cell := Vector2i(-1, -1)
	for s: Dictionary in layout.signs:
		if s["text"] == LOCK_SIGN:
			lock_cell = LayoutData.block_of(s["cell"])
	assert_int(maxi(absi(lock_cell.x - 1), absi(lock_cell.y - 1))).is_equal(1)   # соседняя клетка карты от (1, 1), у площадки хранилища


func test_первый_вход_учебный_затем_restart_в_архив_и_порт_свободен() -> void:
	_start()
	assert_bool(_solo.tutorial).is_true()
	assert_bool(await _arrived(SoloStubScript.NODE_TUTORIAL)).is_true()
	var tut: GrayNode = _solo.server.graph_world.node_of(SoloStubScript.NODE_TUTORIAL)
	assert_bool(tut.vault_requires_open()).is_true()   # учебное хранилище — взломом, с замком тира BASE
	assert_int(int(BreachData.shared().tier_params(tut.breach_tier())["lock_length"])).is_greater(0)
	_solo.server.net.end_session(SESSION, ExitLogic.REASON_CLEAN)   # то же, что площадка выхода (GrayNode._on_leave_requested)
	assert_bool(await _wait_for(func(): return _results.size() == 1)).is_true()
	assert_array(_results[0]).is_equal([ExitLogic.REASON_CLEAN, true])
	var first_port: int = _solo.port
	assert_bool(await _solo.restart()).is_true()
	assert_int(_solo.port).is_not_equal(first_port)
	assert_int(SoloStubScript.free_port(first_port, first_port)).is_equal(first_port)   # прошлая попытка сокет закрыла
	assert_bool(_solo.tutorial).is_false()
	assert_bool(await _arrived(ARCHIVE)).is_true()
	_solo.server.net.end_session(SESSION, ExitLogic.REASON_CLEAN)
	assert_bool(await _wait_for(func(): return _results.size() == 2)).is_true()
	assert_array(_results[1]).is_equal([ExitLogic.REASON_CLEAN, false])
	var second_port: int = _solo.port
	assert_bool(await _solo.restart()).is_true()
	assert_int(SoloStubScript.free_port(second_port, second_port)).is_equal(second_port)
	assert_bool(await _arrived(ARCHIVE)).is_true()
	assert_int(_solo.get_child_count()).is_equal(2)   # одно поддерево сервера и одно клиента: прошлые попытки убраны
	assert_int(_results.size()).is_equal(2)   # остановка ради перезапуска — не конец забега


func test_skip_tutorial_с_архива_аварийный_выход_и_restart_снова_в_учебный() -> void:
	_start(PackedStringArray([SoloStubScript.SKIP_TUTORIAL_ARG]))
	assert_bool(_solo.tutorial).is_false()
	assert_bool(await _arrived(ARCHIVE)).is_true()
	var proto := _solo.flat.get_node("Proto") as ProtoClient
	assert_bool(proto.net.request_exit(ExitLogic.REASON_MANUAL_HOLD)).is_true()   # аварийный выход клиента (Esc 3 с)
	assert_bool(await _wait_for(func(): return _results.size() == 1)).is_true()
	assert_array(_results[0]).is_equal([ExitLogic.REASON_MANUAL_HOLD, false])
	assert_bool(await _solo.restart(true)).is_true()
	assert_bool(_solo.tutorial).is_true()
	assert_bool(await _arrived(SoloStubScript.NODE_TUTORIAL)).is_true()
