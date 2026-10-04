extends GdUnitTestSuite
## Настройки комфорта user://comfort.cfg (необязательный файл [comfort]): нет файла или поле неверно — значения по умолчанию
## из кода и предупреждение; значения держатся в допустимых пределах, чтобы файлом нельзя было выйти за серверные правила.

const TMP := "user://comfort_test.cfg"


func after_test() -> void:
	DirAccess.remove_absolute(TMP)


func _cfg(values: Dictionary) -> ConfigFile:
	var c := ConfigFile.new()
	for k in values:
		c.set_value(ComfortConfig.SECTION, k, values[k])
	return c


func test_defaults_come_from_code() -> void:
	var c := ComfortConfig.new()
	assert_str(c.turn_mode).is_equal("smooth")
	assert_float(c.turn_speed_deg_s).is_equal(RigMath.TURN_SPEED_DEG_S)
	assert_float(c.turn_vignette).is_equal(RigMath.TURN_VIGNETTE_MAX)
	assert_float(c.turn_ramp_up_s).is_equal(RigMath.TURN_RAMP_UP_SEC)
	assert_float(c.turn_ramp_down_s).is_equal(RigMath.TURN_RAMP_DOWN_SEC)
	assert_float(c.teleport_range).is_equal(RigMath.TELEPORT_RANGE)
	assert_float(c.teleport_cooldown).is_equal(RigMath.TELEPORT_COOLDOWN)
	assert_float(c.teleport_blink_s).is_equal(RigMath.TELEPORT_BLINK_SEC)


func test_missing_file_gives_defaults_without_warnings() -> void:
	var c := ComfortConfig.load_file("user://no_such_comfort.cfg")
	assert_bool(c.from_file).is_false()
	assert_array(c.warnings).is_empty()
	assert_str(c.turn_mode).is_equal("smooth")


func test_valid_values_are_applied() -> void:
	var c := ComfortConfig.from_config(_cfg({
		"turn_mode": "snap", "turn_speed_deg_s": 45.0, "turn_vignette": 0.3, "turn_ramp_up_s": 0.4, "turn_ramp_down_s": 0.3,
		"teleport_range": 3.0, "teleport_cooldown": 2.0, "teleport_blink_s": 0.15,
	}))
	assert_array(c.warnings).is_empty()
	assert_str(c.turn_mode).is_equal("snap")
	assert_float(c.turn_speed_deg_s).is_equal(45.0)
	assert_float(c.turn_vignette).is_equal(0.3)
	assert_float(c.turn_ramp_up_s).is_equal(0.4)
	assert_float(c.turn_ramp_down_s).is_equal(0.3)
	assert_float(c.teleport_range).is_equal(3.0)
	assert_float(c.teleport_cooldown).is_equal(2.0)
	assert_float(c.teleport_blink_s).is_equal(0.15)


func test_integers_and_numeric_strings_are_accepted() -> void:
	var c := ComfortConfig.from_config(_cfg({"turn_speed_deg_s": 50, "teleport_range": "3.5"}))
	assert_array(c.warnings).is_empty()
	assert_float(c.turn_speed_deg_s).is_equal(50.0)
	assert_float(c.teleport_range).is_equal(3.5)


func test_bad_values_fall_back_to_defaults_with_a_warning_each() -> void:
	var c := ComfortConfig.from_config(_cfg({"turn_mode": "wobble", "turn_speed_deg_s": "fast", "teleport_range": [1, 2], "turn_vignette": NAN}))
	assert_int(c.warnings.size()).is_equal(4)
	assert_str(c.turn_mode).is_equal("smooth")
	assert_float(c.turn_speed_deg_s).is_equal(RigMath.TURN_SPEED_DEG_S)
	assert_float(c.teleport_range).is_equal(RigMath.TELEPORT_RANGE)
	assert_float(c.turn_vignette).is_equal(RigMath.TURN_VIGNETTE_MAX)
	assert_str(c.warnings[0]).contains("turn_mode")


