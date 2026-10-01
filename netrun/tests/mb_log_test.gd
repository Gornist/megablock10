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
