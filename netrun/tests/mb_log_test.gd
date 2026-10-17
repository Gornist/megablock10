extends GdUnitTestSuite
## Формат журнала: `событие ключ=значение`.


func test_event_only() -> void:
	assert_str(MbLog.format("app.pause")).is_equal("app.pause")


func test_key_value_pairs_in_order() -> void:
	assert_str(MbLog.format("net.connected", {"host": "10.10.0.10", "port": 7777})).is_equal("net.connected host=10.10.0.10 port=7777")


func test_bool_and_float() -> void:
	assert_str(MbLog.format("xr", {"enabled": false, "ms": 14.456})).is_equal("xr enabled=false ms=14.46")


func test_value_with_spaces_is_quoted() -> void:
	assert_str(MbLog.format("xr", {"reason": "очки не подключены"})).is_equal("xr reason=\"очки не подключены\"")
	assert_str(MbLog.format("x", {"a": "b=c", "e": ""})).is_equal("x a=\"b=c\" e=\"\"")


func test_file_gets_timestamped_lines() -> void:
	var path := "user://logs/test_mb_log.log"
	var l := MbLog.new()
	assert_int(l.open(path)).is_equal(OK)
	l.log("start", {"mode": "flat"})
	l.log("app.pause")
	l.close()
	var lines := FileAccess.get_file_as_string(path).strip_edges().split("\n")
	assert_int(lines.size()).is_equal(2)
	var re := RegEx.create_from_string("^t=\\d+ start mode=flat$")
	assert_object(re.search(lines[0])).is_not_null()
	assert_str(lines[1].substr(lines[1].find(" ") + 1)).is_equal("app.pause")


func test_журнал_в_явном_каталоге_строка_на_диске_до_закрытия() -> void:
	var dir := "user://mb_log_test_dir/run1"
	var l := MbLog.new()
	assert_int(l.open("", dir)).is_equal(OK)
	assert_str(l.path.get_base_dir()).is_equal(dir)
	assert_bool(l.path.get_file().begins_with("netrun-")).is_true()
	l.log("start", {"mode": "flat"})
	# файл не закрыт, а строка уже на диске: журнал переживает падение (flush на каждую строку)
	assert_str(FileAccess.get_file_as_string(l.path)).contains("start mode=flat")
	l.close()
	assert_bool(l.is_open()).is_false()
	assert_int(MbLog.append(l.path, "survey.q1", {"value": "да, понятно"})).is_equal(OK)
	var lines := FileAccess.get_file_as_string(l.path).strip_edges().split("\n")
	assert_int(lines.size()).is_equal(2)
	assert_object(RegEx.create_from_string("^t=\\d+ survey.q1 value=\"да, понятно\"$").search(lines[1])).is_not_null()
	DirAccess.remove_absolute(l.path)


func test_по_умолчанию_каталог_очков_и_сигнал_строки() -> void:
	assert_str(MbLog.DIR).is_equal("user://logs")
	assert_str(MbLog.file_name({"year": 2026, "month": 10, "day": 7, "hour": 9, "minute": 5, "second": 3})).is_equal("netrun-20261007-090503.log")
	var got: Array = []
	var l := MbLog.new()
	l.logged.connect(func(e: String, f: Dictionary, t: int): got.append([e, f, t >= 0]))
	l.log("aim.miss", {"reason": "range"})   # без файла: только печать и сигнал
	assert_array(got).is_equal([["aim.miss", {"reason": "range"}, true]])
