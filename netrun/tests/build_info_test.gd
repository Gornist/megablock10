extends GdUnitTestSuite
## Номер сборки (BuildInfo): формат строки, которую подставляет tools/export_flat_win.sh.


func test_build_number_has_valid_format() -> void:
	assert_str(BuildInfo.BUILD).is_not_empty()
	assert_bool(BuildInfo.is_valid(BuildInfo.BUILD)).is_true()


func test_date_and_sha_number_is_valid() -> void:
	assert_bool(BuildInfo.is_valid("1017-ab12cd3")).is_true()
	assert_bool(BuildInfo.is_valid("dev")).is_true()


func test_garbage_numbers_are_rejected() -> void:
	assert_bool(BuildInfo.is_valid("")).is_false()
	assert_bool(BuildInfo.is_valid("10 17")).is_false()
	assert_bool(BuildInfo.is_valid("AB12")).is_false()
	assert_bool(BuildInfo.is_valid("a\"b")).is_false()
