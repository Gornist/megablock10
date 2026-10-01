extends GdUnitTestSuite

func test_dedicated_server_label_selects_server() -> void:
	assert_int(RunMode.detect({"dedicated_server": true}, PackedStringArray())).is_equal(RunMode.Mode.SERVER)


func test_android_selects_client() -> void:
	assert_int(RunMode.detect({"android": true}, PackedStringArray())).is_equal(RunMode.Mode.CLIENT)


func test_desktop_defaults_to_flat() -> void:
	assert_int(RunMode.detect({}, PackedStringArray())).is_equal(RunMode.Mode.FLAT)


func test_args_override() -> void:
	assert_int(RunMode.detect({"android": true}, PackedStringArray(["--server"]))).is_equal(RunMode.Mode.SERVER)
	assert_int(RunMode.detect({}, PackedStringArray(["--client"]))).is_equal(RunMode.Mode.CLIENT)
