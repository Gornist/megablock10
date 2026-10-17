extends GdUnitTestSuite
## Экраны тестера одиночной игры (client/solo/): порядок показа, анкета один раз, H, состояние в cfg, ответы в журнал, меню Esc, итог.
## Логика проверяется на чистых функциях и на SoloUi с ложным SoloStub; одна сквозная проверка — на настоящем SoloStub (сервер и клиент в процессе).

const SoloStubScript := preload("res://client/solo_stub.gd")
const SEEN_PATH := "user://solo_ui_test_seen.cfg"
const RUNS_DIR := "user://solo_ui_test_runs"
const JOURNAL_FILE := "user://solo_ui_test_journal.log"

var _solo: Node


## Ложный SoloStub: сигнал конца забега, журнал с файлом, сводка, запись перезапусков.
class FakeStub extends Node:
	signal run_finished(result: String, tutorial: bool)
	var journal := RunJournal.new()
	var last_summary := {"sec": 75.0, "breaches": 2, "breaches_won": 1, "caught": 0, "aim_miss": 3}
	var deck := {"loot": [{"kind": "shard"}, {"kind": "shard"}, {"kind": "daemon"}], "eddies": 40}
	var restarts: Array[bool] = []
	var flat = null

	func journal_dir() -> String:
		return "user://solo_ui_test_runs/попытка"

	func deck_snapshot() -> Dictionary:
		return deck

	func restart(with_tutorial: bool = false) -> void:
		restarts.append(with_tutorial)


func before_test() -> void:
	_clean()


func after_test() -> void:
	if _solo != null and is_instance_valid(_solo):
		await _solo.stop()
		_solo.queue_free()
	_solo = null
	_clean()


func _clean() -> void:
	for p in [SEEN_PATH, JOURNAL_FILE]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _wait_for(cond: Callable, sec: float = 10.0) -> bool:
	var t := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


## SoloUi с ложным стабом и чистым cfg; журнал стаба пишет в JOURNAL_FILE.
func _ui(controls_seen := false, survey_done := false) -> SoloUi:
	var fake := FakeStub.new()
	add_child(fake)
	auto_free(fake)
	var f := FileAccess.open(JOURNAL_FILE, FileAccess.WRITE)
	f.store_line("t=1 start build=dev")
	f.close()
	fake.journal.log_path = JOURNAL_FILE
	var seen := SoloSeen.load_from(SEEN_PATH)
	seen.controls_seen = controls_seen
	seen.survey_done = survey_done
	var ui := SoloUi.new()
	add_child(ui)
	auto_free(ui)
	ui.setup(fake, seen)
	return ui


func _journal_text() -> String:
	return FileAccess.get_file_as_string(JOURNAL_FILE)


func _fill_survey(s: SurveyScreen) -> void:
	s.select("q1", "4")
	s.select("q2", "не дошёл")
	s.set_text("q3", "в красной комнате")
	s.set_text("q5", "громкий звук")
	s.select("q6", "да")


# --- порядок экранов -------------------------------------------------------

func test_старт_наушники_всегда_картинка_только_впервые() -> void:
	assert_array(SoloUi.startup_screens(false)).is_equal([SoloUi.SCREEN_HEADPHONES, SoloUi.SCREEN_CONTROLS])
	assert_array(SoloUi.startup_screens(true)).is_equal([SoloUi.SCREEN_HEADPHONES])


func test_после_забега_анкета_только_после_первой_настоящей_попытки() -> void:
	assert_array(SoloUi.after_run_screens(true, false)).is_equal([SoloUi.SCREEN_RESULT])   # учебный узел — анкеты нет
	assert_array(SoloUi.after_run_screens(false, false)).is_equal([SoloUi.SCREEN_SURVEY, SoloUi.SCREEN_RESULT])
	assert_array(SoloUi.after_run_screens(false, true)).is_equal([SoloUi.SCREEN_RESULT])   # повторно — никогда
	assert_array(SoloUi.after_run_screens(true, true)).is_equal([SoloUi.SCREEN_RESULT])


