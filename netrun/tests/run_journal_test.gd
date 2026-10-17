extends GdUnitTestSuite
## Журнал попытки одиночной игры (shared/run_journal.gd): имя папки, выбор базового каталога, аргументы клиента, сводка, анкета.
## Настоящие «Документы» не трогаем: базовый каталог в тестах — user://run_journal_test.

const BASE := "user://run_journal_test"
const T := {"year": 2026, "month": 10, "day": 17, "hour": 9, "minute": 5, "second": 7}


func after_test() -> void:
	_rm_tree(BASE)


func _rm_tree(p: String) -> void:
	if not DirAccess.dir_exists_absolute(p):
		return
	for d in DirAccess.get_directories_at(p):
		_rm_tree(p.path_join(d))
	for f in DirAccess.get_files_at(p):
		DirAccess.remove_absolute(p.path_join(f))
	DirAccess.remove_absolute(p)


func test_имя_папки_дата_время_сборка_без_двоеточий() -> void:
	assert_str(RunJournal.dir_name(T, "1017-ab12cd3")).is_equal("20261017-090507-1017-ab12cd3")
	assert_str(RunJournal.dir_name(T, "dev:x/y z")).is_equal("20261017-090507-dev_x_y_z")
	assert_str(RunJournal.dir_name(T, "")).is_equal("20261017-090507-build")


func test_базовый_каталог_явный_документы_только_в_сборке_иначе_запасной() -> void:
	var docs := "C:/Users/t/Documents"
	assert_str(RunJournal.preferred_base(PackedStringArray(["--runs-dir=/tmp/r"]), docs, true)).is_equal("/tmp/r")
	assert_str(RunJournal.preferred_base(PackedStringArray(), docs, true)).is_equal("C:/Users/t/Documents/Мегаблок10/runs")
	assert_str(RunJournal.preferred_base(PackedStringArray(), docs, false)).is_equal(RunJournal.FALLBACK_BASE)
	assert_str(RunJournal.preferred_base(PackedStringArray(), "", true)).is_equal(RunJournal.FALLBACK_BASE)


func test_незаписываемый_каталог_уступает_запасному() -> void:
	assert_str(RunJournal.pick_base(BASE)).is_equal(BASE)
	# путь сквозь обычный файл: создать каталог нельзя
	var blocker := BASE.path_join("file")
	FileAccess.open(blocker, FileAccess.WRITE).close()
	assert_bool(RunJournal.writable(blocker.path_join("runs"))).is_false()
	assert_str(RunJournal.pick_base(blocker.path_join("runs"))).is_equal(RunJournal.FALLBACK_BASE)


func test_папка_попытки_и_повтор_в_ту_же_секунду() -> void:
	var j := RunJournal.new()
	var first := j.begin(BASE, "dev", true, T)
	assert_str(first).is_equal(BASE.path_join("20261017-090507-dev"))
	assert_bool(DirAccess.dir_exists_absolute(first)).is_true()
	assert_str(j.begin(BASE, "dev", false, T)).is_equal(BASE.path_join("20261017-090507-dev-2"))
	assert_bool(j.tutorial).is_false()


func test_аргументы_клиента_туда_и_обратно() -> void:
	var a := RunJournal.client_args("C:/Docs/Мегаблок10/runs/x", true)
	var o := RunJournal.client_options(a)
	assert_str(str(o["dir"])).is_equal("C:/Docs/Мегаблок10/runs/x")
	assert_dict(o["fields"]).is_equal({"build": BuildInfo.BUILD, "solo": true, "tutorial": true})
	var glasses := RunJournal.client_options(PackedStringArray(["--host=10.10.0.10"]))
	assert_str(str(glasses["dir"])).is_empty()
	assert_dict(glasses["fields"]).is_empty()   # строка start очков не меняется


func test_промах_прицела_только_по_вине_прицела() -> void:
	for r in ["far", "range", "room", "cell", "blocked", "hold"]:
		assert_bool(RunJournal.is_aim_miss(r)).override_failure_message(r).is_true()
	for r in ["cooldown", "tunnel", "moved", "wait", ""]:
		assert_bool(RunJournal.is_aim_miss(r)).override_failure_message(r).is_false()


func test_сводка_попытки() -> void:
	var j := RunJournal.new()
	j.begin(BASE, "dev", false, T, 1000)
	j.observe("graph.node", {"node": "node_03"}, 1000)
	j.observe("trace.level", {"level": 1, "value": 30.0}, 2000)
	j.observe_state({"trace": 47.5, "level": 1})
	j.observe("alarm.level", {"level": 2}, 3000)
	j.observe("alarm.level", {"level": 1}, 3500)
	j.observe("aim.miss", {"reason": "range"}, 4000)
	j.observe("breach.start", {}, 5000)
	j.observe("breach.end", {"opened": 2}, 6000)
	j.observe("shard.stowed", {"id": "s1"}, 6500)
	j.observe("graph.node", {"node": "node_04"}, 11000)
	j.observe("graph.node", {"node": "node_03"}, 13000)
	var s := j.summary(ExitLogic.REASON_EJECTED, 14000)
	assert_str(str(s["result"])).is_equal(ExitLogic.REASON_EJECTED)
	assert_bool(s["tutorial"]).is_false()
	assert_float(s["sec"]).is_equal(13.0)
	assert_int(s["nodes"]).is_equal(2)
	assert_str(str(s["node_sec"])).is_equal("node_03:11.0,node_04:2.0")
	assert_int(s["alarm_peak"]).is_equal(2)
	assert_int(s["trace_level_peak"]).is_equal(1)
	assert_float(s["trace_peak"]).is_equal(47.5)
	assert_int(s["breaches"]).is_equal(1)
	assert_int(s["breaches_won"]).is_equal(1)
	assert_int(s["shards"]).is_equal(1)
	assert_int(s["caught"]).is_equal(1)
	assert_int(s["aim_miss"]).is_equal(1)
	assert_int(j.summary(ExitLogic.REASON_CLEAN, 14000)["caught"]).is_equal(0)
	# строка сводки — одна, без пробелов вне кавычек
	assert_bool(MbLog.format("run.summary", s).begins_with("run.summary result=ejected tutorial=false")).is_true()


func test_анкета_дописывается_в_журнал_попытки() -> void:
	var j := RunJournal.new()
	var d := j.begin(BASE, "dev", true, T)
	assert_int(j.log_survey({"q1": "да"})).is_equal(ERR_FILE_NOT_FOUND)   # журнал клиента ещё не открыт
	var l := MbLog.new()
	l.open("", d)
	l.log("start", {"mode": "flat"})
	l.close()
	j.log_path = l.path
	assert_int(j.log_survey({"q1": "понятно", "q2": 4})).is_equal(OK)
	var lines := FileAccess.get_file_as_string(l.path).strip_edges().split("\n")
	assert_int(lines.size()).is_equal(3)
	assert_bool(lines[1].ends_with("survey.q1 value=понятно")).is_true()
	assert_bool(lines[2].ends_with("survey.q2 value=4")).is_true()
