extends GdUnitTestSuite
## Журнал попытки одиночной игры (client/solo_stub.gd + shared/run_journal.gd, flat-playtest.md §2): своя папка на каждую попытку,
## в строке start — build, solo, tutorial; промахи прицела — aim.miss; в конце — run.summary и закрытый журнал; анкета дописывается.
## Базовый каталог подменён (--runs-dir): настоящие «Документы» не трогаем.

const SoloStubScript := preload("res://client/solo_stub.gd")
const SESSION := "s_fake000000000001"
const BASE := "user://solo_journal_test"

var _solo: Node
var _results: Array = []


func before_test() -> void:
	_results = []


func after_test() -> void:
	if _solo != null:
		await _solo.stop()
		_solo.free()
		_solo = null
	_rm_tree(BASE)


func _rm_tree(p: String) -> void:
	if not DirAccess.dir_exists_absolute(p):
		return
	for d in DirAccess.get_directories_at(p):
		_rm_tree(p.path_join(d))
	for f in DirAccess.get_files_at(p):
		DirAccess.remove_absolute(p.path_join(f))
	DirAccess.remove_absolute(p)


func _wait_for(cond: Callable, sec: float = 15.0) -> bool:
	var t := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _start(args: PackedStringArray) -> void:
	_solo = SoloStubScript.new()
	add_child(_solo)
	_solo.run_finished.connect(func(result: String, tutorial: bool): _results.append([result, tutorial]))
	var all := PackedStringArray(["--runs-dir=" + BASE])
	all.append_array(args)
	assert_bool(_solo.start(all)).is_true()


func _proto() -> ProtoClient:
	return _solo.flat.get_node("Proto") as ProtoClient


func _in_node(id: String) -> bool:
	var arrived := func() -> bool:
		return _solo.server.net.has_avatar(SESSION) and _solo.server.graph_world.where(SESSION) == id and _proto().scene.current_node == id
	return await _wait_for(arrived)


func _log_text() -> String:
	return FileAccess.get_file_as_string(_solo.journal.log_path)


func test_папка_попытки_start_промах_прицела_сводка_анкета_и_новая_папка_на_перезапуск() -> void:
	_start(PackedStringArray())
	var first: String = _solo.journal_dir()
	assert_str(first.get_base_dir()).is_equal(BASE)
	assert_bool(first.get_file().ends_with("-" + RunJournal.safe_name(BuildInfo.BUILD))).is_true()
	assert_str(_solo.journal.log_path.get_base_dir()).is_equal(first)
	assert_bool(await _in_node(SoloStubScript.NODE_TUTORIAL)).is_true()
	var text := _log_text()
	assert_str(text).contains("start mode=flat build=%s solo=true tutorial=true" % BuildInfo.BUILD)
	assert_str(text).contains("graph.node node=" + SoloStubScript.NODE_TUTORIAL)
	# промахи прицела: дальше досягаемости (клиент) и клетка занята (сервер); перезарядка — не промах
	var p := _proto()
	var from: Vector3 = p.scene.rig.global_position
	p._on_teleport_attempted(from, from + Vector3(9.0, 0.0, 0.0), false, WorldMsg.REASON_RANGE)
	p._on_teleport_attempted(from, from + Vector3(1.0, 0.0, 0.0), false, WorldMsg.REASON_COOLDOWN)
	p._on_teleport_denied(WorldMsg.REASON_CELL, from, 0.0)
	text = _log_text()
	assert_str(text).contains("aim.miss reason=range by=client dist=9.00")
	assert_str(text).contains("aim.miss reason=cell by=server")
	assert_bool(text.contains("aim.miss reason=cooldown")).is_false()
	# конец забега: сводка и закрытый журнал
	_solo.server.net.end_session(SESSION, ExitLogic.REASON_CLEAN)
	assert_bool(await _wait_for(func(): return _results.size() == 1)).is_true()
	assert_bool(p.log_file.is_open()).is_false()
	text = _log_text()
	var re := RegEx.create_from_string("run\\.summary result=clean tutorial=true build=\\S+ sec=[0-9.]+ nodes=1 node_sec=%s:[0-9.]+ .*aim_miss=2" % SoloStubScript.NODE_TUTORIAL)
	assert_object(re.search(text)).override_failure_message(text.right(400)).is_not_null()
	assert_int(_solo.journal.log_survey({"q1": "понятно"})).is_equal(OK)
	assert_bool(_log_text().strip_edges().ends_with("survey.q1 value=понятно")).is_true()
	# новая попытка — новая папка, без учебного узла
	assert_bool(await _solo.restart()).is_true()
	var second: String = _solo.journal_dir()
	assert_str(second).is_not_equal(first)
	assert_str(second.get_base_dir()).is_equal(BASE)
	assert_str(_log_text()).contains("solo=true tutorial=false")
	assert_str(FileAccess.get_file_as_string(first.path_join(DirAccess.get_files_at(first)[0]))).contains("survey.q1")   # прошлая попытка не тронута


func test_exit_after_разбор_аргумента() -> void:
	assert_float(SoloStubScript.exit_after_sec(PackedStringArray(["--solo", "--exit-after=8"]))).is_equal(8.0)
	assert_float(SoloStubScript.exit_after_sec(PackedStringArray(["--exit-after=0.5"]))).is_equal(0.5)
	assert_float(SoloStubScript.exit_after_sec(PackedStringArray(["--exit-after=x"]))).is_equal(-1.0)
	assert_float(SoloStubScript.exit_after_sec(PackedStringArray())).is_equal(-1.0)


func test_exit_after_сводка_остановка_и_код_0() -> void:
	var codes: Array = []
	_solo = SoloStubScript.new()
	_solo.quit_fn = func(code: int) -> void: codes.append(code)
	add_child(_solo)
	assert_bool(_solo.start(PackedStringArray(["--runs-dir=" + BASE, "--exit-after=1.5", SoloStubScript.SKIP_TUTORIAL_ARG]))).is_true()
	var path: String = _solo.journal.log_path
	assert_bool(await _wait_for(func(): return codes.size() == 1, 20.0)).is_true()
	assert_array(codes).is_equal([0])
	assert_object(_solo.server).is_null()   # сервер и клиент остановлены до выхода
	assert_str(FileAccess.get_file_as_string(path)).contains("run.summary result=exit_after tutorial=false")


func test_остановка_до_конца_забега_пишет_сводку_stopped() -> void:
	_start(PackedStringArray([SoloStubScript.SKIP_TUTORIAL_ARG]))
	assert_bool(await _wait_for(func(): return _proto().net != null and _proto().net.is_connected_to_world)).is_true()
	var path: String = _solo.journal.log_path
	await _solo.stop()
	assert_str(FileAccess.get_file_as_string(path)).contains("run.summary result=stopped tutorial=false")
	assert_int(_results.size()).is_equal(0)   # остановка — не конец забега