func test_короткое_нажатие_esc_отличается_от_зажатия() -> void:
	assert_bool(SoloUi.is_esc_tap(120)).is_true()
	assert_bool(SoloUi.is_esc_tap(SoloUi.ESC_TAP_MAX_MS - 1)).is_true()
	assert_bool(SoloUi.is_esc_tap(SoloUi.ESC_TAP_MAX_MS)).is_false()
	assert_bool(SoloUi.is_esc_tap(3000)).is_false()


# --- состояние «видел» -----------------------------------------------------

func test_cfg_нет_файла_значения_по_умолчанию() -> void:
	var s := SoloSeen.load_from(SEEN_PATH)
	assert_bool(s.controls_seen).is_false()
	assert_bool(s.survey_done).is_false()
	assert_bool(s.hints_visible).is_true()


func test_cfg_состояние_переживает_перезагрузку() -> void:
	var s := SoloSeen.load_from(SEEN_PATH)
	s.mark_controls_seen()
	s.set_hints_visible(false)
	s.mark_survey_done()
	var again := SoloSeen.load_from(SEEN_PATH)
	assert_bool(again.controls_seen).is_true()
	assert_bool(again.hints_visible).is_false()
	assert_bool(again.survey_done).is_true()


# --- подсказки и номер сборки ----------------------------------------------

func test_h_переключает_подсказки_и_запоминает_в_cfg() -> void:
	var seen := SoloSeen.load_from(SEEN_PATH)
	var h := HintsCorner.new(seen)
	add_child(h)
	auto_free(h)
	assert_bool(h.hints_visible()).is_true()
	h.toggle()
	assert_bool(h.hints_visible()).is_false()
	assert_bool(SoloSeen.load_from(SEEN_PATH).hints_visible).is_false()
	h.toggle()
	assert_bool(SoloSeen.load_from(SEEN_PATH).hints_visible).is_true()


func test_подсказки_из_схемы_управления_и_номер_сборки_виден_всегда() -> void:
	var lines := HintsCorner.hint_lines(SoloControls.entries())
	assert_int(lines.size()).is_equal(SoloControls.entries().size())
	assert_str(lines[0]).starts_with(str(SoloControls.entries()[0]["keys"]))
	var seen := SoloSeen.load_from(SEEN_PATH)
	seen.hints_visible = false
	var h := HintsCorner.new(seen)
	add_child(h)
	auto_free(h)
	var build: Label = h.get_node("BuildLabel")
	assert_str(build.text).is_equal(HintsCorner.build_text(BuildInfo.BUILD))
	assert_str(build.text).contains(BuildInfo.BUILD)
	assert_bool(build.visible).is_true()


func test_подсказки_не_переключаются_при_открытом_экране() -> void:
	var ui := _ui(true)
	ui.begin()
	assert_bool(ui.is_modal()).is_true()
	ui.toggle_hints()
	assert_bool(ui.hints.hints_visible()).is_true()
	ui.current.chosen.emit("ready")
	ui.toggle_hints()
	assert_bool(ui.hints.hints_visible()).is_false()


# --- картинка управления ---------------------------------------------------

func test_картинка_управления_по_группам_схемы() -> void:
	var groups := ControlsPicture.grouped(SoloControls.entries())
	var rows := 0
	for g in groups:
		rows += (g["rows"] as Array).size()
	assert_int(rows).is_equal(SoloControls.entries().size())
	assert_str(str(groups[0]["group"])).is_equal(str(SoloControls.entries()[0]["group"]))
	assert_array(ControlsPicture.key_tokens("ПКМ / C")).is_equal(PackedStringArray(["ПКМ", "C"]))
	assert_array(ControlsPicture.key_tokens("ЛКМ (держать)")).is_equal(PackedStringArray(["ЛКМ (держать)"]))


# --- анкета ----------------------------------------------------------------

