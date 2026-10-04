extends GdUnitTestSuite
## APK очков («Client Pico 4 (Android)») собирается без server/ и tests/ (exclude_filter в export_presets.cfg). Глобальный
## class_name оттуда в коде клиента экспорт не замечает, а на очках это ошибка разбора: main.gd ссылался на WorldServer и BotClient,
## и клиент на Pico 4 не стартовал (2026-10-04). Тест ищет такие имена в коде клиента — без строк и комментариев.

const PRESET := "Client Pico 4 (Android)"
## Код, который грузит клиент очков: точка входа, client/, shared/.
const CLIENT_CODE := ["res://main.gd", "res://client", "res://shared"]


func test_client_preset_excludes_server_and_tests() -> void:
	assert_array(_excluded_dirs()).contains(["server", "tests"])


func test_client_code_uses_no_class_from_excluded_dirs() -> void:
	var classes := {}  # class_name -> файл
	for d in _excluded_dirs():
		if d.begins_with("addons/"):
			continue  # плагины редактора (gdUnit4) клиент не зовёт
		for f in _gd_files("res://" + d):
			var cn := _class_name_of(f)
			if not cn.is_empty():
				classes[cn] = f
	assert_dict(classes).contains_keys(["WorldServer", "BotClient", "TraceMeter", "BridgeApi"])
	var strings := RegEx.create_from_string("\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'")
	var ident := RegEx.create_from_string("[A-Za-z_][A-Za-z0-9_]*")
	var found: Array[String] = []
	for root: String in CLIENT_CODE:
		var files: Array[String] = []
		if root.ends_with(".gd"):
			files.append(root)
		else:
			files = _gd_files(root)
		for f in files:
			var lines := FileAccess.get_file_as_string(f).split("\n")
			for i in lines.size():
				var code := strings.sub(lines[i], "\"\"", true).get_slice("#", 0)  # строки и комментарий — не код
				for m in ident.search_all(code):
					var word := m.get_string()
					if classes.has(word):
						found.append("%s:%d %s (%s)" % [f, i + 1, word, classes[word]])
	assert_array(found).is_empty()


## Числа, продублированные в клиенте (уровни trace и состояния ICE приходят числом в снимке сервера).
func test_client_copies_of_server_numbers_match() -> void:
	assert_int(TraceAudio.FLATLINE).is_equal(TraceMeter.Level.FLATLINE)
	assert_int(IceView.STATE_PATROL).is_equal(IceBrain.State.PATROL)
	assert_int(IceView.STATE_SUSPICIOUS).is_equal(IceBrain.State.SUSPICIOUS)
	assert_int(IceView.STATE_SEARCH).is_equal(IceBrain.State.SEARCH)
	assert_int(IceView.STATE_HUNT).is_equal(IceBrain.State.HUNT)


func _excluded_dirs() -> Array[String]:
	var cfg := ConfigFile.new()
	assert_int(cfg.load("res://export_presets.cfg")).is_equal(OK)
	var out: Array[String] = []
	for section in cfg.get_sections():
		if str(cfg.get_value(section, "name", "")) != PRESET:
			continue
		for pat in str(cfg.get_value(section, "exclude_filter", "")).split(",", false):
			var p := pat.strip_edges()
			if p.ends_with("/*"):
				out.append(p.trim_suffix("/*"))
	return out


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for sub in dir.get_directories():
		out.append_array(_gd_files(dir_path.path_join(sub)))
	return out


func _class_name_of(path: String) -> String:
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("class_name "):
			return line.trim_prefix("class_name ").get_slice(" ", 0).strip_edges()
	return ""
