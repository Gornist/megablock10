extends GdUnitTestSuite
## Голос в звонке: вход аудиодрайвера включён в проекте, а APK очков просит у системы микрофон.

const PRESETS_PATH := "res://export_presets.cfg"
const PICO_PRESET := "Client Pico 4 (Android)"
const RECORD_AUDIO_OPTION := "permissions/record_audio"


func _preset_names_with_record_audio() -> Array[String]:
	var cfg := ConfigFile.new()
	assert_int(cfg.load(PRESETS_PATH)).is_equal(OK)
	var found: Array[String] = []
	for section in cfg.get_sections():
		if not section.ends_with(".options"):
			continue
		if cfg.get_value(section, RECORD_AUDIO_OPTION, false):
			var preset_section := section.trim_suffix(".options")
			found.append(str(cfg.get_value(preset_section, "name", "")))
	return found


func test_audio_input_enabled_in_project() -> void:
	assert_bool(ProjectSettings.get_setting("audio/driver/enable_input", false)).is_true()


func test_record_audio_permission_in_pico_preset() -> void:
	assert_array(_preset_names_with_record_audio()).contains([PICO_PRESET])


func test_record_audio_permission_only_in_pico_preset() -> void:
	assert_array(_preset_names_with_record_audio()).is_equal([PICO_PRESET])