func test_анкета_шесть_вопросов_по_порядку() -> void:
	assert_int(SurveyScreen.QUESTIONS.size()).is_equal(6)
	for i in 6:
		assert_str(SurveyScreen.QUESTIONS[i]["id"]).is_equal("q%d" % (i + 1))
	assert_array(SurveyScreen.QUESTIONS[0]["options"]).is_equal(["1", "2", "3", "4", "5"])
	assert_array(SurveyScreen.QUESTIONS[1]["options"]).is_equal(["да", "нет", "не дошёл"])
	assert_array(SurveyScreen.QUESTIONS[5]["options"]).is_equal(["да", "нет"])
	for i in [2, 3, 4]:
		assert_str(SurveyScreen.QUESTIONS[i]["kind"]).is_equal(SurveyScreen.KIND_TEXT)


func test_анкета_отправка_только_когда_выборы_отвечены() -> void:
	var s := SurveyScreen.new()
	add_child(s)
	auto_free(s)
	var sent := [0]
	s.chosen.connect(func(a: String): sent[0] += 1 if a == "submit" else 0)
	s.submit()
	assert_int(sent[0]).is_equal(0)
	s.select("q1", "5")
	s.select("q2", "да")
	assert_bool(s.can_submit()).is_false()   # q6 не отвечен
	s.select("q6", "нет")
	assert_bool(s.can_submit()).is_true()   # текстовые необязательны
	s.submit()
	assert_int(sent[0]).is_equal(1)
	assert_str(str(s.answers()["q3"])).is_equal("")


func test_анкета_чужой_вариант_не_засчитывается() -> void:
	assert_bool(SurveyScreen.is_complete({"q1": "7", "q2": "да", "q6": "да"})).is_false()
	assert_bool(SurveyScreen.is_complete({"q1": "3", "q2": "да", "q6": "да"})).is_true()


func test_ответы_анкеты_попадают_в_журнал_строками_survey() -> void:
	var ui := _ui(true)
	ui._last = {"result": ExitLogic.REASON_CLEAN, "tutorial": false}
	ui.stub.run_finished.emit(ExitLogic.REASON_CLEAN, false)
	assert_str(ui.current_kind).is_equal(SoloUi.SCREEN_SURVEY)
	_fill_survey(ui.current as SurveyScreen)
	ui.current.chosen.emit("submit")
	var text := _journal_text()
	assert_str(text).contains("survey.q1 value=4")
	assert_str(text).contains("survey.q2 value=")
	assert_str(text).contains("не дошёл")
	assert_str(text).contains("survey.q3 value=")
	assert_str(text).contains("в красной комнате")
	assert_str(text).contains("survey.q4 value=")
	assert_str(text).contains("survey.q5 value=")
	assert_str(text).contains("survey.q6 value=")
	assert_str(ui.current_kind).is_equal(SoloUi.SCREEN_RESULT)   # после анкеты — итог
	assert_bool(SoloSeen.load_from(SEEN_PATH).survey_done).is_true()


# --- ход экранов в SoloUi --------------------------------------------------

func test_старт_наушники_потом_картинка_потом_игра() -> void:
	var ui := _ui()
	ui.begin()
	assert_str(ui.current_kind).is_equal(SoloUi.SCREEN_HEADPHONES)
	ui.current.chosen.emit("ready")
	assert_str(ui.current_kind).is_equal(SoloUi.SCREEN_CONTROLS)
	assert_bool(SoloSeen.load_from(SEEN_PATH).controls_seen).is_true()   # картинку увидели — в следующий раз её не будет
	ui.current.chosen.emit("close")
	assert_bool(ui.is_modal()).is_false()


func test_старт_не_первый_без_картинки() -> void:
	var ui := _ui(true)
	ui.begin()
	ui.current.chosen.emit("ready")
	assert_bool(ui.is_modal()).is_false()


