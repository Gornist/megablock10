extends GdUnitTestSuite
## Записи манифеста Pico (addons/netrun_pico_manifest): без них очки со спящими контроллерами не запускают игру («Требуется контроллер»).

const Manifest := preload("res://addons/netrun_pico_manifest/pico_manifest.gd")


func test_объявлены_руки_и_тип_приложения() -> void:
	var s: String = Manifest.application_contents()
	assert_str(s).contains('<meta-data android:name="handtracking" android:value="1" />')
	assert_str(s).contains('<meta-data android:name="pvr.app.type" android:value="vr" />')


func test_одна_запись_на_ключ() -> void:
	var s: String = Manifest.application_contents()
	assert_int(s.count("<meta-data ")).is_equal(Manifest.META_DATA.size())
	assert_bool(s.ends_with("\n")).is_true()


func test_плагин_включён_в_проекте_и_исключён_из_apk() -> void:
	var project := FileAccess.get_file_as_string("res://project.godot")
	assert_str(project).contains("res://addons/netrun_pico_manifest/plugin.cfg")
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	assert_str(presets).contains("addons/netrun_pico_manifest/*")