func test_out_of_range_values_are_clamped_not_trusted() -> void:
	var c := ComfortConfig.from_config(_cfg({
		"turn_speed_deg_s": 999.0, "turn_vignette": 5.0, "teleport_range": 99.0, "teleport_cooldown": 0.0, "teleport_blink_s": 9.0,
	}))
	assert_int(c.warnings.size()).is_equal(5)
	assert_float(c.turn_speed_deg_s).is_equal(RigMath.TURN_SPEED_MAX_DEG_S)
	assert_float(c.turn_vignette).is_equal(RigMath.TURN_VIGNETTE_LIMIT)
	assert_float(c.teleport_range).is_equal(RigMath.TELEPORT_RANGE_LIMIT)       # не дальше серверного предела
	assert_float(c.teleport_cooldown).is_equal(RigMath.TELEPORT_COOLDOWN_LIMIT) # не чаще серверного предела
	assert_float(c.teleport_blink_s).is_equal(RigMath.TELEPORT_BLINK_LIMIT)
	var low := ComfortConfig.from_config(_cfg({"turn_speed_deg_s": -5.0, "teleport_range": 0.0, "turn_ramp_up_s": 0.0}))
	assert_float(low.turn_speed_deg_s).is_greater(0.0)
	assert_float(low.teleport_range).is_greater(0.0)
	assert_float(low.turn_ramp_up_s).is_greater(0.0)   # нулевой разгон — это рывок: не даём


func test_unknown_key_is_a_warning_only() -> void:
	var c := ComfortConfig.from_config(_cfg({"host": "10.10.0.10", "turn_mode": "snap"}))
	assert_int(c.warnings.size()).is_equal(1)
	assert_str(c.warnings[0]).contains("host")
	assert_str(c.turn_mode).is_equal("snap")


func test_file_round_trip_and_corrupt_file() -> void:
	var cfg := _cfg({"turn_speed_deg_s": 40.0, "teleport_range": 2.5})
	assert_int(cfg.save(TMP)).is_equal(OK)
	var c := ComfortConfig.load_file(TMP)
	assert_bool(c.from_file).is_true()
	assert_float(c.turn_speed_deg_s).is_equal(40.0)
	assert_float(c.teleport_range).is_equal(2.5)
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("[comfort\nturn_mode = = =")
	f.close()
	var bad := ComfortConfig.load_file(TMP)
	assert_int(bad.warnings.size()).is_equal(1)
	assert_str(bad.turn_mode).is_equal("smooth")
	assert_float(bad.teleport_range).is_equal(RigMath.TELEPORT_RANGE)


func test_log_fields_carry_the_main_values() -> void:
	var line := MbLog.format("comfort", ComfortConfig.new().log_fields())
	assert_str(line).contains("turn=smooth")
	assert_str(line).contains("speed=60")
	assert_str(line).contains("vignette=0.45")
	assert_str(line).contains("range=4")
	assert_str(line).contains("cooldown=1.2")
	assert_str(line).contains("file=none")


func test_apply_to_rig_sets_every_field() -> void:
	var rig: XRRig = auto_free(preload("res://client/xr_rig.tscn").instantiate())
	add_child(rig)
	var c := ComfortConfig.from_config(_cfg({
		"turn_mode": "snap", "turn_speed_deg_s": 45.0, "turn_vignette": 0.3, "turn_ramp_up_s": 0.4, "turn_ramp_down_s": 0.3,
		"teleport_range": 3.0, "teleport_cooldown": 2.0, "teleport_blink_s": 0.15,
	}))
	c.apply_to(rig)
	assert_str(rig.turn_mode).is_equal("snap")
	assert_float(rig.turn_speed_deg_s).is_equal(45.0)
	assert_float(rig.turn_vignette).is_equal(0.3)
	assert_float(rig.turn_ramp_up_s).is_equal(0.4)
	assert_float(rig.turn_ramp_down_s).is_equal(0.3)
	assert_float(rig.teleport_range).is_equal(3.0)
	assert_float(rig.teleport_cooldown).is_equal(2.0)
	assert_float(rig.teleport_blink_s).is_equal(0.15)