func test_анкета_один_раз_второй_забег_сразу_итог() -> void:
	var ui := _ui(true)
	ui.stub.run_finished.emit(ExitLogic.REASON_EJECTED, false)
	assert_str(ui.current_kind).is_equal(SoloUi.SCREEN_SURVEY)
	_fill_survey(ui.current as SurveyScreen)
	ui.current.chosen.emit("submit")
	assert_str(ui.current_kind).is_equal(SoloUi.SCREEN_RESULT)
	ui.current.chosen.emit("again")
	assert_array(ui.stub.restarts).is_equal([false])
	assert_bool(ui.is_modal()).is_false()
	ui.stub.run_finished.emit(ExitLogic.REASON_CLEAN, false)
	assert_str(ui.current_kind).is_equal(SoloUi.SCREEN_RESULT)   # анкеты больше нет
	assert_bool(SoloSeen.load_from(SEEN_PATH).survey_done).is_true()


func test_после_учебного_узла_анкеты_нет_и_она_остаётся_на_первую_настоящую() -> void:
	var ui := _ui(true)
	ui.stub.run_finished.emit(ExitLogic.REASON_CLEAN, true)
	assert_str(ui.current_kind).is_equal(SoloUi.SCREEN_RESULT)
	assert_bool(SoloSeen.load_from(SEEN_PATH).survey_done).is_false()
	ui.current.chosen.emit("again")
	ui.stub.run_finished.emit(ExitLogic.REASON_EJECTED, false)
	assert_str(ui.current_kind).is_equal(SoloUi.SCREEN_SURVEY)


func test_итог_кнопки_перезапуск_обучение_папка_выход() -> void:
	var ui := _ui(true, true)
	var opened: Array[String] = []
	var quit := [0]
	ui.open_fn = func(p: String) -> int:
		opened.append(p)
		return OK
	ui.quit_fn = func() -> void: quit[0] += 1
	ui.stub.run_finished.emit(ExitLogic.REASON_FLATLINE, false)
	assert_str(ui.current_kind).is_equal(SoloUi.SCREEN_RESULT)
	ui.current.chosen.emit("folder")
	assert_array(opened).is_equal([ui.stub.journal_dir()])
	assert_str(ui.current_kind).is_equal(SoloUi.SCREEN_RESULT)   # папка открылась — итог остаётся
	ui.current.chosen.emit("tutorial")
	assert_array(ui.stub.restarts).is_equal([true])
	ui.stub.run_finished.emit(ExitLogic.REASON_CLEAN, true)
	ui.current.chosen.emit("quit")
	assert_int(quit[0]).is_equal(1)


func test_итог_показывает_исход_добычу_и_путь() -> void:
	assert_str(RunResultScreen.outcome(ExitLogic.REASON_CLEAN)).is_equal(RunResultScreen.OUTCOME_CLEAN)
	assert_str(RunResultScreen.outcome(ExitLogic.REASON_EJECTED)).is_equal(RunResultScreen.OUTCOME_CAUGHT)
	assert_str(RunResultScreen.outcome(ExitLogic.REASON_FLATLINE)).is_equal(RunResultScreen.OUTCOME_CAUGHT)
	assert_str(RunResultScreen.outcome(ExitLogic.REASON_CONNECTION_LOST)).is_equal(RunResultScreen.OUTCOME_FAIL)
	var f := RunResultScreen.loot_figures({"loot": [{"kind": "shard"}, {"kind": "shard"}, {"kind": "daemon"}], "eddies": 40})
	assert_dict(f).is_equal({"shards": 2, "daemons": 1, "eddies": 40})
	assert_str(RunResultScreen.loot_text(f)).is_equal("шарды 2 · демоны 1 · эдди 40")
	assert_dict(RunResultScreen.loot_figures({})).is_equal({"shards": 0, "daemons": 0, "eddies": 0})
	assert_str(RunResultScreen.stats_text({"sec": 75.0, "breaches": 2, "breaches_won": 1, "caught": 0, "aim_miss": 3})).contains("1:15")
	var ui := _ui(true, true)
	ui.stub.run_finished.emit(ExitLogic.REASON_CLEAN, false)
	var scr := ui.current as RunResultScreen
	assert_str((scr.get_node("%LootLine") if false else scr.find_child("LootLine", true, false)).text).contains("шарды 2")
	assert_str((scr.find_child("JournalPath", true, false) as Label).text).contains("solo_ui_test_runs")


