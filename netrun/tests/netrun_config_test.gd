extends GdUnitTestSuite
## Адрес сервера и токен очков из файла netrun.cfg (NetConfig.from_sources): без пересборки APK, у каждых очков свой токен.
## Файл необязателен, аргументы перекрывают его, неверное поле даёт предупреждение (не падение), токен в журнал не попадает.

const DIR := "user://netrun_cfg_test"
const SECRET := "s3cret-v4lue"


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func after_test() -> void:
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	DirAccess.remove_absolute(DIR)


func _write(name: String, content: String) -> String:
	var path := DIR.path_join(name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(content)
	f.close()
	return path


func _paths(list: Array) -> PackedStringArray:
	return PackedStringArray(list)


func test_no_file_keeps_defaults_without_warnings() -> void:
	var c := NetConfig.from_sources(PackedStringArray(), _paths([DIR.path_join("none.cfg")]))
	assert_str(c.host).is_equal(NetConfig.DEFAULT_HOST)
	assert_int(c.port).is_equal(NetConfig.DEFAULT_PORT)
	assert_str(c.token).is_empty()
	assert_str(c.file_path).is_empty()
	assert_array(c.warnings).is_empty()


func test_file_sets_host_port_and_token() -> void:
	var p := _write("a.cfg", "[net]\nhost = \"10.10.0.10\"\nport = 7790\ntoken = \"t03:%s\"\n" % SECRET)
	var c := NetConfig.from_sources(PackedStringArray(), _paths([p]))
	assert_str(c.host).is_equal("10.10.0.10")
	assert_int(c.port).is_equal(7790)
	assert_str(c.token).is_equal("t03:" + SECRET)
	assert_str(c.terminal_id()).is_equal("t03")
	assert_str(c.file_path).is_equal(p)
	assert_array(c.warnings).is_empty()


func test_port_is_optional() -> void:
	var p := _write("a.cfg", "[net]\nhost = \"10.10.0.10\"\ntoken = \"t03:x\"\n")
	assert_int(NetConfig.from_sources(PackedStringArray(), _paths([p])).port).is_equal(NetConfig.DEFAULT_PORT)


func test_first_existing_path_wins() -> void:
	var first := _write("first.cfg", "[net]\nhost = \"10.0.0.1\"\n")
	var second := _write("second.cfg", "[net]\nhost = \"10.0.0.2\"\n")
	var c := NetConfig.from_sources(PackedStringArray(), _paths([DIR.path_join("missing.cfg"), first, second]))
	assert_str(c.host).is_equal("10.0.0.1")
	assert_str(c.file_path).is_equal(first)


func test_args_override_file_fields_one_by_one() -> void:
	var p := _write("a.cfg", "[net]\nhost = \"10.10.0.10\"\nport = 7790\ntoken = \"t03:from-file\"\n")
	var c := NetConfig.from_sources(PackedStringArray(["--token=t99:from-args", "--port=7801"]), _paths([p]))
	assert_str(c.host).is_equal("10.10.0.10")  # из файла: аргумента --host нет
	assert_int(c.port).is_equal(7801)
	assert_str(c.token).is_equal("t99:from-args")


func test_unreadable_file_warns_and_next_path_is_tried() -> void:
	var broken := _write("broken.cfg", "[net\nhost = = =")
	var good := _write("good.cfg", "[net]\nhost = \"10.0.0.2\"\n")
	var c := NetConfig.from_sources(PackedStringArray(), _paths([broken, good]))
	assert_str(c.host).is_equal("10.0.0.2")
	assert_str(c.file_path).is_equal(good)
	assert_int(c.warnings.size()).is_equal(1)
	assert_str(c.warnings[0]).contains("broken.cfg")


func test_wrong_fields_warn_and_keep_previous_values() -> void:
	var p := _write("a.cfg", "[net]\nhost = \"\"\nport = 70000\ntoken = 5\nsurprise = 1\n")
	var c := NetConfig.from_sources(PackedStringArray(), _paths([p]))
	assert_str(c.host).is_equal(NetConfig.DEFAULT_HOST)
	assert_int(c.port).is_equal(NetConfig.DEFAULT_PORT)
	assert_str(c.token).is_empty()
	assert_int(c.warnings.size()).is_equal(4)
	assert_str(" ".join(c.warnings)).contains("surprise")


func test_port_as_string_is_accepted_but_junk_is_not() -> void:
	var ok := NetConfig.from_sources(PackedStringArray(), _paths([_write("s.cfg", "[net]\nport = \"7791\"\n")]))
	assert_int(ok.port).is_equal(7791)
	var bad := NetConfig.from_sources(PackedStringArray(), _paths([_write("j.cfg", "[net]\nport = \"abc\"\n")]))
	assert_int(bad.port).is_equal(NetConfig.DEFAULT_PORT)
	assert_int(bad.warnings.size()).is_equal(1)


func test_file_without_net_section_warns() -> void:
	var c := NetConfig.from_sources(PackedStringArray(), _paths([_write("a.cfg", "[comfort]\nturn_mode = \"snap\"\n")]))
	assert_int(c.warnings.size()).is_equal(1)
	assert_str(c.warnings[0]).contains("[net]")


func test_warnings_never_contain_the_token() -> void:
	var p := _write("a.cfg", "[net]\nhost = \"\"\ntoken = \"t03:%s\"\nport = \"x\"\nextra = \"%s\"\n" % [SECRET, SECRET])
	var c := NetConfig.from_sources(PackedStringArray(), _paths([p]))
	assert_str(" ".join(c.warnings)).not_contains(SECRET)


func test_log_fields_name_the_terminal_but_never_the_token() -> void:
	var p := _write("a.cfg", "[net]\nhost = \"10.10.0.10\"\ntoken = \"t03:%s\"\n" % SECRET)
	var line := MbLog.format("net.config", NetConfig.from_sources(PackedStringArray(), _paths([p])).log_fields())
	assert_str(line).contains("host=10.10.0.10")
	assert_str(line).contains("terminal=t03")
	assert_str(line).contains("token=set")
	assert_str(line).not_contains(SECRET)
	var none := MbLog.format("net.config", NetConfig.from_sources(PackedStringArray(), _paths([])).log_fields())
	assert_str(none).contains("file=none")
	assert_str(none).contains("token=none")


func test_redact_args_hides_token_values_only() -> void:
	var line := NetConfig.redact_args(PackedStringArray(["--host=10.10.0.10", "--token=t03:" + SECRET, "--tokens=a:b,c:d", "--exit-after=5"]))
	assert_str(line).is_equal("--host=10.10.0.10 --token=<скрыт> --tokens=<скрыт> --exit-after=5")


func test_from_args_is_unchanged_by_the_refactoring() -> void:
	var c := NetConfig.from_args(PackedStringArray(["--host=h", "--port=1", "--token=t", "--grace=3", "--beat=0.01", "--tokens=a:b,c:d"]))
	assert_str(c.host).is_equal("h")
	assert_int(c.port).is_equal(1)
	assert_str(c.token).is_equal("t")
	assert_float(c.grace_sec).is_equal(3.0)
	assert_float(c.beat_sec).is_equal(0.1)
	assert_dict(c.tokens).is_equal({"a": "b", "c": "d"})
	assert_array(c.warnings).is_empty()


## Идентификатор пакета в пути внешнего каталога должен совпадать с export_presets.cfg: иначе pico.sh provision и клиент ищут в разных местах.
func test_external_dir_matches_the_exported_package() -> void:
	var cf := ConfigFile.new()
	assert_int(cf.load("res://export_presets.cfg")).is_equal(OK)
	var packages: Array = []
	for s in cf.get_sections():
		if cf.has_section_key(s, "package/unique_name"):
			packages.append(cf.get_value(s, "package/unique_name"))
	var pkg := NetConfig.EXTERNAL_DIR.trim_prefix("/sdcard/Android/data/").get_slice("/", 0)
	assert_array(packages).contains([pkg])
	assert_str(NetConfig.EXTERNAL_DIR).is_equal("/sdcard/Android/data/%s/files" % pkg)


func test_default_paths_look_in_the_external_dir_then_user() -> void:
	var paths := NetConfig.default_paths()
	assert_array(Array(paths)).is_equal([NetConfig.EXTERNAL_DIR + "/netrun.cfg", "user://netrun.cfg"])


## Настоящий клиент берёт адрес и токен из файла, а в журнал токен не пишет (ни в net.config, ни в аргументах запуска).
func test_proto_client_uses_the_file_and_keeps_the_token_out_of_the_log() -> void:
	var p := _write("a.cfg", "[net]\nhost = \"127.0.0.1\"\nport = 17995\ntoken = \"t03:%s\"\n" % SECRET)
	var proto: ProtoClient = auto_free(ProtoClient.new())
	proto.config_paths = _paths([p])
	add_child(proto)
	proto.start(PackedStringArray(["--exit-after=5"]), "flat", false)
	assert_object(proto.net).is_not_null()
	assert_str(proto.net.config.token).is_equal("t03:" + SECRET)
	assert_int(proto.net.config.port).is_equal(17995)
	proto.net.stop_reconnect()
	var log := FileAccess.get_file_as_string(proto.log_file.path)
	assert_str(log).contains("net.config file=")
	assert_str(log).contains("terminal=t03")
	assert_str(log).not_contains(SECRET)


func test_proto_client_without_token_skips_and_says_where_it_looked() -> void:
	var missing := DIR.path_join("none.cfg")
	var proto: ProtoClient = auto_free(ProtoClient.new())
	proto.config_paths = _paths([missing])
	add_child(proto)
	proto.start(PackedStringArray(), "flat", false)
	assert_object(proto.net).is_null()
	var log := FileAccess.get_file_as_string(proto.log_file.path)
	assert_str(log).contains("net.skip reason=no_token")
	assert_str(log).contains("none.cfg")