func test_меню_esc_открывается_закрывается_и_ведёт_к_картинке_управления() -> void:
	var ui := _ui(true, true)
	ui.esc_tap()
	assert_str(ui.current_kind).is_equal(SoloUi.SCREEN_PAUSE)
	ui.esc_tap()
	assert_bool(ui.is_modal()).is_false()
	ui.esc_tap()
	ui.current.chosen.emit("controls")
	assert_str(ui.current_kind).is_equal(SoloUi.SCREEN_CONTROLS)
	ui.current.chosen.emit("close")
	assert_str(ui.current_kind).is_equal(SoloUi.SCREEN_PAUSE)   # из меню — и назад в меню
	ui.current.chosen.emit("resume")
	assert_bool(ui.is_modal()).is_false()
	ui.esc_tap()
	ui.current.chosen.emit("again")
	ui.esc_tap()
	ui.current.chosen.emit("tutorial")
	assert_array(ui.stub.restarts).is_equal([false, true])


func test_esc_не_закрывает_итог_и_анкету() -> void:
	var ui := _ui(true)
	ui.stub.run_finished.emit(ExitLogic.REASON_CLEAN, false)
	ui.esc_tap()
	assert_str(ui.current_kind).is_equal(SoloUi.SCREEN_SURVEY)


func test_забег_кончился_при_открытом_меню_меню_уступает_итогу() -> void:
	var ui := _ui(true, true)
	ui.esc_tap()
	ui.stub.run_finished.emit(ExitLogic.REASON_EJECTED, false)
	assert_str(ui.current_kind).is_equal(SoloUi.SCREEN_RESULT)


func test_пока_экран_открыт_мышь_свободна() -> void:
	var ui := _ui(true, true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ui.esc_tap()
	assert_int(Input.mouse_mode).is_equal(Input.MOUSE_MODE_VISIBLE)


# --- сквозная проверка на настоящем SoloStub --------------------------------

func test_сквозной_забег_анкета_в_журнал_попытки_до_перезапуска() -> void:
	_solo = SoloStubScript.new()
	_solo.seen_path = SEEN_PATH
	add_child(_solo)
	var args := PackedStringArray([SoloStubScript.SKIP_TUTORIAL_ARG, "--runs-dir=" + RUNS_DIR])
	assert_array(SoloStubScript.client_args(args, 49555)).contains(["--tester"])
	assert_bool(_solo.start(args)).is_true()
	assert_object(_solo.ui).is_not_null()
	assert_str(_solo.ui.current_kind).is_equal(SoloUi.SCREEN_HEADPHONES)
	_solo.ui.current.chosen.emit("ready")
	_solo.ui.current.chosen.emit("close")
	assert_bool(_solo.ui.is_modal()).is_false()
	assert_bool(await _wait_for(func(): return _solo.journal_dir() != "" and _solo.journal.log_path != "")).is_true()
	var attempt_dir: String = _solo.journal_dir()
	var log_path: String = _solo.journal.log_path
	_solo._finish(ExitLogic.REASON_EJECTED)   # конец забега: анкета (первая настоящая попытка), затем итог
	assert_str(_solo.ui.current_kind).is_equal(SoloUi.SCREEN_SURVEY)
	_fill_survey(_solo.ui.current as SurveyScreen)
	_solo.ui.current.chosen.emit("submit")
	assert_str(_solo.ui.current_kind).is_equal(SoloUi.SCREEN_RESULT)
	var text := FileAccess.get_file_as_string(log_path)
	assert_str(text).contains("run.summary")
	assert_str(text).contains("survey.q1 value=4")
	assert_str(text).contains("survey.q6 value=")
	assert_str(_solo.journal_dir()).is_equal(attempt_dir)   # до restart журнал указывает на ту же попытку
	assert_dict(_solo.last_summary).contains_keys(["result", "breaches", "aim_miss"])
	_solo.ui.current.chosen.emit("again")   # «Ещё раз»: новая попытка, итог закрыт
	assert_bool(await _wait_for(func(): return _solo.journal_dir() != attempt_dir)).is_true()
	assert_bool(_solo.ui.is_modal()).is_false()
